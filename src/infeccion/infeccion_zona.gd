class_name InfeccionZona
extends Node3D
## Zona de infeccion — siembra y gestiona parches de plasta. (:v
##
## Es el prefab "arrastrable" del sistema (patron de `src/water/nodos/` y de
## `AmbienteAudio`): se pone uno en el mapa, se elige cuantos parches y que
## tan grande la zona, y en runtime va soltando `Parche` contra la
## superficie que encuentre en la direccion de siembra. (:v
##
## Contrasenas de diseno (Fase 2 — ver `meta/docs/Infeccion_Niebla_Roja.md`):
##  - UN ShaderMaterial por ZONA, compartido por todos sus parches. Los
##    uniforms de reaccion (jugador_pos...) se escriben UNA vez por frame
##    y los leen todos: 50 parches = 1 escritura, no 50. (:v
##  - Siembra ESCALONADA (`parches_por_frame`): cada parche son ~121 raycasts;
##    sembrar 30 de golpe es un hitch medible en el frame de carga. (:v
##  - Hijos generados en runtime SIN `owner` — no se escriben en el .tscn
##    (gotcha ya vivido con AmbienteAudio y Relampago). (:v
##  - La textura se inyecta SIEMPRE en `_bind_material()` con un default:
##    un ShaderMaterial puede quedar sin `shader_parameter/*` y salir negro
##    (gotcha del oceano, medido). (:v

const RUTA_SHADER := "res://src/infeccion/shaders/infeccion_parche.gdshader"
## Placeholder de la Fase 2: celular en grises (la misma que usa el oceano).
## En Fase 5 pasara a `assets/env/textures/infeccion/huecos.png`. (:v
const TEXTURA_HUECOS := "res://assets/env/textures/nature/agua1.png"

@export_group("Siembra")
## Puntos de siembra (no parches validos: si un rayo central no toca nada,
## el parche se descarta y NO se reemplaza — mejor hueco que un quad flotando).
@export var cantidad_parches := 14
## Radio de cada parche en metros (la malla mide 2 x radio).
@export_range(0.3, 3.0, 0.05) var radio_parche := 0.9
## Variacion aleatoria del tamanio por parche, 0..1 (0 = todos iguales).
@export_range(0.0, 1.0, 0.05) var desviacion_tamano := 0.35
## Radio de la zona en metros (los puntos salen en un disco uniforme en el
## plano local XZ de ESTE nodo). Para una pared, gira la zona: su plano XZ
## pasa a ser vertical y su "abajo" local apunta contra la pared. (:v
@export var radio_zona := 6.0
## Longitud del rayo de siembra (centrado en el punto). La mitad hacia cada
## lado de la direccion de siembra: asi el punto puede estar en el VACIO y
## aun asi encontrar la superficie (paredes con el plano de siembra detras). :v
@export var alcance_siembra := 6.0
## Hacia donde se siembra en coordenadas LOCALES (por defecto: abajo).
@export var direccion_siembra := Vector3.DOWN
## Capas de colision que cuenta como "superficie" (1 = Entorno).
@export var capas_siembra := 1
## Parches creados por frame. 1 = muy suave, 4 = rapido. :v
@export var parches_por_frame := 2
## Semilla de la distribucion (0 = aleatoria por partida — mapas distintos
## cada vez). Fija la misma semilla = mismo reparto, para capturas comparables.
@export var semilla := 0

@export_group("Material")
## Material compartido por la zona. null = se crea uno propio en runtime
## (asi la demo no necesita un .tres y los mapas pueden traer el suyo). :v
@export var material_infeccion: ShaderMaterial

var _mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _cola: Array[Dictionary] = []
var _parches: Array[Parche] = []
var descartados := 0


func _ready() -> void:
	_rng.seed = semilla if semilla != 0 else _rng.randi()
	_bind_material()
	_cargar_cola()
	# Grupo para que futuros sistemas (la Colmena del spread, la demo de
	# test) encuentren las zonas sin buscar por nombre. (:v
	add_to_group("infeccion_zona")
	if not _cola.is_empty():
		return
	# Zona vacia: no hay nada que hacer en _process. :v
	set_process(false)


func _process(_delta: float) -> void:
	var hechos := 0
	while not _cola.is_empty() and hechos < parches_por_frame:
		var punto: Dictionary = _cola.pop_front()
		_sembrar_uno(punto)
		hechos += 1
	if _cola.is_empty():
		set_process(false)


## Genera los puntos de siembra (disco uniforme en el plano local XZ). :v
func _cargar_cola() -> void:
	var dir := (global_transform.basis * direccion_siembra).normalized()
	var mitad := alcance_siembra * 0.5
	for i in cantidad_parches:
		# sqrt(rand) da disco UNIFORME; sin el sqrt los parches se apelotonan
		# en el centro y los bordes de la zona quedan vacios. (:v
		var ang := _rng.randf_range(0.0, TAU)
		var rad := sqrt(_rng.randf()) * radio_zona
		var local := Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)
		var mundo := global_transform * local
		_cola.append({
			"desde": mundo - dir * mitad,
			"hasta": mundo + dir * mitad,
			"tamano": radio_parche * (1.0 + _rng.randf_range(-desviacion_tamano, desviacion_tamano)),
		})


## Un intento: rayo central -> si toca, se crea el parche y se conforma. :v
func _sembrar_uno(datos: Dictionary) -> void:
	var consulta := PhysicsRayQueryParameters3D.create(
			datos["desde"] as Vector3, datos["hasta"] as Vector3, capas_siembra)
	var golpe := get_world_3d().direct_space_state.intersect_ray(consulta)
	if golpe.is_empty():
		descartados += 1
		return
	var p := Parche.new()
	# ANTES de entrar al arbol: `sembrar` necesita el space state, que solo
	# existe con el nodo ya colgado. (:v
	add_child(p)
	if not p.sembrar(golpe["position"] as Vector3, golpe["normal"] as Vector3,
			float(datos["tamano"]), capas_siembra):
		p.queue_free()
		descartados += 1
		return
	p.material_override = _mat
	# La constante vive en Parche (es decision del parche): referenciarla
	# con el prefijo de clase, si no, "not declared in the current scope". :v
	p.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if Parche.PROYECTAR_SOMBRA else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_parches.append(p)


## Parches sembrados con exito (los descartados no cuentan). :v
func parches() -> Array[Parche]:
	return _parches


## true cuando la cola de siembra esta vacia (todos sembrados o descartados). :v
func siembra_terminada() -> bool:
	return _cola.is_empty()


## El material compartido de esta zona (el que parches y venas leen). :v
func material_zona() -> ShaderMaterial:
	return _mat


## Monta el material de la zona si no viene de fuera, y le inyecta la
## textura SIEMPRE. Red de seguridad copiada del patron `_bind_material`
## de `ocean.gd`: los `shader_parameter/*` no se persisten bien en los
## `.tres` y un material sin textura sale negro (:v
func _bind_material() -> void:
	if material_infeccion != null:
		_mat = material_infeccion
	else:
		var shader := load(RUTA_SHADER) as Shader
		if shader == null:
			push_error("[infeccion] no existe " + RUTA_SHADER)
			return
		_mat = ShaderMaterial.new()
		_mat.shader = shader
	var tex := load(TEXTURA_HUECOS) as Texture2D
	if tex == null:
		push_warning("[infeccion] no existe " + TEXTURA_HUECOS + ": huecos sin placeholder.")
		return
	if _tiene("textura_huecos"):
		_mat.set_shader_parameter("textura_huecos", tex)

	# TODO lo demas, explicitamente. Los `= vec3(...)` del shader NO bastan
	# como defaults en un material creado en codigo — medido 2026-10-10:
	# con la teoria de albedo blanca los parches salian NEGROS en captura, y
	# al empujar los colores desde aqui dejan de salirlo. Mismo criterio que
	# `_bind_material` de ocean.gd: red de seguridad, no adorno (:v
	_c("color_base", Color(0.86, 0.83, 0.73))
	_c("color_rojo", Color(0.4, 0.04, 0.045))
	_c("color_agujero", Color(0.85, 0.07, 0.05))
	_n("escala_huecos", 0.9)
	_n("umbral_huecos", 0.42)
	_n("intensidad_grumos", 0.05)
	_n("frecuencia_latido", 0.8)
	_n("brillo_mucosa", 0.2)
	_n("intensidad_emision", 1.4)


func _c(nombre: String, valor: Color) -> void:
	if _tiene(nombre):
		_mat.set_shader_parameter(nombre, valor)


func _n(nombre: String, valor: float) -> void:
	if _tiene(nombre):
		_mat.set_shader_parameter(nombre, valor)


## Comprueba que el shader declara el uniform ANTES de empujarlo: empujar uno
## inexistente spamea un ERROR POR FRAME (gotcha del repo, ya vivido). :v
func _tiene(nombre: String) -> bool:
	if _mat == null or _mat.shader == null:
		return false
	for p in _mat.shader.get_shader_uniform_list():
		if String(p.name) == nombre:
			return true
	push_warning("[infeccion] el shader no declara el uniform '%s'." % nombre)
	return false
