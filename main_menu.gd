extends Control

func _ready():
	$PlayButton.pressed.connect(_on_play_pressed)
	$ConfigButton.pressed.connect(_on_config_pressed)

func _on_play_pressed():
	print("Iniciando juego...")
	get_tree().change_scene_to_file("res://scene/world.tscn")  # ← cambia esta ruta si es diferente

func _on_config_pressed():
	print("Abriendo configuración...")
	# Aquí podrías abrir otra escena o mostrar un panel
