# === MENÚ PRINCIPAL SIMPLIFICADO ===
# Solo se encarga de la navegación básica y coordinación entre módulos
extends Control

# === MÓDULOS DEL SISTEMA ===
var audio_manager: Node
var language_system: Node
var background_manager: Node
var server_browser: Node

# === REFERENCIAS A CONTENEDORES ===
@onready var main_container = $MainContainer
@onready var multiplayer_container = $MultiplayerContainer
@onready var settings_container = $SettingsContainer
@onready var language_container = $LanguageContainer
@onready var server_browser_container = $ServerBrowserContainer

# === REFERENCIAS A BOTONES ===
@onready var play_button = $MainContainer/VBoxContainer/PlayButton
@onready var multiplayer_button = $MainContainer/VBoxContainer/MultiplayerButton
@onready var settings_button = $MainContainer/VBoxContainer/SettingsButton
@onready var exit_button = $MainContainer/VBoxContainer/ExitButton

@onready var host_button = $MultiplayerContainer/VBoxContainer/HostButton
@onready var join_button = $MultiplayerContainer/VBoxContainer/JoinButton
@onready var back_from_multiplayer = $MultiplayerContainer/VBoxContainer/BackButton

@onready var language_button = $SettingsContainer/VBoxContainer/LanguageButton
@onready var graphics_button = $SettingsContainer/VBoxContainer/GraphicsButton
@onready var audio_button = $SettingsContainer/VBoxContainer/AudioButton
@onready var back_from_settings = $SettingsContainer/VBoxContainer/BackButton

@onready var spanish_button = $LanguageContainer/VBoxContainer/SpanishButton
@onready var english_button = $LanguageContainer/VBoxContainer/EnglishButton
@onready var portuguese_button = $LanguageContainer/VBoxContainer/PortugueseButton
@onready var italian_button = $LanguageContainer/VBoxContainer/ItalianButton
@onready var french_button = $LanguageContainer/VBoxContainer/FrenchButton
@onready var german_button = $LanguageContainer/VBoxContainer/GermanButton
@onready var back_from_language = $LanguageContainer/VBoxContainer/BackButton

# === REFERENCIAS A ELEMENTOS VISUALES ===
@onready var title_label = $MainContainer/TitleLabel
@onready var background_texture = $BackgroundTexture
@onready var background_animation = $BackgroundAnimation

# === REFERENCIAS A ELEMENTOS DE AUDIO ===
@onready var ambient_audio = $AudioContainer/AmbientAudio
@onready var ui_sounds = $AudioContainer/UISounds
@onready var breath_audio = $AudioContainer/BreathAudio

# === INICIALIZACIÓN ===
func _ready():
	print("Inicializando menú principal refactorizado...")
	
	setup_modules()
	setup_initial_state()
	setup_button_connections()
	setup_animations()
	
	print("Menú principal inicializado correctamente")

# === CONFIGURACIÓN DE MÓDULOS ===
func setup_modules():
	"""Crear e inicializar todos los módulos del sistema"""
	print("Configurando módulos del sistema...")
	
	# Crear módulo de audio
	audio_manager = load("res://scripts/ui/MenuAudioManager.gd").new()
	add_child(audio_manager)
	audio_manager.setup_audio_system(ui_sounds, ambient_audio, breath_audio)
	audio_manager.horror_shake_triggered.connect(_on_horror_shake_triggered)
	
	# Crear módulo de idiomas
	language_system = load("res://scripts/ui/MenuLanguageSystem.gd").new()
	add_child(language_system)
	var language_elements = {
		"title_label": title_label,
		"play_button": play_button,
		"multiplayer_button": multiplayer_button,
		"settings_button": settings_button,
		"exit_button": exit_button,
		"host_button": host_button,
		"join_button": join_button,
		"back_from_multiplayer": back_from_multiplayer,
		"language_button": language_button,
		"graphics_button": graphics_button,
		"audio_button": audio_button,
		"back_from_settings": back_from_settings,
		"spanish_button": spanish_button,
		"english_button": english_button,
		"portuguese_button": portuguese_button,
		"italian_button": italian_button,
		"french_button": french_button,
		"german_button": german_button,
		"back_from_language": back_from_language
	}
	language_system.setup_language_system(language_elements)
	
	# Crear módulo de efectos visuales
	background_manager = load("res://scripts/ui/BackgroundManager.gd").new()
	add_child(background_manager)
	background_manager.setup_background_system(background_texture, background_animation, title_label)
	
	# Crear módulo del explorador de servidores
	server_browser = load("res://scripts/ui/ServerBrowser.gd").new()
	add_child(server_browser)
	var server_elements = {
		"server_list": $ServerBrowserContainer/MainContainer/ServerListContainer/ServerListScrollContainer/ServerList,
		"refresh_button": $ServerBrowserContainer/MainContainer/ActionButtonsContainer/RefreshButton,
		"direct_connect_button": $ServerBrowserContainer/MainContainer/ActionButtonsContainer/DirectConnectButton,
		"back_from_server_browser": $ServerBrowserContainer/MainContainer/ActionButtonsContainer/BackButton,
		"server_status_label": $ServerBrowserContainer/StatusLabel,
		"server_subtitle_label": $ServerBrowserContainer/SubtitleLabel,
		"server_browser_container": server_browser_container
	}
	server_browser.setup_server_browser(server_elements)
	server_browser.back_to_multiplayer_requested.connect(_on_back_to_multiplayer)
	
	print("✅ Módulos configurados correctamente")

# === CONFIGURACIÓN DEL ESTADO INICIAL ===
func setup_initial_state():
	"""Establecer qué contenedores están visibles al inicio"""
	print("Configurando estado inicial del menú...")
	
	main_container.visible = true
	multiplayer_container.visible = false
	settings_container.visible = false
	language_container.visible = false
	server_browser_container.visible = false

# === CONFIGURACIÓN DE ANIMACIONES ===
func setup_animations():
	"""Configurar animaciones de aparición del menú"""
	var tween = create_tween()
	main_container.modulate.a = 0.0
	tween.tween_property(main_container, "modulate:a", 1.0, 1.5)

# === CONEXIÓN DE SEÑALES DE BOTONES ===  
func setup_button_connections():
	"""Conectar todas las señales de los botones"""
	print("Conectando señales de botones...")
	
	# Botones del menú principal
	play_button.pressed.connect(_on_play_pressed)
	multiplayer_button.pressed.connect(_on_multiplayer_pressed) 
	settings_button.pressed.connect(_on_settings_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	
	# Botones del menú multijugador
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_from_multiplayer.pressed.connect(_on_back_to_main)
	
	# Botones del menú configuración
	language_button.pressed.connect(_on_language_pressed)
	graphics_button.pressed.connect(_on_graphics_pressed)
	audio_button.pressed.connect(_on_audio_pressed)
	back_from_settings.pressed.connect(_on_back_to_main)
	
	# Botones del menú idiomas
	spanish_button.pressed.connect(_on_spanish_selected)
	english_button.pressed.connect(_on_english_selected)
	portuguese_button.pressed.connect(_on_portuguese_selected)
	italian_button.pressed.connect(_on_italian_selected)
	french_button.pressed.connect(_on_french_selected)
	german_button.pressed.connect(_on_german_selected)
	back_from_language.pressed.connect(_on_back_to_settings)
	
	# Configurar efectos de hover para todos los botones
	setup_hover_effects()

# === EFECTOS DE HOVER ===
func setup_hover_effects():
	"""Configurar efectos de hover para todos los botones"""
	var all_buttons = [
		play_button, multiplayer_button, settings_button, exit_button,
		host_button, join_button, back_from_multiplayer,
		language_button, graphics_button, audio_button, back_from_settings,
		spanish_button, english_button, portuguese_button, italian_button, french_button, german_button, back_from_language
	]
	
	for button in all_buttons:
		if button:
			button.mouse_entered.connect(_on_button_hover.bind(button))
			button.mouse_exited.connect(_on_button_unhover.bind(button))

# === FUNCIONES DE NAVEGACIÓN ===
func hide_all_containers():
	"""Ocultar todos los contenedores"""
	main_container.visible = false
	multiplayer_container.visible = false
	settings_container.visible = false
	language_container.visible = false
	server_browser_container.visible = false

func show_container(container: Control):
	"""Mostrar un contenedor específico con animación"""
	hide_all_containers()
	container.visible = true
	
	container.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(container, "modulate:a", 1.0, 0.3)

# === PROCESAMIENTO PARA MOUSE TRACKING ===
func _process(delta: float):
	"""Procesar tracking del mouse si el BackgroundManager lo necesita"""
	if background_manager:
		background_manager.process_mouse_basic(delta)

# === RESPUESTA A BOTONES DEL MENÚ PRINCIPAL ===
func _on_play_pressed():
	print("Iniciando modo un jugador...")
	audio_manager.play_click_sound()
	get_tree().change_scene_to_file("res://maps/misiones/c1.tscn")

func _on_multiplayer_pressed():
	print("Abriendo menú multijugador...")
	audio_manager.play_click_sound()
	show_container(multiplayer_container)

func _on_settings_pressed():
	print("Abriendo configuración...")
	audio_manager.play_click_sound()
	show_container(settings_container)

func _on_exit_pressed():
	print("Saliendo del juego...")
	audio_manager.play_click_sound()
	get_tree().quit()

# === RESPUESTA A BOTONES DEL MENÚ MULTIJUGADOR ===
func _on_host_pressed():
	print("Creando partida multijugador...")
	audio_manager.play_click_sound()
	get_tree().change_scene_to_file("res://maps/lobby.tscn")

func _on_join_pressed():
	print("Abriendo explorador de servidores...")
	audio_manager.play_click_sound()
	show_container(server_browser_container)
	server_browser.initialize_browser()
	server_browser.refresh_server_list()

# === RESPUESTA A BOTONES DE CONFIGURACIÓN ===
func _on_language_pressed():
	print("Abriendo selección de idioma...")
	audio_manager.play_click_sound()
	show_container(language_container)

func _on_graphics_pressed():
	print("Abriendo configuración gráfica...")
	audio_manager.play_click_sound()

func _on_audio_pressed():
	print("Abriendo configuración de audio...")
	audio_manager.play_click_sound()

# === SELECCIÓN DE IDIOMA ===
func _on_spanish_selected():
	print("Idioma cambiado a español")
	audio_manager.play_click_sound()
	language_system.set_language("spanish")

func _on_english_selected():
	print("Language changed to english")
	audio_manager.play_click_sound()
	language_system.set_language("english")

func _on_portuguese_selected():
	print("Idioma alterado para português")
	audio_manager.play_click_sound()
	language_system.set_language("portuguese")

func _on_italian_selected():
	print("Lingua cambiata in italiano")
	audio_manager.play_click_sound()
	language_system.set_language("italian")

func _on_french_selected():
	print("Langue changée en français")
	audio_manager.play_click_sound()
	language_system.set_language("french")

func _on_german_selected():
	print("Sprache zu Deutsch geändert")
	audio_manager.play_click_sound()
	language_system.set_language("german")

# === NAVEGACIÓN "ATRÁS" ===
func _on_back_to_main():
	print("Volviendo al menú principal...")
	audio_manager.play_back_sound()
	show_container(main_container)

func _on_back_to_settings():
	print("Volviendo a configuración...")
	audio_manager.play_back_sound()
	show_container(settings_container)

func _on_back_to_multiplayer():
	print("Volviendo al menú multijugador...")
	audio_manager.play_back_sound()
	show_container(multiplayer_container)

# === EFECTOS DE HOVER ===
func _on_button_hover(button: Button):
	print("Hover en botón: ", button.name)
	var tween = create_tween()
	tween.tween_property(button, "modulate", Color(1.2, 0.8, 0.8), 0.2)
	audio_manager.play_hover_sound()

func _on_button_unhover(button: Button):
	var tween = create_tween()
	tween.tween_property(button, "modulate", Color.WHITE, 0.3)

# === RESPUESTA A SEÑALES DE MÓDULOS ===
func _on_horror_shake_triggered():
	"""Responder a la señal de activación de efectos de horror"""
	if background_manager:
		background_manager.trigger_horror_shake()
