## CameraPivot — Tripofobia
##
## Cámara third-person que sigue a la cabeza del personaje activo.
## Usa SpringArm3D para evitar clipping con el cuerpo físico.
## Hereda el comportamiento del repo de referencia (MIT) con limpieza.

extends Node3D

@export var target_node: Node3D
@export var physical_skel: Skeleton3D
@export_range(0.01, 1.0) var mouse_sensitivity: float = 0.1
@export_range(0.01, 1.0) var follow_smoothing: float = 0.5
@export var clamp_x_degrees: float = 45.0

var mouse_lock: bool = false


func _physics_process(_delta: float) -> void:
	# Excluir todos los PhysicalBone3D del raycast del SpringArm para evitar
	# que la cámara se choque con el cuerpo del personaje.
	for child in physical_skel.get_children():
		if child is PhysicalBone3D:
			$SpringArm3D.add_excluded_object(child.get_rid())

	if target_node != null:
		global_position = global_position.lerp(target_node.global_position, follow_smoothing)


func _input(event: InputEvent) -> void:
	# Mouse lock / unlock (Escape suelta el cursor)
	if Input.is_action_just_pressed("exit_camera"):
		mouse_lock = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		mouse_lock = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Rotación con mouse (solo cuando está locked)
	if event is InputEventMouseMotion and mouse_lock:
		rotation_degrees.y -= mouse_sensitivity * event.relative.x
		rotation_degrees.x -= mouse_sensitivity * event.relative.y
		rotation_degrees.x = clamp(rotation_degrees.x, -clamp_x_degrees, clamp_x_degrees)
