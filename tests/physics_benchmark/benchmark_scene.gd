## Escena de Benchmark de Física — Box3D vs Jolt
## Genera cientos de objetos físicos para estresar el motor de física.
## Activa Box3D desde Project Settings → Physics → 3D → Physics Engine → "Box3D Physics"
## y compara con Jolt cambiando a "Jolt Physics".
##
## CONTROLES:
## - Click derecho + Mouse: Cámara FPS
## - WASD: Mover horizontal
## - Q/E: Bajar/Subir
## - Shift: Velocidad x3
## - Click izquierdo: ¡BLAST! Empuja objetos cercanos al cursor
## - R: Reset escena
## - Space: Pausar física
## - Esc: Liberar mouse
extends Node3D

## Cuántos cuerpos caerán por columna.
@export var bodies_per_column: int = 30
## Cuántas columnas de objetos (en grilla X×Z).
@export var grid_columns: int = 10
## Separación entre columnas (metros).
@export var grid_spacing: float = 1.5
## Altura desde donde caen (metros).
@export var drop_height: float = 30.0
## Intervalo entre cada spawn (segundos).
@export var spawn_interval: float = 0.04

## Radio de la explosión al click (metros).
@export var blast_radius: float = 12.0
## Fuerza del impulso radial aplicada.
@export var blast_strength: float = 25.0
## Componente vertical del impulso (hace volar cosas hacia arriba).
@export var blast_upward: float = 8.0
## Máximo de objetos afectados por blast (para no saturar).
@export var blast_max_affected: int = 60

## Timer interno para spawn escalonado.
var _spawn_timer: float = 0.0
## Cola de objetos por spawnear.
var _spawn_queue: Array = []
## Objetos ya spawneados.
var _bodies_spawned: int = 0
## Timestamp de inicio.
var _start_time: float = 0.0
## Cantidad de blasts realizados.
var _blast_count: int = 0
## Último blast timestamp (para cooldown/cooldown visual).
var _last_blast_time: float = 0.0
## HUD overlay.
var _hud: CanvasLayer
var _label: RichTextLabel
var _label_right: RichTextLabel
var _label_metrics: RichTextLabel
var _graph_panel: Panel
## Background panel para legibilidad.
var _panel: Panel
var _panel_right: Panel
## Performance tracker con métricas reales.
var _tracker: Node = null
## Physics engine actual.
var _physics_engine: String = "UNKNOWN"

func _ready() -> void:
	# --- Detectar motor de física ---
	_physics_engine = ProjectSettings.get_setting("physics/3d/physics_engine", "DEFAULT")
	print("[Benchmark] Physics engine: %s" % _physics_engine)

	# --- Performance tracker ---
	var TrackerScript := preload("res://tests/physics_benchmark/performance_tracker.gd")
	_tracker = TrackerScript.new()
	_tracker.name = "PerformanceTracker"
	_tracker.set_context(_physics_engine.replace(" ", "_").to_lower())
	add_child(_tracker)

	# --- HUD ---
	_hud = CanvasLayer.new()
	_hud.layer = 100
	add_child(_hud)

	# Panel izquierdo (fondo semitransparente)
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(8, 8)
	_panel.size = Vector2(360, 200)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0.65)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 10
	panel_style.content_margin_top = 8
	panel_style.content_margin_right = 10
	panel_style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", panel_style)
	_hud.add_child(_panel)

	_label = RichTextLabel.new()
	_label.position = Vector2(18, 16)
	_label.size = Vector2(340, 184)
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.add_theme_font_size_override("normal_font_size", 18)
	_label.add_theme_color_override("default_color", Color.WHITE)
	_hud.add_child(_label)

	# Panel derecho (controles)
	_panel_right = Panel.new()
	_panel_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel_right.position = Vector2(-280, 8)
	_panel_right.size = Vector2(272, 250)
	_panel_right.add_theme_stylebox_override("panel", panel_style)
	_hud.add_child(_panel_right)

	_label_right = RichTextLabel.new()
	_label_right.position = Vector2(-270, 16)
	_label_right.size = Vector2(252, 234)
	_label_right.bbcode_enabled = true
	_label_right.fit_content = true
	_label_right.scroll_active = false
	_label_right.add_theme_font_size_override("normal_font_size", 14)
	_label_right.add_theme_color_override("default_color", Color(0.85, 0.9, 1.0))
	_hud.add_child(_label_right)

	# --- Panel de métricas detalladas (centro abajo) ---
	var metrics_panel := Panel.new()
	metrics_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	metrics_panel.position = Vector2(-300, -180)
	metrics_panel.size = Vector2(600, 140)
	var metrics_style := StyleBoxFlat.new()
	metrics_style.bg_color = Color(0, 0, 0, 0.75)
	metrics_style.set_corner_radius_all(8)
	metrics_panel.add_theme_stylebox_override("panel", metrics_style)
	_hud.add_child(metrics_panel)

	_label_metrics = RichTextLabel.new()
	_label_metrics.position = Vector2(-290, -170)
	_label_metrics.size = Vector2(580, 130)
	_label_metrics.bbcode_enabled = true
	_label_metrics.fit_content = true
	_label_metrics.scroll_active = false
	_label_metrics.add_theme_font_size_override("normal_font_size", 13)
	_label_metrics.add_theme_color_override("default_color", Color.WHITE)
	_hud.add_child(_label_metrics)

	# --- Panel para el graph ---
	_graph_panel = Panel.new()
	_graph_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_graph_panel.position = Vector2(-280, -200)
	_graph_panel.size = Vector2(272, 180)
	var graph_style := StyleBoxFlat.new()
	graph_style.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	graph_style.set_corner_radius_all(8)
	graph_style.border_color = Color(0.3, 0.6, 0.3, 0.5)
	graph_style.set_border_width_all(1)
	_graph_panel.add_theme_stylebox_override("panel", graph_style)
	_graph_panel.draw.connect(_on_graph_panel_draw)
	_hud.add_child(_graph_panel)

	# --- Suelo (StaticBody3D) ---
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.position = Vector3.ZERO
	add_child(floor_body)

	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(grid_columns * grid_spacing + 10.0, 0.5, grid_columns * grid_spacing + 10.0)
	floor_shape.shape = box
	floor_shape.position = Vector3(0.0, -0.25, 0.0)
	floor_body.add_child(floor_shape)

	var floor_mesh := MeshInstance3D.new()
	var plane_mesh := BoxMesh.new()
	plane_mesh.size = Vector3(grid_columns * grid_spacing + 10.0, 0.5, grid_columns * grid_spacing + 10.0)
	floor_mesh.mesh = plane_mesh
	floor_mesh.position = Vector3(0.0, -0.25, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.25, 0.28)
	floor_mesh.material_override = mat
	floor_body.add_child(floor_mesh)

	# --- Paredes de contención (4 lados) ---
	_add_wall(Vector3(0, 5, -(grid_columns * grid_spacing + 10.0) / 2.0),
		Vector3(grid_columns * grid_spacing + 10.0, 12.0, 0.5))
	_add_wall(Vector3(0, 5, (grid_columns * grid_spacing + 10.0) / 2.0),
		Vector3(grid_columns * grid_spacing + 10.0, 12.0, 0.5))
	_add_wall(Vector3(-(grid_columns * grid_spacing + 10.0) / 2.0, 5, 0),
		Vector3(0.5, 12.0, grid_columns * grid_spacing + 10.0))
	_add_wall(Vector3((grid_columns * grid_spacing + 10.0) / 2.0, 5, 0),
		Vector3(0.5, 12.0, grid_columns * grid_spacing + 10.0))

	# --- WorldEnvironment (configurar el que viene en la escena) ---
	var world_env := get_node_or_null("WorldEnvironment")
	if world_env == null:
		world_env = WorldEnvironment.new()
		add_child(world_env)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.12, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.3, 0.35)
	env.ambient_light_energy = 0.5
	world_env.environment = env

	# --- Generar cola de spawns ---
	var total := bodies_per_column * grid_columns * grid_columns
	_spawn_queue = []

	var offset_x := -(grid_columns - 1) * grid_spacing * 0.5
	var offset_z := -(grid_columns - 1) * grid_spacing * 0.5

	for x in range(grid_columns):
		for z in range(grid_columns):
			for y in range(bodies_per_column):
				var pos := Vector3(
					offset_x + x * grid_spacing + randf_range(-0.1, 0.1),
					drop_height + y * 1.2,
					offset_z + z * grid_spacing + randf_range(-0.1, 0.1)
				)
				_spawn_queue.append(pos)

	_start_time = Time.get_ticks_usec() / 1000000.0
	_spawn_timer = 0.0
	print("[Benchmark] Cola de %d objetos preparados." % total)


func _process(_delta: float) -> void:
	# El tracker maneja las métricas. Solo refrescamos HUD.
	_update_hud()


func _physics_process(delta: float) -> void:
	if _spawn_queue.is_empty():
		return

	_spawn_timer += delta
	while _spawn_timer >= spawn_interval and not _spawn_queue.is_empty():
		_spawn_timer -= spawn_interval
		_spawn_next_body()


func _on_graph_panel_draw() -> void:
	if _tracker == null or _graph_panel == null:
		return
	var rect := Rect2(Vector2.ZERO, _graph_panel.size)
	_tracker.draw_graph(_graph_panel, rect)
	# Etiquetas del graph
	_graph_panel.draw_string(ThemeDB.fallback_font, Vector2(8, 16),
		"Frame (azul) / Physics (verde)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	_graph_panel.draw_string(ThemeDB.fallback_font, Vector2(8, _graph_panel.size.y - 6),
		"60 FPS line", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.8, 0.5, 0.7))


func _spawn_next_body() -> void:
	if _spawn_queue.is_empty():
		return

	var pos: Vector3 = _spawn_queue.pop_back()
	_bodies_spawned += 1

	var body := RigidBody3D.new()
	body.name = "Box_%d" % _bodies_spawned
	body.position = pos
	body.mass = randf_range(0.5, 3.0)
	body.gravity_scale = 1.0
	body.linear_damp = 0.05
	body.angular_damp = 0.1
	body.contact_monitor = true
	body.max_contacts_reported = 4
	add_child(body)

	# Colisión
	var col := CollisionShape3D.new()
	var shape_type := randi() % 3
	match shape_type:
		0: # Caja
			var s := BoxShape3D.new()
			s.size = Vector3(randf_range(0.3, 0.8), randf_range(0.3, 0.8), randf_range(0.3, 0.8))
			col.shape = s
		1: # Cápsula
			var s := CapsuleShape3D.new()
			s.radius = randf_range(0.15, 0.35)
			s.height = randf_range(0.5, 1.2)
			col.shape = s
		2: # Esfera
			var s := SphereShape3D.new()
			s.radius = randf_range(0.2, 0.5)
			col.shape = s
	body.add_child(col)

	# Mesh visual
	var mesh_inst := MeshInstance3D.new()
	match shape_type:
		0:
			var m := BoxMesh.new()
			m.size = col.shape.size
			mesh_inst.mesh = m
		1:
			var m := CapsuleMesh.new()
			m.radius = col.shape.radius
			m.height = col.shape.height
			mesh_inst.mesh = m
		2:
			var m := SphereMesh.new()
			m.radius = col.shape.radius
			m.height = col.shape.radius * 2.0
			mesh_inst.mesh = m

	var mat := StandardMaterial3D.new()
	var hue := float(_bodies_spawned % 360) / 360.0
	mat.albedo_color = Color.from_hsv(hue, 0.6, 0.7)
	mat.roughness = 0.7
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)


func _add_wall(pos: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.position = pos
	add_child(wall)

	var col := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	col.shape = s
	wall.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mesh_inst.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.3
	mesh_inst.material_override = mat
	wall.add_child(mesh_inst)


func _update_hud() -> void:
	var elapsed := (Time.get_ticks_usec() / 1000000.0) - _start_time
	var total := bodies_per_column * grid_columns * grid_columns
	var remaining := _spawn_queue.size()

	# Engine display
	var engine_display := _physics_engine
	var engine_color := Color.WHITE
	if _physics_engine == "Box3D Physics":
		engine_display = "Box3D"
		engine_color = Color(0.4, 1.0, 0.6) # Verde
	elif _physics_engine == "Jolt Physics":
		engine_display = "Jolt"
		engine_color = Color(1.0, 0.7, 0.3) # Naranja
	else:
		engine_display = _physics_engine + " (default)"
		engine_color = Color(0.8, 0.8, 1.0)

	if _tracker:
		_label.text = (
			"[color=#ffd700]═══ PHYSICS BENCHMARK ═══[/color]\n"
			+ "Engine: [color=#%s]%s[/color]\n" % [engine_color.to_html(false), engine_display]
			+ "FPS:    [color=#ffd700]%.1f[/color]\n" % _tracker.current_fps
			+ "Bodies: [color=#ffd700]%d[/color] / %d\n" % [_bodies_spawned, total]
			+ "Queue:  %d remaining\n" % remaining
			+ "Blasts: [color=#ff6666]%d[/color]\n" % _blast_count
			+ "Time:   %.1fs" % elapsed
		)

		_label_metrics.text = (
			"[color=#ffd700]═══ DETAILED METRICS ═══[/color]\n"
			+ "[color=#88ddff]FRAME TIME (ms):[/color]\n"
			+ "  Cur:[color=#ffffff]%.2f[/color] Avg:[color=#ffffff]%.2f[/color] σ:[color=#ffffff]%.2f[/color]\n" % [_tracker.current_frame_ms, _tracker.avg_frame_ms, _tracker.std_frame_ms]
			+ "  Min:[color=#88ff88]%.2f[/color] p95:[color=#ffff88]%.2f[/color] p99:[color=#ff8888]%.2f[/color] Max:[color=#ff4444]%.2f[/color]\n" % [_tracker.min_frame_ms, _tracker.p95_frame_ms, _tracker.p99_frame_ms, _tracker.max_frame_ms]
			+ "[color=#88ff88]PHYSICS STEP (ms):[/color]\n"
			+ "  Cur:[color=#ffffff]%.2f[/color] Avg:[color=#ffffff]%.2f[/color] σ:[color=#ffffff]%.2f[/color]\n" % [_tracker.current_physics_ms, _tracker.avg_physics_ms, _tracker.std_physics_ms]
			+ "  Min:[color=#88ff88]%.2f[/color] p95:[color=#ffff88]%.2f[/color] p99:[color=#ff8888]%.2f[/color] Max:[color=#ff4444]%.2f[/color]\n" % [_tracker.min_physics_ms, _tracker.p95_physics_ms, _tracker.p99_physics_ms, _tracker.max_physics_ms]
			+ "Samples: %d  ·  CSV: user://benchmark_%s.csv" % [_tracker._all_frame_times.size(), _tracker._benchmark_label]
		)
	else:
		_label.text = "[color=#ffd700]═══ PHYSICS BENCHMARK ═══[/color]\nTracker not initialized"

	# Right panel: controls
	_label_right.text = (
		"[color=#ffd700]═══ CONTROLS ═══[/color]\n"
		+ "[b][color=#ff6666]Click izquierdo: BLAST[/color][/b]\n"
		+ "Click derecho + Mouse: Mirar\n"
		+ "WASD: Mover horizontal\n"
		+ "Q/E: Bajar/Subir\n"
		+ "Shift: Velocidad x3\n"
		+ "Esc: Liberar mouse\n"
		+ "R: Reset  ·  Space: Pausar\n"
		+ "\n"
		+ "[color=#ffd700]═══ BLAST ═══[/color]\n"
		+ "Radio: %.1fm  Fuerza: %.0f\n" % [blast_radius, blast_strength]
		+ "Upward: %.1f  Max hits: %d\n" % [blast_upward, blast_max_affected]
		+ "\n"
		+ "[color=#ffd700]═══ MÉTRICAS ═══[/color]\n"
		+ "Frame ms + Physics ms\n"
		+ "Min/Avg/p95/p99/Max\n"
		+ "Se exporta CSV cada 5s\n"
		+ "a user://benchmark_*.csv"
	)

func _unhandled_input(event: InputEvent) -> void:
	# Click izquierdo = BLAST
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_perform_blast(event.position)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				get_tree().reload_current_scene()
			KEY_SPACE:
				get_tree().paused = not get_tree().paused


func _perform_blast(screen_pos: Vector2) -> void:
	# Cooldown para no spamear (0.08s)
	var now := Time.get_ticks_usec() / 1000000.0
	if now - _last_blast_time < 0.08:
		return
	_last_blast_time = now

	# Obtener cámara activa
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	# Raycast desde la cámara a través del punto del cursor
	var ray_from := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var ray_to := ray_from + ray_dir * 200.0  # 200m max distance

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var hit := space.intersect_ray(query)
	var target_pos: Vector3

	if hit:
		target_pos = hit.position
	else:
		# Si no golpeó nada, usar un punto lejano en la dirección
		target_pos = ray_to

	# Aplicar impulso radial a todos los RigidBody3D dentro del radio
	var affected := 0
	var bodies := get_tree().get_nodes_in_group("blastable")
	if bodies.is_empty():
		# Si no usamos grupos, recorrer hijos directos
		bodies = get_children()

	# Ordenar por distancia para afectar los más cercanos primero
	var candidates: Array = []  # Array de [RigidBody3D, float]
	for node in bodies:
		if not (node is RigidBody3D):
			continue
		if not node.is_inside_tree():
			continue
		var rb: RigidBody3D = node
		var dist: float = rb.global_position.distance_to(target_pos)
		if dist <= blast_radius:
			candidates.append([rb, dist])

	candidates.sort_custom(func(a, b): return a[1] < b[1])

	for pair in candidates:
		if affected >= blast_max_affected:
			break
		var body: RigidBody3D = pair[0]
		var dist: float = pair[1]

		# Calcular dirección radial (huyendo del epicentro)
		var dir := (body.global_position - target_pos).normalized()
		if dir.length_squared() < 0.001:
			dir = Vector3.UP  # fallback si está exactamente encima

		# Falloff cuadrático: más cerca = más fuerza
		var falloff := 1.0 - (dist / blast_radius)
		falloff = falloff * falloff  # cuadrático

		var impulse := dir * blast_strength * falloff
		impulse.y += blast_upward * falloff  # componente vertical

		# Aplicar impulso
		body.apply_impulse(impulse)

		# También añadir torque random para hacerlos girar
		body.apply_torque_impulse(Vector3(
			randf_range(-1, 1),
			randf_range(-1, 1),
			randf_range(-1, 1)
		) * blast_strength * 0.05 * falloff)

		affected += 1

	_blast_count += 1
	if affected > 0:
		print("[Blast #%d] Affected %d bodies at %s" % [_blast_count, affected, target_pos])
