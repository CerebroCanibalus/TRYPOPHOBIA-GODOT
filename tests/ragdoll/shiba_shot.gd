extends Node3D

## CAPTURAS del Shiba: 1a persona y 3a persona, con la cabeza girada.
## Uso: Godot --path <proj> res://tests/ragdoll/shiba_shot.tscn
##      (sin --headless para que renderice de verdad)

@export var ruta_salida := "user://shiba_shot.png"

@onready var shiba: Node3D = $Shiba

var _t := 0.0
var _fase := 0
var _capturas := 0


func _ready() -> void:
	print("[shot] listo")
	get_window().grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_t += delta
	var cam := shiba.get_node_or_null("CameraPivot") as Node3D
	if cam == null:
		return

	match _fase:
		0:
			# 1a persona: el personaje se queda quieto y mira alrededor.
			if _t > 1.2:
				_fase = 1
				cam.rotation_degrees.y = -35.0
				cam.rotation_degrees.x = -12.0
				print("[shot] girando la cabeza a la izquierda")
		1:
			if _t > 2.2:
				_fase = 2
				_capturar("1persona")
		2:
			if _t > 2.6:
				_fase = 3
				cam.call("toggle_third_person")
				print("[shot] modo 3a persona")
		3:
			if _t > 4.0:
				_fase = 4
				_capturar("3persona")
		4:
			if _t > 4.4:
				_fase = 5
				# Caminar para ver el ciclo de paseo.
				Input.action_press("move_forward")
		5:
			if _t > 6.0:
				_fase = 6
				Input.action_release("move_forward")
				_capturar("caminando")
		6:
			if _t > 6.4:
				get_tree().quit()


func _capturar(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var ruta := "res://tests/ragdoll/shots/shiba_%s.png" % nombre
	DirAccess.make_dir_recursive_absolute("res://tests/ragdoll/shots")
	var err := img.save_png(ruta)
	print("[shot] ", nombre, " -> ", ruta, " err=", err, " (", img.get_width(), "x", img.get_height(), ")")
	_capturas += 1
