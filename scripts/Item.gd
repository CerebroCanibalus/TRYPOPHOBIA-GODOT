class_name Item extends RigidBody3D


const MIN_VELOCITY_FOR_SOUND = 3.0


@export var sound_scene: PackedScene


func _ready():
	body_entered.connect(on_collided)


func on_collided(_body: Node):
	if not sound_scene: return
	if linear_velocity.length() < MIN_VELOCITY_FOR_SOUND: return
	add_child(sound_scene.instantiate())


func interact(player: Player):
	player.pick_up(self)
