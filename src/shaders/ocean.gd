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
## SOLO FALLBACK: si la escena tiene un nodo `Atmosfera` (el dueño de los
## globals de viento desde la decision D-I2), estos exports NO se usan para
## empujar nada — Ocean lee los getters de Atmosfera en `_push_globals`.
## Siguen aqui para los mapas/demo SIN Atmosfera (demo_agua), que es el
## codigo que ya estaba validado y no se toca (:v
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

# --- viento del ULTIMO frame, tal cual se empujo a los shader globals -------
# RenderingServer.global_shader_parameter_get() da ERROR en runtime
# ("nunca usarse fuera del editor"): este par de getters es la forma legal de
# que WaterSurface replique la direccion de las olas sin leer globals. :v
var _wind_actual := 0.0
var _wind_dir_actual := Vector3(0.0, 0.0, 1.0)
## Cache del nodo Atmosfera, la DUEÑA de los globals de viento (decision
## D-I2). Se re-resuelve si desaparece; un mapa sin Atmosfera (demo_agua)
## es el caso normal y ahi manda el fallback de este script (:v
var _atm_cache: Atmosfera

## Color del cielo reflejado en el agua. Lo unico que el shader no saca de la
## Environment. La niebla y el sol los pone la ESCENA, no el material.
var _reflect_color := Color(0.42, 0.055, 0.058)
var _mat: ShaderMaterial


func _ready() -> void:
	_time = randf() * TAU
	# Estado inicial del viento para que WaterSurface no arranque con (0,0,1)
	# mientras este _ready no haya corrido su primer _push_globals. :v
	_wind_actual = clampf(wind_intensity, 0.0, 1.0)
	var h0 := deg_to_rad(wind_heading_deg)
	_wind_dir_actual = Vector3(sin(h0), 0.0, cos(h0))
	_pull_from_environment()
	_bind_material()


## Intensidad de viento real (con racha) empujada a los shader globals. :v
func wind_intensity_actual() -> float:
	return _wind_actual


## Direccion de viento real empujada a los shader globals. :v
func wind_direction_actual() -> Vector3:
	return _wind_dir_actual


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
## Viento: UN SOLO ESCRITOR de los shader globals en toda la escena (:v
##
## Si hay un nodo `Atmosfera` (grupo "atmosfera", decision D-I2), ELLA es la
## dueña: ya se encarga ella de empujar `wind_intensity`/`wind_direction`, y
## aqui solo se cachean sus getters para que los lectores por GDScript
## (`WaterSurface`, la futura infeccion) reciban el mismo valor que ella.
## Los shaders los leen al RENDERIZAR, que es despues de TODOS los
## `_process`, asi que el orden de ejecucion entre nodos no importa (:v
##
## Si NO hay Atmosfera, manda la logica de este nodo: es el fallback de
## SIEMPRE, intacto, para demo_agua y cualquier mapa sin Atmosfera. :v
func _push_viento() -> void:
	var atm := _atmosfera()
	if atm != null:
		_wind_actual = atm.wind_intensity_actual()
		_wind_dir_actual = atm.wind_direction_actual()
		return

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
	_wind_actual = wind
	_wind_dir_actual = dir
	# wind_intensity / wind_direction SI son shader_globals de project.godot: se
	# comparten con agua1.gdshader y con cualquier otro shader de viento.
	# RenderingServer.global_shader_parameter_set() sobre un nombre inexistente
	# no avisa: empuja un ERROR por frame y el agua se queda con el valor viejo.
	RenderingServer.global_shader_parameter_set("wind_intensity", wind)
	RenderingServer.global_shader_parameter_set("wind_direction", dir)


## Atmosfera de la escena si existe; `null` = este nodo es el dueño del
## viento. Se cachea y se re-resuelve solo si el cache caduca, para no hacer
## una busqueda de grupo en cada frame cuando no hay Atmosfera (:v
func _atmosfera() -> Atmosfera:
	if _atm_cache != null and is_instance_valid(_atm_cache) and _atm_cache.is_inside_tree():
		return _atm_cache
	_atm_cache = get_tree().get_first_node_in_group("atmosfera") as Atmosfera
	return _atm_cache


func _push_globals() -> void:
	_push_viento()

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
	# OJO: el tipo es `Material`, no `SkyMaterial`. Esa clase NO EXISTE en
	# Godot 4.7 (ProceduralSkyMaterial hereda directo de Material), y con ella
	# aqui el script entero dejaba de parsear: Godot lo descartaba con
	# "Failed to load script ... Parse error" y el nodo Ocean quedaba SIN
	# script. Consecuencia real e invisible: `_bind_material()` nunca metia
	# agua1.png en el material y `_pull_from_environment()` nunca actualizaba
	# el reflejo. Un solo tipo inexistente mataba el script entero (:v
	var sky_mat: Material = null
	if env.sky != null:
		sky_mat = env.sky.sky_material
	if sky_mat is ProceduralSkyMaterial:
		var psm := sky_mat as ProceduralSkyMaterial
		# Mezcla horizonte y cenit: el agua refleja la franja baja del cielo,
		# pero con algo del color de arriba aporta algo de variacion.
		_reflect_color = psm.sky_horizon_color.lerp(psm.sky_top_color, 0.25)
	elif sky_mat is ShaderMaterial and _es_cielo_alien(sky_mat as ShaderMaterial):
		# CIelo del sistema canonico (`sky_alien.gdshader`).
		#
		# OJO: aqui NO se puede leer el COLOR final del shader — eso se
		# evalua en la GPU. Lo que se hace es REPLICAR la aritmetica del
		# horizonte (EYEDIR.y = 0) con los mismos uniforms, que es una
		# operacion deterministica. Sin esto el agua se quedaba en el
		# hardcode (0.42, 0.055, 0.058) y dejaba de reflejar el cielo:
		# el mar ponia rojo niebla contra un cielo teal.
		_reflect_color = _color_horizonte_cielo_alien(sky_mat as ShaderMaterial)
	elif env.background_mode == Environment.BG_COLOR:
		_reflect_color = env.background_color
	elif env.fog_enabled:
		# Si el cielo es un shader que no sabemos leer, la niebla es lo mas
		# parecido que queda.
		_reflect_color = env.fog_light_color


## Detecta si el material usa `sky_alien.gdshader`, el cielo del sistema
## canonico. Se comprueba por un uniform propio suyo (`sun_a_direction`) y no
## por `resource_path`, para que funcione aunque el shader se cargue con otro
## nombre o se duplique el recurso.
func _es_cielo_alien(mat: ShaderMaterial) -> bool:
	if mat.shader == null:
		return false
	return mat.shader.get_shader_uniform_list().any(
		func(p: Dictionary) -> bool: return String(p.name) == "sun_a_direction"
	)


## Replica el COLOR que el sky shader produce en el horizonte (EYEDIR.y = 0).
##
## No se puede leer el resultado del shader desde GDScript: se ejecuta en la
## GPU. Pero en el horizonte toda la aritmetica se vuelve deterministica y
## depende solo de uniforms, asi que se puede recomputar aqui. Es la misma
## cadena que `sky_alien.gdshader::sky()`, en el mismo orden (:v
##
## Devuelve el color YA en el espacio que el shader esperaba, igual que hacia
## la rama de ProceduralSkyMaterial que sustituye.
func _color_horizonte_cielo_alien(mat: ShaderMaterial) -> Color:
	# En EYEDIR.y = 0, `_eyedir_y = abs(sin(0)) = 0`, asi que todas las
	# mezclas zenit/horizonte caen al TERMINO DE ABAJO.
	var day_bottom := _pcol(mat, "day_bottom_color", Color(0.4, 0.8, 1.0))
	var sunset_bottom := _pcol(mat, "sunset_bottom_color", Color(1.0, 0.5, 0.7))
	var sunset_top := _pcol(mat, "sunset_top_color", Color(0.7, 0.75, 1.0))
	var night_bottom := _pcol(mat, "night_bottom_color", Color(0.1, 0.0, 0.2))
	var clouds_cutoff := _pfloat(mat, "clouds_cutoff", 0.3)
	var clouds_weight := _pfloat(mat, "clouds_weight", 0.0)

	var c := day_bottom
	# Cielo oscurecido por tormenta, igual que en el shader.
	c = c.lerp(Color(0, 0, 0), clampf((0.7 - clouds_cutoff) * clouds_weight, 0.0, 1.0))

	# ---- Atardecer: los dos soles suman, con el primario pesando mas ------
	var dir_a := _pvec3(mat, "sun_a_direction", Vector3.UP)
	var dir_b := _pvec3(mat, "sun_b_direction", Vector3.UP)
	var e_a := _pfloat(mat, "sun_a_energy", 1.0)
	var e_b := _pfloat(mat, "sun_b_energy", 0.6)
	var b_on := _pfloat(mat, "sun_b_enabled", 1.0)

	var sunset_a := clampf(0.5 - absf(dir_a.y), 0.0, 0.5) * 2.0 * e_a
	var sunset_b := clampf(0.5 - absf(dir_b.y), 0.0, 0.5) * 2.0 * b_on * e_b
	var sunset := clampf(maxf(sunset_a, sunset_b), 0.0, 1.0)

	# `_sunset_distance` depende de EYEDIR, que aqui no tenemos: es la
	# direccion hacia la que mira la camara. Como el reflejo es UN solo color
	# para todo el mar, se usa 0.5, el valor neutro entre "atrasado" y "al
	# lado del sol". Es una aproximacion deliberada, no un descuido.
	var sunset_col := sunset_bottom.lerp(sunset_top, 0.5).lerp(sunset_bottom, sunset * 0.5)
	c = c.lerp(sunset_col, sunset)

	# ---- Noche: los DOS soles por debajo del horizonte ---------------------
	# Con la binaria, si uno sigue arriba NO es de noche. Igual que el shader:
	# se toma el MINIMO de "cuanto bajo esta cada uno".
	var bajo_a := clampf(-dir_a.y + 0.7, 0.0, 1.0)
	var bajo_b := clampf(-dir_b.y + 0.7, 0.0, 1.0)
	var bajo_b_enc := lerpf(1.0, bajo_b, b_on)
	var night := minf(bajo_a, bajo_b_enc)
	c = c.lerp(night_bottom, night)

	return c


## Uniform Color con default si falta. Los defaults coinciden con los del
## shader, para que un .tres sin esa clave se comporte igual que con ella.
func _pcol(mat: ShaderMaterial, nombre: String, dflt: Color) -> Color:
	var v = mat.get_shader_parameter(nombre)
	return dflt if v == null else (v as Color)


func _pfloat(mat: ShaderMaterial, nombre: String, dflt: float) -> float:
	var v = mat.get_shader_parameter(nombre)
	return dflt if v == null else float(v)


func _pvec3(mat: ShaderMaterial, nombre: String, dflt: Vector3) -> Vector3:
	var v = mat.get_shader_parameter(nombre)
	return dflt if v == null else (v as Vector3)


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
