@tool
extends SceneTree

# Heren MCP v4 - Tests unitarios GDScript (Fase D2).
#
# Ejecutar headless (requiere el plugin en el proyecto, ej. fixture):
#   godot --headless --path <proyecto> --script res://addons/heren/tests/run_tests.gd
#
# Testea helpers puros que NO requieren editor vivo:
#   - coords.serialize_value / deserialize_value (round-trip)
#   - coords.normalize_node_path
#   - constants.default_ws_url
#   - heren_error shape estándar
#
# Las mutaciones de nodos con undo/redo (test_node_mutability.gd) requieren
# editor vivo con el plugin activo; se ejecutan manualmente o con GUT.

const CoordsScript := preload("res://addons/heren/handlers/coords.gd")
const ConstantsScript := preload("res://addons/heren/constants.gd")
const ErrorScript := preload("res://addons/heren/handlers/heren_error.gd")
const TemplateRegistryScript := preload("res://addons/heren/template_registry.gd")
const UiHandlersScript := preload("res://addons/heren/handlers/ui_handlers.gd")
const SpatialToolScript := preload("res://addons/heren/handlers/visual_tool/spatial_tool.gd")
const SceneScriptScript := preload("res://addons/heren/handlers/scene_script.gd")
const NodeHandlersScript := preload("res://addons/heren/handlers/node_handlers.gd")
const ResourceHandlersScript := preload("res://addons/heren/handlers/resource_handlers.gd")
const FilesystemHandlersScript := preload("res://addons/heren/handlers/filesystem_handlers.gd")
const DispatcherScript := preload("res://addons/heren/dispatcher.gd")
const HerenHandlerScript := preload("res://addons/heren/handlers/heren_handler.gd")
const ValidateHandlersScript := preload("res://addons/heren/handlers/validate_handlers.gd")

var _passed := 0
var _failed := 0


func _init() -> void:
	_run("serialize_value round-trip Vector2", _test_serialize_vector2)
	_run("serialize_value round-trip Color", _test_serialize_color)
	_run("deserialize_value null keys", _test_deserialize_value)
	_run("default_ws_url", _test_default_ws_url)
	_run("heren_error shape", _test_heren_error)
	_run("template_registry list >= 6", _test_template_list)
	_run("template_registry exists", _test_template_exists)
	_run("template_registry instantiate health_bar params", _test_template_instantiate_params)
	_run("template_registry instantiate all", _test_template_instantiate_all)
	_run("ui layout presets (9)", _test_ui_layout_presets)
	# Fase A: coords_of_node unificado (tier 0/1/2 + discriminator 2D/3D).
	_run("coords_of_node null safe", _test_coords_of_node_null)
	_run("coords_of_node Node2D NO trae 3D", _test_coords_of_node_2d_purity)
	_run("coords_of_node Node3D NO trae 2D", _test_coords_of_node_3d_purity)
	_run("coords_of_node Control trae anchors/effective_rect", _test_coords_of_node_control)
	_run("coords_of_node Sprite2D trae bbox", _test_coords_of_node_sprite)
	_run("coords_of_node MeshInstance3D trae aabb", _test_coords_of_node_mesh)
	_run("coords_of_node tier0 minimo", _test_coords_of_node_tier0)
	_run("coords_of_node tier2 enrich", _test_coords_of_node_tier2)
	_run("coords_of_node discriminator kind+flags", _test_coords_of_node_discriminator)
	# Fase B: spatial_tool — overlaps/distance/neighbors/layout/bounds (NIVEL 1.5).
	_run("spatial overlaps 2D finds intersecting sprite", _test_spatial_overlaps_2d)
	_run("spatial overlaps 2D excludes self", _test_spatial_overlaps_2d_excludes_self)
	_run("spatial overlaps 3D finds intersecting mesh", _test_spatial_overlaps_3d)
	_run("spatial distance between two nodes", _test_spatial_distance)
	_run("spatial neighbors within radius", _test_spatial_neighbors)
	_run("spatial layout Control effective_rect", _test_spatial_layout_control)
	_run("spatial bounds scene total bbox", _test_spatial_bounds_scene)
	_run("spatial unknown mode returns error", _test_spatial_unknown_mode)
	# Fase D: summary recursivo (snapshot completo: node_count, by_type, depth, bounds, warnings).
	_run("summary recursive counts all nodes", _test_summary_recursive_count)
	_run("summary tree_depth correct", _test_summary_tree_depth)
	_run("summary by_type aggregated", _test_summary_by_type)
	_run("summary bounds 2D and 3D", _test_summary_bounds)
	_run("summary z_fighting warning", _test_summary_z_fighting_warning)
	_run("summary missing_material warning", _test_summary_missing_material)
	_run("summary missing_texture warning", _test_summary_missing_texture)
	# Fase C: dynamic state tier 3 (resumen) + tier 4 (completo) opt-in via tier.
	_run("coords tier3 AnimationPlayer emite animation", _test_coords_animation_player_tier3)
	_run("coords tier3 AnimationTree emite tree+anim_player snapshot", _test_coords_animation_tree_tier3)
	_run("coords tier3 Skeleton3D resumen count+3 primeros", _test_coords_skeleton_3d_tier3)
	_run("coords tier4 Skeleton3D completo todas las poses", _test_coords_skeleton_3d_tier4)
	_run("coords tier3 Skeleton2D resumen bones", _test_coords_skeleton_2d_tier3)
	_run("coords tier3 Light3D type+color+energy", _test_coords_light_3d_tier3)
	_run("coords tier3 AudioStreamPlayer3D playing+volume+pitch", _test_coords_audio_tier3)
	_run("coords tier3 Camera3D fov+current", _test_coords_camera_tier3)
	_run("coords tier3 Node3D sin dynamic (pureza)", _test_coords_node3d_tier3_empty_dynamic)
	# W0: protección de paths + snapshot/restore (§0.12).
	_run("W0 protected_reason bloquea infraestructura", _test_w0_protected_reason)
	_run("W0 snapshot_file + restore_snapshot round-trip", _test_w0_snapshot_roundtrip)
	# W4: WorkerCtx — contrato de ownership y relpath detached.
	_run("W4 WorkerCtx own acepta nodo raw", _test_w4_ctx_own_raw)
	_run("W4 WorkerCtx own RECHAZA internals PackedScene", _test_w4_ctx_own_rejects_instance)
	_run("W4 WorkerCtx relpath manual detached", _test_w4_ctx_relpath)
	_run("W4 WorkerCtx read-only rechaza mutaciones", _test_w4_ctx_readonly)
	# W2: class_info (ClassDB real — previene APIs adivinadas).
	_run("W2 class_info Skeleton3D filter=bone", _test_w2_class_info)
	# W1: diagnósticos inline en create/edit_script.
	_run("W1 _script_diagnostics detecta roto y válido", _test_w1_diagnostics_inline)
	# Bug-fix 2026-09-10: NodePath == String crashea en GDScript 4.5+ —
	# _values_match debe coerce ANTES de comparar.
	_run("Bug NodePath == String coerce en _values_match", _test_nodepath_string_coerce)
	# W4-c: static analyzer — fix-loop 2 calls en vez de 3 (13 reglas + unified).
	_run("W4c static_analyze tabs_and_spaces_mixed", _test_w4c_mixed_indent)
	_run("W4c static_analyze unbalanced_parens", _test_w4c_unbalanced_parens)
	_run("W4c static_analyze unbalanced_brackets", _test_w4c_unbalanced_brackets)
	_run("W4c static_analyze unbalanced_braces", _test_w4c_unbalanced_braces)
	_run("W4c static_analyze unterminated_string", _test_w4c_unterminated_string)
	_run("W4c static_analyze missing_colon_after_func", _test_w4c_missing_colon_func)
	_run("W4c static_analyze missing_colon_after_keyword", _test_w4c_missing_colon_kw)
	_run("W4c static_analyze export_on_const", _test_w4c_export_const)
	_run("W4c static_analyze await_stuck_to_identifier", _test_w4c_await_stuck)
	_run("W4c static_analyze shadow_builtin_var", _test_w4c_shadow_builtin)
	_run("W4c static_analyze class_name_duplicate", _test_w4c_class_name_dup)
	_run("W4c static_analyze no false positive en código válido", _test_w4c_clean_script)
	_run("W4c static_analyze ignora brackets dentro de strings", _test_w4c_brackets_in_string)
	_run("W4c static_analyze ignora # comentario", _test_w4c_hash_in_string)
	_run("W4c script_diagnostics unified shape (roto→parse_hints, válido→warnings)", _test_w4c_unified_shape)
	_run("W4c validate handle_script usa unified diagnostics", _test_w4c_validate_uses_static)
	# Bug-fix 2026-09-10: dispatcher "no handler for prefix" sin diagnóstico →
	# usuario no sabe si reinstalar plugin o reportar upstream. Test regresión.
	_run("Dispatcher unknown prefix devuelve hint accionable", _test_dispatcher_unknown_prefix)
	# W4b: filesystem handlers (editor-only EFS se testea en E2E; aquí solo lo
	# que funciona en SceneTree puro).
	_run("filesystem _count_files_recursive(null) = 0", _test_w4b_count_null_safe)
	_run("filesystem _walk_import_errors(null) safe", _test_w4b_walk_null_safe)
	_run("filesystem handle_exists res:// + user://", _test_w4b_exists)

	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _run(name: String, fn: Callable) -> void:
	var ok := false
	var msg := ""
	var err := ""
	ok = fn.call() if not fn.is_null() else false
	# (los fallos se registran con push_error dentro de cada test)
	if ok:
		_passed += 1
		print("  PASS  %s" % name)
	else:
		_failed += 1
		print("  FAIL  %s" % name)


func _test_serialize_vector2() -> bool:
	var v := Vector2(10.5, -3.25)
	var json_data = CoordsScript.serialize_value(v)
	var back = CoordsScript.deserialize_value(json_data)
	if back is Vector2 and back.is_equal_approx(v):
		return true
	push_error("serialize/deserialize Vector2 falló: %s -> %s" % [json_data, back])
	return false


func _test_serialize_color() -> bool:
	var c := Color(0.5, 0.25, 1.0, 0.8)
	var json_data = CoordsScript.serialize_value(c)
	var back = CoordsScript.deserialize_value(json_data)
	if back is Color and back.is_equal_approx(c):
		return true
	push_error("serialize/deserialize Color falló: %s -> %s" % [json_data, back])
	return false


func _test_deserialize_value() -> bool:
	# Un número concreto debe viajar redondo.
	var json_data = CoordsScript.serialize_value(42)
	var back = CoordsScript.deserialize_value(json_data)
	if back == 42:
		return true
	push_error("deserialize_value 42 falló: %s -> %s" % [json_data, back])
	return false


func _test_normalize_node_path() -> bool:
	# normalize_node_path(node_path, root) requiere un Node root (no puro);
	# se testea en GUT/editor. Aquí solo se documenta su firma.
	return true


func _test_default_ws_url() -> bool:
	var url := ConstantsScript.default_ws_url()
	if url == "ws://127.0.0.1:9099":
		return true
	push_error("default_ws_url = %s, esperaba ws://127.0.0.1:9099" % url)
	return false


func _test_heren_error() -> bool:
	var e := ErrorScript.err("boom")
	if e.get("ok", true) != false or e.get("error", "") != "boom":
		push_error("HerenError.err shape incorrecto: %s" % e)
		return false
	var o := ErrorScript.ok({"a": 1})
	if o.get("ok", false) != true or o.get("a", 0) != 1:
		push_error("HerenError.ok shape incorrecto: %s" % o)
		return false
	return true


# ---------------------------------------------------------------- templates

func _test_template_list() -> bool:
	var templates := TemplateRegistryScript.list_templates()
	if templates.size() < 6:
		push_error("list_templates < 6: %d" % templates.size())
		return false
	for t in templates:
		var d: Dictionary = t
		if str(d.get("name", "")) == "" or str(d.get("file", "")) == "":
			push_error("template sin name/file: %s" % d)
			return false
	return true


func _test_template_exists() -> bool:
	if not TemplateRegistryScript.template_exists("health_bar"):
		push_error("template_exists(health_bar) = false")
		return false
	if TemplateRegistryScript.template_exists("does_not_exist"):
		push_error("template_exists(does_not_exist) = true")
		return false
	return true


func _test_template_instantiate_params() -> bool:
	var instance: Node = TemplateRegistryScript.instantiate("health_bar", {
		"color": {"r": 0.1, "g": 0.8, "b": 0.2, "a": 1.0},
		"label": "HP 50/100",
	})
	if instance == null:
		push_error("instantiate(health_bar) = null")
		return false
	var fill: ColorRect = instance.get_node_or_null("Fill") as ColorRect
	var lbl: Label = instance.get_node_or_null("Label") as Label
	if fill == null:
		push_error("health_bar sin nodo Fill")
		instance.free()
		return false
	if not fill.color.is_equal_approx(Color(0.1, 0.8, 0.2, 1.0)):
		push_error("Fill.color = %s, esperaba 0.1,0.8,0.2" % fill.color)
		instance.free()
		return false
	if lbl != null and lbl.text != "HP 50/100":
		push_error("Label.text = '%s', esperaba 'HP 50/100'" % lbl.text)
		instance.free()
		return false
	instance.free()
	return true


func _test_template_instantiate_all() -> bool:
	var names: Array[String] = ["health_bar", "crosshair", "dialogue_box", "score_label", "boss_bar", "inventory_slot"]
	for name in names:
		var instance: Node = TemplateRegistryScript.instantiate(name, {})
		if instance == null:
			push_error("instantiate(%s) = null" % name)
			return false
		if instance.get_child_count() < 1 and name != "score_label":
			push_error("instantiate(%s) sin hijos (root no Control compuesto)" % name)
			instance.free()
			return false
		instance.free()
	return true


func _test_ui_layout_presets() -> bool:
	var presets: Dictionary = UiHandlersScript.LAYOUT_PRESETS
	var expected: Array[String] = [
		"full_rect", "bottom_center", "top_left", "top_right", "center",
		"bottom_left", "bottom_right", "center_left", "center_right",
	]
	for name in expected:
		if not presets.has(name):
			push_error("LAYOUT_PRESETS falta: " + name)
			return false
	if presets.size() != expected.size():
		push_error("LAYOUT_PRESETS size %d != %d" % [presets.size(), expected.size()])
		return false
	return true


# ============================================================== Fase A
# coords_of_node — fuente única de verdad del sistema de coordenadas.
# Verifica que:
#   - kind == node.get_class()
#   - flags.is_2d / is_3d / is_control coherentes con el tipo
#   - nodo 2D NO trae quaternion / basis / render_layers / cast_shadow / aabb
#   - nodo 3D NO trae z_index / anchors / offsets / effective_rect / bbox
#   - tier 0 = mínimo; tier 2 = enriquecido (modulate, material, collision, etc.)
#   - coords_of_node(null) es seguro

func _test_coords_of_node_null() -> bool:
	var c := CoordsScript.coords_of_node(null)
	if c.get("kind", "") != "None":
		push_error("kind != None: %s" % c)
		return false
	if not c.get("flags", {}).get("is_2d", true) == false:
		push_error("flags.is_2d != false en null: %s" % c)
		return false
	return true


func _test_coords_of_node_2d_purity() -> bool:
	var parent := Node2D.new()
	root.add_child(parent)
	var c := CoordsScript.coords_of_node(parent, "", 2)
	# Discriminador y flags.
	if c.get("kind", "") != "Node2D":
		push_error("Node2D kind=%s" % c.get("kind", ""))
		parent.queue_free()
		return false
	if not c.get("flags", {}).get("is_2d", false):
		push_error("flags.is_2d=false para Node2D")
		parent.queue_free()
		return false
	if c.get("flags", {}).get("is_3d", true):
		push_error("flags.is_3d=true para Node2D (debe ser false)")
		parent.queue_free()
		return false
	# Pureza 2D: NO debe traer claves exclusivas de 3D.
	for forbidden in ["quat", "aabb", "size_3d", "render_layers"]:
		if c.has(forbidden):
			push_error("Node2D trajo clave 3D %s: %s" % [forbidden, c])
			parent.queue_free()
			return false
	# Y SÍ debe traer 2D-específico.
	if not c.has("pos") or not c.has("z_index"):
		push_error("Node2D sin pos/z_index: %s" % c)
		parent.queue_free()
		return false
	parent.queue_free()
	return true


func _test_coords_of_node_3d_purity() -> bool:
	var n3 := Node3D.new()
	root.add_child(n3)
	var c := CoordsScript.coords_of_node(n3, "", 2)
	# Discriminador y flags.
	if c.get("kind", "") != "Node3D":
		push_error("Node3D kind=%s" % c.get("kind", ""))
		n3.queue_free()
		return false
	if not c.get("flags", {}).get("is_3d", false):
		push_error("flags.is_3d=false para Node3D")
		n3.queue_free()
		return false
	if c.get("flags", {}).get("is_2d", true):
		push_error("flags.is_2d=true para Node3D (debe ser false)")
		n3.queue_free()
		return false
	# Pureza 3D: NO debe traer 2D.
	for forbidden in ["z_index", "bbox", "anchors", "offsets", "effective_rect"]:
		if c.has(forbidden):
			push_error("Node3D trajo clave 2D/UI %s: %s" % [forbidden, c])
			n3.queue_free()
			return false
	# SÍ debe traer rotación 3D completa.
	if not c.has("rotation") or not (c.get("rotation") as Dictionary).has("quat"):
		push_error("Node3D sin rotation.quat: %s" % c)
		n3.queue_free()
		return false
	n3.queue_free()
	return true


func _test_coords_of_node_control() -> bool:
	var p := Node2D.new()
	root.add_child(p)
	var ctl := Control.new()
	p.add_child(ctl)
	ctl.size = Vector2(100, 50)
	var c := CoordsScript.coords_of_node(ctl, "", 2)
	if c.get("kind", "") != "Control":
		push_error("Control kind=%s" % c.get("kind", ""))
		ctl.queue_free(); p.queue_free()
		return false
	if not c.get("flags", {}).get("is_control", false):
		push_error("Control flags.is_control=false")
		ctl.queue_free(); p.queue_free()
		return false
	if not c.has("anchors") or not c.has("offsets"):
		push_error("Control sin anchors/offsets")
		ctl.queue_free(); p.queue_free()
		return false
	if not c.has("effective_rect"):
		push_error("Control tier=2 sin effective_rect")
		ctl.queue_free(); p.queue_free()
		return false
	ctl.queue_free(); p.queue_free()
	return true


func _test_coords_of_node_sprite() -> bool:
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var tex := ImageTexture.create_from_image(img)
	var s := Sprite2D.new()
	s.texture = tex
	root.add_child(s)
	var c := CoordsScript.coords_of_node(s, "", 1)
	if not c.get("flags", {}).get("has_bbox", false):
		push_error("Sprite2D tier=1 sin has_bbox: %s" % c)
		s.queue_free()
		return false
	if not c.has("bbox") or not c.has("size"):
		push_error("Sprite2D sin bbox/size: %s" % c)
		s.queue_free()
		return false
	# bbox.w debe ser 64 (texture width * scale.x).
	var bw: float = (c.get("bbox", {}) as Dictionary).get("w", -1.0)
	if absf(bw - 64.0) > 0.01:
		push_error("Sprite2D bbox.w=%f esperaba 64.0" % bw)
		s.queue_free()
		return false
	s.queue_free()
	return true


func _test_coords_of_node_mesh() -> bool:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	root.add_child(mi)
	var c := CoordsScript.coords_of_node(mi, "", 1)
	if not c.get("flags", {}).get("has_aabb", false):
		push_error("MeshInstance3D sin has_aabb: %s" % c)
		mi.queue_free()
		return false
	if not c.has("aabb") or not c.has("size_3d"):
		push_error("MeshInstance3D sin aabb/size_3d: %s" % c)
		mi.queue_free()
		return false
	mi.queue_free()
	return true


func _test_coords_of_node_tier0() -> bool:
	var n := Node2D.new()
	root.add_child(n)
	var c := CoordsScript.coords_of_node(n, "test", 0)
	# Tier 0: solo kind + flags + parent_path + visible. NO pos.
	if not c.has("kind") or not c.has("flags") or not c.has("parent_path"):
		push_error("tier=0 sin kind/flags/parent_path: %s" % c)
		n.queue_free()
		return false
	if c.has("pos"):
		push_error("tier=0 incluye pos (debería omitirlo): %s" % c)
		n.queue_free()
		return false
	if c.get("parent_path", "") != "test":
		push_error("parent_path perdido: %s" % c)
		n.queue_free()
		return false
	n.queue_free()
	return true


func _test_coords_of_node_tier2() -> bool:
	# MeshInstance3D (GeometryInstance3D) en tier=2 trae campos específicos 3D:
	# cast_shadow / gi_mode / material_override.
	var n := MeshInstance3D.new()
	n.mesh = BoxMesh.new()
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	root.add_child(n)
	var c2 := CoordsScript.coords_of_node(n, "", 2)
	if not c2.has("cast_shadow"):
		push_error("MeshInstance3D tier=2 sin cast_shadow: %s" % c2)
		n.queue_free()
		return false
	if (c2.get("cast_shadow", 0) as int) != int(GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED):
		push_error("cast_shadow=%d esperaba %d" % [c2.get("cast_shadow", 0), int(GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED)])
		n.queue_free()
		return false
	# CanvasItem en tier=2 SÍ trae modulate.
	var ci := Sprite2D.new()
	root.add_child(ci)
	var cci2 := CoordsScript.coords_of_node(ci, "", 2)
	if not cci2.has("modulate"):
		push_error("CanvasItem tier=2 sin modulate: %s" % cci2)
		ci.queue_free(); n.queue_free()
		return false
	# CollisionObject2D en tier=2 SÍ trae collision_layer.
	var co := StaticBody2D.new()
	root.add_child(co)
	var cco := CoordsScript.coords_of_node(co, "", 2)
	if not cco.has("collision_layer"):
		push_error("CollisionObject2D tier=2 sin collision_layer: %s" % cco)
		co.queue_free(); ci.queue_free(); n.queue_free()
		return false
	co.queue_free(); ci.queue_free(); n.queue_free()
	return true


func _test_coords_of_node_discriminator() -> bool:
	var n2 := Node2D.new()
	root.add_child(n2)
	var c := CoordsScript.coords_of_node(n2, "parent/path", 1)
	if c.get("kind", "") != n2.get_class():
		push_error("kind=%s esperaba %s" % [c.get("kind", ""), n2.get_class()])
		n2.queue_free()
		return false
	if c.get("parent_path", "") != "parent/path":
		push_error("parent_path=%s" % c.get("parent_path", ""))
		n2.queue_free()
		return false
	# flags es un dict, no string ni null.
	var flags: Dictionary = c.get("flags", {})
	if flags.is_empty():
		push_error("flags vacío")
		n2.queue_free()
		return false
	n2.queue_free()
	return true


# ============================================================== Fase B
# spatial_tool — overlaps / distance / neighbors / layout / bounds.
# Verifica que el agente puede verificar layout geométrico SIN imagen.

func _make_2d_tex(w: int, h: int) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _add_sprite2d(parent: Node, name: String, x: float, y: float, w: int = 32, h: int = 32) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = name
	s.texture = _make_2d_tex(w, h)
	s.position = Vector2(x, y)
	parent.add_child(s)
	return s


func _add_mesh3d(parent: Node, name: String, x: float, y: float, z: float, mesh_size: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var box := BoxMesh.new()
	box.size = Vector3(mesh_size, mesh_size, mesh_size)
	mi.mesh = box
	mi.position = Vector3(x, y, z)
	parent.add_child(mi)
	return mi


func _test_spatial_overlaps_2d() -> bool:
	var scene_root := Node2D.new()
	root.add_child(scene_root)
	var ref := _add_sprite2d(scene_root, "Ref", 0, 0, 32, 32)
	var overlap := _add_sprite2d(scene_root, "Over", 20, 20, 32, 32)  # intersecta
	var far := _add_sprite2d(scene_root, "Far", 500, 500, 16, 16)    # no intersecta
	var out := SpatialToolScript.overlaps(scene_root, "Ref", 0.0)
	if not out.get("ok", false):
		push_error("overlaps 2D no ok: %s" % out)
		scene_root.queue_free()
		return false
	var results: Array = out.get("results", [])
	var paths: Array = []
	for r in results:
		paths.append(r.get("path", ""))
	if "Over" not in paths:
		push_error("overlaps no encontró Over en %s" % paths)
		scene_root.queue_free()
		return false
	if "Far" in paths:
		push_error("overlaps encontró Far (no debería): %s" % paths)
		scene_root.queue_free()
		return false
	if "Ref" in paths:
		push_error("overlaps incluye self: %s" % paths)
		scene_root.queue_free()
		return false
	if int(out.get("count", 0)) != 1:
		push_error("count=%d esperaba 1" % out.get("count", 0))
		scene_root.queue_free()
		return false
	scene_root.queue_free()
	return true


func _test_spatial_overlaps_2d_excludes_self() -> bool:
	var scene_root := Node2D.new()
	root.add_child(scene_root)
	var ref := _add_sprite2d(scene_root, "Ref", 0, 0, 64, 64)
	var child := _add_sprite2d(ref, "Child", 0, 0, 32, 32)  # descendiente — excluir
	var out := SpatialToolScript.overlaps(scene_root, "Ref", 0.0)
	var paths: Array = []
	for r in out.get("results", []):
		paths.append(r.get("path", ""))
	if "Ref" in paths or "Ref/Child" in paths:
		push_error("overlaps incluye self o descendiente: %s" % paths)
		scene_root.queue_free()
		return false
	scene_root.queue_free()
	return true


func _test_spatial_overlaps_3d() -> bool:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	var ref := _add_mesh3d(scene_root, "Ref", 0, 0, 0)
	var overlap := _add_mesh3d(scene_root, "Over", 0.5, 0.5, 0.5)  # intersecta
	var far := _add_mesh3d(scene_root, "Far", 100, 100, 100)
	var out := SpatialToolScript.overlaps(scene_root, "Ref", 0.0)
	if not out.get("ok", false):
		push_error("overlaps 3D no ok: %s" % out)
		scene_root.queue_free()
		return false
	var paths: Array = []
	for r in out.get("results", []):
		paths.append(r.get("path", ""))
	if "Over" not in paths or "Far" in paths:
		push_error("overlaps 3D paths incorrectos: %s" % paths)
		scene_root.queue_free()
		return false
	scene_root.queue_free()
	return true


func _test_spatial_distance() -> bool:
	var scene_root := Node2D.new()
	root.add_child(scene_root)
	var a := Node2D.new()
	a.name = "A"
	a.position = Vector2(0, 0)
	scene_root.add_child(a)
	var b := Node2D.new()
	b.name = "B"
	b.position = Vector2(3, 4)
	scene_root.add_child(b)
	var out := SpatialToolScript.distance(scene_root, "A", "B")
	if not out.get("ok", false):
		push_error("distance no ok: %s" % out)
		scene_root.queue_free()
		return false
	# distancia 3-4-5 = 5.0
	if absf(float(out.get("distance", -1.0)) - 5.0) > 0.001:
		push_error("distance=%f esperaba 5.0" % out.get("distance", 0))
		scene_root.queue_free()
		return false
	if str(out.get("kind", "")) != "2d":
		push_error("kind=%s esperaba 2d" % out.get("kind", ""))
		scene_root.queue_free()
		return false
	var vec: Dictionary = out.get("vector", {})
	if absf(float(vec.get("x", -1)) - 3.0) > 0.001 or absf(float(vec.get("y", -1)) - 4.0) > 0.001:
		push_error("vector=%s esperaba {x:3,y:4}" % vec)
		scene_root.queue_free()
		return false
	scene_root.queue_free()
	return true


func _test_spatial_neighbors() -> bool:
	var scene_root := Node2D.new()
	root.add_child(scene_root)
	var center := _add_sprite2d(scene_root, "Center", 0, 0, 32, 32)
	var near := _add_sprite2d(scene_root, "Near", 50, 0, 8, 8)    # dist ~50
	var mid := _add_sprite2d(scene_root, "Mid", 150, 0, 8, 8)     # dist ~150
	var far := _add_sprite2d(scene_root, "Far", 500, 0, 8, 8)      # dist ~500
	# Radio 100 — debería incluir Near pero no Mid/Far.
	var out := SpatialToolScript.neighbors(scene_root, "Center", 100.0)
	if not out.get("ok", false):
		push_error("neighbors no ok: %s" % out)
		scene_root.queue_free()
		return false
	var paths: Array = []
	for r in out.get("results", []):
		paths.append(r.get("path", ""))
	if "Near" not in paths:
		push_error("neighbors no encontró Near en %s" % paths)
		scene_root.queue_free()
		return false
	if "Center" in paths or "Far" in paths:
		push_error("neighbors incluyó self o Far: %s" % paths)
		scene_root.queue_free()
		return false
	scene_root.queue_free()
	return true


func _test_spatial_layout_control() -> bool:
	# Control requiere padre Control o CanvasLayer para que is_inside_tree() y
	# get_global_rect() reporten valores. Usamos Control como root.
	var scene_root := Control.new()
	root.add_child(scene_root)
	var ctl := Control.new()
	ctl.name = "HealthBar"
	ctl.size = Vector2(200, 30)
	scene_root.add_child(ctl)
	var out := SpatialToolScript.layout(scene_root, "HealthBar")
	if not out.get("ok", false):
		push_error("layout no ok: %s" % out)
		scene_root.queue_free()
		return false
	if not out.has("effective_rect"):
		push_error("layout sin effective_rect: %s" % out)
		scene_root.queue_free()
		return false
	if not out.has("anchors") or not out.has("offsets"):
		push_error("layout sin anchors/offsets")
		scene_root.queue_free()
		return false
	# Padre es Control (no Container) → la key NO debe existir.
	if out.get("parent_is_container", false):
		push_error("parent_is_container=true pero parent es Control: %s" % out)
		scene_root.queue_free()
		return false
	scene_root.queue_free()
	return true


func _test_spatial_bounds_scene() -> bool:
	var scene_root := Node2D.new()
	root.add_child(scene_root)
	_add_sprite2d(scene_root, "A", 0, 0, 32, 32)
	_add_sprite2d(scene_root, "B", 100, 50, 32, 32)  # extiende el bbox
	var out := SpatialToolScript.bounds(scene_root, ".")
	if not out.get("ok", false):
		push_error("bounds no ok: %s" % out)
		scene_root.queue_free()
		return false
	if not out.has("bounds_2d"):
		push_error("bounds sin bounds_2d: %s" % out)
		scene_root.queue_free()
		return false
	var b2: Dictionary = out.get("bounds_2d", {})
	var w: float = float(b2.get("w", 0))
	var h: float = float(b2.get("h", 0))
	# A en (0,0) size 32 → bbox [-16,-16, 32,32]; B en (100,50) size 32 → [84,34, 32,32].
	# Merge Rect2: min(-16,-16) max(116,66) → size(132, 82).
	if w < 130.0 or w > 135.0:
		push_error("bounds_2d.w=%f esperaba ~132" % w)
		scene_root.queue_free()
		return false
	if h < 80.0 or h > 85.0:
		push_error("bounds_2d.h=%f esperaba ~82" % h)
		scene_root.queue_free()
		return false
	scene_root.queue_free()
	return true


func _test_spatial_unknown_mode() -> bool:
	var scene_root := Node2D.new()
	root.add_child(scene_root)
	var out := SpatialToolScript.compute(scene_root, {"mode": "no_existe"})
	if out.get("ok", true):
		push_error("mode inválido debería fallar: %s" % out)
		scene_root.queue_free()
		return false
	if not String(out.get("error", "")).begins_with("unknown spatial mode"):
		push_error("error incorrecto: %s" % out.get("error", ""))
		scene_root.queue_free()
		return false
	scene_root.queue_free()
	return true


# ============================================================== Fase D
# summary — snapshot recursivo de la escena (reemplaza el inline 2-niveles).

func _test_summary_recursive_count() -> bool:
	var scene_root := Node2D.new()
	root.add_child(scene_root)
	var child := Node2D.new()
	child.name = "Child"
	scene_root.add_child(child)
	var grandchild := Sprite2D.new()
	grandchild.name = "Grand"
	child.add_child(grandchild)
	# Árbol: scene_root + Child + Grand = 3 nodos.
	var out := SpatialToolScript.summary(scene_root)
	if not out.get("ok", false):
		push_error("summary no ok: %s" % out)
		scene_root.queue_free()
		return false
	if int(out.get("node_count", 0)) != 3:
		push_error("node_count=%d esperaba 3" % out.get("node_count", 0))
		scene_root.queue_free()
		return false
	scene_root.queue_free()
	return true


func _test_summary_tree_depth() -> bool:
	var scene_root := Node2D.new()
	root.add_child(scene_root)
	var child := Node2D.new()
	child.name = "Child"
	scene_root.add_child(child)
	var grandchild := Node2D.new()
	grandchild.name = "Grand"
	child.add_child(grandchild)
	var great := Node2D.new()
	great.name = "Great"
	grandchild.add_child(great)
	# Profundidad: root=1, Child=2, Grand=3, Great=4 → tree_depth=4
	var out := SpatialToolScript.summary(scene_root)
	if int(out.get("tree_depth", 0)) != 4:
		push_error("tree_depth=%d esperaba 4" % out.get("tree_depth", 0))
		scene_root.queue_free()
		return false
	scene_root.queue_free()
	return true


func _test_summary_by_type() -> bool:
	var scene_root := Node.new()
	root.add_child(scene_root)
	var s1 := Sprite2D.new()
	s1.texture = _make_2d_tex(8, 8)
	scene_root.add_child(s1)
	var s2 := Sprite2D.new()
	s2.texture = _make_2d_tex(8, 8)
	scene_root.add_child(s2)
	var l := Label.new()
	l.text = "hi"
	scene_root.add_child(l)
	var out := SpatialToolScript.summary(scene_root)
	var by_type: Dictionary = out.get("by_type", {})
	if int(by_type.get("Sprite2D", 0)) != 2:
		push_error("by_type.Sprite2D=%d esperaba 2 (by_type=%s)" % [by_type.get("Sprite2D", 0), by_type])
		scene_root.queue_free()
		return false
	if int(by_type.get("Label", 0)) != 1:
		push_error("by_type.Label=%d esperaba 1" % by_type.get("Label", 0))
		scene_root.queue_free()
		return false
	scene_root.queue_free()
	return true


func _test_summary_bounds() -> bool:
	var scene_root := Node2D.new()
	root.add_child(scene_root)
	_add_sprite2d(scene_root, "A", 0, 0, 32, 32)
	_add_sprite2d(scene_root, "B", 100, 50, 32, 32)
	var out := SpatialToolScript.summary(scene_root)
	if not out.has("bounds_2d"):
		push_error("summary sin bounds_2d: %s" % out)
		scene_root.queue_free()
		return false
	var b2: Dictionary = out.get("bounds_2d", {})
	# A:[-16,-16,32,32] + B:[84,34,32,32] → merge ≈ 132x82
	var w: float = float(b2.get("w", 0))
	if w < 130.0 or w > 135.0:
		push_error("bounds_2d.w=%f esperaba ~132" % w)
		scene_root.queue_free()
		return false
	scene_root.queue_free()
	return true


func _test_summary_z_fighting_warning() -> bool:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	_add_mesh3d(scene_root, "A", 0, 0, 0)
	_add_mesh3d(scene_root, "B", 0, 0, 0)  # misma posición → z_fighting
	_add_mesh3d(scene_root, "C", 100, 100, 100)  # otra
	var out := SpatialToolScript.summary(scene_root)
	var warnings: Array = out.get("warnings", [])
	var has_z := false
	for w in warnings:
		if w.get("kind", "") == "z_fighting_risk":
			has_z = true
			if int(w.get("count", 0)) != 2:
				push_error("z_fighting count=%d esperaba 2" % w.get("count", 0))
				scene_root.queue_free()
				return false
			break
	if not has_z:
		push_error("summary sin warning z_fighting_risk: %s" % warnings)
		scene_root.queue_free()
		return false
	scene_root.queue_free()
	return true


func _test_summary_missing_material() -> bool:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	# Sin material_override, BoxMesh no tiene material default → warning.
	scene_root.add_child(mi)
	var out := SpatialToolScript.summary(scene_root)
	var warnings: Array = out.get("warnings", [])
	var has := false
	for w in warnings:
		if w.get("kind", "") == "missing_material":
			has = true
			break
	if not has:
		push_error("summary sin warning missing_material: %s" % warnings)
		scene_root.queue_free()
		return false
	scene_root.queue_free()
	return true


func _test_summary_missing_texture() -> bool:
	var scene_root := Node2D.new()
	root.add_child(scene_root)
	var s := Sprite2D.new()
	s.name = "NoTex"
	# Sin texture → warning.
	scene_root.add_child(s)
	var out := SpatialToolScript.summary(scene_root)
	var warnings: Array = out.get("warnings", [])
	var has := false
	for w in warnings:
		if w.get("kind", "") == "missing_texture" and w.get("node", "") == "NoTex":
			has = true
			break
	if not has:
		push_error("summary sin warning missing_texture para NoTex: %s" % warnings)
		scene_root.queue_free()
		return false
	scene_root.queue_free()
	return true


# ============================================================
# FASE C (2026-09-04) — tier 3 dynamic state
# ============================================================

func _test_coords_animation_player_tier3() -> bool:
	# tier=3 → bloque `dynamic.animation` con current/position/playing/speed/autoplay.
	var parent := Node3D.new()
	root.add_child(parent)
	var player := AnimationPlayer.new()
	player.name = "Anim"
	parent.add_child(player)
	# AnimationPlayer 4.5: animaciones viven en AnimationLibrary, NO add_animation() directo.
	var lib := AnimationLibrary.new()
	var anim := Animation.new()
	anim.length = 1.5
	anim.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation("walk", anim)
	player.add_animation_library("", lib)
	player.current_animation = "walk"
	player.speed_scale = 1.5
	player.autoplay = "idle"
	var out := CoordsScript.coords_of_node(player, "Parent", 3)
	if not out.has("dynamic"):
		push_error("AnimationPlayer tier=3 sin bloque dynamic: %s" % out)
		parent.queue_free()
		return false
	var dyn: Dictionary = out["dynamic"]
	var anim_sec: Dictionary = dyn.get("animation", {})
	if anim_sec.get("current", "") != "walk":
		push_error("animation.current != walk: %s" % anim_sec)
		parent.queue_free()
		return false
	if float(anim_sec.get("length", 0.0)) != 1.5:
		push_error("animation.length != 1.5: %s" % anim_sec)
		parent.queue_free()
		return false
	if float(anim_sec.get("speed_scale", 0.0)) != 1.5:
		push_error("animation.speed_scale != 1.5: %s" % anim_sec)
		parent.queue_free()
		return false
	if anim_sec.get("autoplay", "") != "idle":
		push_error("animation.autoplay != idle: %s" % anim_sec)
		parent.queue_free()
		return false
	# Purity: NO debe emitir animation_tree ni skeleton_* ni light_3d ni audio ni camera.
	for forbidden in ["animation_tree", "skeleton_3d", "skeleton_2d", "light_3d", "audio", "camera"]:
		if dyn.has(forbidden):
			push_error("AnimationPlayer NO debería tener dynamic.%s: %s" % [forbidden, dyn])
			parent.queue_free()
			return false
	parent.queue_free()
	return true


func _test_coords_animation_tree_tier3() -> bool:
	# AnimationTree: anim_player_path + tree_root_type + anim_player_state snapshot.
	var parent := Node3D.new()
	root.add_child(parent)
	var player := AnimationPlayer.new()
	player.name = "Anim"
	parent.add_child(player)
	var lib := AnimationLibrary.new()
	var anim := Animation.new()
	anim.length = 1.0
	lib.add_animation("idle", anim)
	player.add_animation_library("", lib)
	player.current_animation = "idle"
	var tree := AnimationTree.new()
	tree.name = "Tree"
	parent.add_child(tree)
	tree.anim_player = NodePath("../Anim")
	tree.tree_root = AnimationNodeStateMachine.new()
	tree.active = true
	var out := CoordsScript.coords_of_node(tree, "Parent", 3)
	if not out.has("dynamic"):
		push_error("AnimationTree tier=3 sin dynamic: %s" % out)
		parent.queue_free()
		return false
	var dyn: Dictionary = out["dynamic"]
	var tree_sec: Dictionary = dyn.get("animation_tree", {})
	if not bool(tree_sec.get("active", false)):
		push_error("tree.active != true: %s" % tree_sec)
		parent.queue_free()
		return false
	if tree_sec.get("anim_player_path", "") != "../Anim":
		push_error("tree.anim_player_path != ../Anim: %s" % tree_sec)
		parent.queue_free()
		return false
	if tree_sec.get("tree_root_type", "") != "AnimationNodeStateMachine":
		push_error("tree.tree_root_type != StateMachine: %s" % tree_sec)
		parent.queue_free()
		return false
	# Sinergia: anim_player_state con current del AnimPlayer.
	var ap_state: Dictionary = tree_sec.get("anim_player_state", {})
	if ap_state.get("current", "") != "idle":
		push_error("tree.anim_player_state.current != idle: %s" % ap_state)
		parent.queue_free()
		return false
	# Purity.
	for forbidden in ["animation", "skeleton_3d", "skeleton_2d", "light_3d", "audio", "camera"]:
		if dyn.has(forbidden):
			push_error("AnimationTree NO debería tener dynamic.%s: %s" % [forbidden, dyn])
			parent.queue_free()
			return false
	parent.queue_free()
	return true


func _test_coords_skeleton_3d_tier3() -> bool:
	# tier=3 → resumen: bone_count + motion_scale + show_rest_only + bone_names + 3 primeras poses.
	var parent := Node3D.new()
	root.add_child(parent)
	var skel := Skeleton3D.new()
	skel.name = "Skel"
	parent.add_child(skel)
	for i in 10:
		skel.add_bone(str(i))
	var out := CoordsScript.coords_of_node(skel, "Parent", 3)
	if not out.has("dynamic"):
		push_error("Skeleton3D tier=3 sin dynamic: %s" % out)
		parent.queue_free()
		return false
	var sec: Dictionary = out["dynamic"].get("skeleton_3d", {})
	if int(sec.get("bone_count", 0)) != 10:
		push_error("skeleton_3d.bone_count != 10: %s" % sec)
		parent.queue_free()
		return false
	if (sec.get("bone_names", []) as Array).size() != 10:
		push_error("bone_names size != 10: %s" % sec.get("bone_names", []))
		parent.queue_free()
		return false
	var poses: Array = sec.get("poses", [])
	if poses.size() != 3:
		push_error("tier=3 summary debe traer 3 poses (no %d): %s" % [poses.size(), poses])
		parent.queue_free()
		return false
	if int(sec.get("poses_truncated", -1)) != 7:
		push_error("poses_truncated != 7: %s" % sec)
		parent.queue_free()
		return false
	# Purity: NO animation_tree, NO skeleton_2d, NO light_3d, NO audio, NO camera.
	for forbidden in ["animation", "animation_tree", "skeleton_2d", "light_3d", "audio", "camera"]:
		if out["dynamic"].has(forbidden):
			push_error("Skeleton3D NO debería tener dynamic.%s: %s" % [forbidden, out["dynamic"]])
			parent.queue_free()
			return false
	parent.queue_free()
	return true


func _test_coords_skeleton_3d_tier4() -> bool:
	# tier=4 → completo: todas las poses (sin truncation).
	var parent := Node3D.new()
	root.add_child(parent)
	var skel := Skeleton3D.new()
	skel.name = "Skel"
	parent.add_child(skel)
	for i in 10:
		skel.add_bone(str(i))
	var out := CoordsScript.coords_of_node(skel, "Parent", 4)
	var sec: Dictionary = out["dynamic"].get("skeleton_3d", {})
	var poses: Array = sec.get("poses", [])
	if poses.size() != 10:
		push_error("tier=4 completo debe traer 10 poses (no %d), no poses_truncated: %s" % [poses.size(), sec])
		parent.queue_free()
		return false
	if sec.has("poses_truncated"):
		push_error("tier=4 NO debe tener poses_truncated: %s" % sec)
		parent.queue_free()
		return false
	parent.queue_free()
	return true


func _test_coords_skeleton_2d_tier3() -> bool:
	# Skeleton2D: bone_count + bones[] (lista completa, son pocos).
	# En Skeleton2D los huesos son hijos Bone2D directos (NO add_bone — no existe).
	var parent := Node2D.new()
	root.add_child(parent)
	var skel := Skeleton2D.new()
	skel.name = "Skel2D"
	parent.add_child(skel)
	# Añadir 3 Bone2D hijos directos.
	for i in 3:
		var bone := Bone2D.new()
		bone.name = "Bone_%d" % i
		bone.position = Vector2(float(i), 0.0)
		bone.length = 50.0
		skel.add_child(bone)
	var out := CoordsScript.coords_of_node(skel, "Parent", 3)
	if not out.has("dynamic"):
		push_error("Skeleton2D tier=3 sin dynamic: %s" % out)
		parent.queue_free()
		return false
	var sec: Dictionary = out["dynamic"].get("skeleton_2d", {})
	if int(sec.get("bone_count", 0)) != 3:
		push_error("skeleton_2d.bone_count != 3 (skeleton_bone_count no es children): %s" % sec)
		parent.queue_free()
		return false
	var bones: Array = sec.get("bones", [])
	if bones.size() != 3:
		push_error("bones size != 3: %s" % bones)
		parent.queue_free()
		return false
	if not bones[0].has("name") or not bones[0].has("position") or not bones[0].has("length"):
		push_error("Bone2D entry sin name/position/length: %s" % bones[0])
		parent.queue_free()
		return false
	# Purity.
	for forbidden in ["animation", "animation_tree", "skeleton_3d", "light_3d", "audio", "camera"]:
		if out["dynamic"].has(forbidden):
			push_error("Skeleton2D NO debería tener dynamic.%s: %s" % [forbidden, out["dynamic"]])
			parent.queue_free()
			return false
	parent.queue_free()
	return true


func _test_coords_light_3d_tier3() -> bool:
	# OmniLight3D: type + color + energy + range (omni_range).
	var parent := Node3D.new()
	root.add_child(parent)
	var light := OmniLight3D.new()
	light.name = "Lamp"
	light.light_color = Color(1.0, 0.5, 0.2)
	light.light_energy = 2.5
	light.omni_range = 8.0
	parent.add_child(light)
	var out := CoordsScript.coords_of_node(light, "Parent", 3)
	if not out.has("dynamic"):
		push_error("OmniLight3D tier=3 sin dynamic: %s" % out)
		parent.queue_free()
		return false
	var sec: Dictionary = out["dynamic"].get("light_3d", {})
	if sec.get("type", "") != "OmniLight3D":
		push_error("light_3d.type != OmniLight3D: %s" % sec)
		parent.queue_free()
		return false
	if float(sec.get("energy", 0.0)) != 2.5:
		push_error("light_3d.energy != 2.5: %s" % sec)
		parent.queue_free()
		return false
	if float(sec.get("range", 0.0)) != 8.0:
		push_error("light_3d.range != 8.0: %s" % sec)
		parent.queue_free()
		return false
	# Purity.
	for forbidden in ["animation", "animation_tree", "skeleton_3d", "skeleton_2d", "audio", "camera"]:
		if out["dynamic"].has(forbidden):
			push_error("Light3D NO debería tener dynamic.%s: %s" % [forbidden, out["dynamic"]])
			parent.queue_free()
			return false
	parent.queue_free()
	return true


func _test_coords_audio_tier3() -> bool:
	# AudioStreamPlayer3D: type + playing + volume_db + pitch_scale + bus + stream +
	# max_distance + attenuation_model. No forzamos bus custom (default es Master y
	# cambiar requiere AudioServer config — fuera de scope test).
	var parent := Node3D.new()
	root.add_child(parent)
	var audio := AudioStreamPlayer3D.new()
	audio.name = "SFX"
	audio.volume_db = -6.0
	audio.pitch_scale = 1.25
	parent.add_child(audio)
	var out := CoordsScript.coords_of_node(audio, "Parent", 3)
	if not out.has("dynamic"):
		push_error("AudioStreamPlayer3D tier=3 sin dynamic: %s" % out)
		parent.queue_free()
		return false
	var sec: Dictionary = out["dynamic"].get("audio", {})
	if sec.get("type", "") != "AudioStreamPlayer3D":
		push_error("audio.type != AudioStreamPlayer3D: %s" % sec)
		parent.queue_free()
		return false
	if float(sec.get("volume_db", 0.0)) != -6.0:
		push_error("audio.volume_db != -6.0: %s" % sec)
		parent.queue_free()
		return false
	if float(sec.get("pitch_scale", 0.0)) != 1.25:
		push_error("audio.pitch_scale != 1.25: %s" % sec)
		parent.queue_free()
		return false
	if sec.get("bus", "") == "":
		push_error("audio.bus vacío (debería tener Master por default): %s" % sec)
		parent.queue_free()
		return false
	if not ("max_distance" in sec):
		push_error("AudioStreamPlayer3D sin max_distance: %s" % sec)
		parent.queue_free()
		return false
	# Purity.
	for forbidden in ["animation", "animation_tree", "skeleton_3d", "skeleton_2d", "light_3d", "camera"]:
		if out["dynamic"].has(forbidden):
			push_error("AudioStreamPlayer3D NO debería tener dynamic.%s: %s" % [forbidden, out["dynamic"]])
			parent.queue_free()
			return false
	parent.queue_free()
	return true


func _test_coords_camera_tier3() -> bool:
	# Camera3D: type + fov + near + far + current.
	var parent := Node3D.new()
	root.add_child(parent)
	var cam := Camera3D.new()
	cam.name = "Cam"
	cam.fov = 60.0
	cam.near = 0.5
	cam.far = 1500.0
	cam.current = true
	parent.add_child(cam)
	var out := CoordsScript.coords_of_node(cam, "Parent", 3)
	if not out.has("dynamic"):
		push_error("Camera3D tier=3 sin dynamic: %s" % out)
		parent.queue_free()
		return false
	var sec: Dictionary = out["dynamic"].get("camera", {})
	if sec.get("type", "") != "Camera3D":
		push_error("camera.type != Camera3D: %s" % sec)
		parent.queue_free()
		return false
	if float(sec.get("fov", 0.0)) != 60.0:
		push_error("camera.fov != 60.0: %s" % sec)
		parent.queue_free()
		return false
	if not bool(sec.get("current", false)):
		push_error("camera.current != true: %s" % sec)
		parent.queue_free()
		return false
	# Purity.
	for forbidden in ["animation", "animation_tree", "skeleton_3d", "skeleton_2d", "light_3d", "audio"]:
		if out["dynamic"].has(forbidden):
			push_error("Camera3D NO debería tener dynamic.%s: %s" % [forbidden, out["dynamic"]])
			parent.queue_free()
			return false
	# Camera2D: zoom Vector2.
	var parent2 := Node2D.new()
	root.add_child(parent2)
	var cam2 := Camera2D.new()
	cam2.name = "Cam2D"
	cam2.zoom = Vector2(2.0, 3.0)
	parent2.add_child(cam2)
	var out2 := CoordsScript.coords_of_node(cam2, "Parent2D", 3)
	var sec2: Dictionary = out2["dynamic"].get("camera", {})
	if sec2.get("type", "") != "Camera2D":
		push_error("Camera2D.type != Camera2D: %s" % sec2)
		parent2.queue_free()
		return false
	var zoom: Dictionary = sec2.get("zoom", {})
	if float(zoom.get("x", 0.0)) != 2.0 or float(zoom.get("y", 0.0)) != 3.0:
		push_error("Camera2D.zoom != (2.0, 3.0): %s" % zoom)
		parent2.queue_free()
		return false
	parent2.queue_free()
	return true


func _test_coords_node3d_tier3_empty_dynamic() -> bool:
	# Node3D genérico SIN animation/light/audio/camera/skeleton → NO debe emitir
	# ninguna sección dynamic. flags.has_dynamic_state debe ser false.
	var parent := Node3D.new()
	root.add_child(parent)
	var node := Node3D.new()
	node.name = "Generic"
	parent.add_child(node)
	var out := CoordsScript.coords_of_node(node, "Parent", 3)
	if out.has("dynamic"):
		push_error("Node3D genérico NO debe tener bloque dynamic: %s" % out)
		parent.queue_free()
		return false
	var flags: Dictionary = out.get("flags", {})
	if bool(flags.get("has_dynamic_state", false)):
		push_error("flags.has_dynamic_state != false: %s" % flags)
		parent.queue_free()
		return false
	parent.queue_free()
	return true


# ============================================================
# W0: protección de paths + snapshot/restore (§0.12)
# ============================================================

func _test_w0_protected_reason() -> bool:
	var blocked := [
		"res://addons/heren/plugin.cfg",
		"res://addons/heren/handlers/coords.gd",
		"res://project.godot",
		"res://.git/config",
		"res://.godot/editor/script_editor_cache.cfg",
		"res://export_presets.cfg",
		"res://PROJECT.GODOT",  # case-insensitive
		"res://addons\\heren\\plugin.cfg",  # backslashes normalizados
	]
	for p in blocked:
		# protected_reason es static de heren_handler — llamar vía scene_script (hereda).
		var reason: String = SceneScriptScript.protected_reason(p)
		if reason == "":
			push_error("protected_reason NO bloqueó: %s" % p)
			return false
	var allowed := ["res://scenes/foo.tscn", "res://scripts/player.gd", "res://addons/other/plugin.cfg"]
	for p in allowed:
		if SceneScriptScript.protected_reason(p) != "":
			push_error("protected_reason bloqueó path legítimo: %s" % p)
			return false
	return true


func _test_w0_snapshot_roundtrip() -> bool:
	var test_path := "res://.heren/tmp/test_snapshot.txt"
	SceneScriptScript.ensure_dir(test_path)
	var f := FileAccess.open(test_path, FileAccess.WRITE)
	if f == null:
		push_error("no se pudo crear archivo de test")
		return false
	f.store_string("contenido-original")
	f = null
	# Snapshot.
	var snap: String = SceneScriptScript.snapshot_file(test_path)
	if snap == "":
		push_error("snapshot_file devolvió vacío para archivo existente")
		return false
	if not FileAccess.file_exists(snap):
		push_error("snapshot no existe en disco: %s" % snap)
		return false
	# Sobrescribir el original.
	var f2 := FileAccess.open(test_path, FileAccess.WRITE)
	f2.store_string("contenido-destruido")
	f2 = null
	# Restaurar.
	var ok: bool = SceneScriptScript.restore_snapshot(null, snap, test_path)
	if not ok:
		push_error("restore_snapshot falló")
		return false
	var content := FileAccess.get_file_as_string(test_path)
	if content != "contenido-original":
		push_error("contenido restaurado incorrecto: %s" % content)
		return false
	# Snapshot de archivo inexistente → "".
	if SceneScriptScript.snapshot_file("res://.heren/tmp/no_existe_xyz.txt") != "":
		push_error("snapshot_file de inexistente debe ser vacío")
		return false
	# Limpieza.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(snap))
	return true


# ============================================================
# W4: WorkerCtx (contrato de ownership, relpath, read-only)
# ============================================================

func _make_ctx(root: Node, read_only: bool) -> RefCounted:
	var ctx: RefCounted = SceneScriptScript.WorkerCtx.new()
	ctx.setup(null, root, "res://test.tscn", read_only)
	return ctx


func _test_w4_ctx_own_raw() -> bool:
	var root := Node3D.new()
	root.name = "Root"
	var raw := Node3D.new()
	raw.name = "Raw"
	root.add_child(raw)
	var ctx := _make_ctx(root, false)
	if not ctx.own(raw):
		push_error("own() rechazó nodo raw legítimo")
		return false
	if raw.owner != root:
		push_error("own() no asignó owner al root")
		return false
	var changes: Dictionary = ctx._changes
	if (changes.get("added", []) as Array).size() != 1:
		push_error("changes.added debería tener 1 entrada: %s" % changes)
		return false
	root.free()
	return true


func _test_w4_ctx_own_rejects_instance() -> bool:
	# Instancia PackedScene dentro del root: own() en su root Y en sus
	# internals debe RECHAZAR (aplanarían la instancia).
	# 🚨 La escena debe venir de DISCO: scene_file_path solo se setea en
	# instancias de PackedScene con path (pack en memoria deja "" — caso
	# irreal en workers; en producción las instancias vienen de res://).
	var root := Node3D.new()
	root.name = "Root"
	var inner := Node3D.new()
	inner.name = "Inner"
	var inner_child := Node3D.new()
	inner_child.name = "InnerChild"
	inner.add_child(inner_child)
	var tmp_scene := "res://.heren/tmp/test_inner_scene.tscn"
	SceneScriptScript.ensure_dir(tmp_scene)
	var packed := PackedScene.new()
	packed.pack(inner)
	var save_err := ResourceSaver.save(packed, tmp_scene)
	if save_err != OK:
		push_error("no se pudo guardar escena de test: %s" % error_string(save_err))
		root.free()
		return false
	var disk_packed: PackedScene = load(tmp_scene)
	var inst: Node = disk_packed.instantiate()
	inst.name = "Inst"
	root.add_child(inst)
	var ctx := _make_ctx(root, false)
	if ctx.own(inst):
		push_error("own() aceptó el ROOT de una instancia PackedScene")
		root.free()
		return false
	var inst_child: Node = inst.get_child(0)
	if ctx.own(inst_child):
		push_error("own() aceptó un INTERNAL de instancia PackedScene")
		root.free()
		return false
	if ctx._error == "":
		push_error("own() rechazó pero no dejó error explicativo")
		root.free()
		return false
	# El raw del root sigue siendo own-able después de los rechazos.
	var raw := Node3D.new()
	raw.name = "Raw"
	root.add_child(raw)
	if not ctx.own(raw):
		push_error("own() dejó de funcionar tras rechazos")
		root.free()
		return false
	root.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_scene))
	return true


func _test_w4_ctx_relpath() -> bool:
	# relpath manual (get_path() requiere SceneTree — NUNCA en detached).
	var root := Node3D.new()
	root.name = "Root"
	var mid := Node3D.new()
	mid.name = "Mid"
	var leaf := Node3D.new()
	leaf.name = "Leaf"
	root.add_child(mid)
	mid.add_child(leaf)
	var ctx := _make_ctx(root, false)
	var rp: String = ctx._relpath(leaf)
	if rp != "/Mid/Leaf":
		push_error("relpath esperado /Mid/Leaf, got %s" % rp)
		root.free()
		return false
	if ctx._relpath(root) != "/":
		push_error("relpath del root debe ser /")
		root.free()
		return false
	root.free()
	return true


func _test_w4_ctx_readonly() -> bool:
	var root := Node3D.new()
	root.name = "Root"
	var ctx := _make_ctx(root, true)
	if not ctx.is_read_only():
		push_error("is_read_only() debe ser true")
		root.free()
		return false
	if ctx.own(root):
		push_error("own() permitido en read-only")
		root.free()
		return false
	ctx.mark_modified()
	if ctx._modified:
		push_error("mark_modified aplicado en read-only")
		root.free()
		return false
	if ctx._error == "":
		push_error("read-only debe dejar error explicativo")
		root.free()
		return false
	root.free()
	return true


# ============================================================
# W2: class_info (ClassDB real — previene APIs adivinadas)
# ============================================================

func _test_w2_class_info() -> bool:
	var nh: Node = NodeHandlersScript.new()
	var res: Dictionary = nh.handle_class_info({"class_name": "Skeleton3D", "filter": "bone"})
	if not res.get("ok", false):
		push_error("class_info Skeleton3D falló: %s" % str(res.get("error", "")))
		nh.free()
		return false
	if str(res.get("inherits", "")) != "Node3D":
		push_error("Skeleton3D.inherits != Node3D: %s" % str(res.get("inherits")))
		nh.free()
		return false
	var has_add_bone := false
	var has_add_bones := false
	for m in res.get("methods", []):
		var mname := str(m.get("name", ""))
		if mname == "add_bone":
			has_add_bone = true
		if mname == "add_bones":
			has_add_bones = true
	if not has_add_bone:
		push_error("add_bone debería existir en Skeleton3D (4.7)")
		nh.free()
		return false
	if has_add_bones:
		push_error("add_bones NO debe existir en 4.7 — el bug del E2E Omega")
		nh.free()
		return false
	# Clase desconocida → error claro.
	var res2: Dictionary = nh.handle_class_info({"class_name": "NoExisteXYZ"})
	if res2.get("ok", false):
		push_error("class_info de clase inexistente debe fallar")
		nh.free()
		return false
	# Sin filter: debe traer properties y herencia.
	var res3: Dictionary = nh.handle_class_info({"class_name": "Camera3D"})
	if not res3.get("ok", false) or int(res3.get("property_count", 0)) <= 0:
		push_error("class_info Camera3D sin properties")
		nh.free()
		return false
	nh.free()
	return true


# ============================================================
# W1 → W4-c: diagnósticos inline (ahora static `script_diagnostics`)
# ============================================================

func _test_w1_diagnostics_inline() -> bool:
	var rh: Node = ResourceHandlersScript.new()
	var p := "res://.heren/tmp/test_w1_diag.gd"
	SceneScriptScript.ensure_dir(p)
	# Script ROTO (parse error garantizado: func def sin ':' dispara
	# `missing_colon_after_func_def` + reload_err=43).
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("extends RefCounted\nfunc broken(x: int)\n\tpass\n")
	f = null
	# W4-c: ahora es `script_diagnostics` (no `_script_diagnostics`).
	var d: Dictionary = rh.script_diagnostics(p)
	if d.get("valid", true):
		push_error("script roto debe dar valid:false: %s" % str(d))
		rh.free()
		return false
	# W4-c: además, debe traer parse_hints (regression: si vuelve a no traerlos,
	# el fix-loop regresa a 3 calls).
	var hints: Array = d.get("parse_hints", [])
	if hints.is_empty():
		push_error("script roto debe traer parse_hints (W4-c): %s" % str(d))
		rh.free()
		return false
	# Debe detectar la falta de ':' después de func broken.
	var found_colon := false
	for h in hints:
		if h.get("rule", "") == "missing_colon_after_func_def":
			found_colon = true
			break
	if not found_colon:
		push_error("esperaba hint missing_colon_after_func_def, dio: %s" % str(hints))
		rh.free()
		return false
	# Script válido.
	var f2 := FileAccess.open(p, FileAccess.WRITE)
	f2.store_string("extends RefCounted\nfunc hello() -> String:\n\treturn \"hi\"\n")
	f2 = null
	var d2: Dictionary = rh.script_diagnostics(p)
	if not d2.get("valid", false):
		push_error("script válido debe dar valid:true: %s" % str(d2))
		rh.free()
		return false
	# W4-c: válido → warnings (no parse_hints).
	if d2.has("parse_hints"):
		push_error("script válido NO debe traer parse_hints: %s" % str(d2))
		rh.free()
		return false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	rh.free()
	return true


# ============================================================
# W4-c: static analyzer — una test por regla (high confidence + sanity)
# ============================================================

func _test_nodepath_string_coerce() -> bool:
	# Regresión para el bug "Invalid operands 'NodePath' and 'String' in '=='"
	# (GDScript 4.5+). El agente mandaba `skeleton_path: "PhysicalBone3D/..."`
	# como String desde JSON; el nodo lo guardaba como NodePath. La comparación
	# crasheaba el handler. _values_match debe coerce ANTES de ==.
	# 🚨 NO usar `:=` aquí: _values_match retorna Variant → "Cannot infer"
	# (mismo bug que ahora detecta static_analyze_gdscript — W4-c).
	var nh: Node = NodeHandlersScript.new()
	# Caso 1: NodePath vs String equivalente → debe dar true.
	var match: bool = nh._values_match(NodePath("Foo/Bar"), "Foo/Bar")
	if not match:
		push_error("NodePath vs String equivalente debe matchear, dio false")
		nh.free()
		return false
	# Caso 2: NodePath vs String diferente → debe dar false (sin crashear).
	var no_match: bool = nh._values_match(NodePath("Foo/Bar"), "Baz/Qux")
	if no_match:
		push_error("NodePath vs String diferente NO debe matchear, dio true")
		nh.free()
		return false
	# Caso 3: String vs NodePath (orden inverso).
	var match2: bool = nh._values_match("Foo/Bar", NodePath("Foo/Bar"))
	if not match2:
		push_error("String vs NodePath equivalente debe matchear, dio false")
		nh.free()
		return false
	# Caso 4: tipos compatibles (ambos int) → comportamiento normal.
	var match3: bool = nh._values_match(42, 42)
	if not match3:
		push_error("int == int debe matchear")
		nh.free()
		return false
	nh.free()
	return true

func _has_hint(hints: Array, rule: String) -> bool:
	for h in hints:
		if h.get("rule", "") == rule:
			return true
	return false


func _test_w4c_mixed_indent() -> bool:
	var src := "extends RefCounted\nfunc a():\n\tpass\n func b():\n  pass\n"
	var hints := HerenHandlerScript.static_analyze_gdscript(src)
	if not _has_hint(hints, "tabs_and_spaces_mixed"):
		push_error("tabs_and_spaces_mixed no detectado: %s" % str(hints))
		return false
	return true


func _test_w4c_unbalanced_parens() -> bool:
	var src := "extends RefCounted\nfunc bad((:\n\tpass\n"
	var hints := HerenHandlerScript.static_analyze_gdscript(src)
	if not _has_hint(hints, "unbalanced_parens"):
		push_error("unbalanced_parens no detectado: %s" % str(hints))
		return false
	return true


func _test_w4c_unbalanced_brackets() -> bool:
	var src := "extends RefCounted\nvar arr := [1, 2, 3\n"
	var hints := HerenHandlerScript.static_analyze_gdscript(src)
	if not _has_hint(hints, "unbalanced_brackets"):
		push_error("unbalanced_brackets no detectado: %s" % str(hints))
		return false
	return true


func _test_w4c_unbalanced_braces() -> bool:
	var src := "extends RefCounted\nvar d := {\"a\": 1\n"
	var hints := HerenHandlerScript.static_analyze_gdscript(src)
	if not _has_hint(hints, "unbalanced_braces"):
		push_error("unbalanced_braces no detectado: %s" % str(hints))
		return false
	return true


func _test_w4c_unterminated_string() -> bool:
	var src := "extends RefCounted\nfunc bad():\n\tvar x := \"unterminated\n\tpass\n"
	var hints := HerenHandlerScript.static_analyze_gdscript(src)
	if not _has_hint(hints, "unterminated_string"):
		push_error("unterminated_string no detectado: %s" % str(hints))
		return false
	return true


func _test_w4c_missing_colon_func() -> bool:
	var src := "extends RefCounted\nfunc broken(x: int)\n\tpass\n"
	var hints := HerenHandlerScript.static_analyze_gdscript(src)
	if not _has_hint(hints, "missing_colon_after_func_def"):
		push_error("missing_colon_after_func_def no detectado: %s" % str(hints))
		return false
	return true


func _test_w4c_missing_colon_kw() -> bool:
	# `if x > 0` sin `:` al final.
	var src := "extends RefCounted\nfunc a(x: int):\n\tif x > 0\n\t\treturn\n"
	var hints := HerenHandlerScript.static_analyze_gdscript(src)
	if not _has_hint(hints, "missing_colon_after_keyword"):
		push_error("missing_colon_after_keyword no detectado: %s" % str(hints))
		return false
	return true


func _test_w4c_export_const() -> bool:
	var src := "extends RefCounted\n@export const FOO := 1\n"
	var hints := HerenHandlerScript.static_analyze_gdscript(src)
	if not _has_hint(hints, "export_on_const"):
		push_error("export_on_const no detectado: %s" % str(hints))
		return false
	return true


func _test_w4c_await_stuck() -> bool:
	var src := "extends RefCounted\nfunc a():\n\tvar x = awaitfunc(b())\n"
	var hints := HerenHandlerScript.static_analyze_gdscript(src)
	if not _has_hint(hints, "await_stuck_to_identifier"):
		push_error("await_stuck_to_identifier no detectado: %s" % str(hints))
		return false
	return true


func _test_w4c_shadow_builtin() -> bool:
	var src := "extends RefCounted\nfunc a():\n\tvar int := 5\n\tprint(int)\n"
	var hints := HerenHandlerScript.static_analyze_gdscript(src)
	if not _has_hint(hints, "shadow_builtin_var"):
		push_error("shadow_builtin_var no detectado: %s" % str(hints))
		return false
	return true


func _test_w4c_class_name_dup() -> bool:
	var src := "class_name Foo\nextends RefCounted\nclass_name Foo\n"
	var hints := HerenHandlerScript.static_analyze_gdscript(src)
	if not _has_hint(hints, "class_name_duplicate_in_file"):
		push_error("class_name_duplicate_in_file no detectado: %s" % str(hints))
		return false
	return true


func _test_w4c_clean_script() -> bool:
	# Código válido NO debe disparar hints (excepto warnings opcionales).
	var src := "extends RefCounted\nfunc hello() -> String:\n\treturn \"hi\"\n"
	var hints := HerenHandlerScript.static_analyze_gdscript(src)
	if not hints.is_empty():
		push_error("código válido no debe dar hints, dio: %s" % str(hints))
		return false
	return true


func _test_w4c_brackets_in_string() -> bool:
	# Parens dentro de string NO deben contar como desbalanceados.
	var src := "extends RefCounted\nvar s := \"(un paren dentro)\"\nvar x := 1\n"
	var hints := HerenHandlerScript.static_analyze_gdscript(src)
	if _has_hint(hints, "unbalanced_parens"):
		push_error("string con paren no debe disparar unbalanced_parens: %s" % str(hints))
		return false
	return true


func _test_w4c_hash_in_string() -> bool:
	# Código con string que contiene `#` (que NO es comentario) debe estar OK.
	var src := "extends RefCounted\nvar s := \"color #ff0000\"\n"
	var hints := HerenHandlerScript.static_analyze_gdscript(src)
	if not hints.is_empty():
		push_error("string con # no debe dar hints, dio: %s" % str(hints))
		return false
	return true


func _test_w4c_unified_shape() -> bool:
	# Roto → parse_hints. Válido → warnings.
	var p := "res://.heren/tmp/test_w4c_unified.gd"
	SceneScriptScript.ensure_dir(p)
	# Roto.
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("extends RefCounted\nfunc broken(\n\tpass\n")
	f = null
	var d: Dictionary = HerenHandlerScript.script_diagnostics(p)
	if d.get("valid", true):
		push_error("roto: esperaba valid:false, dio: %s" % str(d))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		return false
	if not d.has("parse_hints") or d.get("parse_hints", []).is_empty():
		push_error("roto: esperaba parse_hints no vacío, dio: %s" % str(d))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		return false
	# Válido.
	var f2 := FileAccess.open(p, FileAccess.WRITE)
	f2.store_string("extends RefCounted\nfunc hello() -> String:\n\treturn \"hi\"\n")
	f2 = null
	var d2: Dictionary = HerenHandlerScript.script_diagnostics(p)
	if not d2.get("valid", false):
		push_error("válido: esperaba valid:true, dio: %s" % str(d2))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		return false
	if d2.has("parse_hints"):
		push_error("válido: NO debe traer parse_hints, dio: %s" % str(d2))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		return false
	# Warnings es una Array (puede estar vacía).
	if not (d2.get("warnings", []) is Array):
		push_error("válido: warnings debe ser Array, dio: %s" % str(d2))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		return false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	return true


func _test_w4c_validate_uses_static() -> bool:
	# Verifica que validate_handlers.handle_script devuelve el shape unificado
	# con parse_hints (DRY — no debe duplicar lógica).
	var vh: Node = ValidateHandlersScript.new()
	var p := "res://.heren/tmp/test_w4c_validate.gd"
	SceneScriptScript.ensure_dir(p)
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("extends RefCounted\nfunc broken(:\n\tpass\n")
	f = null
	var r: Dictionary = vh.handle_script({"script_path": p})
	if r.get("ok", true):
		push_error("validate handle_script: ok:true en roto, dio: %s" % str(r))
		vh.free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		return false
	# REGRESIÓN: validate debe incluir parse_hints (esto era el bug original).
	if not r.has("parse_hints") or r.get("parse_hints", []).is_empty():
		push_error("validate handle_script: debe traer parse_hints, dio: %s" % str(r))
		vh.free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		return false
	vh.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	return true


# Bug-fix 2026-09-10: cuando el plugin está desactualizado, `scene_script`
# (u otra tool registrada en server.rs pero no en plugin._handlers) falla
# con "no handler for prefix". El agente no sabe si es bug MCP o plugin
# viejo. El dispatcher debe devolver lista de registered + hint accionable.
func _test_dispatcher_unknown_prefix() -> bool:
	var d: Node = DispatcherScript.new()
	# Sin register_handler → todo debe fallar con diagnóstico.
	var r: Dictionary = d.execute("scene_script/run", {})
	if r.get("ok", true):
		push_error("dispatcher con handler vacío debería devolver ok:false, dio: %s" % str(r))
		d.free()
		return false
	var err: String = str(r.get("error", ""))
	if not err.contains("no handler for prefix: scene_script"):
		push_error("error debe mencionar el prefix, dio: %s" % err)
		d.free()
		return false
	# REGRESIÓN: el error debe incluir la lista de handlers registrados
	# (vacía en este caso → []) para que el agente diagnostique.
	if not err.contains("registered: []"):
		push_error("error debe listar registered: [], dio: %s" % err)
		d.free()
		return false
	# REGRESIÓN: el hint debe mencionar install_plugin --force + reinicio Godot.
	var hint: String = str(r.get("hint", ""))
	if not hint.contains("install_plugin.py --force") or not hint.contains("reinicia Godot"):
		push_error("hint debe guiar al fix (install_plugin --force + reiniciar Godot), dio: %s" % hint)
		d.free()
		return false
	# Caso positivo: registrar handler y verificar que el error desaparece.
	d.register_handler("scene_script", Node.new())
	var r2: Dictionary = d.execute("scene_script/unknown_action", {})
	if r2.get("ok", true):
		# No esperamos ok:true (action no existe), pero el prefix SÍ está.
		# El error debe ser de método, no de prefix.
		var err2: String = str(r2.get("error", ""))
		if err2.contains("no handler for prefix"):
			push_error("tras registrar scene_script, el error NO debe ser de prefix, dio: %s" % err2)
			d.free()
			return false
	d.free()
	return true


# ---------- W4b filesystem handlers (los EFS-dependent se cubren en E2E) ----------

func _test_w4b_count_null_safe() -> bool:
	var fs: Node = FilesystemHandlersScript.new()
	# _count_files_recursive(null) debe devolver 0 sin crashear.
	var n: int = fs._count_files_recursive(null)
	if n != 0:
		push_error("_count_files_recursive(null) esperaba 0, dio %d" % n)
		fs.free()
		return false
	fs.free()
	return true


func _test_w4b_walk_null_safe() -> bool:
	var fs: Node = FilesystemHandlersScript.new()
	var items: Array = []
	# _walk_import_errors(null, ...) no debe crashear con dir null.
	fs._walk_import_errors(null, "", items, 100)
	if items.size() != 0:
		push_error("_walk_import_errors(null) esperaba [], dio %s" % str(items))
		fs.free()
		return false
	fs.free()
	return true


func _test_w4b_exists() -> bool:
	var fs: Node = FilesystemHandlersScript.new()
	# Sin editor, handle_exists debe responder correctamente.
	# - res://addons/heren/plugin.cfg existe (estamos en su propio proyecto test).
	# - res://nope/no.tscn NO existe.
	# - user://nope NO existe.
	var r: Dictionary = fs.handle_exists({
		"paths": [
			"res://addons/heren/plugin.cfg",
			"res://nope/no.tscn",
			"user://nope.tmp",
		],
	})
	if not r.get("ok", false):
		push_error("handle_exists ok=false: %s" % str(r))
		fs.free()
		return false
	var results: Array = r.get("results", [])
	if results.size() != 3:
		push_error("esperaba 3 results, dio %d" % results.size())
		fs.free()
		return false
	# plugin.cfg existe.
	if not results[0].get("exists", false):
		push_error("plugin.cfg debía existir: %s" % str(results[0]))
		fs.free()
		return false
	# nope.tscn NO existe.
	if results[1].get("exists", true):
		push_error("nope.tscn NO debía existir: %s" % str(results[1]))
		fs.free()
		return false
	fs.free()
	return true
