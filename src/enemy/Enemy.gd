extends CharacterBody3D


const SPEED = 2.0


@onready var navigation: NavigationAgent3D = $NavigationAgent3D


# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")


func hear(sound: SoundArea):
	navigation.target_position = sound.global_position


func _physics_process(delta):
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	move()
	move_and_slide()


func move():
	if navigation.is_navigation_finished():
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		return

	var direction = global_position.direction_to(navigation.get_next_path_position())
	direction = (direction * Vector3(1, 0, 1)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		basis = Basis.looking_at(direction)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
