# Script singleton (autoload) para manejar configuraciones globales del juego
# Este script permanece en memoria durante toda la ejecución del juego
# Extiende Node en lugar de Control porque no es un elemento de UI
extends Node

# === SEÑALES GLOBALES ===
# Las señales permiten que otros scripts sepan cuando cambió algo importante

# Señal que se emite cuando cambia el idioma del juego
signal language_changed(new_language: String)

# Señal que se emite cuando cambian las configuraciones de audio
signal audio_settings_changed(master_volume: float, sfx_volume: float, music_volume: float)

# Señal que se emite cuando cambian las configuraciones gráficas
signal graphics_settings_changed()

# === CONSTANTES ===
# Las constantes son valores que nunca cambian durante la ejecución

# Ruta donde se guarda el archivo de configuración
const SETTINGS_FILE_PATH = "user://game_settings.cfg"

# Idiomas disponibles en el juego
const AVAILABLE_LANGUAGES = ["english", "spanish"]

# Configuración gráfica por defecto
const DEFAULT_GRAPHICS_SETTINGS = {
	"fullscreen": false,
	"resolution": Vector2i(1920, 1080),
	"vsync": true,
	"msaa": 1,  # Anti-aliasing
	"shadows": true,
	"post_processing": true
}

# === VARIABLES DE CONFIGURACIÓN ===
# Estas variables almacenan las configuraciones actuales del juego

# === CONFIGURACIÓN DE IDIOMA ===
var current_language: String = "english"  # Idioma actual del juego

# === CONFIGURACIÓN DE AUDIO ===
var master_volume: float = 1.0      # Volumen maestro (0.0 a 1.0)
var music_volume: float = 0.7       # Volumen de música
var sfx_volume: float = 0.8         # Volumen de efectos de sonido
var ui_sounds_enabled: bool = true  # Si los sonidos de UI están habilitados

# === CONFIGURACIÓN GRÁFICA ===
var fullscreen_enabled: bool = false           # Pantalla completa
var current_resolution: Vector2i = Vector2i(1920, 1080)  # Resolución actual
var vsync_enabled: bool = true                 # Sincronización vertical
var msaa_level: int = 1                        # Nivel de anti-aliasing
var shadows_enabled: bool = true               # Sombras habilitadas
var post_processing_enabled: bool = true      # Post-procesamiento habilitado

# === CONFIGURACIÓN DE CONTROLES ===
var mouse_sensitivity: float = 1.0    # Sensibilidad del mouse
var invert_mouse_y: bool = false      # Invertir eje Y del mouse

# === CONFIGURACIÓN DE JUEGO ===
var subtitles_enabled: bool = true    # Subtítulos habilitados
var gore_level: int = 3               # Nivel de gore (0-3)
var jumpscare_intensity: int = 2      # Intensidad de sustos (0-3)

# === DICCIONARIO DE TRADUCCIONES COMPLETO ===
# Este diccionario contiene TODAS las traducciones del juego
var game_translations = {
	"english": {
		# Menú principal
		"title": "TRYPOPHOBIA",
		"play": "SINGLE PLAYER",
		"multiplayer": "MULTIPLAYER",
		"settings": "SETTINGS",
		"exit": "EXIT",
		
		# Menú multijugador
		"host_game": "HOST GAME",
		"join_game": "JOIN GAME",
		"server_browser": "SERVER BROWSER",
		"private_lobby": "PRIVATE LOBBY",
		
		# Configuración
		"language": "LANGUAGE",
		"graphics": "GRAPHICS",
		"audio": "AUDIO",
		"controls": "CONTROLS",
		"gameplay": "GAMEPLAY",
		"back": "BACK",
		
		# Idiomas
		"spanish": "ESPAÑOL",
		"english": "ENGLISH",
		
		# Configuración gráfica
		"resolution": "RESOLUTION",
		"fullscreen": "FULLSCREEN",
		"vsync": "V-SYNC",
		"shadows": "SHADOWS",
		"post_processing": "POST PROCESSING",
		"anti_aliasing": "ANTI-ALIASING",
		
		# Configuración de audio
		"master_volume": "MASTER VOLUME",
		"music_volume": "MUSIC VOLUME",
		"sfx_volume": "SFX VOLUME",
		"ui_sounds": "UI SOUNDS",
		
		# Configuración de controles
		"mouse_sensitivity": "MOUSE SENSITIVITY",
		"invert_mouse": "INVERT MOUSE Y",
		
		# Configuración de juego
		"subtitles": "SUBTITLES",
		"gore_level": "GORE LEVEL",
		"jumpscare_intensity": "JUMPSCARE INTENSITY",
		
		# Niveles de configuración
		"off": "OFF",
		"low": "LOW",
		"medium": "MEDIUM",
		"high": "HIGH",
		"ultra": "ULTRA",
		
		# Estados del juego
		"loading": "LOADING...",
		"connecting": "CONNECTING...",
		"disconnected": "DISCONNECTED",
		"paused": "PAUSED"
	},
	"spanish": {
		# Menú principal
		"title": "TRYPOPHOBIA",
		"play": "UN JUGADOR",
		"multiplayer": "MULTIJUGADOR",
		"settings": "CONFIGURACIÓN",
		"exit": "SALIR",
		
		# Menú multijugador
		"host_game": "CREAR PARTIDA",
		"join_game": "UNIRSE A PARTIDA",
		"server_browser": "NAVEGADOR DE SERVIDORES",
		"private_lobby": "SALA PRIVADA",
		
		# Configuración
		"language": "IDIOMA",
		"graphics": "GRÁFICOS",
		"audio": "AUDIO",
		"controls": "CONTROLES",
		"gameplay": "JUGABILIDAD",
		"back": "ATRÁS",
		
		# Idiomas
		"spanish": "ESPAÑOL",
		"english": "ENGLISH",
		
		# Configuración gráfica
		"resolution": "RESOLUCIÓN",
		"fullscreen": "PANTALLA COMPLETA",
		"vsync": "SINCRONIZACIÓN VERTICAL",
		"shadows": "SOMBRAS",
		"post_processing": "POST-PROCESAMIENTO",
		"anti_aliasing": "ANTI-ALIASING",
		
		# Configuración de audio
		"master_volume": "VOLUMEN MAESTRO",
		"music_volume": "VOLUMEN MÚSICA",
		"sfx_volume": "VOLUMEN EFECTOS",
		"ui_sounds": "SONIDOS DE INTERFAZ",
		
		# Configuración de controles
		"mouse_sensitivity": "SENSIBILIDAD RATÓN",
		"invert_mouse": "INVERTIR RATÓN Y",
		
		# Configuración de juego
		"subtitles": "SUBTÍTULOS",
		"gore_level": "NIVEL DE GORE",
		"jumpscare_intensity": "INTENSIDAD DE SUSTOS",
		
		# Niveles de configuración
		"off": "DESACTIVADO",
		"low": "BAJO",
		"medium": "MEDIO",
		"high": "ALTO",
		"ultra": "ULTRA",
		
		# Estados del juego
		"loading": "CARGANDO...",
		"connecting": "CONECTANDO...",
		"disconnected": "DESCONECTADO",
		"paused": "PAUSADO"
	}
}

# === FUNCIÓN DE INICIALIZACIÓN ===
# _ready() se ejecuta cuando este script se carga (al inicio del juego)
func _ready():
	print("Inicializando sistema de configuraciones globales...")
	
	# Cargar configuraciones guardadas del archivo
	load_settings()
	
	# Aplicar las configuraciones cargadas
	apply_all_settings()
	
	print("Sistema de configuraciones iniciado correctamente")

# === FUNCIONES DE TRADUCCIÓN ===

# Obtener texto traducido según el idioma actual
# Esta función es la más importante para la localización
func get_text(key: String) -> String:
	# Verificar si el idioma actual existe en las traducciones
	if current_language in game_translations:
		# Verificar si la clave específica existe para este idioma
		if key in game_translations[current_language]:
			# Devolver la traducción
			return game_translations[current_language][key]
		else:
			# Si no existe la clave, usar inglés como respaldo
			print("Advertencia: Clave de traducción no encontrada: ", key)
			if key in game_translations["english"]:
				return game_translations["english"][key]
			else:
				# Si tampoco existe en inglés, devolver la clave misma
				return key.to_upper()
	else:
		# Si el idioma no existe, usar inglés
		print("Advertencia: Idioma no soportado: ", current_language)
		current_language = "english"
		return get_text(key)  # Llamada recursiva con inglés

# Cambiar idioma del juego
func set_language(new_language: String):
	print("Cambiando idioma a: ", new_language)
	
	# Verificar que el idioma es válido
	if new_language in AVAILABLE_LANGUAGES:
		var old_language = current_language
		current_language = new_language
		
		# Guardar el cambio inmediatamente
		save_settings()
		
		# Notificar a otros scripts que cambió el idioma
		language_changed.emit(new_language)
		
		print("Idioma cambiado de ", old_language, " a ", new_language)
	else:
		print("Error: Idioma no válido: ", new_language)

# === FUNCIONES DE CONFIGURACIÓN DE AUDIO ===

# Establecer volumen maestro
func set_master_volume(volume: float):
	# Asegurar que el volumen esté en rango válido (0.0 a 1.0)
	master_volume = clamp(volume, 0.0, 1.0)
	
	# Aplicar el volumen inmediatamente
	apply_audio_settings()
	
	# Guardar configuraciones
	save_settings()
	
	print("Volumen maestro establecido a: ", master_volume)

# Establecer volumen de música
func set_music_volume(volume: float):
	music_volume = clamp(volume, 0.0, 1.0)
	apply_audio_settings()
	save_settings()
	print("Volumen de música establecido a: ", music_volume)

# Establecer volumen de efectos de sonido
func set_sfx_volume(volume: float):
	sfx_volume = clamp(volume, 0.0, 1.0)
	apply_audio_settings()
	save_settings()
	print("Volumen de efectos establecido a: ", sfx_volume)

# Activar/desactivar sonidos de UI
func set_ui_sounds_enabled(enabled: bool):
	ui_sounds_enabled = enabled
	save_settings()
	print("Sonidos de UI: ", "activados" if enabled else "desactivados")

# === FUNCIONES DE CONFIGURACIÓN GRÁFICA ===

# Activar/desactivar pantalla completa
func set_fullscreen(enabled: bool):
	fullscreen_enabled = enabled
	
	# Aplicar inmediatamente el cambio de pantalla completa
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	
	save_settings()
	print("Pantalla completa: ", "activada" if enabled else "desactivada")

# Cambiar resolución
func set_resolution(resolution: Vector2i):
	current_resolution = resolution
	
	# Aplicar la nueva resolución
	DisplayServer.window_set_size(resolution)
	
	save_settings()
	print("Resolución cambiada a: ", resolution)

# Activar/desactivar V-Sync
func set_vsync(enabled: bool):
	vsync_enabled = enabled
	
	# Aplicar V-Sync inmediatamente
	if enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	
	save_settings()
	print("V-Sync: ", "activado" if enabled else "desactivado")

# === FUNCIONES DE APLICACIÓN DE CONFIGURACIONES ===

# Aplicar todas las configuraciones guardadas
func apply_all_settings():
	print("Aplicando todas las configuraciones...")
	
	apply_graphics_settings()
	apply_audio_settings()
	apply_control_settings()
	
	print("Configuraciones aplicadas correctamente")

# Aplicar configuraciones gráficas
func apply_graphics_settings():
	# Aplicar pantalla completa
	set_fullscreen(fullscreen_enabled)
	
	# Aplicar resolución
	set_resolution(current_resolution)
	
	# Aplicar V-Sync
	set_vsync(vsync_enabled)
	
	# Emitir señal de que cambiaron las configuraciones gráficas
	graphics_settings_changed.emit()

# Aplicar configuraciones de audio
func apply_audio_settings():
	# Convertir volúmenes lineales a decibelios (logarítmicos)
	# Godot usa escala logarítmica para el volumen
	var master_db = linear_to_db(master_volume)
	var music_db = linear_to_db(music_volume * master_volume)
	var sfx_db = linear_to_db(sfx_volume * master_volume)
	
	# Aplicar volúmenes a los buses de audio
	# Los buses de audio son canales que agrupan sonidos
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), master_db)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), music_db)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), sfx_db)
	
	# Emitir señal de cambio de audio
	audio_settings_changed.emit(master_volume, sfx_volume, music_volume)

# Aplicar configuraciones de controles
func apply_control_settings():
	# Las configuraciones de controles se aplican en el jugador
	# Aquí podríamos establecer configuraciones globales de input
	pass

# === FUNCIONES DE PERSISTENCIA (GUARDAR/CARGAR) ===

# Guardar todas las configuraciones en archivo
func save_settings():
	print("Guardando configuraciones...")
	
	# ConfigFile es una clase especial de Godot para archivos de configuración
	var config = ConfigFile.new()
	
	# === GUARDAR CONFIGURACIÓN DE IDIOMA ===
	config.set_value("language", "current", current_language)
	
	# === GUARDAR CONFIGURACIÓN DE AUDIO ===
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "ui_sounds_enabled", ui_sounds_enabled)
	
	# === GUARDAR CONFIGURACIÓN GRÁFICA ===
	config.set_value("graphics", "fullscreen", fullscreen_enabled)
	config.set_value("graphics", "resolution_x", current_resolution.x)
	config.set_value("graphics", "resolution_y", current_resolution.y)
	config.set_value("graphics", "vsync", vsync_enabled)
	config.set_value("graphics", "msaa", msaa_level)
	config.set_value("graphics", "shadows", shadows_enabled)
	config.set_value("graphics", "post_processing", post_processing_enabled)
	
	# === GUARDAR CONFIGURACIÓN DE CONTROLES ===
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("controls", "invert_mouse_y", invert_mouse_y)
	
	# === GUARDAR CONFIGURACIÓN DE JUEGO ===
	config.set_value("gameplay", "subtitles_enabled", subtitles_enabled)
	config.set_value("gameplay", "gore_level", gore_level)
	config.set_value("gameplay", "jumpscare_intensity", jumpscare_intensity)
	
	# Guardar el archivo
	var error = config.save(SETTINGS_FILE_PATH)
	if error == OK:
		print("Configuraciones guardadas correctamente")
	else:
		print("Error al guardar configuraciones: ", error)

# Cargar configuraciones desde archivo
func load_settings():
	print("Cargando configuraciones...")
	
	var config = ConfigFile.new()
	var error = config.load(SETTINGS_FILE_PATH)
	
	# Si el archivo no existe o hay error, usar valores por defecto
	if error != OK:
		print("No se encontró archivo de configuración, usando valores por defecto")
		set_default_settings()
		return
	
	# === CARGAR CONFIGURACIÓN DE IDIOMA ===
	current_language = config.get_value("language", "current", "english")
	
	# === CARGAR CONFIGURACIÓN DE AUDIO ===
	master_volume = config.get_value("audio", "master_volume", 1.0)
	music_volume = config.get_value("audio", "music_volume", 0.7)
	sfx_volume = config.get_value("audio", "sfx_volume", 0.8)
	ui_sounds_enabled = config.get_value("audio", "ui_sounds_enabled", true)
	
	# === CARGAR CONFIGURACIÓN GRÁFICA ===
	fullscreen_enabled = config.get_value("graphics", "fullscreen", false)
	var res_x = config.get_value("graphics", "resolution_x", 1920)
	var res_y = config.get_value("graphics", "resolution_y", 1080)
	current_resolution = Vector2i(res_x, res_y)
	vsync_enabled = config.get_value("graphics", "vsync", true)
	msaa_level = config.get_value("graphics", "msaa", 1)
	shadows_enabled = config.get_value("graphics", "shadows", true)
	post_processing_enabled = config.get_value("graphics", "post_processing", true)
	
	# === CARGAR CONFIGURACIÓN DE CONTROLES ===
	mouse_sensitivity = config.get_value("controls", "mouse_sensitivity", 1.0)
	invert_mouse_y = config.get_value("controls", "invert_mouse_y", false)
	
	# === CARGAR CONFIGURACIÓN DE JUEGO ===
	subtitles_enabled = config.get_value("gameplay", "subtitles_enabled", true)
	gore_level = config.get_value("gameplay", "gore_level", 3)
	jumpscare_intensity = config.get_value("gameplay", "jumpscare_intensity", 2)
	
	print("Configuraciones cargadas correctamente")

# Establecer valores por defecto
func set_default_settings():
	print("Estableciendo configuraciones por defecto...")
	
	# Valores por defecto
	current_language = "english"
	master_volume = 1.0
	music_volume = 0.7
	sfx_volume = 0.8
	ui_sounds_enabled = true
	fullscreen_enabled = false
	current_resolution = Vector2i(1920, 1080)
	vsync_enabled = true
	msaa_level = 1
	shadows_enabled = true
	post_processing_enabled = true
	mouse_sensitivity = 1.0
	invert_mouse_y = false
	subtitles_enabled = true
	gore_level = 3
	jumpscare_intensity = 2
	
	# Guardar los valores por defecto
	save_settings()

# === FUNCIONES DE UTILIDAD ===

# Verificar si un idioma está disponible
func is_language_available(language: String) -> bool:
	return language in AVAILABLE_LANGUAGES

# Obtener lista de idiomas disponibles
func get_available_languages() -> Array[String]:
	return AVAILABLE_LANGUAGES

# Obtener configuración como diccionario (útil para debugging)
func get_all_settings() -> Dictionary:
	return {
		"language": current_language,
		"audio": {
			"master_volume": master_volume,
			"music_volume": music_volume,
			"sfx_volume": sfx_volume,
			"ui_sounds_enabled": ui_sounds_enabled
		},
		"graphics": {
			"fullscreen": fullscreen_enabled,
			"resolution": current_resolution,
			"vsync": vsync_enabled,
			"msaa": msaa_level,
			"shadows": shadows_enabled,
			"post_processing": post_processing_enabled
		},
		"controls": {
			"mouse_sensitivity": mouse_sensitivity,
			"invert_mouse_y": invert_mouse_y
		},
		"gameplay": {
			"subtitles_enabled": subtitles_enabled,
			"gore_level": gore_level,
			"jumpscare_intensity": jumpscare_intensity
		}
	} 