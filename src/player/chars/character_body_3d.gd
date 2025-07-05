extends CharacterBody3D

@export var speed := 10.0
@export var mouse_sensitivity := 0.002
@export var jump_velocity := 8.0
@export var crouch_height := 0.5  # Altura de la cámara agachado
@export var normal_height := 1.0  # Altura de la cámara normal
@export var crouch_collider_height := 1.0  # Altura del collider agachado
@export var normal_collider_height := 2.0  # Altura del collider normal

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var camera_pivot: Node3D
var collider: CollisionShape3D

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera_pivot = $CameraPivot
	collider = $CollisionShape3D

func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation_degrees.x = clamp(camera_pivot.rotation_degrees.x, -90, 90)

func _physics_process(delta):
	var input_dir = Vector3.ZERO

	# Movimiento lateral y frontal
	if Input.is_action_pressed("ui_right"):
		input_dir.x += 1
	if Input.is_action_pressed("ui_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("ui_down"):
		input_dir.z += 1
	if Input.is_action_pressed("ui_up"):
		input_dir.z -= 1

	input_dir = input_dir.normalized()
	var direction = (transform.basis * input_dir).normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	# Gravedad
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		# Saltar
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity

	# Agacharse (cámara y colisión)
	if Input.is_action_pressed("crouch"):
		camera_pivot.position.y = crouch_height
		var shape = collider.shape
		if shape is CapsuleShape3D:
			shape.height = crouch_collider_height
	else:
		camera_pivot.position.y = normal_height
		var shape = collider.shape
		if shape is CapsuleShape3D:
			shape.height = normal_collider_height

	# Mover jugador
	move_and_slide()
