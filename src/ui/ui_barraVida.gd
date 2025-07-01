# Player.gd
extends CharacterBody3D

var max_health := 100
var current_health := 100

@onready var blood_overlay := $"../CanvasLayer/BloodOverlay"

func take_damage(amount: int):
	current_health -= amount
	current_health = clamp(current_health, 0, max_health)
	update_blood_overlay()
	
func heal(amount: int):
	current_health += amount
	current_health = clamp(current_health, 0, max_health)
	update_blood_overlay()

func update_blood_overlay():
	var health_ratio = float(current_health) / float(max_health)

	# Ocultar todas primero
	for blood in blood_overlay.get_children():
		blood.visible = false

	if health_ratio < 0.3:
		blood_overlay.get_node("Blood3").visible = true
	elif health_ratio < 0.6:
		blood_overlay.get_node("Blood2").visible = true
	elif health_ratio < 0.9:
		blood_overlay.get_node("Blood1").visible = true
