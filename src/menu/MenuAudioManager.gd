# === GESTOR DE AUDIO DEL MENÚ ===
# Responsable de manejar todos los efectos de sonido y audio del menú principal
extends Node

# === SEÑALES ===
# Estas señales permiten comunicación con el menú principal
signal horror_shake_triggered

# === REFERENCIAS A NODOS DE AUDIO ===
var ui_sounds: AudioStreamPlayer
var ambient_audio: AudioStreamPlayer  
var breath_audio: AudioStreamPlayer

# === UTILIDADES DE AUDIO ===
# Cache de streams para evitar cargas repetidas en tiempo de ejecución
var stream_cache: Dictionary = {}
# Generador de aleatoriedad para variación sutil de pitch
var rng := RandomNumberGenerator.new()

# === DICCIONARIO DE ARCHIVOS DE AUDIO ===
var horror_sounds = {
	"hover": "res://audio/sfx/menu/hover.wav",
	"click": "res://audio/sfx/menu/click.wav", 
	"transition": "res://audio/sfx/menu/transition.wav",
	"back": "res://audio/sfx/menu/click.wav",
	"ambient": "res://audio/sfx/ui/dark_ambient.ogg",
	"breath": "res://audio/sfx/ui/heavy_breath.ogg"
}

# === INICIALIZACIÓN ===
func setup_audio_system(ui_node: AudioStreamPlayer, ambient_node: AudioStreamPlayer, breath_node: AudioStreamPlayer):
	"""Configurar las referencias a los nodos de audio"""
	ui_sounds = ui_node
	ambient_audio = ambient_node
	breath_audio = breath_node
	
	# Inicializa RNG para modulación sutil de pitch en SFX
	rng.randomize()
	
	# Pre-carga de SFX del menú para evitar stutter al primer uso
	preload_ui_streams()
	
	print("🎵 Configurando sistema de audio directo...")
	setup_ambient_audio()
	setup_breath_audio()
	test_audio_files()

# === CONFIGURACIÓN DE AUDIO AMBIENTE ===
func setup_ambient_audio():
	if ambient_audio:
		var ambient_stream = get_stream(horror_sounds["ambient"])
		if ambient_stream:
			ambient_audio.stream = ambient_stream
			ambient_audio.volume_db = -40
			ambient_audio.autoplay = false
			if ambient_stream is AudioStreamOggVorbis:
				ambient_stream.loop = true
			# Fade-in suave para un inicio más profesional
			ambient_audio.play()
			var tw = create_tween()
			tw.tween_property(ambient_audio, "volume_db", -15.0, 1.5).from(-40.0)
			print("Audio ambiente configurado")
		else:
			ambient_audio.autoplay = false
			ambient_audio.stream = null
			print("Advertencia: No se pudo cargar audio ambiente (se desactiva autoplay)")

# === CONFIGURACIÓN DE AUDIO DE RESPIRACIÓN ===
func setup_breath_audio():
	if breath_audio:
		var breath_stream = get_stream(horror_sounds["breath"])
		if breath_stream:
			breath_audio.stream = breath_stream
			breath_audio.volume_db = -35
			breath_audio.autoplay = false
			if breath_stream is AudioStreamOggVorbis:
				breath_stream.loop = true
			# Fade-in controlado para respiración
			breath_audio.play()
			var tw = create_tween()
			tw.tween_property(breath_audio, "volume_db", -20.0, 1.2).from(-35.0)
			print("Audio de respiración configurado")
		else:
			breath_audio.autoplay = false
			breath_audio.stream = null
			print("Advertencia: No se pudo cargar audio de respiración (se desactiva autoplay)")

# === PRUEBA DE ARCHIVOS DE AUDIO ===
func test_audio_files():
	print("🔍 Probando archivos de audio...")
	
	var click_sound = get_stream("res://audio/sfx/menu/click.wav")
	if click_sound:
		print("✅ click.wav cargado correctamente")
	else:
		print("❌ Error: no se pudo cargar click.wav")
	
	var hover_sound = get_stream("res://audio/sfx/menu/hover.wav")
	if hover_sound:
		print("✅ hover.wav cargado correctamente")
	else:
		print("❌ Error: no se pudo cargar hover.wav")
	
	var transition_sound = get_stream("res://audio/sfx/menu/transition.wav")
	if transition_sound:
		print("✅ transition.wav cargado correctamente")
	else:
		print("❌ Error: no se pudo cargar transition.wav")

# === FUNCIONES PÚBLICAS DE REPRODUCCIÓN ===

func play_click_sound():
	"""Reproducir sonido de clic"""
	print("🔊 Intentando reproducir sonido de click...")
	if ui_sounds:
		var path = "res://audio/sfx/menu/click.wav"
		var click_sound = get_stream(path)
		if click_sound:
			play_stream(ui_sounds, path, -8.0, 1.0, 0.03)
			print("✅ Sonido de click reproducido")
		else:
			print("❌ No se pudo cargar click.wav")
	else:
		print("❌ Nodo ui_sounds no disponible")
	
	# Emitir señal para activar efectos visuales
	horror_shake_triggered.emit()

func play_hover_sound():
	"""Reproducir sonido de hover"""
	print("🔊 Intentando reproducir sonido de hover...")
	if ui_sounds:
		var path = "res://audio/sfx/menu/hover.wav"
		var hover_sound = get_stream(path)
		if hover_sound:
			play_stream(ui_sounds, path, -12.0, 1.0, 0.02)
			print("✅ Sonido de hover reproducido")
		else:
			print("❌ No se pudo cargar hover.wav")
	else:
		print("❌ Nodo ui_sounds no disponible")

func play_transition_sound():
	"""Reproducir sonido de transición"""
	print("🔊 Intentando reproducir sonido de transición...")
	if ui_sounds:
		var path = "res://audio/sfx/menu/transition.wav"
		var transition_sound = get_stream(path)
		if transition_sound:
			play_stream(ui_sounds, path, -6.0, 1.0, 0.015)
			print("✅ Sonido de transición reproducido")
		else:
			print("❌ No se pudo cargar transition.wav")
	else:
		print("❌ Nodo ui_sounds no disponible")

func play_back_sound():
	"""Reproducir sonido de retroceso"""
	play_click_sound()

# === UTILIDADES INTERNAS ===
func get_stream(path: String) -> Resource:
	# Devuelve un stream desde cache o lo carga y almacena
	if stream_cache.has(path):
		return stream_cache[path]
	var res = load(path)
	if res:
		stream_cache[path] = res
	return res

func preload_ui_streams():
	# Pre-carga de SFX más usados en el menú
	for key in ["click", "hover", "transition"]:
		var p: String = horror_sounds.get(key, "")
		if p != "":
			get_stream(p)

func play_stream(player: AudioStreamPlayer, path: String, volume_db: float, base_pitch: float = 1.0, pitch_variation: float = 0.03):
	# Reproduce un stream con pequeña variación de pitch para naturalidad
	var stream: Resource = get_stream(path)
	if not stream:
		return
	player.stop()
	player.stream = stream
	player.pitch_scale = clamp(base_pitch + rng.randf_range(-pitch_variation, pitch_variation), 0.85, 1.15)
	player.volume_db = volume_db
	player.play()
