# MenuAudioManager.gd
# Script singleton para manejar todos los sonidos del menú
# Proporciona una interfaz centralizada para reproducir sonidos de UI

extends Node

# === REFERENCIAS A NODOS DE AUDIO ===
var ui_sounds: AudioStreamPlayer
var ambient_audio: AudioStreamPlayer
var breath_audio: AudioStreamPlayer

# === RECURSOS DE AUDIO PRECARGADOS ===
# Precargar los recursos mejora el rendimiento
var click_sound: AudioStream
var hover_sound: AudioStream  
var transition_sound: AudioStream

# === CONFIGURACIÓN DE VOLÚMENES ===
var click_volume: float = -8.0      # dB
var hover_volume: float = -12.0     # dB  
var transition_volume: float = -6.0 # dB

# === FUNCIÓN DE INICIALIZACIÓN ===
func _ready():
	print("🎵 Inicializando MenuAudioManager...")
	load_audio_resources()

# Cargar todos los recursos de audio
func load_audio_resources():
	print("🎵 Cargando recursos de audio del menú...")
	
	# Cargar sonidos del menú
	click_sound = load("res://audio/sfx/menu/click.wav")
	hover_sound = load("res://audio/sfx/menu/hover.wav")
	transition_sound = load("res://audio/sfx/menu/transition.wav")
	
	# Verificar que se cargaron correctamente
	if click_sound:
		print("✅ Sonido de click cargado")
	else:
		print("❌ Error cargando sonido de click")
	
	if hover_sound:
		print("✅ Sonido de hover cargado")
	else:
		print("❌ Error cargando sonido de hover")
	
	if transition_sound:
		print("✅ Sonido de transición cargado")
	else:
		print("❌ Error cargando sonido de transición")

# Configurar referencias a los nodos de audio
func setup_audio_nodes(ui_node: AudioStreamPlayer, ambient_node: AudioStreamPlayer, breath_node: AudioStreamPlayer):
	ui_sounds = ui_node
	ambient_audio = ambient_node
	breath_audio = breath_node
	
	print("🎵 Nodos de audio configurados en MenuAudioManager")

# === FUNCIONES PÚBLICAS PARA REPRODUCIR SONIDOS ===

# Reproducir sonido de click
func play_click():
	if ui_sounds and click_sound:
		ui_sounds.stream = click_sound
		ui_sounds.volume_db = click_volume
		ui_sounds.play()
		print("🔊 Reproduciendo sonido de click")
	else:
		print("⚠️ No se puede reproducir click - nodo o sonido faltante")

# Reproducir sonido de hover
func play_hover():
	if ui_sounds and hover_sound:
		ui_sounds.stream = hover_sound
		ui_sounds.volume_db = hover_volume
		ui_sounds.play()
		print("🔊 Reproduciendo sonido de hover")
	else:
		print("⚠️ No se puede reproducir hover - nodo o sonido faltante")

# Reproducir sonido de transición/vibración
func play_transition():
	if ui_sounds and transition_sound:
		ui_sounds.stream = transition_sound
		ui_sounds.volume_db = transition_volume
		ui_sounds.play()
		print("🔊 Reproduciendo sonido de transición")
	else:
		print("⚠️ No se puede reproducir transición - nodo o sonido faltante")

# === FUNCIONES DE CONTROL DE VOLUMEN ===

# Establecer volumen del click
func set_click_volume(volume_db: float):
	click_volume = volume_db
	print("🔊 Volumen de click establecido a: ", volume_db, "dB")

# Establecer volumen del hover
func set_hover_volume(volume_db: float):
	hover_volume = volume_db
	print("🔊 Volumen de hover establecido a: ", volume_db, "dB")

# Establecer volumen de transición
func set_transition_volume(volume_db: float):
	transition_volume = volume_db
	print("🔊 Volumen de transición establecido a: ", volume_db, "dB")

# === FUNCIONES DE UTILIDAD ===

# Detener todos los sonidos de UI
func stop_all_ui_sounds():
	if ui_sounds:
		ui_sounds.stop()
		print("🔇 Todos los sonidos de UI detenidos")

# Verificar si hay sonidos reproduciéndose
func is_playing() -> bool:
	if ui_sounds:
		return ui_sounds.playing
	return false

# Obtener información del estado actual
func get_audio_status() -> Dictionary:
	return {
		"click_loaded": click_sound != null,
		"hover_loaded": hover_sound != null,
		"transition_loaded": transition_sound != null,
		"ui_sounds_ready": ui_sounds != null,
		"is_playing": is_playing()
	} 