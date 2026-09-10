@tool
extends Node

# Heren MCP v4 - Undo/Redo wrapper.
# Wraps mutation operations in EditorUndoRedoManager actions so that
# every operation from the MCP is undoable via Ctrl+Z (ADR-002 advantage).
# NOTE (Godot 4.6): add_do_method takes (Object, StringName, ...args),
# NOT a bare Callable.

var _editor_plugin: EditorPlugin


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func begin_action(action_name: String) -> void:
	var urm := _undo_redo_manager()
	if urm:
		urm.create_action(action_name)


func commit_action() -> void:
	var urm := _undo_redo_manager()
	if urm:
		urm.commit_action()


func add_do_method(obj: Object, method: StringName, args: Array = []) -> void:
	var urm := _undo_redo_manager()
	if urm:
		# add_do_method is varargs; callv expands the Array so add_child(node)
		# is called with the node, NOT with an Array wrapping it.
		var call_args: Array = [obj, method]
		call_args.append_array(args)
		urm.callv(&"add_do_method", call_args)


func add_undo_method(obj: Object, method: StringName, args: Array = []) -> void:
	var urm := _undo_redo_manager()
	if urm:
		var call_args: Array = [obj, method]
		call_args.append_array(args)
		urm.callv(&"add_undo_method", call_args)


func add_do_property(obj: Object, property: StringName, value: Variant) -> void:
	var urm := _undo_redo_manager()
	if urm:
		urm.add_do_property(obj, property, value)


func add_undo_property(obj: Object, property: StringName, value: Variant) -> void:
	var urm := _undo_redo_manager()
	if urm:
		urm.add_undo_property(obj, property, value)


func _undo_redo_manager() -> EditorUndoRedoManager:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_undo_redo()
