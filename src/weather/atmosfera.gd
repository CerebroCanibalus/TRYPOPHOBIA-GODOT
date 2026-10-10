@tool
extends Node3D
class_name Atmosfera
## Nodo canonico de ATMOSFERA. Se arrastra a un nivel y ya esta: dentro
## vive TODO lo que es cielo y niebla del mapa, en un solo sitio (:v
##
## Hace esto en `_ready()`:
##   1. Resuelve la Environment del WorldEnvironment HIJO. Este nodo es el
##      DUEÑO UNICO: antes adoptaba la del mapa y competian dos por ser el
##      primero registrado, que es como Godot decide quien manda
##      (`world_environment.cpp` -> `get_first_node_in_group`). O sea que
##      ganaba el primero del arbol, silenciosamente.
##   2. Pone `src/shaders/sky_alien.gdshader` como sky material, sustituyendo
##      lo que hubiese (ProceduralSkyMaterial, panorama, ...).
##   3. Empuja los uniforms del `AtmosferaPreset`.
##   4. Reescribe la Environment (niebla, tonemap, ambiente), si el preset lo
##      manda con `entorno_activo`.
##   5. Configura la precipitacion.
##
## NO HAY LUZ EN ESTE NODO, y es a proposito: la DirectionalLight3D que
## ilumina el escenario la pone el MAPA (en petrolera, `Sol` en la raiz).
## Atmosfera solo LEE esa luz para saber donde pintar el disco del sol
## primario, de modo que lo que se ve en el cielo y lo que proyecta sombras
## son lo mismo sin que nadie sincronice dos cosas a mano (:v
##
## NO hay ciclo dia/noche ni transiciones: el preset se aplica una vez y se
## queda. Lo unico que se anima es cosmético (las nubes derivan con `TIME`).
##
## HIJOS: `WorldEnvironment` y `Precipitacion`. Los soles y la luna NO son
## nodos — sus direcciones viven en el preset (:v

const RUTA_SHADER := "res://src/shaders/sky_alien.gdshader"
## Donde se monta el sistema de rayos. NO vive en ninguna escena: se crea en
## runtime si el preset lo pide, y por eso `relampago.gd` no lleva `@tool`.
const RUTA_RAYOS := NodePath("Relampago")
## Las tres capas de lluvia, en orden de nivel: índice 0 = Suave, 1 =
## Moderada, 2 = Fuerte. El índice ES el nivel, así que aniadir una cuarta
## capa solo exige meterla aqui en su sitio (:v
const RUTAS_LLUVIA := [
	"res://audio/sfx/clima/lluvia_capa1.ogg",
	"res://audio/sfx/clima/lluvia_capa2.ogg",
	"res://audio/sfx/clima/lluvia_capa3.ogg",
]
## Lo MISMO para el viento: mismo orden, mismo sistema de niveles, mismos tres
## grados. Solo cambian los .ogg (:v
const RUTAS_VIENTO := [
	"res://audio/sfx/clima/viento1.ogg",
	"res://audio/sfx/clima/viento2.ogg",
	"res://audio/sfx/clima/viento3.ogg",
]

## Preset de este nivel. Sin el, el nodo no hace nada y deja el cielo tal
## como este en la escena.
##
## El setter tiene motivos de EDITOR: `_ready` solo corre una vez al abrir la
## escena, y este script es `@tool`. Sin el setter, elegir un preset en el
## inspector no refrescaria nada hasta reabrir, y el artista veria el cielo
## viejo y creeria que no funcionaba (:v
@export var preset: AtmosferaPreset:
	set(v):
		preset = v
		if Engine.is_editor_hint() and is_inside_tree():
			_aplicar()

@export_group("Enlazado")
@export var ruta_emisor: NodePath = NodePath("Precipitacion")
## Ruta al WorldEnvironment PROPIO de este nodo (su hijo). No se busca fuera:
## este nodo es el dueño unico del cielo y de la niebla del nivel (:v
@export var ruta_entorno: NodePath = NodePath("WorldEnvironment")

@export_group("Precipitacion")
## El emisor sigue a la camara para no poder ser culleado. Ver la cabecera de
## `_configurar_precipitacion`: sin esto, girar la mirada hace desaparecer la
## lluvia entera. Desactivalo SOLO si la lluvia es localizada a una zona; en
## ese caso amplia `visibility_aabb` a mano.
@export var precip_seguir_camara := true

## Medio ancho y medio alto del volumen de emision, y recorrido de caida que
## hay que dejar cubierto bajo el. En metros. Van aqui y no en el preset porque
## son geometria del emisor, no datos de clima: los comparte todo nivel.
##
## El volumen NO es enorme a proposito: como el emisor va pegado a la camara,
## 15 m de radio ya cubren lo que se ve, y cuanto mas grande peor la densidad
## (2000 gotas repartidas en una caja de 50 m son gotas invisibles).
const PRECIP_ANCHO := 15.0
const PRECIP_ALTO := 20.0
## Gravedad -20 con lifetime 2 s -> unos 40 m de caida; sobra margen.
const PRECIP_CAIDA := 55.0

## Cadencia del refresco en vivo del EDITOR. 0.1 s es imperceptible para el
## ojo y es barato: en cada tic se compara la firma (valores del preset +
## direccion de la luz) y SOLO si ha cambiado se vuelve a aplicar el preset.
## En reposo no se toca nada, ni nodos ni recursos.
const REFREJO_EDITOR := 0.1

var _mat: ShaderMaterial
var _env: Environment
## Emisor de precipitacion, cacheado en `_configurar_precipitacion` para que
## `_process` no tenga que resolver el NodePath 60 veces por segundo (:v
var _emisor: GPUParticles3D
## Sistema de rayos. Solo existe en runtime y solo si el preset lo pide (:v
var _relampago: Relampago
## Sonido de clima. UN nodo `AmbienteAudio` POR SONIDO y no uno solo, porque
## `AmbienteAudio.nivel` es un valor UNICO por instancia: con un solo nodo no
## habria forma de tener lluvia fuerte con viento suave. Los dos van con
## `grupo = "clima"`, asi que comparten bus maestro y se apilan sin cortarse.
## Sigue siendo solo runtime y el preset sigue mandando (:v
var _audio_lluvia: AmbienteAudio
var _audio_viento: AmbienteAudio
var _scape_lluvia: SoundScape
var _scape_viento: SoundScape

# --- Refresco en vivo del editor -------------------------------------------
var _t_refresco := 0.0
var _firma_cache := ""
## Nombres de las propiedades del preset, cacheados: se piden UNA vez en vez
## de llamar a `get_property_list()` diez veces por segundo.
var _nombres_preset: PackedStringArray = []
## Para no repetir el aviso de WorldEnvironment ajeno en cada refresco.
var _aviso_competicion_dado := false


func _ready() -> void:
	# En el editor hay que pedirlo a mano: sin `set_process(true)` un script
	# `@tool` no recibe `_process`, y entonces el refresco en vivo de abajo
	# no correria nunca (:v
	set_process(true)
	_aplicar()


## Aplica el preset entero. Se llama desde `_ready` y desde el setter de
## `preset` (en editor). Es IDEMPOTENTE a proposito: se puede ejecutar
## tantas veces como haga falta sin acumular nada, porque todo lo que toca
## se sobrescribe entero (:v
func _aplicar() -> void:
	if preset == null:
		# En el editor es normal: todavia no se ha elegido preset, y avisar
		# cada vez que se abre la escena solo ensuciaria la consola.
		if not Engine.is_editor_hint():
			push_warning("[atmosfera] sin preset: el cielo se queda como este en la escena.")
		return

	_env = _resolver_entorno()
	if _env == null:
		# Caso esperado al editar clima.tscn suelto (no se crea WE en editor).
		if not Engine.is_editor_hint():
			push_warning("[atmosfera] no hay WorldEnvironment y no se pudo crear uno.")
		return

	_mat = _asegurar_material(_env)
	if _mat == null:
		push_warning("[atmosfera] no se pudo montar el sky shader.")
		return

	_empujar_cielo(_mat)
	if preset.entorno_activo:
		_empujar_entorno(_env)
	_configurar_precipitacion()
	# El ULTIMO: `configurar()` de Relampago captura los valores BASE de la
	# Environment, asi que tiene que correr ya con el preset aplicado. Si no,
	# tomaria como base los valores por defecto y el destello multiplicaria
	# una referencia equivocada (:v
	_configurar_rayos()
	# El sonido de clima va despues de la precipitacion porque decide si
	# llueve con lo que acaba de configurar (:v
	_configurar_clima_audio()


# ---------------------------------------------------------------------------
#  Entorno
# ---------------------------------------------------------------------------
## Devuelve la Environment que manda en la escena: la del WorldEnvironment
## HIJO de este nodo.
##
## ANTES este nodo ADOPTABA el WorldEnvironment que ya tuviera el mapa, y eso
## era exactamente la competencia que se noto. Dos WorldEnvironment en la misma
## escena y Godot se queda con el PRIMERO REGISTRADO (`world_environment.cpp`
## -> `get_first_node_in_group`), con aviso "Only the first Environment has an
## effect": o sea que quien manda dependia del ORDEN DEL ARBOL. Silencioso y
## no determinista.
##
## Ahora el dueño es SIEMPRE este nodo, y el mapa no debe traer el suyo. Todo
## el cielo y toda la niebla de un nivel se editan en un solo sitio (:v
func _resolver_entorno() -> Environment:
	var we := get_node_or_null(ruta_entorno) as WorldEnvironment
	if we == null:
		# En el editor NO creo nada: abrir `atmosfera.tscn` para editar la
		# plantilla no debe colarsele un hijo que la plantilla no tenia.
		if Engine.is_editor_hint():
			return null
		# SE CREA UNA VACIA, y eso es casi siempre un ERROR DE ESTRUCTURA: el
		# mapa ha puesto su WorldEnvironment en otro sitio (como HERMANO, que
		# es el lapsus tipico) y entonces el preset no manda sobre NADA — el
		# cielo se queda en los defaults y la niebla ni se entera. Me atrapo
		# dos veces antes de escribir este aviso, y las dos parecia un bug del
		# sistema, no un nodo mal colgado (:v
		push_warning("[atmosfera] no hay ningun hijo llamado '%s': creo una " % String(ruta_entorno) +
				"Environment vacia. Si el mapa trae la suya en otro sitio, " +
				"este nodo NO la esta usando — colgala de AQUI.")
		we = WorldEnvironment.new()
		we.name = String(ruta_entorno)
		add_child(we)
	if we.environment == null:
		we.environment = Environment.new()
	_avisar_competicion(we)
	return we.environment


## Si el mapa tambien trae su WorldEnvironment, este nodo y el mapa compiten
## por ser el primero registrado. NO lo borro: quitarle la Environment a un
## mapa es destructivo y solo es seguro si el preset la cubre entera
## (`entorno_activo`). Se avisa con su ruta para que lo quite quien sepa que no
## lo necesita (:v
func _avisar_competicion(mio: WorldEnvironment) -> void:
	# Una sola vez por instancia: en el editor `_aplicar` corre cada 0.1 s
	# cuando cambia algo, y repetir el aviso (con su barrido del arbol) seria
	# puro ruido (:v
	if _aviso_competicion_dado:
		return
	var ajenos := _otros_world_environment(mio)
	if ajenos.is_empty():
		return
	_aviso_competicion_dado = true
	var rutas := PackedStringArray()
	for w in ajenos:
		rutas.append(String(w.get_path()))
	push_warning("[atmosfera] hay %d WorldEnvironment fuera de este nodo: %s. " % [
		ajenos.size(), ", ".join(rutas)
	] + "Solo gana el primero registrado del arbol, asi que o este o el suyo. " +
		"Quita el del mapa: ahora el cielo y la niebla viven dentro de Atmosfera.")


func _otros_world_environment(mio: WorldEnvironment) -> Array[WorldEnvironment]:
	var salida: Array[WorldEnvironment] = []
	var raiz := _raiz_busqueda()
	if raiz == null:
		return salida
	_coger_world_env(raiz, mio, salida)
	return salida


func _coger_world_env(n: Node, mio: WorldEnvironment, salida: Array[WorldEnvironment]) -> void:
	# No entro dentro de mi: el WorldEnvironment que esta ahi es el mio.
	if n == self:
		return
	if n is WorldEnvironment and n != mio:
		salida.append(n)
		return
	for c in n.get_children():
		_coger_world_env(c, mio, salida)


## Raiz desde la que buscar: la escena actual si existe, si no voy subiendo
## hasta la ventana. `current_scene` puede ser null muy temprano en el arranque.
func _raiz_busqueda() -> Node:
	var escena := get_tree().current_scene
	if escena != null:
		return escena
	var n: Node = self
	while n.get_parent() != null:
		n = n.get_parent()
	return n


## Garantiza que el cielo use `sky_alien.gdshader`. Si ya lo usa, lo devuelve
## tal cual; si no, monta un ShaderMaterial nuevo con ese shader.
func _asegurar_material(env: Environment) -> ShaderMaterial:
	if env.sky == null:
		env.sky = Sky.new()
	var actual := env.sky.sky_material
	if actual is ShaderMaterial:
		var sm := actual as ShaderMaterial
		if sm.shader != null and sm.shader.resource_path == RUTA_SHADER:
			return sm

	var shader := load(RUTA_SHADER) as Shader
	if shader == null:
		push_error("[atmosfera] no existe " + RUTA_SHADER)
		return null
	var nuevo := ShaderMaterial.new()
	nuevo.shader = shader
	env.sky.sky_material = nuevo
	return nuevo


# ---------------------------------------------------------------------------
#  Sky shader
# ---------------------------------------------------------------------------
func _empujar_cielo(m: ShaderMaterial) -> void:
	# ---- Cielo ----------------------------------------------------------
	_c(m, "day_top_color", preset.day_top_color)
	_c(m, "day_bottom_color", preset.day_bottom_color)
	_c(m, "sunset_top_color", preset.sunset_top_color)
	_c(m, "sunset_bottom_color", preset.sunset_bottom_color)
	_c(m, "night_top_color", preset.night_top_color)
	_c(m, "night_bottom_color", preset.night_bottom_color)

	# ---- Horizonte ------------------------------------------------------
	_c(m, "horizon_color", preset.horizon_color)
	_f(m, "horizon_blur", preset.horizon_blur)

	# ---- Estrellas ------------------------------------------------------
	_f(m, "stars_speed", preset.estrellas_velocidad)
	_f(m, "stars_scale", preset.estrellas_escala)
	_f(m, "stars_opacity", preset.estrellas_opacidad)

	# ---- Disco de los soles y la luna -----------------------------------
	_c(m, "sun_a_color", preset.sol_a_color)
	_c(m, "sun_a_sunset_color", preset.sol_a_sunset_color)
	_f(m, "sun_a_size", preset.sol_a_size)
	_f(m, "sun_a_blur", preset.sol_a_blur)
	_f(m, "sun_a_energy", preset.sol_a_energy)

	_c(m, "sun_b_color", preset.sol_b_color)
	_c(m, "sun_b_sunset_color", preset.sol_b_sunset_color)
	_f(m, "sun_b_size", preset.sol_b_size)
	_f(m, "sun_b_blur", preset.sol_b_blur)
	_f(m, "sun_b_energy", preset.sol_b_energy)
	_f(m, "sun_b_enabled", preset.sol_b_encendido)

	_c(m, "moon_color", preset.luna_color)
	_f(m, "moon_size", preset.luna_size)
	_f(m, "moon_blur", preset.luna_blur)
	_f(m, "moon_enabled", preset.luna_encendida)

	# ---- DIRECCIONES ------------------------------------------------------
	# El primario NO viene del preset: sale de la DirectionalLight3D que ya
	# trae el mapa. Asi el disco que se dibuja en el cielo coincide SIEMPRE
	# con el sitio de donde sale la luz, y no hay dos cosas que sincronizar a
	# mano. Si el mapa no tiene ninguna luz, manda el respaldo del preset.
	# El secundario y la luna van del preset: no tienen luz de la que leer.
	# OJO con el nombre: el shader declara `sun_a_direction` (ingles). Durante
	# toda la vida de este script se escribio `sun_a_direccion`, y `_tiene()`
	# lo descartaba SIN avisar porque el uniform no existe -> el disco del sol
	# primario se quedaba en el default (0,1,0), a plomo, mientras la luz venia
	# de `Sol`. El reflejo era "el cielo no se actualiza" (:v
	_v3(m, "sun_a_direction", _direccion_sol_primario())
	_v3(m, "sun_b_direction", preset.sol_b_direccion)
	_v3(m, "moon_direction", preset.luna_direccion)

	# ---- Nubes — Kelvin-Helmholtz, el UNICO sistema ----------------------
	# Mismo nombre en el shader, en el preset y aqui. Antes habia `clouds_*`
	# para lo convencional y `kh_*` para la KH, con el preset hablando en
	# espanol: tres familias para dos sistemas que encima se pisaban (:v
	_c(m, "nubes_borde", preset.nubes_borde)
	_c(m, "nubes_cima", preset.nubes_cima)
	_c(m, "nubes_media", preset.nubes_media)
	_c(m, "nubes_base", preset.nubes_base)
	_f(m, "nubes_altura", preset.nubes_altura)
	_f(m, "nubes_periodo", preset.nubes_periodo)
	_f(m, "nubes_rollo", preset.nubes_rollo)
	_f(m, "nubes_radio", preset.nubes_radio)
	_f(m, "nubes_grosor", preset.nubes_grosor)
	_f(m, "nubes_direccion", preset.nubes_direccion)
	_f(m, "nubes_velocidad", preset.nubes_velocidad)
	_f(m, "nubes_corte", preset.nubes_corte)
	_f(m, "nubes_difuminado", preset.nubes_difuminado)
	_f(m, "nubes_peso", preset.nubes_peso)
	_f(m, "nubes_intensidad", preset.nubes_intensidad)

	# --- Nubes v2: parallax, sombreado y fundido por distancia --------------
	# Mismo nombre en los tres sitios que el resto (`shader` = `preset` =
	# `aqui`). Aniadir uno exige tocar los tres, y si no, `_tiene()` lo
	# descarta en silencio — que ya es como se nos colo el bug del sol (:v
	_i(m, "nubes_capas", preset.nubes_capas)
	_f(m, "nubes_capa2_altura", preset.nubes_capa2_altura)
	_f(m, "nubes_rizo_ancho", preset.nubes_rizo_ancho)
	_f(m, "nubes_fundido_horizonte", preset.nubes_fundido_horizonte)
	_f(m, "nubes_sombra", preset.nubes_sombra)

	# El radio del halo de tormenta si es ESTATICO; `rayos_intensidad`,
	# `rayos_color` y `rayos_direccion` los empuja `relampago.gd` cada frame.
	_f(m, "rayos_radio", preset.rayos_nube_radio)
	# A cero al arrancar: el material puede venir de un `.tres` con basura.
	_f(m, "rayos_intensidad", 0.0)


## Direccion "hacia la estrella" del sol primario.
##
## Se busca en la DirectionalLight3D que trae el MAPA, nunca en este nodo: la
## luz es de la escena, Clima no la crea ni la toca, solo la pinta en el
## cielo. Es `basis.z` y no `-basis.z` porque la luz ilumina a lo largo de -Z
## pero el cielo se dibuja con +Z, que es como sky.cpp rellena
## LIGHTX_DIRECTION. Si el mapa no tiene ninguna, manda el respaldo (:v
func _direccion_sol_primario() -> Vector3:
	var luz := _buscar_luz_direccional()
	if luz != null:
		return luz.global_transform.basis.z.normalized()
	return preset.sol_a_direccion.normalized()


func _buscar_luz_direccional() -> DirectionalLight3D:
	var raiz := _raiz_busqueda()
	if raiz == null:
		return null
	return _buscar_luz_desde(raiz)


func _buscar_luz_desde(n: Node) -> DirectionalLight3D:
	# No entro en los hijos de este nodo. Clima no tiene luz propia (es una
	# decision: la luz la pone el mapa), pero si alguna vez la tuviera no
	# deberia leerse a si mismo y dar por bueno su propio error (:v
	if n != self and n is DirectionalLight3D:
		return n
	for c in n.get_children():
		if c == self:
			continue
		var hit := _buscar_luz_desde(c)
		if hit != null:
			return hit
	return null


# ---------------------------------------------------------------------------
#  Environment (solo si el preset la toca)
# ---------------------------------------------------------------------------
func _empujar_entorno(env: Environment) -> void:
	env.background_mode = preset.fondo_modo as Environment.BGMode
	env.background_color = preset.fondo_color
	env.background_energy_multiplier = preset.fondo_energia

	env.ambient_light_source = preset.ambiente_fuente as Environment.AmbientSource
	env.ambient_light_color = preset.ambiente_color
	env.ambient_light_energy = preset.ambiente_energia

	env.tonemap_mode = preset.tonemap_modo as Environment.ToneMapper
	env.tonemap_exposure = preset.tonemap_exposicion

	# Niebla clasica: el mapa puede tenerla apagada aunque sus valores
	# guardados sigan ahi. Se respeta el flag del preset, no el default.
	env.fog_enabled = preset.niebla_activa
	if preset.niebla_activa:
		env.fog_mode = preset.niebla_modo as Environment.FogMode
		env.fog_light_color = preset.niebla_color
		env.fog_light_energy = preset.niebla_energia
		env.fog_density = preset.niebla_densidad
		env.fog_sky_affect = preset.niebla_afecta_cielo

	env.volumetric_fog_enabled = preset.niebla_vol_activa
	if preset.niebla_vol_activa:
		env.volumetric_fog_density = preset.niebla_vol_densidad
		env.volumetric_fog_albedo = preset.niebla_vol_albedo
		env.volumetric_fog_emission = preset.niebla_vol_emision
		env.volumetric_fog_emission_energy = preset.niebla_vol_emision_energia
		env.volumetric_fog_gi_inject = preset.niebla_vol_gi
		env.volumetric_fog_anisotropy = preset.niebla_vol_anisotropia
		env.volumetric_fog_length = preset.niebla_vol_longitud
		env.volumetric_fog_detail_spread = preset.niebla_vol_detalle
		env.volumetric_fog_sky_affect = preset.niebla_vol_afecta_cielo


# ---------------------------------------------------------------------------
#  Precipitacion
#
#  EL PUNTO CRITICO DE ESTA SECCION ES EL CULLING.
#
#  GPUParticles3D es un VisualInstance3D: Godot lo cullnea contra el AABB
#  `visibility_aabb`, que por DEFECTO es una caja de 8x8x8 metros. Con el
#  emisor fijo en el mundo basta con girar la mirada para que esa caja salga
#  del frustum -> el motor deja de dibujar el sistema ENTERO y la lluvia o la
#  niebla desaparecen de golpe, sin error ni warning, solo dejando de estar.
#
#  Dos defensas, y ninguna basta sola:
#    1. El emisor SIGUE A LA CAMARA. Una caja que contiene la camara
#       interseca el frustum en cualquier direccion de la mirada.
#    2. `visibility_aabb` amplia, cubriendo emision + caida, para que las
#       particulas no se corten al salirse de la caja por abajo.
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_refrescar_editor(delta)
		return

	if _emisor == null or not _emisor.emitting:
		return
	if not precip_seguir_camara:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# SOLO posicion. La rotacion se queda alineada al mundo a proposito: la
	# lluvia cae siempre hacia abajo aunque el jugador gire la camara.
	# Con `local_coords = false` las gotas ya emitidas no se arrastran.
	_emisor.global_position = cam.global_position


# Cache de la DirectionalLight3D del mapa para la firma del editor: la busqueda
# recursiva recorre el arbol entero (3786 nodos en petrolera), asi que no se
# hace diez veces por segundo sino solo cuando el cache se invalida.
var _luz_cache: DirectionalLight3D
var _tick_luz := 0


## Refresco en vivo del EDITOR.
##
## ANTES `_aplicar` solo se llamaba en `_ready` (una vez al abrir la escena) y
## en el setter de `preset` (solo si se REASIGNABA el recurso). Con eso, editar
## las propiedades del preset en el inspector o girar la luz `Sol` no hacia NADA
## hasta que se corriera el juego — que era justo lo que se noto (:v
##
## No se suscribe a `Resource.changed` porque un Resource corriente no lo emite
## al asignarle propiedades desde el inspector. En su lugar se compara una
## firma barata y se reaplica SOLO cuando algo ha cambiado de verdad, para no
## tocar nodos ni recursos en los miles de frames en los que no pasa nada.
func _refrescar_editor(delta: float) -> void:
	_t_refresco += delta
	if _t_refresco < REFREJO_EDITOR:
		return
	_t_refresco = 0.0
	if preset == null:
		return
	var firma := _firma_editor()
	# Si la firma sale VACIA es que el filtro de propiedades ha vuelto a fallar
	# (YA PASO UNA VEZ: se filtro por `PROPERTY_USAGE_SCRIPT_VARIABLE` y en
	# Godot 4.7 da 0 aciertos sobre las exportadas de un Resource, asi que la
	# firma era solo la luz y tocar el preset no movia nada). Ante la duda se
	# re-aplica igual: mejor gastar un poco que dejar el cielo muerto (:v
	if firma == _firma_cache and not firma.is_empty():
		return
	_firma_cache = firma
	_aplicar()


## Propiedades de Resource que NO son datos del preset. Si entran en la firma,
## cualquier cosa que Godot toque del recurso (o una simple reabertura) la
## reescribiria y el refresco se dispararia sin haber cambiado nada.
const _NOS_FIRMA := [
	"script",
	"resource_name",
	"resource_path",
	"resource_local_to_scene",
	"resource_scene_unique_id",
]


## Firma de todo lo que manda sobre el cielo: los valores del preset, las
## propiedades propias de este nodo y la orientacion de la DirectionalLight3D
## del mapa (de donde sale la direccion del sol primario). Si dos ticks seguidos
## dan lo mismo, no hay nada que volver a aplicar.
func _firma_editor() -> String:
	if _nombres_preset.is_empty():
		# FILTRO MEDIDO, no supuesto.
		#
		# El intento natural era `int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE`,
		# pero en Godot 4.7 eso da CERO aciertos sobre las propiedades exportadas
		# de un Resource: `get_property_list()` les pone STORAGE|EDITOR (6) y el
		# flag 4096 no aparece por ningun sitio. Resultado: lista de nombres
		# vacia -> firma de solo la luz -> cambios de preset sin refrescar.
		#
		# `PROPERTY_USAGE_STORAGE` (2) si esta, y ademas es exactamente lo que
		# se escribe en el `.tres`, que es lo que nos interesa seguir. Quedan
		# fuera los cabeceros de grupo/categoria (64/128) y el denylist.
		for p in preset.get_property_list():
			if not (int(p.usage) & PROPERTY_USAGE_STORAGE):
				continue
			var n := String(p.name)
			if n in _NOS_FIRMA or n.begins_with("metadata/"):
				continue
			_nombres_preset.append(n)

	var partes := PackedStringArray()
	for n in _nombres_preset:
		partes.append(n + "=" + str(preset.get(n)))

	# Propiedades de ESTE nodo (rutas, precip_seguir_camara, ...). Van aparte
	# del preset porque son del nodo y no del recurso. SOLO valores que se
	# serializan estable: cualquier Object (`owner`, el propio `preset`, ...)
	# se salta, porque su `str()` no es una forma fiable de comparar y meterlo
	# ahi arriesgaria que la firma cambiara en cada tick.
	for p in get_property_list():
		if not (int(p.usage) & PROPERTY_USAGE_STORAGE):
			continue
		var n := String(p.name)
		if n in _NOS_FIRMA or n.begins_with("metadata/"):
			continue
		var v: Variant = get(n)
		if v is Object:
			continue
		partes.append(n + "=" + str(v))

	_tick_luz += 1
	if _luz_cache == null or not is_instance_valid(_luz_cache) \
			or not _luz_cache.is_inside_tree() or _tick_luz >= 20:
		_tick_luz = 0
		_luz_cache = _buscar_luz_direccional()
	if _luz_cache != null:
		partes.append("luz=" + str(_luz_cache.global_transform.basis.z))

	return ";".join(partes)


func _configurar_precipitacion() -> void:
	_emisor = get_node_or_null(ruta_emisor) as GPUParticles3D
	if _emisor == null:
		return
	var em := _emisor

	# Fuerzo las dos propiedades que deciden el culling, aun en el caso de
	# que alguien las toque en el editor: si `local_coords` se quedara en
	# true, todo el cielo de gotas se arrastraria con la camara al moverse.
	em.local_coords = false
	em.visibility_aabb = AABB(
		Vector3(-PRECIP_ANCHO, -PRECIP_ALTO - PRECIP_CAIDA, -PRECIP_ANCHO),
		Vector3(PRECIP_ANCHO * 2.0, PRECIP_ALTO * 2.0 + PRECIP_CAIDA, PRECIP_ANCHO * 2.0)
	)

	# El volumen de emision se fija AQUI y no en el editor: tiene que casar
	# con el `visibility_aabb` de arriba, y si cambian las constantes el
	# editor no se entera de nada.
	var pm := em.process_material as ParticleProcessMaterial
	if pm != null:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(PRECIP_ANCHO, PRECIP_ALTO, PRECIP_ANCHO)
		pm.color = preset.precipitacion_color

	var llueve := preset.precipitacion != AtmosferaPreset.Precipitacion.NINGUNA
	em.emitting = llueve
	em.visible = llueve
	if not llueve:
		return

	# `amount` no admite 0.
	#
	# La base era 2000 y con `precipitacion_intensidad` en el tope salian 8000
	# particulas repartidas por un volumen de 30x40x30 m: o sea, QUINCE
	# churretes en pantalla para una tormenta pesada. Medido en captura. La
	# base subio a 5000.
	#
	# El NIVEL (Suave/Moderada/Fuerte) escala esa base y la intensidad es el
	# ajuste fino por encima. Los factores estan elegidos para que FUERTE con
	# la intensidad de la petrolera (3.6) siga dando las 18000 particulas ya
	# validadas: no se mueve lo que ya funciona (:v
	var factor_nivel := 1.0
	match preset.precipitacion_nivel:
		AtmosferaPreset.NivelLluvia.SUAVE:
			factor_nivel = 0.35
		AtmosferaPreset.NivelLluvia.MODERADA:
			factor_nivel = 0.65
		AtmosferaPreset.NivelLluvia.FUERTE:
			factor_nivel = 1.0
	em.amount = maxi(1, int(round(5000.0 * preset.precipitacion_intensidad * factor_nivel)))
	em.speed_scale = 1.0
	# Al activar la lluvia de golpe no hay que esperar `lifetime` a que el
	# volumen se llene: `preprocess` simula eso por delante.
	em.preprocess = em.lifetime

	if pm == null:
		push_warning("[atmosfera] el emisor de precipitacion no tiene process_material.")
		return

	# Cada tipo cae distinto, y es la GRAVEDAD la que manda en como se lee:
	# la gota acelera y se alinea con su velocidad -> rayada; la nieve casi
	# no cae y se revolotea. `turbulence` solo para nieve, para la lluvia
	# estaria moviendo las gotas de lado.
	#
	# El align de gota/granizo es Z_BILLBOARD + Y_TO_VELOCITY, no el
	# Y_TO_VELOCITY a secas: alineando solo la Y, el quad mira a donde le da
	# y de canto queda DE CANTO, invisible. El billboard le da la cara a la
	# camara y el Y a la velocidad le pone la rayada (:v
	match preset.precipitacion:
		AtmosferaPreset.Precipitacion.LLUVIA:
			em.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY

			# VIENTO: inclina la caida. Sin esto la gota va a plomo y una
			# tormenta pesada se lee como un grifo abierto, no como temporal.
			# La inclinacion se mete en la VELOCIDAD y no en una rotacion,
			# porque el modo de alineado de arriba alinea la gota con SU
			# velocidad — inclinar la velocidad incluye el churrete (:v
			var v: float = clampf(preset.precipitacion_viento, 0.0, 1.0)
			# La gravedad se afloja al inclinar: con la misma gravedad y mas
			# velocidad horizontal la trayectoria se queda casi vertical y el
			# viento no se llega a ver.
			pm.gravity = Vector3(0.0, -30.0, 0.0).lerp(Vector3(0.0, -16.0, 0.0), v)
			pm.direction = Vector3(v * 0.9, -1.0, v * 0.35).normalized()
			pm.spread = 8.0 * v
			var vel: float = preset.precipitacion_velocidad
			pm.initial_velocity_min = lerpf(vel * 0.6, vel * 1.15, v)
			pm.initial_velocity_max = lerpf(vel, vel * 1.75, v)

			# Escala de la gota. A 1.0 el quad de 0.6 m salia mas largo que una
			# barandilla cuando la gota cae pegada a la camara, y se leia como
			# astilla flotando en vez de lluvia. Medido en captura, no supuesto.
			pm.scale_min = 0.45
			pm.scale_max = 0.62
			pm.turbulence_enabled = false
		AtmosferaPreset.Precipitacion.GRANIZO:
			em.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
			pm.gravity = Vector3(0.0, -55.0, 0.0)
			pm.initial_velocity_min = preset.precipitacion_velocidad
			pm.initial_velocity_max = preset.precipitacion_velocidad * 1.6
			pm.scale_min = 1.5
			pm.scale_max = 2.5
			pm.turbulence_enabled = false
		AtmosferaPreset.Precipitacion.NIEVE:
			em.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
			pm.gravity = Vector3(0.0, -3.0, 0.0)
			pm.initial_velocity_min = preset.precipitacion_velocidad * 0.15
			pm.initial_velocity_max = preset.precipitacion_velocidad * 0.35
			pm.scale_min = 2.0
			pm.scale_max = 3.5
			pm.turbulence_enabled = true
			# `turbulence_influence` es Vector2 (min, max), no float.
			pm.turbulence_influence = Vector2(0.2, 0.5)


# ---------------------------------------------------------------------------
#  Sonido de clima (lluvia; el viento entrara con el MISMO sistema)
# ---------------------------------------------------------------------------
## Monta el sonido de clima. Lluvia y viento usan EXACTAMENTE el mismo
## mecanismo: un soundscape por sonido, una capa por .ogg donde el INDICE es
## el nivel, cada uno en su propio `AmbienteAudio` con `grupo = "clima"` —
## mismo bus maestro, asi que se apilan sin cortarse (patron ya validado en la
## demo de audio con la tormenta sobre el mapa). Anadir otro sonido de clima
## consiste en llamar otra vez al constructor (:v)
##
## Van en NODOS DISTINTOS y no en uno solo porque `AmbienteAudio.nivel` es un
## valor UNICO por instancia: con un solo nodo no se podria tener lluvia fuerte
## con viento suave, que es lo normal en la vida real.
##
## Los soundscapes se construyen EN CODIGO y no como `.tres`: los .ogg y su
## `nivel_min` estan aqui, asi el preset sigue siendo la unica fuente de verdad
## de los niveles. Mismo criterio que `Relampago` montando sus nodos.
##
## Idempotente como `_aplicar`: si ya existen solo se reajustan niveles y
## volumentes; destruirlos cada vez romperia los fades y creceria/bus libre.
func _configurar_clima_audio() -> void:
	if Engine.is_editor_hint():
		return

	# ---- Lluvia -----------------------------------------------------------
	if _scape_lluvia == null:
		_scape_lluvia = _construir_scape_por_nivel(
				"lluvia", RUTAS_LLUVIA, preset.lluvia_volumen_db)
		if not _scape_lluvia.capas.is_empty():
			_audio_lluvia = _montar_audio_clima("ClimaLluvia", _scape_lluvia)
	_ajustar_audio_clima(
			_audio_lluvia, _scape_lluvia,
			preset.precipitacion_nivel, preset.lluvia_volumen_db,
			preset.clima_sonido
			and preset.precipitacion != AtmosferaPreset.Precipitacion.NINGUNA)

	# ---- Viento: identico ---------------------------------------------------
	if _scape_viento == null:
		_scape_viento = _construir_scape_por_nivel(
				"viento", RUTAS_VIENTO, preset.viento_volumen_db)
		if not _scape_viento.capas.is_empty():
			_audio_viento = _montar_audio_clima("ClimaViento", _scape_viento)
	_ajustar_audio_clima(
			_audio_viento, _scape_viento,
			preset.viento_nivel, preset.viento_volumen_db,
			preset.clima_sonido and preset.viento_activo)


func _montar_audio_clima(nodo: String, scape: SoundScape) -> AmbienteAudio:
	var a := AmbienteAudio.new()
	a.name = nodo
	a.grupo = "clima"
	# Sin zonas: lluvia y viento se oyen en TODO el mapa, no en una region.
	a.mostrar_gizmos = false
	add_child(a)
	var glo: Array[SoundScape] = [scape]
	a.globales = glo
	return a


## Nivel, volumen y encendido de un AmbienteAudio de clima ya montado.
func _ajustar_audio_clima(
		a: AmbienteAudio,
		scape: SoundScape,
		nivel: int,
		vol_db: float,
		encendido: bool
) -> void:
	if a == null or scape == null:
		return
	# El volumen de CADA sonido vive en su capa y no en el maestro del nodo:
	# con un unico `volumen_db` no se podria subir la lluvia sin subir el
	# viento. El maestro se queda a 0 y sirve de corte de emergencia (:v
	for c in scape.capas:
		c.volumen_base = vol_db
	a.volumen_db = 0.0
	a.nivel = clampi(nivel, 0, 2)
	# Con intensidad 0 las capas se van con SU fade_out en vez de destruir el
	# nodo: recrearlo al tocar el preset meteria un chasquido y dejaria los
	# buses creciendo y liberandose.
	a.set_intensidad(1.0 if encendido else 0.0)


## Un soundscape de N capas donde el INDICE de cada .ogg ES su nivel :v
##
## `nivel_min = i` hace que capa1 suene desde el nivel 0, capa2 desde el 1 y
## capa3 desde el 2 — asi subir de "suave" a "fuerte" se oye como capas que se
## ANADEN y no como un volumen que sube de golpe. Funciona igual para lluvia,
## viento o lo que sea: es el sistema, no la lluvia.
func _construir_scape_por_nivel(
		nombre: String,
		rutas: Array,
		vol_db: float
) -> SoundScape:
	var scape := SoundScape.new()
	scape.nombre = nombre
	for i in rutas.size():
		var st := load(String(rutas[i])) as AudioStream
		if st == null:
			push_warning("[atmosfera] no se pudo cargar " + String(rutas[i]))
			continue
		var capa := SoundCapa.new()
		capa.nombre = "%s_capa%d" % [nombre, i + 1]
		# Literal tipado: asignar `[st]` a `Array[AudioStream]` directamente
		# puede caer a un Array sin tipo y quedar VACIO en silencio — la misma
		# trampa que ya dejo notas el sistema de audio (:v
		var pistas: Array[AudioStream] = [st]
		capa.streams = pistas
		capa.nivel_min = i
		capa.nivel_max = -1
		capa.volumen_base = vol_db
		# Tardas en entrar para que el cambio de nivel se note como un
		# ENCAJE de capas, no como un corte.
		capa.fade_in = 1.6
		capa.fade_out = 2.4
		scape.capas.append(capa)
	if scape.capas.is_empty():
		push_warning("[atmosfera] ninguna capa cargada para '%s': sin sonido." % nombre)
	return scape


# ---------------------------------------------------------------------------
#  Rayos
# ---------------------------------------------------------------------------
## Monta `Relampago` si el preset lo pide.
##
## SOLO en runtime. En el editor no se crea ni un nodo: por eso abrir
## `atmosfera.tscn` no deja nunca rastro de tormenta en el fichero. Es
## idempotente como `_aplicar` — si el nodo ya existe se re-configura y no se
## monta un segundo por cada refresco del editor (:v
func _configurar_rayos() -> void:
	if Engine.is_editor_hint():
		return

	var viejo := get_node_or_null(RUTA_RAYOS) as Relampago
	if not preset.rayos_activos:
		if viejo != null:
			viejo.queue_free()
		_relampago = null
		return

	if viejo == null:
		viejo = Relampago.new()
		viejo.name = "Relampago"
		# Sin `owner`: si lo llevara, el nodo se escribiria en el `.tscn` al
		# guardar y dejaria de ser un hijo de runtime.
		add_child(viejo)

	_relampago = viejo
	_relampago.preset = preset
	_relampago.configurar(preset, _mat, _env)


# ---------------------------------------------------------------------------
#  Helpers de uniforms
#
# `get_shader_parameter` devuelve null si la clave no existe, y asignar un
# uniform inexistente empuja un ERROR POR FRAME en consola. Por eso cada
# empujone comprueba que el shader realmente lo declara (:v
# ---------------------------------------------------------------------------
func _c(m: ShaderMaterial, nombre: String, valor: Color) -> void:
	if _tiene(m, nombre):
		m.set_shader_parameter(nombre, valor)


func _f(m: ShaderMaterial, nombre: String, valor: float) -> void:
	if _tiene(m, nombre):
		m.set_shader_parameter(nombre, valor)


## Los uniforms `int` no aceptan un float de paso: `nubes_capas` esta
## declarado como `int` porque se compara en el shader, y empujarle un 2.0
## no hace lo que parece (:v
func _i(m: ShaderMaterial, nombre: String, valor: int) -> void:
	if _tiene(m, nombre):
		m.set_shader_parameter(nombre, valor)


func _v3(m: ShaderMaterial, nombre: String, valor: Vector3) -> void:
	if _tiene(m, nombre):
		m.set_shader_parameter(nombre, valor)


var _cache_uniforms: Dictionary = {}


func _tiene(m: ShaderMaterial, nombre: String) -> bool:
	var clave: String = m.shader.resource_path if m.shader != null else "?"
	if not _cache_uniforms.has(clave):
		var set := {}
		if m.shader != null:
			for p in m.shader.get_shader_uniform_list():
				set[String(p.name)] = true
		_cache_uniforms[clave] = set
	var set_nom: Dictionary = _cache_uniforms[clave]
	if not set_nom.has(nombre):
		push_warning("[atmosfera] el shader no declara el uniform '%s'." % nombre)
		return false
	return true
