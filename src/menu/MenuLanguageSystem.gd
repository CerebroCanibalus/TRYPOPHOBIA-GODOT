# === SISTEMA DE IDIOMAS DEL MENÚ ===
# Responsable de manejar traducciones y cambio de idioma
extends Node

# === SEÑALES ===
signal language_changed(new_language: String)

# === VARIABLES DE ESTADO ===
var current_language: String = "english"

# === DICCIONARIO DE TRADUCCIONES ===
var translations = {
	"english": {
		"title": "TRYPOPHOBIA",
		"play": "SINGLE PLAYER",
		"multiplayer": "MULTIPLAYER", 
		"settings": "SETTINGS",
		"exit": "EXIT",
		"host_game": "HOST GAME",
		"join_game": "JOIN GAME",
		"back": "BACK",
		"language": "LANGUAGE",
		"graphics": "GRAPHICS", 
		"audio": "AUDIO",
		"spanish": "ESPAÑOL",
		"english": "ENGLISH",
		"portuguese": "PORTUGUÊS",
		"italian": "ITALIANO",
		"french": "FRANÇAIS",
		"german": "DEUTSCH"
	},
	"spanish": {
		"title": "TRYPOPHOBIA",
		"play": "UN JUGADOR",
		"multiplayer": "MULTIJUGADOR",
		"settings": "CONFIGURACIÓN", 
		"exit": "SALIR",
		"host_game": "CREAR PARTIDA",
		"join_game": "UNIRSE A PARTIDA",
		"back": "ATRÁS",
		"language": "IDIOMA",
		"graphics": "GRÁFICOS",
		"audio": "AUDIO", 
		"spanish": "ESPAÑOL",
		"english": "ENGLISH",
		"portuguese": "PORTUGUÊS",
		"italian": "ITALIANO",
		"french": "FRANÇAIS",
		"german": "DEUTSCH"
	},
	"portuguese": {
		"title": "TRYPOPHOBIA",
		"play": "UM JOGADOR",
		"multiplayer": "MULTIJOGADOR",
		"settings": "CONFIGURAÇÕES",
		"exit": "SAIR",
		"host_game": "CRIAR JOGO",
		"join_game": "ENTRAR NO JOGO",
		"back": "VOLTAR",
		"language": "IDIOMA",
		"graphics": "GRÁFICOS",
		"audio": "ÁUDIO",
		"spanish": "ESPAÑOL",
		"english": "ENGLISH",
		"portuguese": "PORTUGUÊS",
		"italian": "ITALIANO",
		"french": "FRANÇAIS",
		"german": "DEUTSCH"
	},
	"italian": {
		"title": "TRYPOPHOBIA",
		"play": "GIOCATORE SINGOLO",
		"multiplayer": "MULTIGIOCATORE",
		"settings": "IMPOSTAZIONI",
		"exit": "ESCI",
		"host_game": "OSPITA PARTITA",
		"join_game": "UNISCITI PARTITA",
		"back": "INDIETRO",
		"language": "LINGUA",
		"graphics": "GRAFICA",
		"audio": "AUDIO",
		"spanish": "ESPAÑOL",
		"english": "ENGLISH",
		"portuguese": "PORTUGUÊS",
		"italian": "ITALIANO",
		"french": "FRANÇAIS",
		"german": "DEUTSCH"
	},
	"french": {
		"title": "TRYPOPHOBIA",
		"play": "UN JOUEUR",
		"multiplayer": "MULTIJOUEUR",
		"settings": "PARAMÈTRES",
		"exit": "QUITTER",
		"host_game": "HÉBERGER PARTIE",
		"join_game": "REJOINDRE PARTIE",
		"back": "RETOUR",
		"language": "LANGUE",
		"graphics": "GRAPHIQUES",
		"audio": "AUDIO",
		"spanish": "ESPAÑOL",
		"english": "ENGLISH",
		"portuguese": "PORTUGUÊS",
		"italian": "ITALIANO",
		"french": "FRANÇAIS",
		"german": "DEUTSCH"
	},
	"german": {
		"title": "TRYPOPHOBIA",
		"play": "EINZELSPIELER",
		"multiplayer": "MEHRSPIELER",
		"settings": "EINSTELLUNGEN",
		"exit": "BEENDEN",
		"host_game": "SPIEL HOSTEN",
		"join_game": "SPIEL BEITRETEN",
		"back": "ZURÜCK",
		"language": "SPRACHE",
		"graphics": "GRAFIK",
		"audio": "AUDIO",
		"spanish": "ESPAÑOL",
		"english": "ENGLISH",
		"portuguese": "PORTUGUÊS",
		"italian": "ITALIANO",
		"french": "FRANÇAIS",
		"german": "DEUTSCH"
	}
}

# === REFERENCIAS A ELEMENTOS UI ===
var title_label: Label
var play_button: Button
var multiplayer_button: Button
var settings_button: Button
var exit_button: Button
var host_button: Button
var join_button: Button
var back_from_multiplayer: Button
var language_button: Button
var graphics_button: Button
var audio_button: Button
var back_from_settings: Button
var spanish_button: Button
var english_button: Button
var portuguese_button: Button
var italian_button: Button
var french_button: Button
var german_button: Button
var back_from_language: Button

# === INICIALIZACIÓN ===
func setup_language_system(ui_elements: Dictionary):
	"""Configurar las referencias a elementos UI"""
	title_label = ui_elements["title_label"]
	play_button = ui_elements["play_button"]
	multiplayer_button = ui_elements["multiplayer_button"]
	settings_button = ui_elements["settings_button"]
	exit_button = ui_elements["exit_button"]
	host_button = ui_elements["host_button"]
	join_button = ui_elements["join_button"]
	back_from_multiplayer = ui_elements["back_from_multiplayer"]
	language_button = ui_elements["language_button"]
	graphics_button = ui_elements["graphics_button"]
	audio_button = ui_elements["audio_button"]
	back_from_settings = ui_elements["back_from_settings"]
	spanish_button = ui_elements["spanish_button"]
	english_button = ui_elements["english_button"]
	portuguese_button = ui_elements.get("portuguese_button")
	italian_button = ui_elements.get("italian_button")
	french_button = ui_elements.get("french_button")
	german_button = ui_elements.get("german_button")
	back_from_language = ui_elements["back_from_language"]
	
	# Cargar idioma guardado
	load_saved_language()
	update_ui_language()

# === FUNCIONES PÚBLICAS ===
func set_language(language: String):
	"""Cambiar idioma y actualizar UI"""
	current_language = language
	update_ui_language()
	save_language_preference()
	language_changed.emit(current_language)

func get_current_language() -> String:
	"""Obtener idioma actual"""
	return current_language

func get_text(key: String) -> String:
	"""Obtener texto traducido para una clave"""
	if current_language in translations and key in translations[current_language]:
		return translations[current_language][key]
	
	# Fallback a inglés si no se encuentra la traducción
	if key in translations["english"]:
		return translations["english"][key]
	
	return key  # Fallback a la clave misma

# === ACTUALIZACIÓN DE UI ===
func update_ui_language():
	"""Actualizar todos los textos del UI según el idioma seleccionado"""
	print("Actualizando idioma a: ", current_language)
	
	var texts = translations[current_language]
	
	# Actualizar textos del menú principal
	if title_label:
		title_label.text = texts["title"]
	if play_button:
		play_button.text = texts["play"]
	if multiplayer_button:
		multiplayer_button.text = texts["multiplayer"]
	if settings_button:
		settings_button.text = texts["settings"]
	if exit_button:
		exit_button.text = texts["exit"]
	
	# Actualizar textos del menú multijugador
	if host_button:
		host_button.text = texts["host_game"]
	if join_button:
		join_button.text = texts["join_game"]
	if back_from_multiplayer:
		back_from_multiplayer.text = texts["back"]
	
	# Actualizar textos del menú configuración
	if language_button:
		language_button.text = texts["language"]
	if graphics_button:
		graphics_button.text = texts["graphics"]
	if audio_button:
		audio_button.text = texts["audio"]
	if back_from_settings:
		back_from_settings.text = texts["back"]
	
	# Actualizar textos del menú idiomas
	if spanish_button:
		spanish_button.text = texts["spanish"]
	if english_button:
		english_button.text = texts["english"]
	if portuguese_button:
		portuguese_button.text = texts["portuguese"]
	if italian_button:
		italian_button.text = texts["italian"]
	if french_button:
		french_button.text = texts["french"]
	if german_button:
		german_button.text = texts["german"]
	if back_from_language:
		back_from_language.text = texts["back"]

# === PERSISTENCIA ===
func load_saved_language():
	"""Cargar idioma guardado desde archivo de configuración"""
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")
	
	if err == OK:
		current_language = config.get_value("game", "language", "english")
		print("Idioma cargado: ", current_language)
	else:
		print("No se encontró archivo de configuración, usando inglés por defecto")
		current_language = "english"

func save_language_preference():
	"""Guardar preferencia de idioma"""
	var config = ConfigFile.new()
	
	# Cargar configuración existente (si existe)
	config.load("user://settings.cfg")
	
	# Establecer el nuevo valor de idioma
	config.set_value("game", "language", current_language)
	
	# Guardar el archivo
	var err = config.save("user://settings.cfg")
	if err == OK:
		print("Idioma guardado correctamente: ", current_language)
	else:
		print("Error al guardar configuración de idioma") 