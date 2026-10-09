class_name WaterVolume
extends Area3D
## Volumen de agua jugable: decide DONDE hay agua, con que densidad y con que
## corriente. :v
##
## El TOPE no lo pone el shape sino el WaterSurface (olas + marea), asi que la
## caja se autorrelic hasta POR ENCIMA de la cresta maxima (marea + swell) y el
## punto de arriba lo resuelve la superficie. Si no hay WaterSurface, el tope
## de la caja es el nivel, estatico. :v
##
## Sigue el patron de SoundArea (capa propia + duck-typing), pero con
## monitoring persistente: aqui no hay one-shot, el volumen vive todo el mapa.
## El test es ANALITICO (WaterShapeTest), no por overlap, para que un punto
## suelto —la cabeza de un personaje, una sonda de un cajon— pueda preguntar
## "¿hay agua aqui?" sin montar un Area3D por cuerpo. :v

## Bit de capa 3d_physics que ocupan los volumenes de agua. Ocupar capa propia
## deja que la camara u otros sistemas detecten "esto es agua" por overlap. :v
const CAPA: int = 9

@export_group("Fluido")
## Densidad del fluido en kg/m3. 1000 = agua dulce; el petroleo va por debajo.
@export_range(50.0, 2000.0, 1.0) var densidad := 1000.0
## Velocidad de la corriente en m/s (espacio de mundo). El arrastre arrastra
## hacia ESTE vector, no lo suma: es la velocidad del fluido, no un empujon. :v
@export var corriente := Vector3.ZERO

@export_group("Superficie")
## WaterSurface que da la altura. Vacio = primer nodo del grupo
## `water_surface` de la escena (asi un solo nodo manda para todo el mapa). :v
@export var superficie: NodePath
## true = el shape solo da XZ + fondo y la tapa la pone la superficie.
@export var abierto_arriba := true

static var _registro: Array[WaterVolume] = []

var _sup: WaterSurface
var _tope_estatico: float = 0.0
var _formas: Array[CollisionShape3D] = []


## Registro estatico de los volumenes vivos. WaterQuery itera esto: sin
## registro habria que barrer el arbol de la escena por cada punto. :v
static func registro() -> Array[WaterVolume]:
	return _registro


func _enter_tree() -> void:
	_registro.append(self)


func _exit_tree() -> void:
	_registro.erase(self)


func _ready() -> void:
	# Capa propia, sin monitor: nadie hace overlap contra nosotros, el test es
	# por punto. monitorable=true por si la camara quiere "¿estoy dentro?". :v
	collision_layer = 0
	collision_mask = 0
	set_collision_layer_value(CAPA, true)
	monitoring = false
	monitorable = true
	recargar_formas()
	if abierto_arriba and not WaterShapeTest.soporta_abierto(_formas[0] if _formas.size() > 0 else null):
		push_warning("[water] %s: la forma no soporta modo abierto (usa BoxShape); \
el tope del agua quedara clavado en el shape." % name)


## Vuelve a leer las CollisionShape3D hijas. Llamar si se anaden shapes en
## runtime (generacion procedural de niveles). :v
func recargar_formas() -> void:
	_formas.clear()
	for h in get_children():
		var cs := h as CollisionShape3D
		if cs != null:
			_formas.append(cs)
	_tope_estatico = _calcular_tope_estatico()


## Altura de la superficie del agua en el punto `p` (Y de mundo). :v
func nivel_agua_en(p: Vector3) -> float:
	var sup := _superficie()
	if sup != null:
		return sup.altura_en(p)
	return _tope_estatico


## ¿El punto esta dentro del volumen de agua? — XZ + fondo, y ademas bajo la
## superficie. Es LA pregunta que hace WaterQuery. :v
func contiene(p: Vector3) -> bool:
	if p.y > nivel_agua_en(p):
		return false
	var abierto := abierto_arriba and _superficie() != null
	for cs in _formas:
		if WaterShapeTest.contiene(cs, cs.to_local(p), abierto):
			return true
	return false


## Misma prueba ignorando la superficie: sirve para dibujar el volumen en el
## editor o para debug de "dentro de la caja pero sobre el agua". :v
func contiene_forma(p: Vector3) -> bool:
	for cs in _formas:
		if WaterShapeTest.contiene(cs, cs.to_local(p), abierto_arriba):
			return true
	return false


## Lista de shapes (cacheada en _ready). Exposta para que WaterQuery no tenga
## que recorrer hijos en el hot path. :v
func formas() -> Array[CollisionShape3D]:
	return _formas


func _superficie() -> WaterSurface:
	if _sup != null and is_instance_valid(_sup):
		return _sup
	_sup = null
	if not superficie.is_empty():
		_sup = get_node_or_null(superficie) as WaterSurface
	if _sup == null:
		# Sin cache cuando no hay: get_first_node_in_group es una busqueda en
		# hash, no un barrido de arbol, y asi un WaterSurface que llegue
		# tarde (carga async) se coge sin reiniciar el nivel. :v
		_sup = get_tree().get_first_node_in_group("water_surface") as WaterSurface
	return _sup


## Nivel sin superficie asociada: la tapa del AABB global de las formas. :v
func _calcular_tope_estatico() -> float:
	var tope := global_position.y
	for cs in _formas:
		if cs.shape == null:
			continue
		var laabb := WaterShapeTest.aabb_de(cs.shape)
		for i in 8:
			tope = maxf(tope, (cs.global_transform * laabb.get_endpoint(i)).y)
	return tope
