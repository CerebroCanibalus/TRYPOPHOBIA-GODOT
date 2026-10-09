class_name AirVolume
extends Area3D
## Zona de AIRE SECO: "aqui NO entra el agua". :v
##
## Es la pieza de las instalaciones sumergidas: una sala, un tunel, una
## burbuja. Un punto dentro de un AirVolume NO cuenta como sumergido aunque
## este por debajo de la superficie y metido en un WaterVolume — WaterQuery
## le da prioridad al aire sobre el agua. :v
##
## La forma aqui SI es cerrada (abierto = false): el techo de la sala es el
## techo del aire, y si te acercas al techo con la cabeza ya no respiras. :v
##
## Mismo esquema que WaterVolume: forma analitica, sin overlap, sin queries.

## Bit de capa 3d_physics que ocupan las bolsas de aire (7 = 64). Separado del
## agua (9) para que un detector por overlap pueda distinguirlas. :v
const CAPA: int = 7

@export_group("Aire")
## false = el volumen esta ahi pero no se puede respirar (gas, niebla roja...).
@export var respirable := true

static var _registro: Array[AirVolume] = []

var _formas: Array[CollisionShape3D] = []


static func registro() -> Array[AirVolume]:
	return _registro


func _enter_tree() -> void:
	_registro.append(self)


func _exit_tree() -> void:
	_registro.erase(self)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	set_collision_layer_value(CAPA, true)
	monitoring = false
	monitorable = true
	recargar_formas()


func recargar_formas() -> void:
	_formas.clear()
	for h in get_children():
		var cs := h as CollisionShape3D
		if cs != null:
			_formas.append(cs)


func formas() -> Array[CollisionShape3D]:
	return _formas


## ¿El punto esta dentro de esta bolsa de aire? Test CERRADO (forma completa). :v
func contiene(p: Vector3) -> bool:
	for cs in _formas:
		if WaterShapeTest.contiene(cs, cs.to_local(p), false):
			return true
	return false
