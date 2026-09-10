extends RayCast3D
## EL PUNTERO: un rayo desde el centro de la camara que fija DONDE van a actuar
## las manos del jugador.
##
## El rayo NO agarra nada: solo APUNTA. La interaccion exige CONTACTO de la mano
## (decision del General, 2026-09-10). Este nodo:
##   1. lanza el rayo desde el centro de la camara,
##   2. coloca el `Pointer` (destino 3D que perseguiran las manos) en el impacto,
##   3. actualiza el reticle 2D con el estado.
##
## El alcance es CORTO a proposito: si el brazo no llega, la mano no toca y no
## hay interaccion. Por eso el reticle solo se ilumina con cosas alcanzables.

const ReticleScript = preload("res://src/ragdoll_character/pointer_reticle.gd")

## Distancia maxima del rayo (m). Mantenerla cerca del alcance REAL del brazo:
## mas alla, el reticle prometeria objetivos que la mano nunca puede tocar.
@export var interact_range := 0.9
## Destino 3D de las manos (invisible por ahora: es DATA, no decoracion).
## Si queda null se busca "Pointer" en la raiz de la escena.
@export var pointer: Node3D
## Reticle 2D. Si queda null se busca "Reticle" en la raiz de la escena.
@export var reticle: Control

var has_target := false

var _initialized := false


func _ready() -> void:
	target_position = Vector3(0.0, 0.0, -interact_range)
	enabled = true
	_resolve_refs()
	_exclude_own_body()
	_initialized = true


## El ragdoll puede estar INSTANCIADO dentro de otra escena, asi que la raiz no
## es "subir hasta el padre null": es el `owner` (la raiz de la escena instanciada).
func _scene_root() -> Node:
	if owner != null:
		return owner
	var node: Node = self
	while node.get_parent() != null:
		node = node.get_parent()
	return node


func _resolve_refs() -> void:
	var root := _scene_root()
	if root == null:
		return
	if pointer == null:
		pointer = root.get_node_or_null("Pointer") as Node3D
	if reticle == null:
		reticle = root.find_child("Reticle", true, false) as Control


## El rayo nace DENTRO del propio personaje: sin excluir sus huesos, el reticle
## marcaria "objetivo" sobre los brazos del jugador todos los frames.
func _exclude_own_body() -> void:
	var root := _scene_root()
	if root == null:
		return
	for b in root.find_children("*", "PhysicalBone3D", true, false):
		add_exception_rid((b as CollisionObject3D).get_rid())


func _physics_process(_delta: float) -> void:
	if not _initialized:
		return
	target_position = Vector3(0.0, 0.0, -interact_range)

	# Punto por defecto: el final del alcance, para que las manos apunten
	# adelante sin estirarse cuando no hay nada que tocar.
	var point := global_position - global_transform.basis.z * interact_range
	has_target = false
	if is_colliding() and get_collider() is PhysicsBody3D:
		point = get_collision_point()
		has_target = true

	if pointer != null:
		pointer.global_position = point
	# El IK de brazos vive en el ragdoll. Duck typing (has_method) para no acoplar
	# los scripts: el puntero solo avisa donde esta el objetivo.
	var root := _scene_root()
	if root != null and root.has_method("update_hand_targets"):
		root.update_hand_targets(point, has_target)
	if reticle != null:
		# Object.set() en vez de `reticle.state = ...`: el export esta tipado
		# como Control y el analizador no conoce la propiedad `state`.
		reticle.set("state", ReticleScript.State.TARGET if has_target else ReticleScript.State.IDLE)
