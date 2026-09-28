class_name Ocean
extends Node3D
## Controlador del oceano de `petrolera_c1`.
##
## El shader `src/shaders/ocean_stylized.gdshader` es `unshaded` y lleva la
## niebla A MANO (`render_mode fog_disabled`). Eso significa que NADIE mas le
## dice como se ve: este nodo es el que le inyecta, cada frame, los valores
## reales de la escena. Si no esta este nodo, el agua se dibuja con los
## defaults del shader y se desincroniza del cielo.
##
## Tambien es el dueño de la marea y del radar de sonido.
##
## NOTA MULTIPLAYER: la marea es estado COMPARTIDO. En co-op el nivel del mar
## lo decide el servidor y se replica; ver `apply_network_tide()`. El viento y
## el radar de sonido son locales o semi-locales a proposito (que el agua se
## vea distinta en cada cliente rompe la inmersion y da ventaja-competitive).

## Segundos que dura un ciclo de marea completo (subida + bajada).
@export_range(30.0, 1800.0, 1.0) var tide_period := 420.0
## Amplitud de la marea en metros. 0 = mar calmada.
@export_range(0.0, 4.0, 0.05) var tide_amplitude := 0.9
## Fase inicial 0..1. Cambiala por nivel para desincronizar el mar entre mapas.
@export_range(0.0, 1.0, 0.01) var tide_phase := 0.0
## Desfase del ciclo para que el agua empiece subiendo, no bajando.
@export var tide_starts_high := true

@export_group("Viento")
## 0 = mar plano. 1 = oleaje completo.
@export_range(0.0, 1.0, 0.01) var wind_intensity := 0.65
## Si esta apagado, el viento queda FIJO: ni racha ni deriva de rumbo. Util
## para comparar dos capturas del agua sin que el mar se mueva entre una y otra.
@export var auto_wind := true
## Rumbo por defecto en grados (0 = +Z, gira antihorario).
@export_range(0.0, 360.0, 0.5) var wind_heading_deg := 35.0
## Racha: el viento sube y baja solo. Da movimiento sin que el jugador lo note.
@export_range(0.0, 0.5, 0.01) var wind_gust := 0.18

@export_group("Radar de sonido")
## Segundos que vive un anillo de ruido en la superficie.
@export_range(0.5, 10.0, 0.1) var ripple_lifetime := 3.2
## Escala de fuerza 0..1 que se aplica al ruido mas fuerte reciente.
@export_range(0.1, 4.0, 0.05) var ripple_gain := 1.0

@export_group("Petroleo")
## Centro de las manchas de aceite, en XZ de mundo. Por defecto (0,0), que es
## donde esta la refineria. El aceite sale de las tuberías: se concentra aqui
## y no se reparte por el oceano entero.
@export var oil_center_xz := Vector2.ZERO

@export_group("Enlazado")
## Nodo del que se copia el color de fondo (el cielo reflejado en el agua).
## Si es null, se busca el WorldEnvironment de la escena.
@export var environment_path: NodePath
## Material del oceano. Si es null se busca por el shader.
@export var ocean_material: ShaderMaterial
## Texturas del shader. Se inyectan SIEMPRE al arrancar, porque un
## ShaderMaterial guardado sin `shader_parameter/*` sale en negro: esas claves
## no son propiedades del Resource, y las herramientas que editan .tres suelen
## reportar exito sin escribirlas de verdad. Este bloque es la red de seguridad.
@export_group("Texturas")
@export var normal_map: Texture2D
@export var foam_noise: Texture2D

const DEFAULT_NORMAL_MAP := "res://assets/env/textures/nature/agua1_nm.png"
const DEFAULT_FOAM_NOISE := "res://assets/env/textures/nature/agua1.png"

var _time := 0.0
var _ripple_time := 0.0
var _ripple_center := Vector3.ZERO
var _ripple_strength := 0.0
var _tide_override := INF  ## si != INF, manda la red y el ciclo local se ignora

## Color del cielo reflejado en el agua. Lo unico que el shader no saca de la
## Environment. La niebla y el sol los pone la ESCENA, no el material.
var _reflect_color := Color(0.42, 0.055, 0.058)
var _mat: ShaderMaterial


func _ready() -> void:
	_time = randf() * TAU
	_pull_from_environment()
	_bind_material()


## Resuelve el material y le empuja las texturas. Idempotente: se puede
## llamar cada vez que el material se pierde (recarga de escena).
func _bind_material() -> ShaderMaterial:
	if ocean_material != null:
		_mat = ocean_material
	else:
		_mat = _find_ocean_material()
	if _mat == null:
		push_warning("[ocean] no se encontro el material del oceano: el agua saldra negra.")
		return null
	if normal_map == null:
		normal_map = load(DEFAULT_NORMAL_MAP) as Texture2D
	if foam_noise == null:
		foam_noise = load(DEFAULT_FOAM_NOISE) as Texture2D
	_mat.set_shader_parameter("normal_map", normal_map)
	_mat.set_shader_parameter("foam_noise", foam_noise)
	return _mat


func _process(delta: float) -> void:
	_time += delta * (0.0 if Engine.is_editor_hint() else 1.0)
	_ripple_time += delta
	_push_globals()
	# El anillo decae solo: si nadie hace ruido, la superficie se calma.
	_ripple_strength = maxf(0.0, _ripple_strength - delta / maxf(ripple_lifetime, 0.01))


## Emite un ruido visible en la superficie. `world_pos` en coordenadas de
## mundo; `strength` 0..1 segun lo fuerte que fue el ruido en el juego.
## Llamar desde el sistema de sonido (SoundArea) cada vez que un jugador
## hace ruido audible. Los enemigos ya persiguen esos mismos SoundArea, asi
## que el radar no cablea nada nuevo: solo pone en la superficie lo que el
## juego ya sabe.
func emit_noise(world_pos: Vector3, strength: float) -> void:
	var s := clampf(strength, 0.0, 1.0) * ripple_gain
	if s <= 0.001:
		return
	# Un ruido mas fuerte que el actual reinicia el anillo. Asi el agua marca
	# el ULTIMO ruido fuerte, no una mezcla de todos.
	if s >= _ripple_strength * 0.7:
		_ripple_center = world_pos
		_ripple_time = 0.0
		_ripple_strength = s


## Impone un nivel de marea vindo de la red. El servidor es la autoridad.
## Los clientes llaman esto en vez de dejar correr el ciclo local.
func apply_network_tide(level: float) -> void:
	_tide_override = level


## Libera la marea y devuelve a controlar el ciclo local.
func release_network_tide() -> void:
	_tide_override = INF


## Altura del agua en metros. El servidor la usa para decidir si una ruta
## sigue transitable; la envia en el mismo paquete que el resto del estado.
func current_tide_level() -> float:
	if is_finite(_tide_override):
		return _tide_override
	var p := tide_phase
	# 0 = empieza baja y sube; 0.5 = empieza alta y baja. Es un corrimiento de
	# media vuelta, no un signo: asi el ciclo es continuo.
	if not tide_starts_high:
		p += 0.5
	return tide_amplitude * sin(TAU * (p + _time / maxf(tide_period, 1.0)))


# ---------------------------------------------------------------------------
#  Globals
# ---------------------------------------------------------------------------
func _push_globals() -> void:
	var gust := 1.0
	var heading := deg_to_rad(wind_heading_deg)
	if auto_wind:
		# Dos senos incomensurables: la racha nunca se repite exactamente, asi
		# que el mar no se lee como un bucle. Y el rumbo deriva +-12 grados muy
		# despacio, porque un viento que gira 90 grados en un minuto no es
		# viento, es un rotor.
		gust += wind_gust * (sin(_time * 0.37) * 0.5 + sin(_time * 1.13) * 0.3)
		heading = deg_to_rad(wind_heading_deg + sin(_time * 0.021) * 12.0)
	var wind := clampf(wind_intensity * gust, 0.0, 1.0)
	var dir := Vector3(sin(heading), 0.0, cos(heading))
	# wind_intensity / wind_direction SI son shader_globals de project.godot: se
	# comparten con agua1.gdshader y con cualquier otro shader de viento.
	# RenderingServer.global_shader_parameter_set() sobre un nombre inexistente
	# no avisa: empuja un ERROR por frame y el agua se queda con el valor viejo.
	RenderingServer.global_shader_parameter_set("wind_intensity", wind)
	RenderingServer.global_shader_parameter_set("wind_direction", dir)

	# Marea y radar de sonido. Uniforms del material, no shader globals.
	if _mat == null or _mat.get_instance_id() == 0:
		_bind_material()
	if _mat == null:
		return
	_mat.set_shader_parameter("tide_level", current_tide_level())
	_mat.set_shader_parameter("ripple_center", _ripple_center)
	_mat.set_shader_parameter("ripple_time", _ripple_time)
	_mat.set_shader_parameter("ripple_strength", _ripple_strength * exp(-_ripple_time * 0.55))

	# El unico color que el shader NO saca de la Environment es el del cielo
	# REFLEJADO. No es niebla (la niebla la pone el Environment, el shader ya
	# no la toca) ni sol (el sol lo pone la DirectionalLight3D, y el material
	# es "lit"). Es lo que se ve en la superficie cuando miras el agua de lado,
	# y hace falta porque un Fresnel contra el negro daria un mar sin horizonte.
	_mat.set_shader_parameter("reflect_color", _reflect_color)
	_mat.set_shader_parameter("oil_center", oil_center_xz)


func _find_ocean_material() -> ShaderMaterial:
	# El oceano se identifica por el shader, no por el nombre del nodo: asi da
	# igual que se llame "Mar" o "Oceano_Lejano".
	# Se miran LOS DOS sitios donde puede vivir un material: el override del
	# MeshInstance3D y el material de la superficie de la malla. Mirando solo
	# uno de los dos, el agua se queda sin controlador y el viento y la marea
	# se apagan en silencio.
	var ocean := get_parent()
	if ocean == null:
		return null
	for child in ocean.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var candidates: Array[Material] = []
		if mi.material_override != null:
			candidates.append(mi.material_override)
		if mi.mesh != null:
			for surf in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(surf)
				if m != null:
					candidates.append(m)
		for mat in candidates:
			var sm := mat as ShaderMaterial
			if sm != null and sm.shader != null and sm.shader.resource_path != "" \
					and "ocean_stylized" in sm.shader.resource_path:
				return sm
	return null


# ---------------------------------------------------------------------------
#  Sincronizacion con la escena
# ---------------------------------------------------------------------------
func _pull_from_environment() -> void:
	# Lo unico que se copia de la Environment es el color de CIELO, que es lo
	# que el agua refleja. TODO lo demas (niebla, sol, ambiente) lo pone la
	# escena sobre el material, que es "lit".
	var root := get_tree().current_scene
	var we := _resolve(environment_path, root, "WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment

	# El reflejo del agua es, sobre todo, lo que hay JUSTO sobre el horizonte.
	# En una escena con cielo de shader (BACKGROUND_SKY) ese color no es ni el
	# background ni el de la niebla: hay que sacarlo del ProceduralSkyMaterial.
	# Sin esto el agua reflejaba el rojo de la niebla contra un cielo turquesa
	# y el horizonte no casaba.
	var sky_mat: SkyMaterial = null
	if env.sky != null:
		sky_mat = env.sky.sky_material
	if sky_mat is ProceduralSkyMaterial:
		var psm := sky_mat as ProceduralSkyMaterial
		# Mezcla horizonte y cenit: el agua refleja la franja baja del cielo,
		# pero con algo del color de arriba aporta algo de variacion.
		_reflect_color = psm.sky_horizon_color.lerp(psm.sky_top_color, 0.25)
	elif env.background_mode == Environment.BG_COLOR:
		_reflect_color = env.background_color
	elif env.fog_enabled:
		# Si el cielo es un shader que no sabemos leer, la niebla es lo mas
		# parecido que queda.
		_reflect_color = env.fog_light_color


## Resuelve un NodePath explicito; si esta vacio, busca el primer nodo de
## `cls` en la escena. El mapa tiene "Cielo" (WorldEnvironment) y "Sol"
## (DirectionalLight3D) como hijos de la raiz; se busca por clase y no por
## nombre para que renombrarlos no rompa el oceano.
func _resolve(path: NodePath, root: Node, cls: String) -> Node:
	if path != NodePath() and not path.is_empty():
		var n := get_node_or_null(path)
		if n != null:
			return n
	if root == null:
		return null
	return _find_by_class(root, cls)


func _find_by_class(root: Node, cls: String) -> Node:
	if root.is_class(cls):
		return root
	for c in root.get_children():
		var hit := _find_by_class(c, cls)
		if hit != null:
			return hit
	return null
