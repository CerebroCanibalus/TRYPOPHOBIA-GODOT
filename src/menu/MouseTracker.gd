# Script para rastrear la posición del mouse y actualizar efectos visuales
# Este script se ejecuta cada frame para mantener actualizada la posición del mouse
extends Node

# === SEÑALES ===
# Señal que se emite cuando cambia la posición del mouse
signal mouse_position_changed(position: Vector2)

# === VARIABLES ===
# Posición actual del mouse
var current_mouse_position: Vector2 = Vector2.ZERO

# Posición anterior del mouse (para detectar cambios)
var previous_mouse_position: Vector2 = Vector2.ZERO

# Referencia al material del fondo (se establece desde el menú principal)
var background_material: ShaderMaterial = null

# Configuración de sensibilidad
var mouse_sensitivity: float = 1.0
var update_threshold: float = 1.0  # Solo actualizar si el mouse se movió más de 1 píxel

# === FUNCIÓN DE INICIALIZACIÓN ===
func _ready():
	print("MouseTracker inicializado")
	
	# Configurar para que se ejecute cada frame
	set_process(true)

# === FUNCIÓN PRINCIPAL DE PROCESAMIENTO ===
# _process() se ejecuta cada frame (60 veces por segundo)
func _process(delta: float):
	# Obtener la posición actual del mouse
	var new_mouse_position = get_viewport().get_mouse_position()
	
	# Verificar si el mouse se movió lo suficiente como para actualizar
	if new_mouse_position.distance_to(previous_mouse_position) > update_threshold:
		# Actualizar posiciones
		previous_mouse_position = current_mouse_position
		current_mouse_position = new_mouse_position
		
		# Emitir señal de cambio
		mouse_position_changed.emit(current_mouse_position)
		
		# Actualizar shader si existe material
		update_shader_mouse_position()

# === FUNCIONES DE ACTUALIZACIÓN ===

# Actualizar la posición del mouse en el shader
func update_shader_mouse_position():
	if background_material:
		# Convertir posición de pantalla a coordenadas normalizadas (0.0 a 1.0)
		var viewport_size = get_viewport().get_visible_rect().size
		var normalized_position = Vector2(
			current_mouse_position.x / viewport_size.x,
			current_mouse_position.y / viewport_size.y
		)
		
		# Aplicar sensibilidad del mouse
		normalized_position = (normalized_position - Vector2(0.5, 0.5)) * mouse_sensitivity + Vector2(0.5, 0.5)
		
		# Asegurar que esté en el rango válido
		normalized_position = normalized_position.clamp(Vector2.ZERO, Vector2.ONE)
		
		# Actualizar parámetro del shader
		background_material.set_shader_parameter("mouse_position", normalized_position)

# Establecer el material del fondo
func set_background_material(material: ShaderMaterial):
	background_material = material
	print("Material de fondo establecido en MouseTracker")

# Configurar sensibilidad del mouse
func set_mouse_sensitivity(sensitivity: float):
	mouse_sensitivity = clamp(sensitivity, 0.1, 5.0)
	print("Sensibilidad del mouse establecida a: ", mouse_sensitivity)

# Obtener posición actual del mouse normalizada
func get_normalized_mouse_position() -> Vector2:
	var viewport_size = get_viewport().get_visible_rect().size
	return Vector2(
		current_mouse_position.x / viewport_size.x,
		current_mouse_position.y / viewport_size.y
	)

# === FUNCIONES DE UTILIDAD ===

# Verificar si el mouse está en movimiento
func is_mouse_moving() -> bool:
	return current_mouse_position != previous_mouse_position

# Obtener velocidad del mouse (píxeles por segundo)
func get_mouse_velocity() -> Vector2:
	return (current_mouse_position - previous_mouse_position) * 60.0  # 60 FPS

# Calcular distancia desde el centro de la pantalla
func get_distance_from_center() -> float:
	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	return current_mouse_position.distance_to(center) 