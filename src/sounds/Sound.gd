@tool
class_name SoundArea extends Area3D


signal played


@export var audio_player: AudioStreamPlayer3D


func _ready():
	if Engine.is_editor_hint():
		monitoring = true
		monitorable = false
		collision_layer = 0
		collision_mask = 0
		set_collision_mask_value(17, true)
		return

	if audio_player:
		audio_player.finished.connect(queue_free)
		audio_player.play()
	else:
		played.connect(queue_free)

	body_entered.connect(on_heard)
	await get_tree().physics_frame
	await get_tree().physics_frame
	body_entered.disconnect(on_heard)
	played.emit()


func on_heard(body):
	if body.has_method("hear"):
		body.hear(self)
