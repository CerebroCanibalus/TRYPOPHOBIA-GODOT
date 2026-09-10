@tool
extends Node

# Heren MCP v4 - Contrato base para handlers (Fase C4).
# Todos los handlers extienden esta clase para garantizar el contrato mínimo:
#   set_editor_plugin(plugin)  — inyecta el EditorPlugin
#   _editor_interface()        — acceso a EditorInterface
#   _args_dict(args, key)      — lee un dict desde args (string JSON o dict)
# Los handlers pueden sobrescribir set_editor_plugin para guardar extras
# (ej. _undo_redo) llamando super.set_editor_plugin(plugin).

const HerenError := preload("heren_error.gd")

var _editor_plugin: EditorPlugin


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_editor_interface()


## Lee `key` de args como Dictionary. Acepta dict directo o string JSON.
func _args_dict(args: Dictionary, key: String) -> Dictionary:
	var raw: Variant = args.get(key, {})
	if raw is Dictionary:
		return raw
	if raw is String:
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
	return {}


## Error canónico (shape estándar, Fase C6). Usar en handlers nuevos/migrados.
func _err(msg: String) -> Dictionary:
	return HerenError.err(msg)
