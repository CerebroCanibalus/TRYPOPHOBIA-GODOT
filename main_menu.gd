# Script principal del menú - Extiende la clase Control de Godot
# Control es la clase base para todos los elementos de UI en Godot
extends Control

# === DECLARACIÓN DE VARIABLES ===
# @onready significa que estas variables se inicializan cuando el nodo está listo
# Esto es importante porque los nodos hijos no existen hasta que el nodo padre está en el árbol de escenas

# Referencias a contenedores principales del menú
@onready var main_container = $MainContainer  # Contenedor del menú principal
@onready var multiplayer_container = $MultiplayerContainer  # Contenedor del menú multijugador
@onready var settings_container = $SettingsContainer  # Contenedor de configuración
@onready var language_container = $LanguageContainer  # Contenedor de selección de idioma
@onready var server_browser_container = $ServerBrowserContainer  # Contenedor del explorador de servidores

# Referencias a botones del menú principal
@onready var play_button = $MainContainer/VBoxContainer/PlayButton
@onready var multiplayer_button = $MainContainer/VBoxContainer/MultiplayerButton
@onready var settings_button = $MainContainer/VBoxContainer/SettingsButton
@onready var exit_button = $MainContainer/VBoxContainer/ExitButton

# Referencias a botones del menú multijugador
@onready var host_button = $MultiplayerContainer/VBoxContainer/HostButton
@onready var join_button = $MultiplayerContainer/VBoxContainer/JoinButton
@onready var back_from_multiplayer = $MultiplayerContainer/VBoxContainer/BackButton

# Referencias a botones del menú de configuración
@onready var language_button = $SettingsContainer/VBoxContainer/LanguageButton
@onready var graphics_button = $SettingsContainer/VBoxContainer/GraphicsButton
@onready var audio_button = $SettingsContainer/VBoxContainer/AudioButton
@onready var back_from_settings = $SettingsContainer/VBoxContainer/BackButton

# Referencias a elementos de selección de idioma
@onready var spanish_button = $LanguageContainer/VBoxContainer/SpanishButton
@onready var english_button = $LanguageContainer/VBoxContainer/EnglishButton
@onready var back_from_language = $LanguageContainer/VBoxContainer/BackButton

# Referencias a elementos del explorador de servidores
@onready var server_list = $ServerBrowserContainer/MainContainer/ServerListContainer/ServerListScrollContainer/ServerList
@onready var refresh_button = $ServerBrowserContainer/MainContainer/ActionButtonsContainer/RefreshButton
@onready var direct_connect_button = $ServerBrowserContainer/MainContainer/ActionButtonsContainer/DirectConnectButton
@onready var back_from_server_browser = $ServerBrowserContainer/MainContainer/ActionButtonsContainer/BackButton
@onready var server_status_label = $ServerBrowserContainer/StatusLabel
@onready var server_subtitle_label = $ServerBrowserContainer/SubtitleLabel

# Referencias a elementos de audio para efectos de horror
@onready var ambient_audio = $AudioContainer/AmbientAudio  # Audio ambiente inquietante
@onready var ui_sounds = $AudioContainer/UISounds  # Sonidos de interfaz
@onready var breath_audio = $AudioContainer/BreathAudio  # Sonidos de respiración



# Referencias a elementos visuales
@onready var background_animation = $BackgroundAnimation  # Animación del fondo
@onready var title_label = $MainContainer/TitleLabel  # Título del juego
@onready var background_texture = $BackgroundTexture  # Textura de fondo interactiva
@onready var background_material: ShaderMaterial  # Material con shader para efectos
@onready var mouse_tracker: Node  # Rastreador de posición del mouse

# === VARIABLES DE ESTADO ===
# Estas variables mantienen el estado actual del menú y del juego

# Variable que guarda el idioma actual del juego
# Por defecto en inglés, se puede cambiar desde configuración
var current_language: String = "english"

# Diccionario que contiene todas las traducciones del juego
# Esto permite cambiar fácilmente entre idiomas sin recargar la escena
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
		"english": "ENGLISH"
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
		"english": "ENGLISH"
	}
}

# Diccionario que contiene las rutas de los archivos de audio para efectos de horror
var horror_sounds = {
	"hover": "res://audio/sfx/menu/hover.wav",            # Sonido al pasar sobre botón
	"click": "res://audio/sfx/menu/click.wav",            # Sonido al hacer clic
	"transition": "res://audio/sfx/menu/transition.wav",  # Sonido para transiciones/vibraciones
	"back": "res://audio/sfx/menu/click.wav",             # Usar click para retroceder también
	"ambient": "res://audio/sfx/ui/dark_ambient.ogg",     # Audio ambiente oscuro (mantener si existe)
	"breath": "res://audio/sfx/ui/heavy_breath.ogg"       # Respiración pesada (mantener si existe)
}

# === FUNCIÓN PRINCIPAL DE INICIALIZACIÓN ===
# _ready() es una función especial que se ejecuta automáticamente
# cuando el nodo se agrega al árbol de escenas por primera vez
func _ready():
	print("Inicializando menú principal...")  # Debug: confirmar que el menú se está cargando
	
	# Llamar a todas las funciones de configuración en orden específico
	setup_initial_state()      # Configurar estado inicial del menú
	setup_button_connections() # Conectar todas las señales de los botones
	setup_horror_atmosphere()  # Configurar ambiente de horror
	setup_animations()         # Configurar animaciones visuales
	update_ui_language()       # Actualizar textos según idioma seleccionado
	
	print("Menú principal inicializado correctamente")

# === CONFIGURACIÓN DEL ESTADO INICIAL ===
# Esta función establece qué contenedores están visibles al inicio
func setup_initial_state():
	print("Configurando estado inicial del menú...")
	
	# Mostrar solo el contenedor principal al inicio
	# En Godot, visible = true hace que el nodo sea visible, false lo oculta
	main_container.visible = true
	multiplayer_container.visible = false  # Ocultar menú multijugador
	settings_container.visible = false     # Ocultar menú configuración
	language_container.visible = false     # Ocultar menú idiomas
	server_browser_container.visible = false  # Ocultar explorador de servidores
	
	# Cargar idioma guardado desde configuración
	# PlayerPrefs o similar se usaría aquí en un juego real
	load_saved_language()

# === CONEXIÓN DE SEÑALES DE BOTONES ===  
# En Godot, las señales son como eventos - cuando algo pasa (ej: clic en botón)
# se ejecuta una función específica
func setup_button_connections():
	print("Conectando señales de botones...")
	
	# === BOTONES DEL MENÚ PRINCIPAL ===
	# .pressed es la señal que se emite cuando se hace clic en el botón
	# .connect() vincula esa señal con una función específica
	
	play_button.pressed.connect(_on_play_pressed)
	multiplayer_button.pressed.connect(_on_multiplayer_pressed) 
	settings_button.pressed.connect(_on_settings_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	
	# === BOTONES DEL MENÚ MULTIJUGADOR ===
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_from_multiplayer.pressed.connect(_on_back_to_main)
	
	# === BOTONES DEL MENÚ CONFIGURACIÓN ===
	language_button.pressed.connect(_on_language_pressed)
	graphics_button.pressed.connect(_on_graphics_pressed)
	audio_button.pressed.connect(_on_audio_pressed)
	back_from_settings.pressed.connect(_on_back_to_main)
	
	# === BOTONES DEL MENÚ IDIOMAS ===
	spanish_button.pressed.connect(_on_spanish_selected)
	english_button.pressed.connect(_on_english_selected)
	back_from_language.pressed.connect(_on_back_to_settings)
	
	# === BOTONES DEL EXPLORADOR DE SERVIDORES ===
	refresh_button.pressed.connect(_on_refresh_servers_pressed)
	direct_connect_button.pressed.connect(_on_direct_connect_pressed)
	back_from_server_browser.pressed.connect(_on_back_to_multiplayer)
	
	# === EFECTOS DE HOVER (pasar mouse sobre botón) ===
	# mouse_entered se ejecuta cuando el cursor entra en el área del botón
	# mouse_exited se ejecuta cuando el cursor sale del área del botón
	
	# Conectar efectos de hover para todos los botones principales
	var all_buttons = [
		play_button, multiplayer_button, settings_button, exit_button,
		host_button, join_button, back_from_multiplayer,
		language_button, graphics_button, audio_button, back_from_settings,
		spanish_button, english_button, back_from_language,
		refresh_button, direct_connect_button, back_from_server_browser
	]
	
	# for es un bucle que repite código para cada elemento en una lista
	for button in all_buttons:
		# Verificar que el botón existe antes de conectar señales
		if button:  # if verifica si la variable no es null
			button.mouse_entered.connect(_on_button_hover.bind(button))
			button.mouse_exited.connect(_on_button_unhover.bind(button))
			# .bind() permite pasar parámetros adicionales a la función conectada

# === CONFIGURACIÓN DE ATMÓSFERA DE HORROR ===
# Esta función configura todos los elementos que crean la atmósfera terrorífica
func setup_horror_atmosphere():
	print("Configurando atmósfera de horror...")
	
	# === CONFIGURACIÓN DEL SISTEMA DE AUDIO ===
	setup_direct_audio_system()
	
	# === CONFIGURACIÓN DE AUDIO AMBIENTE ===
	if ambient_audio:  # Verificar que el nodo existe
		# Intentar cargar el archivo de audio ambiente
		var ambient_stream = load(horror_sounds["ambient"])
		if ambient_stream:  # Si el archivo existe
			ambient_audio.stream = ambient_stream
			ambient_audio.volume_db = -15  # Volumen en decibelios (negativo = más bajo)
			ambient_audio.autoplay = true  # Reproducir automáticamente
			ambient_audio.loop = true      # Repetir infinitamente
			print("Audio ambiente configurado")
		else:
			print("Advertencia: No se pudo cargar audio ambiente")
	
	# === CONFIGURACIÓN DE AUDIO DE RESPIRACIÓN ===
	if breath_audio:
		var breath_stream = load(horror_sounds["breath"])
		if breath_stream:
			breath_audio.stream = breath_stream
			breath_audio.volume_db = -20  # Más bajo que el ambiente
			breath_audio.autoplay = true
			breath_audio.loop = true
			print("Audio de respiración configurado")
	
	# === CONFIGURACIÓN DEL FONDO INTERACTIVO ===
	setup_interactive_background()
	setup_mouse_tracker()
	
	# === EFECTOS VISUALES DE HORROR ===
	# Configurar el fondo con efectos escalofriantes
	if background_animation:
		background_animation.play("horror_idle")  # Reproducir animación de fondo
	
	# Configurar el título con efecto de temblor
	if title_label:
		# Crear un efecto de temblor sutil en el título
		create_title_shake_effect()

# === CONFIGURACIÓN DIRECTA DEL SISTEMA DE AUDIO ===
func setup_direct_audio_system():
	print("🎵 Configurando sistema de audio directo...")
	
	# Verificar que tenemos los nodos de audio
	if ui_sounds:
		print("✅ Nodo ui_sounds encontrado")
	else:
		print("❌ Nodo ui_sounds NO encontrado")
	
	# Verificar que los archivos de sonido existen
	test_audio_files()

# Función para probar si los archivos de audio se pueden cargar
func test_audio_files():
	print("🔍 Probando archivos de audio...")
	
	# Probar cada archivo de sonido
	var click_sound = load("res://audio/sfx/menu/click.wav")
	if click_sound:
		print("✅ click.wav cargado correctamente")
	else:
		print("❌ Error: no se pudo cargar click.wav")
	
	var hover_sound = load("res://audio/sfx/menu/hover.wav")
	if hover_sound:
		print("✅ hover.wav cargado correctamente")
	else:
		print("❌ Error: no se pudo cargar hover.wav")
	
	var transition_sound = load("res://audio/sfx/menu/transition.wav")
	if transition_sound:
		print("✅ transition.wav cargado correctamente")
	else:
		print("❌ Error: no se pudo cargar transition.wav")

# === CONFIGURACIÓN DE ANIMACIONES ===
func setup_animations():
	print("Configurando animaciones...")
	
	# Crear un Tween para animaciones suaves
	# Tween es una herramienta de Godot para crear transiciones suaves entre valores
	var tween = create_tween()
	
	# Animar la aparición del menú principal
	# modulate controla la transparencia y color de un nodo
	main_container.modulate.a = 0.0  # Empezar completamente transparente
	tween.tween_property(main_container, "modulate:a", 1.0, 1.5)  # Fade in en 1.5 segundos

# === ACTUALIZACIÓN DE IDIOMA ===
# Esta función actualiza todos los textos del UI según el idioma seleccionado
func update_ui_language():
	print("Actualizando idioma a: ", current_language)
	
	# Obtener el diccionario de traducciones para el idioma actual
	var texts = translations[current_language]
	
	# === ACTUALIZAR TEXTOS DEL MENÚ PRINCIPAL ===
	title_label.text = texts["title"]
	play_button.text = texts["play"]
	multiplayer_button.text = texts["multiplayer"]
	settings_button.text = texts["settings"]
	exit_button.text = texts["exit"]
	
	# === ACTUALIZAR TEXTOS DEL MENÚ MULTIJUGADOR ===
	host_button.text = texts["host_game"]
	join_button.text = texts["join_game"]
	back_from_multiplayer.text = texts["back"]
	
	# === ACTUALIZAR TEXTOS DEL MENÚ CONFIGURACIÓN ===
	language_button.text = texts["language"]
	graphics_button.text = texts["graphics"]
	audio_button.text = texts["audio"]
	back_from_settings.text = texts["back"]
	
	# === ACTUALIZAR TEXTOS DEL MENÚ IDIOMAS ===
	spanish_button.text = texts["spanish"]
	english_button.text = texts["english"]
	back_from_language.text = texts["back"]

# === FUNCIONES DE EFECTOS VISUALES ===

# Configurar el fondo interactivo con shader
func setup_interactive_background():
	print("=== INICIANDO CONFIGURACIÓN DE FONDO FUTURISTA ROJO ===")
	
	if not background_texture:
		print("ERROR: No se encontró el nodo BackgroundTexture")
		return
	
	print("BackgroundTexture encontrado: ", background_texture)
	
	# Crear material con shader
	background_material = ShaderMaterial.new()
	print("Material creado: ", background_material)
	
	# Intentar cargar primero el shader simplificado para debugging
	var shader_file = load("res://assets/shaders/simple_horror_background.gdshader")
	if not shader_file:
		print("No se pudo cargar shader simplificado, intentando con el complejo...")
		shader_file = load("res://assets/shaders/interactive_horror_background.gdshader")
	
	if shader_file:
		background_material.shader = shader_file
		print("✅ Shader cargado correctamente: ", shader_file)
		
		# Configurar parámetros para estilo futurista ROJO
		background_material.set_shader_parameter("shake_intensity", 0.0)
		background_material.set_shader_parameter("shake_speed", 30.0)  # Velocidad tech
		background_material.set_shader_parameter("mouse_position", Vector2(0.5, 0.5))
		background_material.set_shader_parameter("parallax_strength", 0.025)  # Sutil y tech
		background_material.set_shader_parameter("horror_tint", Vector3(0.6, 0.1, 0.1))  # ROJO futurista
		background_material.set_shader_parameter("digital_glow", 1.3)  # Brillo rojo
		background_material.set_shader_parameter("scan_speed", 2.5)  # Velocidad de escaneo
		
		print("✅ Parámetros futuristas ROJOS del shader configurados")
		
		# Aplicar el material al fondo
		background_texture.material = background_material
		print("✅ Material aplicado al fondo")
		
		# Crear la textura futurista roja
		create_temporary_background()
		
		print("=== CONFIGURACIÓN DE FONDO FUTURISTA ROJO COMPLETADA ===")
		
	else:
		print("❌ ERROR: No se pudo cargar ningún shader")
		print("Verificando archivos de shader...")
		
		# Verificar si los archivos existen
		var simple_exists = FileAccess.file_exists("res://assets/shaders/simple_horror_background.gdshader")
		var complex_exists = FileAccess.file_exists("res://assets/shaders/interactive_horror_background.gdshader")
		
		print("Shader simple existe: ", simple_exists)
		print("Shader complejo existe: ", complex_exists)

# Crear una textura temporal para el fondo si no existe la imagen
func create_temporary_background():
	print("--- Creando textura futurista ROJA ---")
	
	# Intentar cargar la imagen primero
	var background_image = load("res://assets/textures/menu_background.png")
	if background_image:
		background_texture.texture = background_image
		print("✅ Imagen de fondo cargada: ", background_image)
		return
	
	print("No se encontró imagen, creando textura procedural futurista ROJA...")
	
	# Crear una textura futurista post-apocalíptica con paleta ROJA
	var texture_size = Vector2i(512, 512)  # Mayor resolución para más detalle
	var image = Image.create(texture_size.x, texture_size.y, false, Image.FORMAT_RGB8)
	
	# Crear múltiples capas futuristas ROJAS
	create_red_digital_base_layer(image)
	add_red_circuit_patterns(image)
	add_red_holographic_glitches(image)
	add_red_data_corruption(image)
	add_red_neon_traces(image)
	add_red_quantum_distortions(image)
	
	# Crear y aplicar la textura
	var texture = ImageTexture.new()
	texture.set_image(image)
	background_texture.texture = texture
	
	print("✅ Textura futurista ROJA post-horror creada (", texture_size, ")")
	print("✅ Textura aplicada al BackgroundTexture")

# Crear capa base digital con patrones geométricos ROJOS
func create_red_digital_base_layer(image: Image):
	var size = image.get_size()
	
	for x in range(size.x):
		for y in range(size.y):
			# Crear patrón de grilla futurista
			var grid_x = x / 32  # Celdas más grandes
			var grid_y = y / 32
			
			# Coordenadas locales dentro de la celda
			var local_x = x % 32
			var local_y = y % 32
			
			# Determinar tipo de celda basado en posición
			var cell_type = (grid_x * 73 + grid_y * 137) % 100
			
			var color: Color
			
			# Crear diferentes tipos de paneles futuristas ROJOS
			if cell_type < 30:  # Paneles principales
				if local_x < 2 or local_x > 29 or local_y < 2 or local_y > 29:
					# Bordes luminosos ROJOS
					color = Color(0.4, 0.15, 0.12)  # Rojo metálico
				else:
					# Interior oscuro con variación sutil
					var variation = sin(grid_x * 1.2) * cos(grid_y * 0.8) * 0.03
					color = Color(0.12 + variation, 0.05 + variation * 0.5, 0.04 + variation * 0.3)
			
			elif cell_type < 60:  # Paneles de datos
				# Crear patrón de líneas de datos ROJAS
				var data_pattern = (local_x + local_y * 3) % 8
				if data_pattern < 2:
					color = Color(0.25, 0.08, 0.06)  # Líneas de datos rojas
				else:
					color = Color(0.08, 0.03, 0.02)  # Fondo oscuro
			
			elif cell_type < 85:  # Paneles corrompidos
				# Crear efecto de corrupción digital ROJA
				var corruption = sin(local_x * 0.5 + grid_x) * cos(local_y * 0.3 + grid_y)
				if corruption > 0.3:
					color = Color(0.35, 0.08, 0.05)  # Rojo de error intenso
				else:
					color = Color(0.06, 0.02, 0.01)  # Negro rojizo
			
			else:  # Paneles especiales
				# Crear patrones hexagonales futuristas ROJOS
				var hex_pattern = create_hex_pattern(local_x, local_y)
				if hex_pattern:
					color = Color(0.28, 0.12, 0.08)  # Rojo tecnológico
				else:
					color = Color(0.08, 0.04, 0.02)
			
			image.set_pixel(x, y, color)

# Crear patrón hexagonal futurista
func create_hex_pattern(x: int, y: int) -> bool:
	var center_x = 16
	var center_y = 16
	var radius = 12
	
	# Calcular distancia aproximada para crear hexágono
	var dx = abs(x - center_x)
	var dy = abs(y - center_y)
	
	# Aproximación de forma hexagonal
	return (dx + dy * 0.866) < radius and dx < radius * 0.866

# Agregar patrones de circuitos futuristas ROJOS
func add_red_circuit_patterns(image: Image):
	var size = image.get_size()
	
	# Crear líneas de circuito principales ROJAS
	for circuit_id in range(12):
		var start_x = (circuit_id * 47) % size.x
		var start_y = (circuit_id * 83) % size.y
		var direction = circuit_id % 4  # 4 direcciones
		
		var current_x = start_x
		var current_y = start_y
		var length = 50 + (circuit_id % 100)
		
		for step in range(length):
			if current_x >= 0 and current_x < size.x and current_y >= 0 and current_y < size.y:
				# Color de circuito ROJO con pulso
				var pulse = sin(step * 0.2 + circuit_id) * 0.15 + 0.85
				var circuit_color = Color(0.6 * pulse, 0.15 * pulse, 0.1 * pulse)
				
				# Dibujar línea de circuito con grosor
				for thickness in range(-1, 2):
					var px = current_x
					var py = current_y + thickness
					if direction % 2 == 1:  # Intercambiar para líneas verticales
						px = current_x + thickness
						py = current_y
					
					if px >= 0 and px < size.x and py >= 0 and py < size.y:
						var existing = image.get_pixel(px, py)
						image.set_pixel(px, py, existing.lerp(circuit_color, 0.8))
			
			# Avanzar en la dirección correspondiente
			match direction:
				0: current_x += 1  # Derecha
				1: current_y += 1  # Abajo
				2: current_x -= 1  # Izquierda
				3: current_y -= 1  # Arriba
			
			# Cambiar dirección ocasionalmente
			if step % 25 == 0:
				direction = (direction + (circuit_id % 3) + 1) % 4

# Agregar efectos holográficos y glitches ROJOS
func add_red_holographic_glitches(image: Image):
	var size = image.get_size()
	
	# Crear zonas de glitch holográfico ROJAS
	for glitch_zone in range(8):
		var center_x = (glitch_zone * 91) % size.x
		var center_y = (glitch_zone * 127) % size.y
		var radius = 15 + (glitch_zone % 20)
		
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var px = center_x + dx
				var py = center_y + dy
				
				if px >= 0 and px < size.x and py >= 0 and py < size.y:
					var distance = sqrt(dx * dx + dy * dy)
					
					# Crear efecto de glitch con ruido digital
					var glitch_noise = sin(dx * 0.8 + glitch_zone) * cos(dy * 1.2 + glitch_zone)
					
					if distance + glitch_noise * 3 < radius:
						var intensity = (radius - distance) / radius
						
						# Colores holográficos ROJOS cambiantes
						var holo_color: Color
						match glitch_zone % 4:
							0: holo_color = Color(0.8, 0.2, 0.1)   # Rojo holográfico
							1: holo_color = Color(0.7, 0.1, 0.4)   # Magenta
							2: holo_color = Color(0.9, 0.4, 0.1)   # Naranja neón
							3: holo_color = Color(0.6, 0.05, 0.2)  # Rojo oscuro futurista
						
						var existing = image.get_pixel(px, py)
						image.set_pixel(px, py, existing.lerp(holo_color, intensity * 0.5))

# Agregar corrupción de datos y códigos ROJOS
func add_red_data_corruption(image: Image):
	var size = image.get_size()
	
	# Crear líneas de código corrompido ROJAS
	for corruption_line in range(15):
		var y_pos = (corruption_line * 31) % size.y
		var start_x = (corruption_line * 43) % (size.x - 80)
		
		# Crear "caracteres" de código corrompido
		for char_pos in range(20):
			var char_x = start_x + char_pos * 4
			var char_pattern = (char_pos + corruption_line) % 16
			
			# Diferentes patrones de "código"
			for pixel_y in range(3):
				for pixel_x in range(3):
					var px = char_x + pixel_x
					var py = y_pos + pixel_y
					
					if px < size.x and py < size.y:
						# Crear patrón de píxeles que simula texto corrompido
						var should_draw = (char_pattern >> (pixel_y * 3 + pixel_x)) & 1
						
						if should_draw:
							var corruption_color: Color
							if corruption_line % 3 == 0:
								corruption_color = Color(0.7, 0.15, 0.1)  # Rojo error
							elif corruption_line % 3 == 1:
								corruption_color = Color(0.8, 0.3, 0.1)   # Naranja terminal
							else:
								corruption_color = Color(0.6, 0.1, 0.3)   # Magenta código
							
							image.set_pixel(px, py, corruption_color)

# Agregar trazas de neón futuristas ROJAS
func add_red_neon_traces(image: Image):
	var size = image.get_size()
	
	# Crear trazas curvas de neón ROJAS
	for trace_id in range(6):
		var start_x = (trace_id * 71) % size.x
		var start_y = (trace_id * 103) % size.y
		
		# Crear curva sinusoidal
		for step in range(150):
			var progress = step / 150.0
			var curve_x = start_x + step * 2
			var curve_y = start_y + sin(progress * PI * 3 + trace_id) * 20
			
			if curve_x < size.x and curve_y >= 0 and curve_y < size.y:
				# Color neón ROJO brillante con fade
				var brightness = 1.0 - progress * 0.7
				var neon_color: Color
				
				match trace_id % 3:
					0: neon_color = Color(1.0 * brightness, 0.2 * brightness, 0.3 * brightness)  # Rojo neón
					1: neon_color = Color(0.9 * brightness, 0.4 * brightness, 0.1 * brightness)  # Naranja neón
					2: neon_color = Color(0.8 * brightness, 0.1 * brightness, 0.5 * brightness)  # Magenta neón
				
				var existing = image.get_pixel(int(curve_x), int(curve_y))
				image.set_pixel(int(curve_x), int(curve_y), existing.lerp(neon_color, 0.7))

# Agregar distorsiones cuánticas ROJAS
func add_red_quantum_distortions(image: Image):
	var size = image.get_size()
	
	# Crear áreas de distorsión cuántica ROJAS
	for quantum_zone in range(4):
		var center_x = (quantum_zone * 113) % size.x
		var center_y = (quantum_zone * 157) % size.y
		var radius = 25 + (quantum_zone % 15)
		
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var px = center_x + dx
				var py = center_y + dy
				
				if px >= 0 and px < size.x and py >= 0 and py < size.y:
					var distance = sqrt(dx * dx + dy * dy)
					
					if distance < radius:
						# Crear efecto de ondas cuánticas
						var wave = sin(distance * 0.3 + quantum_zone) * cos(distance * 0.2)
						var intensity = (radius - distance) / radius * abs(wave)
						
						# Color de distorsión cuántica ROJA
						var quantum_color = Color(0.8, 0.2, 0.3)  # Rojo cuántico
						
						var existing = image.get_pixel(px, py)
						image.set_pixel(px, py, existing.lerp(quantum_color, intensity * 0.25))

# Configurar el rastreador de mouse
func setup_mouse_tracker():
	print("--- Configurando rastreador de mouse ---")
	
	# Verificar si el archivo MouseTracker existe
	var mouse_tracker_exists = FileAccess.file_exists("res://scripts/MouseTracker.gd")
	print("MouseTracker.gd existe: ", mouse_tracker_exists)
	
	if not mouse_tracker_exists:
		print("⚠️ MouseTracker.gd no encontrado, usando sistema básico...")
		setup_basic_mouse_tracking()
		return
	
	# Intentar cargar MouseTracker
	var mouse_tracker_script = load("res://scripts/MouseTracker.gd")
	if mouse_tracker_script:
		mouse_tracker = mouse_tracker_script.new()
		add_child(mouse_tracker)
		
		# Conectar señal de cambio de posición del mouse
		mouse_tracker.mouse_position_changed.connect(_on_mouse_position_changed)
		
		# Establecer el material del fondo en el tracker
		if background_material:
			mouse_tracker.set_background_material(background_material)
			print("✅ Material establecido en MouseTracker")
		
		print("✅ MouseTracker configurado correctamente")
	else:
		print("❌ Error cargando MouseTracker, usando sistema básico...")
		setup_basic_mouse_tracking()

# Sistema básico de tracking del mouse como respaldo
func setup_basic_mouse_tracking():
	print("Configurando tracking básico del mouse...")
	
	# Activar procesamiento de input
	set_process(true)
	
	print("✅ Tracking básico del mouse activado")

# Procesamiento básico del mouse (solo si MouseTracker falla)
func _process(delta: float):
	if background_material and not mouse_tracker:
		# Solo actualizar cada pocos frames para optimizar
		if Engine.get_process_frames() % 3 == 0:
			update_mouse_position_basic()

# Actualización básica de posición del mouse
func update_mouse_position_basic():
	if background_material:
		var mouse_pos = get_viewport().get_mouse_position()
		var viewport_size = get_viewport().get_visible_rect().size
		
		if viewport_size.x > 0 and viewport_size.y > 0:
			var normalized_pos = Vector2(
				mouse_pos.x / viewport_size.x,
				mouse_pos.y / viewport_size.y
			)
			background_material.set_shader_parameter("mouse_position", normalized_pos)

# Función que se ejecuta cuando cambia la posición del mouse
func _on_mouse_position_changed(position: Vector2):
	# Esta función se ejecuta cada vez que el mouse se mueve
	# Puedes agregar efectos adicionales aquí si es necesario
	pass

# Crear efecto de temblor en el título
func create_title_shake_effect():
	if not title_label:
		return
	
	# Guardar la posición original del título
	var original_position = title_label.position
	
	# Crear un Timer para el efecto de temblor
	var shake_timer = Timer.new()
	add_child(shake_timer)  # Agregar el timer como hijo de este nodo
	shake_timer.wait_time = 0.1  # Temblor cada 0.1 segundos
	shake_timer.autostart = true
	shake_timer.timeout.connect(_on_shake_timer_timeout.bind(original_position))

# Función que se ejecuta cada vez que el timer de temblor se dispara
func _on_shake_timer_timeout(original_pos: Vector2):
	if title_label:
		# Crear un temblor aleatorio muy sutil
		var shake_strength = 2.0  # Intensidad del temblor
		var random_offset = Vector2(
			randf_range(-shake_strength, shake_strength),  # Movimiento aleatorio en X
			randf_range(-shake_strength, shake_strength)   # Movimiento aleatorio en Y
		)
		title_label.position = original_pos + random_offset

# === FUNCIONES DE EFECTOS DE HOVER ===

# Función que se ejecuta cuando el mouse entra en un botón
func _on_button_hover(button: Button):
	print("Hover en botón: ", button.name)
	
	# === EFECTO VISUAL ===
	# Crear animación suave para cambiar el color del botón
	var tween = create_tween()
	# modulate cambia el color/transparencia. Color(1.2, 0.8, 0.8) = rojizo más brillante
	tween.tween_property(button, "modulate", Color(1.2, 0.8, 0.8), 0.2)
	
	# === EFECTO 3D EN EL FONDO ===
	# El MouseTracker se encarga automáticamente de actualizar la posición
	# No necesitamos hacer nada aquí, ya que se actualiza cada frame
	
	# === EFECTO DE AUDIO ===
	# Reproducir sonido de hover directamente
	play_hover_sound()

# Función que se ejecuta cuando el mouse sale de un botón
func _on_button_unhover(button: Button):
	# Volver al color original
	var tween = create_tween()
	tween.tween_property(button, "modulate", Color.WHITE, 0.3)

# === FUNCIONES DE NAVEGACIÓN ENTRE MENÚS ===

# Función que oculta todos los contenedores
func hide_all_containers():
	main_container.visible = false
	multiplayer_container.visible = false
	settings_container.visible = false
	language_container.visible = false

# Función que muestra un contenedor específico con animación
func show_container(container: Control):
	hide_all_containers()  # Primero ocultar todos
	container.visible = true  # Mostrar el deseado
	
	# Animar la aparición
	container.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(container, "modulate:a", 1.0, 0.3)

# === FUNCIONES DE RESPUESTA A BOTONES DEL MENÚ PRINCIPAL ===

# Función que se ejecuta cuando se presiona el botón "SINGLE PLAYER"
func _on_play_pressed():
	print("Iniciando modo un jugador...")
	
	# Reproducir sonido de clic
	play_click_sound()
	
	# Cambiar a la escena del juego
	# get_tree() obtiene el árbol principal de la escena
	# change_scene_to_file() cambia a una escena diferente
	get_tree().change_scene_to_file("res://maps/misiones/c1.tscn")

# Función que se ejecuta cuando se presiona el botón "MULTIPLAYER"
func _on_multiplayer_pressed():
	print("Abriendo menú multijugador...")
	play_click_sound()
	show_container(multiplayer_container)

# Función que se ejecuta cuando se presiona el botón "SETTINGS" 
func _on_settings_pressed():
	print("Abriendo configuración...")
	play_click_sound()
	show_container(settings_container)

# Función que se ejecuta cuando se presiona el botón "EXIT"
func _on_exit_pressed():
	print("Saliendo del juego...")
	play_click_sound()
	
	# Salir del juego
	# get_tree().quit() cierra completamente la aplicación
	get_tree().quit()

# === FUNCIONES DE RESPUESTA A BOTONES DEL MENÚ MULTIJUGADOR ===

# Función para crear/hostear una partida multijugador
func _on_host_pressed():
	print("Creando partida multijugador...")
	play_click_sound()
	
	# Aquí iría la lógica para crear un servidor
	# Por ahora, solo cambiar a la escena del juego
	get_tree().change_scene_to_file("res://maps/lobby.tscn")

# Función para unirse a una partida existente
func _on_join_pressed():
	print("Abriendo explorador de servidores...")
	play_click_sound()
	show_container(server_browser_container)
	
	# Inicializar el explorador de servidores
	setup_server_browser()
	refresh_server_list()

# === FUNCIONES DE RESPUESTA A BOTONES DE CONFIGURACIÓN ===

# Función para abrir configuración de idiomas
func _on_language_pressed():
	print("Abriendo selección de idioma...")
	play_click_sound()
	show_container(language_container)

# Función para abrir configuración de gráficos
func _on_graphics_pressed():
	print("Abriendo configuración gráfica...")
	play_click_sound()
	# Aquí se abriría un menú de configuración gráfica

# Función para abrir configuración de audio
func _on_audio_pressed():
	print("Abriendo configuración de audio...")
	play_click_sound()
	# Aquí se abriría un menú de configuración de audio

# === FUNCIONES DE SELECCIÓN DE IDIOMA ===

# Función que se ejecuta cuando se selecciona español
func _on_spanish_selected():
	print("Idioma cambiado a español")
	play_click_sound()
	current_language = "spanish"
	update_ui_language()  # Actualizar todos los textos
	save_language_preference()  # Guardar la preferencia

# Función que se ejecuta cuando se selecciona inglés
func _on_english_selected():
	print("Language changed to english")
	play_click_sound()
	current_language = "english" 
	update_ui_language()
	save_language_preference()

# === FUNCIONES DE NAVEGACIÓN "ATRÁS" ===

# Volver al menú principal desde cualquier submenú
func _on_back_to_main():
	print("Volviendo al menú principal...")
	play_back_sound()
	show_container(main_container)

# Volver a configuración desde selección de idioma
func _on_back_to_settings():
	print("Volviendo a configuración...")
	play_back_sound()
	show_container(settings_container)

# === FUNCIONES DE AUDIO ===

# Reproducir sonido de clic
func play_click_sound():
	print("🔊 Intentando reproducir sonido de click...")
	if ui_sounds:
		var click_sound = load("res://audio/sfx/menu/click.wav")
		if click_sound:
			ui_sounds.stream = click_sound
			ui_sounds.volume_db = -8.0
			ui_sounds.play()
			print("✅ Sonido de click reproducido")
		else:
			print("❌ No se pudo cargar click.wav")
	else:
		print("❌ Nodo ui_sounds no disponible")
	
	# === EFECTO DE VIBRACIÓN TERRORÍFICA ===
	# Activar vibración en el fondo al hacer clic
	trigger_horror_shake()

# Reproducir sonido de hover
func play_hover_sound():
	print("🔊 Intentando reproducir sonido de hover...")
	if ui_sounds:
		var hover_sound = load("res://audio/sfx/menu/hover.wav")
		if hover_sound:
			ui_sounds.stream = hover_sound
			ui_sounds.volume_db = -12.0
			ui_sounds.play()
			print("✅ Sonido de hover reproducido")
		else:
			print("❌ No se pudo cargar hover.wav")
	else:
		print("❌ Nodo ui_sounds no disponible")

# Reproducir sonido de transición
func play_transition_sound():
	print("🔊 Intentando reproducir sonido de transición...")
	if ui_sounds:
		var transition_sound = load("res://audio/sfx/menu/transition.wav")
		if transition_sound:
			ui_sounds.stream = transition_sound
			ui_sounds.volume_db = -6.0
			ui_sounds.play()
			print("✅ Sonido de transición reproducido")
		else:
			print("❌ No se pudo cargar transition.wav")
	else:
		print("❌ Nodo ui_sounds no disponible")

# === FUNCIONES DE EFECTOS INTERACTIVOS ===

# Esta función ya no es necesaria porque el MouseTracker se encarga automáticamente
# Se mantiene por compatibilidad pero está comentada
# func update_background_mouse_position():
# 	if background_material:
# 		# Obtener posición del mouse en la pantalla
# 		var mouse_pos = get_viewport().get_mouse_position()
# 		
# 		# Convertir a coordenadas normalizadas (0.0 a 1.0)
# 		var viewport_size = get_viewport().get_visible_rect().size
# 		var normalized_pos = Vector2(
# 			mouse_pos.x / viewport_size.x,
# 			mouse_pos.y / viewport_size.y
# 		)
# 		
# 		# Actualizar parámetro del shader
# 		background_material.set_shader_parameter("mouse_position", normalized_pos)

# Activar vibración terrorífica al hacer clic
func trigger_horror_shake():
	print("⚡ ACTIVANDO DISTORSIÓN DIGITAL FUTURISTA")
	
	# === REPRODUCIR SONIDO DE TRANSICIÓN ===
	play_transition_sound()
	
	if not background_material:
		print("❌ No hay material para distorsionar")
		return
	
	# Activar distorsión digital muy sutil (reducida 80%)
	background_material.set_shader_parameter("shake_intensity", 0.0024)  # Reducido 80% de 0.012
	print("✅ Intensidad de distorsión digital establecida: 0.0024 (ultra sutil)")
	
	# Crear timer para desactivar la distorsión después de 0.5 segundos
	var shake_timer = Timer.new()
	add_child(shake_timer)
	shake_timer.wait_time = 0.5  # Exactamente 0.5 segundos
	shake_timer.one_shot = true
	shake_timer.timeout.connect(_on_digital_distortion_finished)
	shake_timer.start()
	
	print("⏰ Timer de distorsión digital iniciado (0.5 segundos)")

# Función que se ejecuta cuando termina la distorsión digital
func _on_digital_distortion_finished():
	print("⚡ FINALIZANDO DISTORSIÓN DIGITAL")
	
	if background_material:
		background_material.set_shader_parameter("shake_intensity", 0.0)
		print("✅ Distorsión digital desactivada")
	else:
		print("❌ No se pudo desactivar distorsión - no hay material")

# Reproducir sonido de retroceso
func play_back_sound():
	# Usar el sonido de click para retroceder
	play_click_sound()

# === FUNCIONES DE PERSISTENCIA ===

# Cargar idioma guardado desde el archivo de configuración
func load_saved_language():
	# En un juego real, esto cargaría desde un archivo de configuración
	# Por ejemplo, usando ConfigFile de Godot
	
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")
	
	if err == OK:  # Si el archivo se cargó correctamente
		current_language = config.get_value("game", "language", "english")
		print("Idioma cargado: ", current_language)
	else:
		print("No se encontró archivo de configuración, usando inglés por defecto")
		current_language = "english"

# Guardar preferencia de idioma
func save_language_preference():
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

# === FUNCIONES DEL EXPLORADOR DE SERVIDORES ===

# Configuración inicial del explorador de servidores
func setup_server_browser():
	print("🌐 Configurando explorador de servidores...")
	
	# Configurar textos iniciales con temática de horror
	update_server_browser_texts()
	
	# Limpiar lista anterior
	clear_server_list()
	
	# Configurar estado inicial
	server_status_label.text = "Estado: Preparando antenas de comunicación..."
	
	print("✅ Explorador de servidores configurado")

# Actualizar textos del explorador con temática del juego
func update_server_browser_texts():
	var title_text = "EXPEDICIONES PERDIDAS"
	var subtitle_text = "Señales detectadas en el vacío cósmico..."
	
	server_browser_container.get_node("TitleLabel").text = title_text
	server_subtitle_label.text = subtitle_text

# Limpiar la lista de servidores
func clear_server_list():
	print("🧹 Limpiando lista de servidores...")
	
	# Eliminar todos los elementos hijos del contenedor de lista
	for child in server_list.get_children():
		child.queue_free()  # queue_free() elimina el nodo de forma segura

# Refrescar la lista de servidores
func refresh_server_list():
	print("🔄 Buscando expediciones disponibles...")
	
	# Actualizar estado
	server_status_label.text = "Estado: Escaneando frecuencias de emergencia..."
	server_subtitle_label.text = "Interceptando transmisiones de supervivientes..."
	
	# Limpiar lista actual
	clear_server_list()
	
	# Simular búsqueda con delay
	await get_tree().create_timer(1.5).timeout
	
	# Por ahora, generar servidores de ejemplo
	generate_sample_servers()
	
	# Actualizar estado final
	server_status_label.text = "Estado: Exploración completada"

# Generar servidores de ejemplo para demostración
func generate_sample_servers():
	print("📡 Generando lista de expediciones...")
	
	# Lista de expediciones ficticias con temática del juego
	var sample_servers = [
		{
			"name": "🚀 Expedición Aurora - ACTIVA",
			"description": "7/8 tripulantes • Estación Minera Artemis",
			"ping": 45,
			"players": 7,
			"max_players": 8,
			"status": "active",
			"ip": "192.168.1.100",
			"port": 7777
		},
		{
			"name": "⚠️ Carabela En Peligro - CRÍTICO", 
			"description": "4/8 tripulantes • Sistema Kepler-442",
			"ping": 89,
			"players": 4,
			"max_players": 8,
			"status": "critical",
			"ip": "192.168.1.101", 
			"port": 7777
		},
		{
			"name": "🔴 Expedición Perdida - SIN RESPUESTA",
			"description": "1/8 tripulantes • Ubicación Desconocida",
			"ping": 999,
			"players": 1,
			"max_players": 8,
			"status": "lost",
			"ip": "192.168.1.102",
			"port": 7777
		},
		{
			"name": "🟢 Estación Segura - ESTABLE",
			"description": "6/8 tripulantes • Base Lunar Europa", 
			"ping": 23,
			"players": 6,
			"max_players": 8,
			"status": "safe",
			"ip": "192.168.1.103",
			"port": 7777
		}
	]
	
	# Crear un elemento visual para cada servidor
	for server_data in sample_servers:
		create_server_item(server_data)

# Crear un elemento visual para un servidor individual
func create_server_item(server_data: Dictionary):
	# Crear contenedor principal del servidor
	var server_item = Panel.new()
	server_item.custom_minimum_size = Vector2(750, 80)
	
	# Configurar estilo del panel según el estado del servidor
	var style_box = StyleBoxFlat.new()
	match server_data.status:
		"active":
			style_box.bg_color = Color(0.1, 0.3, 0.1, 0.8)  # Verde oscuro
			style_box.border_color = Color(0.3, 0.8, 0.3, 1)
		"critical":
			style_box.bg_color = Color(0.3, 0.2, 0.1, 0.8)  # Naranja oscuro
			style_box.border_color = Color(0.9, 0.6, 0.2, 1)
		"lost":
			style_box.bg_color = Color(0.3, 0.1, 0.1, 0.8)  # Rojo oscuro
			style_box.border_color = Color(0.8, 0.3, 0.3, 1)
		"safe":
			style_box.bg_color = Color(0.1, 0.1, 0.3, 0.8)  # Azul oscuro
			style_box.border_color = Color(0.3, 0.3, 0.8, 1)
	
	style_box.border_width_left = 2
	style_box.border_width_right = 2
	style_box.border_width_top = 2
	style_box.border_width_bottom = 2
	style_box.corner_radius_top_left = 5
	style_box.corner_radius_top_right = 5
	style_box.corner_radius_bottom_left = 5
	style_box.corner_radius_bottom_right = 5
	
	server_item.add_theme_stylebox_override("panel", style_box)
	
	# Crear contenedor horizontal para organizar elementos
	var h_container = HBoxContainer.new()
	h_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h_container.add_theme_constant_override("separation", 15)
	server_item.add_child(h_container)
	
	# Información principal del servidor
	var info_container = VBoxContainer.new()
	info_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_container.add_child(info_container)
	
	# Nombre del servidor
	var name_label = Label.new()
	name_label.text = server_data.name
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	info_container.add_child(name_label)
	
	# Descripción del servidor
	var desc_label = Label.new()
	desc_label.text = server_data.description
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	info_container.add_child(desc_label)
	
	# Información de conexión (ping)
	var ping_container = VBoxContainer.new()
	ping_container.custom_minimum_size = Vector2(80, 0)
	h_container.add_child(ping_container)
	
	var ping_label = Label.new()
	var ping_color = Color.GREEN if server_data.ping < 50 else (Color.YELLOW if server_data.ping < 100 else Color.RED)
	ping_label.text = str(server_data.ping) + "ms"
	ping_label.add_theme_font_size_override("font_size", 16)
	ping_label.add_theme_color_override("font_color", ping_color)
	ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ping_container.add_child(ping_label)
	
	# Botón de conexión
	var connect_button = Button.new()
	connect_button.text = "UNIRSE"
	connect_button.custom_minimum_size = Vector2(100, 60)
	connect_button.add_theme_font_size_override("font_size", 16)
	
	# Configurar estilo del botón
	if server_data.status == "lost":
		connect_button.disabled = true
		connect_button.text = "PERDIDO"
		connect_button.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	else:
		connect_button.add_theme_color_override("font_color", Color.WHITE)
		# Conectar señal del botón para unirse al servidor
		connect_button.pressed.connect(_on_server_connect_pressed.bind(server_data))
	
	h_container.add_child(connect_button)
	
	# Agregar el elemento completo a la lista
	server_list.add_child(server_item)

# === FUNCIONES DE RESPUESTA A BOTONES DEL EXPLORADOR ===

# Función para refrescar servidores
func _on_refresh_servers_pressed():
	print("🔄 Botón refrescar presionado")
	play_click_sound()
	refresh_server_list()

# Función para conexión directa
func _on_direct_connect_pressed():
	print("🔌 Abriendo conexión directa...")
	play_click_sound()
	
	# Aquí iría un popup para ingresar IP y puerto manualmente
	server_status_label.text = "Estado: Función de conexión directa en desarrollo..."

# Función para volver al menú multijugador
func _on_back_to_multiplayer():
	print("⬅️ Volviendo al menú multijugador...")
	play_back_sound()
	show_container(multiplayer_container)

# Función para conectarse a un servidor específico
func _on_server_connect_pressed(server_data: Dictionary):
	print("🌐 Intentando conectar a: ", server_data.name)
	print("📡 IP: ", server_data.ip, ":", server_data.port)
	play_click_sound()
	
	# Actualizar estado
	server_status_label.text = "Estado: Estableciendo enlace cuántico con " + server_data.name + "..."
	
	# Aquí iría la lógica real de conexión a servidor
	# Por ahora solo simular el intento de conexión
	await get_tree().create_timer(2.0).timeout
	
	if server_data.status == "active" or server_data.status == "safe":
		server_status_label.text = "Estado: ¡Conexión establecida! Iniciando transferencia..."
		# Aquí cargaría la escena del juego
		print("✅ Conexión exitosa - Cargar escena de juego")
	else:
		server_status_label.text = "Estado: ⚠️ Fallo en la conexión - Señal demasiado débil"
		print("❌ Conexión fallida")
