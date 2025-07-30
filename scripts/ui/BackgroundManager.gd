# === GESTOR DE EFECTOS VISUALES DEL MENÚ ===
# Responsable de manejar fondo interactivo, shaders y efectos de horror
extends Node

# === REFERENCIAS A NODOS VISUALES ===
var background_texture: TextureRect
var background_animation: AnimationPlayer
var title_label: Label
var background_material: ShaderMaterial
var mouse_tracker: Node

# === INICIALIZACIÓN ===
func setup_background_system(bg_texture: TextureRect, bg_animation: AnimationPlayer, title: Label):
	"""Configurar las referencias a elementos visuales"""
	background_texture = bg_texture
	background_animation = bg_animation
	title_label = title
	
	print("Configurando atmósfera de horror...")
	setup_interactive_background()
	setup_mouse_tracker()
	setup_animations()

# === CONFIGURACIÓN DE ANIMACIONES ===
func setup_animations():
	print("Configurando animaciones...")
	
	# Efectos visuales de horror
	if background_animation:
		background_animation.play("horror_idle")
	
	# Configurar el título con efecto de temblor
	if title_label:
		create_title_shake_effect()

# === CONFIGURACIÓN DEL FONDO INTERACTIVO ===
func setup_interactive_background():
	print("=== CONFIGURANDO FONDO DEL MENÚ CON FondoMenu.png ===")
	
	if not background_texture:
		print("ERROR: No se encontró el nodo BackgroundTexture")
		return
	
	print("BackgroundTexture encontrado: ", background_texture)
	
	# Cargar la imagen oficial del fondo del menú
	load_menu_background()
	
	# Crear material con shader para efectos interactivos
	setup_shader_material()
	
	print("=== CONFIGURACIÓN DE FONDO DEL MENÚ COMPLETADA ===")

# === CARGAR FONDO OFICIAL DEL MENÚ ===
func load_menu_background():
	"""Cargar la imagen oficial FondoMenu.png"""
	print("--- Cargando FondoMenu.png ---")
	
	# Cargar la imagen oficial del fondo
	var background_image = load("res://assets/textures/FondoMenu.png")
	if background_image:
		background_texture.texture = background_image
		print("✅ FondoMenu.png cargado correctamente")
	else:
		print("❌ ERROR: No se pudo cargar FondoMenu.png")
		# Fallback a color sólido si falla
		create_fallback_background()

# === CONFIGURAR MATERIAL CON SHADER ===
func setup_shader_material():
	"""Crear y configurar el material con shader para efectos interactivos"""
	print("--- Configurando shader para efectos interactivos ---")
	
	# Crear material con shader
	background_material = ShaderMaterial.new()
	print("Material creado: ", background_material)
	
	# Intentar cargar shader
	var shader_file = load("res://assets/shaders/simple_horror_background.gdshader")
	if not shader_file:
		print("No se pudo cargar shader simplificado, intentando con el complejo...")
		shader_file = load("res://assets/shaders/interactive_horror_background.gdshader")
	
	if shader_file:
		background_material.shader = shader_file
		print("✅ Shader cargado correctamente: ", shader_file)
		
		# Configurar parámetros para efectos sutiles sobre la imagen
		background_material.set_shader_parameter("shake_intensity", 0.0)
		background_material.set_shader_parameter("shake_speed", 30.0)
		background_material.set_shader_parameter("mouse_position", Vector2(0.5, 0.5))
		background_material.set_shader_parameter("parallax_strength", 0.025)
		background_material.set_shader_parameter("horror_tint", Vector3(0.6, 0.1, 0.1))
		background_material.set_shader_parameter("digital_glow", 1.3)
		background_material.set_shader_parameter("scan_speed", 2.5)
		
		print("✅ Parámetros del shader configurados")
		
		# Aplicar el material al fondo
		background_texture.material = background_material
		print("✅ Material aplicado al fondo")
		
	else:
		print("❌ WARNING: No se pudo cargar shader - efectos interactivos deshabilitados")

# === FONDO DE RESPALDO ===
func create_fallback_background():
	"""Crear un fondo de respaldo si falla la carga de la imagen"""
	print("--- Creando fondo de respaldo ---")
	
	# Crear una imagen simple de color sólido
	var texture_size = Vector2i(512, 512)
	var image = Image.create(texture_size.x, texture_size.y, false, Image.FORMAT_RGB8)
	
	# Rellenar con color oscuro apropiado para el juego
	var horror_color = Color(0.1, 0.05, 0.05)  # Rojo muy oscuro
	image.fill(horror_color)
	
	# Crear y aplicar la textura
	var texture = ImageTexture.new()
	texture.set_image(image)
	background_texture.texture = texture
	
	print("✅ Fondo de respaldo creado")

# === CONFIGURACIÓN DEL RASTREADOR DE MOUSE ===
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
		get_parent().add_child(mouse_tracker)
		
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

# === SISTEMA BÁSICO DE TRACKING DEL MOUSE ===
func setup_basic_mouse_tracking():
	print("Configurando tracking básico del mouse...")
	get_parent().set_process(true)
	print("✅ Tracking básico del mouse activado")

# === PROCESAMIENTO BÁSICO DEL MOUSE ===
func process_mouse_basic(delta: float):
	if background_material and not mouse_tracker:
		# Solo actualizar cada pocos frames para optimizar
		if Engine.get_process_frames() % 3 == 0:
			update_mouse_position_basic()

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

func _on_mouse_position_changed(position: Vector2):
	# Esta función se ejecuta cada vez que el mouse se mueve
	pass

# === EFECTOS DE HORROR ===
func trigger_horror_shake():
	"""Activar vibración terrorífica"""
	print("⚡ ACTIVANDO DISTORSIÓN DIGITAL FUTURISTA")
	
	if not background_material:
		print("❌ No hay material para distorsionar")
		return
	
	# Activar distorsión digital muy sutil
	background_material.set_shader_parameter("shake_intensity", 0.0024)
	print("✅ Intensidad de distorsión digital establecida: 0.0024 (ultra sutil)")
	
	# Crear timer para desactivar la distorsión después de 0.5 segundos
	var shake_timer = Timer.new()
	get_parent().add_child(shake_timer)
	shake_timer.wait_time = 0.5
	shake_timer.one_shot = true
	shake_timer.timeout.connect(_on_digital_distortion_finished)
	shake_timer.start()
	
	print("⏰ Timer de distorsión digital iniciado (0.5 segundos)")

func _on_digital_distortion_finished():
	"""Función que se ejecuta cuando termina la distorsión digital"""
	print("⚡ FINALIZANDO DISTORSIÓN DIGITAL")
	
	if background_material:
		background_material.set_shader_parameter("shake_intensity", 0.0)
		print("✅ Distorsión digital desactivada")
	else:
		print("❌ No se pudo desactivar distorsión - no hay material")

# === EFECTO DE TEMBLOR EN EL TÍTULO ===
func create_title_shake_effect():
	if not title_label:
		return
	
	# Crear efecto de pulsación constante para el título
	create_title_pulse_effect()
	
	# Guardar la posición original del título
	var original_position = title_label.position
	
	# Crear un Timer para el efecto de temblor sutil
	var shake_timer = Timer.new()
	get_parent().add_child(shake_timer)
	shake_timer.wait_time = 0.15
	shake_timer.autostart = true
	shake_timer.timeout.connect(_on_shake_timer_timeout.bind(original_position))

func create_title_pulse_effect():
	"""Crear efecto de pulsación constante en el título"""
	if not title_label:
		return
	
	print("--- Creando efecto de pulsación en el título ---")
	
	# Crear animación de pulsación continua
	var pulse_tween = create_tween()
	pulse_tween.set_loops()  # Hacer que se repita infinitamente
	
	# Configurar secuencia de pulsación
	pulse_tween.tween_property(title_label, "modulate:a", 0.7, 2.0)
	pulse_tween.tween_property(title_label, "modulate:a", 1.0, 2.0)
	
	# Crear efecto de brillo adicional
	var glow_tween = create_tween()
	glow_tween.set_loops()
	
	# Efecto de cambio de color sutil (más blanco brillante)
	var original_color = title_label.modulate
	var bright_color = Color(1.1, 1.1, 1.1, 1.0)
	
	glow_tween.tween_property(title_label, "modulate", bright_color, 3.0)
	glow_tween.tween_property(title_label, "modulate", original_color, 3.0)
	
	print("✅ Efecto de pulsación del título activado")

func _on_shake_timer_timeout(original_pos: Vector2):
	if title_label:
		# Crear un temblor aleatorio muy sutil
		var shake_strength = 1.0
		var random_offset = Vector2(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength)
		)
		title_label.position = original_pos + random_offset 