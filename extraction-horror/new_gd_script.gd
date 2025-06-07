extends CharacterBody3D

@export var speed := 5.0

var direction := Vector3.ZERO

func _process(_delta):
	direction = Vector3.ZERO

	if Input.is_action_pressed("ui_right"):
		direction.x += 1
	if Input.is_action_pressed("ui_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_up"):
		direction.z -= 1
	if Input.is_action_pressed("ui_down"):
		direction.z += 1

	direction = direction.normalized()

func _physics_process(delta):
	var velocity = direction * speed
	velocity.y = self.velocity.y
	self.velocity = velocity
	move_and_slide()
