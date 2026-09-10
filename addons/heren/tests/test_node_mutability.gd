@tool
# Test de mutabilidad de nodos para Heren MCP v4.
#
# Se puede ejecutar de dos formas:
#   1. Con GUT instalado: añadir esta carpeta como suite de tests.
#   2. Desde línea de comandos: godot --headless --path <proyecto> --script addons/heren/tests/test_node_mutability.gd
#
# El test crea una escena temporal, opera nodos a través del dispatcher,
# verifica undo/redo y finalmente limpia.

extends Node

const SceneHandlers := preload("res://addons/heren/handlers/scene_handlers.gd")
const NodeHandlers := preload("res://addons/heren/handlers/node_handlers.gd")
const UndoRedoWrapper := preload("res://addons/heren/undo_redo_wrapper.gd")

var _plugin: EditorPlugin
var _scene_handlers: Node
var _node_handlers: Node
var _undo: Node
var _temp_scene_path := "res://_heren_test_temp_mutability.tscn"


func _ready() -> void:
	# En ejecución headless sin plugin activo, no tenemos EditorPlugin real.
	# Creamos uno mínimo solo si estamos dentro del editor.
	if Engine.is_editor_hint():
		_plugin = EditorPlugin.new()
	else:
		# Fallback para ejecución standalone: el test no puede correr sin editor.
		push_warning("Este test requiere ejecutarse dentro del editor de Godot (GUT o --script en editor).")
		get_tree().quit(0)
		return

	_setup()
	var passed := _run_all()
	_teardown()

	print("TEST_RESULT: %s" % ["PASS" if passed else "FAIL"])
	get_tree().quit(0 if passed else 1)


func _setup() -> void:
	_undo = UndoRedoWrapper.new()
	_undo.set_editor_plugin(_plugin)
	add_child(_undo)

	_scene_handlers = SceneHandlers.new()
	_scene_handlers.set_editor_plugin(_plugin)
	add_child(_scene_handlers)

	_node_handlers = NodeHandlers.new()
	_node_handlers.set_editor_plugin(_plugin)
	add_child(_node_handlers)

	# Crear escena limpia.
	_scene_handlers.handle_create({"scene_path": _temp_scene_path})
	_scene_handlers.handle_save({"scene_path": _temp_scene_path})


func _teardown() -> void:
	if _scene_handlers != null:
		_scene_handlers.handle_unload({"scene_path": _temp_scene_path})
	if FileAccess.file_exists(_temp_scene_path):
		DirAccess.remove_absolute(_temp_scene_path)
		# También intentar borrar el .uid si existe.
		if FileAccess.file_exists(_temp_scene_path + ".uid"):
			DirAccess.remove_absolute(_temp_scene_path + ".uid")
	if _node_handlers:
		_node_handlers.queue_free()
	if _scene_handlers:
		_scene_handlers.queue_free()
	if _undo:
		_undo.queue_free()


func _run_all() -> bool:
	var ok := true
	ok = _test_add_node() and ok
	ok = _test_set_property() and ok
	ok = _test_undo_redo() and ok
	ok = _test_duplicate() and ok
	ok = _test_remove_node() and ok
	return ok


func _test_add_node() -> bool:
	var result = _node_handlers.handle_add({
		"scene_path": _temp_scene_path,
		"parent_path": ".",
		"node_type": "Node2D",
		"node_name": "Hero",
	}) as Dictionary
	if not _assert_ok(result, "add Hero"):
		return false

	var info = _node_handlers.handle_get_info({
		"scene_path": _temp_scene_path,
		"node_path": "Hero",
	}) as Dictionary
	if not _assert_ok(info, "get_info Hero"):
		return false
	if info.get("type", "") != "Node2D":
		push_error("Hero deberia ser Node2D, es %s" % info.get("type"))
		return false
	return true


func _test_set_property() -> bool:
	var result = _node_handlers.handle_set_prop({
		"scene_path": _temp_scene_path,
		"node_path": "Hero",
		"property_name": "position",
		"value": {"x": 42.0, "y": 7.0},
	})
	if not _assert_ok(result, "set_prop position"):
		return false

	var info = _node_handlers.handle_get_info({
		"scene_path": _temp_scene_path,
		"node_path": "Hero",
	})
	if not _assert_ok(info, "get_info Hero after set_prop"):
		return false

	var pos = info.get("props", {}).get("position", {})
	if not (pos is Dictionary):
		push_error("position deberia ser Dictionary, es %s" % typeof(pos))
		return false
	if pos.get("x", -1) != 42.0 or pos.get("y", -1) != 7.0:
		push_error("position no coincide: %s" % pos)
		return false
	return true


func _test_undo_redo() -> bool:
	# Guardar posición antes del undo.
	var before = _node_handlers.handle_get_info({
		"scene_path": _temp_scene_path,
		"node_path": "Hero",
	})
	if not _assert_ok(before, "get_info before undo"):
		return false
	var before_pos = before.get("props", {}).get("position", {})

	_undo.undo()

	var after_undo = _node_handlers.handle_get_info({
		"scene_path": _temp_scene_path,
		"node_path": "Hero",
	})
	if not _assert_ok(after_undo, "get_info after undo"):
		return false
	var after_pos = after_undo.get("props", {}).get("position", {})

	if before_pos == after_pos:
		push_error("undo no cambio la posicion")
		return false

	_undo.redo()

	var after_redo = _node_handlers.handle_get_info({
		"scene_path": _temp_scene_path,
		"node_path": "Hero",
	})
	if not _assert_ok(after_redo, "get_info after redo"):
		return false
	var redo_pos = after_redo.get("props", {}).get("position", {})

	if redo_pos.get("x", -1) != 42.0 or redo_pos.get("y", -1) != 7.0:
		push_error("redo no restauró la posicion: %s" % redo_pos)
		return false
	return true


func _test_duplicate() -> bool:
	var result = _node_handlers.handle_duplicate({
		"scene_path": _temp_scene_path,
		"node_path": "Hero",
		"new_name": "HeroClone",
	})
	if not _assert_ok(result, "duplicate Hero"):
		return false

	var info = _node_handlers.handle_get_info({
		"scene_path": _temp_scene_path,
		"node_path": "HeroClone",
	})
	if not _assert_ok(info, "get_info HeroClone"):
		return false
	if info.get("type", "") != "Node2D":
		push_error("HeroClone deberia ser Node2D")
		return false
	return true


func _test_remove_node() -> bool:
	var result = _node_handlers.handle_remove({
		"scene_path": _temp_scene_path,
		"node_path": "HeroClone",
	})
	if not _assert_ok(result, "remove HeroClone"):
		return false

	var info = _node_handlers.handle_get_info({
		"scene_path": _temp_scene_path,
		"node_path": "HeroClone",
	})
	if info.get("ok", false):
		push_error("HeroClone deberia haber sido eliminado")
		return false
	return true


func _assert_ok(result: Dictionary, ctx: String) -> bool:
	if result.get("ok", false):
		return true
	push_error("[%s] fallo: %s" % [ctx, result.get("error", "sin error")])
	return false
