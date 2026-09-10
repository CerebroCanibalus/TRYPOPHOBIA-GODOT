## Cámara de control libre para el benchmark.
## Click derecho + mover mouse para mirar.
## WASD para moverse, Q/E para subir/bajar.
extends Camera3D

@export var move_speed: float = 15.0
@export var mouse_sensitivity: float = 0.003
@export var fast_multiplier: float = 3.0

var _yaw: float = 0.0
var _pitch: float = 0.0
var _captured: bool = false


func _ready() -> void:
	# Inicializar rotación desde la transform actual
	var t := transform.basis
	var euler := t.get_euler()
	_yaw = euler.y
	_pitch = euler.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _captured:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clamp(_pitch, -1.4, 1.4)
		_update_rotation()
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_captured = event.pressed
			if _captured:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			_captured = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0
	if Input.is_key_pressed(KEY_Q):
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_E):
		input_dir.y += 1.0

	if input_dir == Vector3.ZERO:
		return

	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fast_multiplier

	# Transformar input local a global según yaw
	var forward := -Vector3(sin(_yaw), 0.0, cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var move := (forward * -input_dir.z) + (right * input_dir.x)
	move.y = input_dir.y

	global_position += move.normalized() * speed * delta


func _update_rotation() -> void:
	var rot_y := Basis(Vector3.UP, _yaw)
	var rot_x := Basis(Vector3.RIGHT, _pitch)
	transform.basis = rot_y * rot_x