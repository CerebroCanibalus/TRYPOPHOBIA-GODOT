extends CharacterBody3D

@export var speed := 10.0
@export var mouse_sensitivity := 0.002
@export var jump_velocity := 8.0
@export var crouch_height := 0.5  # Altura de la cámara agachado
@export var normal_height := 1.0  # Altura de la cámara normal
@export var crouch_collider_height := 1.0  # Altura del collider agachado
@export var normal_collider_height := 2.0  # Altura del collider normal

# Camara e interacciones putita

@export_group("Camera")
@export var mouseSens = Vector2(0.2, 0.2)
@onready var camera = $Camera3D

@export_category("Holding Objects")
@export var throwForce = 7.5
@export var followSpeed = 5.0
@export var followDistance = 2.5
@export var maxDistanceFromCamera = 5.0
@export var dropBelowPlayer = false
@export var groundRay: RayCast3D # Only needed if dropBelowPlayer is true

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var camera_pivot: Node3D
var collider: CollisionShape3D

#Declaro acá objetos agarrados con el raycast para interactuar
@onready var interactRay = $Camera3D/InteractRay
var heldObject: RigidBody3D

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
	#Agarre de objetos
	handle_holding_objects()
	
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
	
		# Mover jugador
	move_and_slide()

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
	
func set_held_object(body: RigidBody3D):
	if body is RigidBody3D:
		heldObject = body

func drop_held_object():
	heldObject = null
	
func throw_held_object():
	var obj = heldObject
	drop_held_object()
	obj.apply_central_impulse(-camera.global_basis.z * throwForce * 10)
	
func handle_holding_objects():
	# Throwing Objects
	if Input.is_action_just_pressed("throw"):
		if heldObject != null: throw_held_object()
		
	# Dropping Objects
	if Input.is_action_just_pressed("interact"):
		if heldObject != null: drop_held_object()
		elif interactRay.is_colliding(): set_held_object(interactRay.get_collider())
		
	# Object Following
	if heldObject != null:
		var targetPos = camera.global_transform.origin + (camera.global_basis * Vector3(0, 0, -followDistance)) # 2.5 units in front of camera
		var objectPos = heldObject.global_transform.origin # Held object position
		heldObject.linear_velocity = (targetPos - objectPos) * followSpeed # Our desired position
		
		# Drop the object if it's too far away from the camera
		if heldObject.global_position.distance_to(camera.global_position) > maxDistanceFromCamera:
			drop_held_object()
			
		# Drop the object if the player is standing on it (must enable dropBelowPlayer and set a groundRay/RayCast3D below the player)
		if dropBelowPlayer && groundRay.is_colliding():
			if groundRay.get_collider() == heldObject: drop_held_object()
#https://github.com/sventomasek/Godot-Scripts/blob/main/Player3D.gd Código para intentar añadir interacciones físicas.
