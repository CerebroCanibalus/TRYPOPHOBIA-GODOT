class_name Player extends CharacterBody3D


const SPEED = 3.0
const RUN_SPEED = 6.0
const MAX_RUN_ANGLE = deg_to_rad(50)
const MOUSE_SPEED = 0.002

const ANIM_WALK_AMOUNT = { stand = 0.0, walk = 0.4, run = 1.7 }
const ANIM_WALK_SPEED  = { stand = 0.0, walk = 0.7, run = 1.5 }

const THROW_SPEED = 8

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")


@onready var camera_position: Node3D = $CameraPosition
@onready var interactor: RayCast3D = $CameraPosition/Interactor
@onready var item_ray: RayCast3D = $%ItemRay
@onready var item_transform: RemoteTransform3D = $%ItemRay/ItemTransform
@onready var flashlight: Node3D = $%Flashlight
@onready var flashlight_ray: RayCast3D = $CameraPosition/FlashlightRay
@onready var hands_animation: AnimationTree = $%HandsAnimation


@export var distraction_sound_scene: PackedScene


var held_item: Item = null
var held_item_position: Vector3 = Vector3.ZERO
var held_item_velocity: Vector3 = Vector3.ZERO

var hand_animation_tween: Tween = null

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta):
	if is_instance_valid(held_item):
		var current_position := held_item.global_position
		held_item_velocity = ((current_position - held_item_position) / delta).limit_length(velocity.length())
		held_item_position = held_item.global_position
	
		if item_ray.is_colliding():
			item_transform.global_position = item_ray.get_collision_point()
		else:
			item_transform.global_position = item_ray.to_global(item_ray.target_position)

	if flashlight_ray.is_colliding():
		flashlight.basis = Basis.looking_at(lerp(-flashlight.basis.z, flashlight.to_local(flashlight_ray.get_collision_point()).normalized(), delta))

	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Get the input direction and handle the movement/deceleration.
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		if Input.is_action_pressed("run") and abs(input_dir.rotated(TAU/4).angle()) < MAX_RUN_ANGLE:
			velocity.x = direction.x * RUN_SPEED
			velocity.z = direction.z * RUN_SPEED
			set_hands_anim("run", delta)
		else:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
			set_hands_anim("walk", delta)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		set_hands_anim("stand", delta)

	move_and_slide()


func set_hands_anim(anim, delta):
	hands_animation.set(
		"parameters/walking/add_amount",
		lerp(
			float(hands_animation.get("parameters/walking/add_amount")),
			ANIM_WALK_AMOUNT[anim],
			20 * delta
		)
	)
	hands_animation.set(
		"parameters/speed/scale",
		lerp(
			float(hands_animation.get("parameters/speed/scale")),
			ANIM_WALK_SPEED[anim],
			20 * delta
		)
	)


func _unhandled_input(event):
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SPEED)
		camera_position.rotation.x = clamp(
			camera_position.rotation.x - event.relative.y * MOUSE_SPEED,
			-TAU/4,
			TAU/4
		)
	# 	$%Flashlight.horizontal += event.relative.x * MOUSE_SPEED

	if event.is_action_pressed("distract"):
		var distraction_sound = distraction_sound_scene.instantiate()
		add_child(distraction_sound)

	if event.is_action_pressed("interact"):
		interact()

	if event.is_action_pressed("drop"):
		drop()

	if event.is_action_pressed("throw"):
		throw()


func interact():
	var interactable = interactor.get_collider()
	if interactable and interactable.has_method("interact"):
		interactable.interact(self)


func pick_up(item: Item):
	if held_item: return
	held_item = item
	hands_animation.set("parameters/grab/request", 1)


func on_pickup_animation():
	held_item.freeze = true
	item_transform.remote_path = item_transform.get_path_to(held_item)


func drop():
	if not held_item: return
	held_item.freeze = false
	item_transform.remote_path = NodePath("")
	held_item.linear_velocity = held_item_velocity
	held_item = null


func throw():
	if not held_item: return
	held_item.freeze = false
	item_transform.remote_path = NodePath("")
	var throw_direction = -camera_position.global_basis.z.normalized()
	held_item.linear_velocity = held_item_velocity
	held_item.linear_velocity += throw_direction * THROW_SPEED
	held_item = null
