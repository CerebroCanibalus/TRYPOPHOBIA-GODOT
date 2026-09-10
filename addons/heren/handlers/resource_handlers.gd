@tool
extends "res://addons/heren/handlers/heren_handler.gd"
# Heren MCP v4 - Resource handlers (Fase 2).
# Recursos .tres y scripts .gd vía EditorFileSystem + ResourceSaver (ADR-002):
# el editor vivo importa, valida y da tipos. Sin session_id: la operación se
# hace contra el proyecto del editor abierto.
#
# Actions (heredadas de v3 resource_tool.py, adaptadas a editor vivo):
#   create          -> ClassDB.instantiate + props + ResourceSaver.save
#   read            -> ResourceLoader.load + serializar propiedades
#   update          -> load + props + save
#   delete          -> DirAccess.remove
#   list            -> DirAccess walk (filtro por extensión, recursivo)
#   create_script   -> FileAccess escribir .gd con template
#   read_script     -> FileAccess leer .gd
#   edit_script     -> FileAccess reescribir/append .gd
#
# NO portado de v3: update_scene_subresource (parcheaba .tscn en texto; en v4
# la escena viva se edita con node_handlers, sin tocar el archivo a mano).

const HerenCoordsScript := preload("coords.gd")
const HerenSceneRegistryScript := preload("../scene_registry.gd")



func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


# ---------------------------------------------------------------- helpers

func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_editor_interface()


func _ensure_parent_dir(path: String) -> void:
	var dir_path := path.get_base_dir()
	if dir_path != "" and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))


## Accepts a Dictionary directly, or a JSON string (clients may send either).
func _args_dict(args: Dictionary, key: String) -> Dictionary:
	var raw: Variant = args.get(key, {})
	if raw is Dictionary:
		return raw
	if raw is String:
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
	return {}


## Type of a file via EditorFileSystem (e.g. "GDScript", "ShaderMaterial").
func _file_type(res_path: String) -> String:
	var ei := _editor_interface()
	if ei == null:
		return ""
	var efs: EditorFileSystem = ei.get_resource_filesystem()
	if efs == null:
		return ""
	return efs.get_file_type(res_path)


## Serialize all STORAGE properties of a resource (skip internal/runtime).
func _serialize_resource_props(res: Resource) -> Dictionary:
	var out := {}
	for prop in res.get_property_list():
		var usage: int = int(prop.usage)
		if usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		if usage & PROPERTY_USAGE_INTERNAL != 0:
			continue
		var name: StringName = prop.name
		if name in ["resource_path", "resource_local_to_scene", "resource_name"]:
			continue
		out[name] = HerenCoordsScript.serialize_value(res.get(name), true)
	return out


## Walk a directory collecting files. Works with res:// or user:// paths.
func _walk(dir_path: String, ext: String, recursive: bool, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if dir.current_is_dir():
			if recursive and not fname.begins_with("."):
				_walk(dir_path.path_join(fname), ext, true, out)
		else:
			if ext == "" or fname.get_extension() == ext:
				var full := dir_path.path_join(fname)
				out.append({
					"path": full,
					"name": fname,
					"type": _file_type(full),
				})
		fname = dir.get_next()
	dir.list_dir_end()


## Small template map for create_script (kept tiny - no full engine).
func _script_template(template: String) -> String:
	match template:
		"CharacterBody2D":
			return "extends CharacterBody2D\n\n\nfunc _physics_process(_delta: float) -> void:\n\tpass\n"
		"Node2D":
			return "extends Node2D\n\n\nfunc _ready() -> void:\n\tpass\n"
		"RefCounted":
			return "extends RefCounted\n\n\nfunc _init() -> void:\n\tpass\n"
		"Resource":
			return "extends Resource\n\n\nfunc _init() -> void:\n\tpass\n"
		_:
			return "extends Node\n\n\nfunc _ready() -> void:\n\tpass\n"


# ---------------------------------------------------------------- handlers

func handle_create(args: Dictionary) -> Dictionary:
	var resource_path: String = str(args.get("resource_path", ""))
	var resource_type: String = str(args.get("resource_type", "Resource"))
	if resource_path == "":
		return {"ok": false, "error": "resource_path required"}

	var resource: Variant = ClassDB.instantiate(resource_type)
	if resource == null or not resource is Resource:
		return {"ok": false, "error": "invalid_resource_type: " + resource_type}
	var res := resource as Resource

	var properties := _args_dict(args, "properties")
	for key in properties.keys():
		if key in res:
			res.set(key, HerenCoordsScript.deserialize_value(properties[key]))

	_ensure_parent_dir(resource_path)
	var err := ResourceSaver.save(res, resource_path)
	if err != OK:
		return {"ok": false, "error": "save_failed: " + error_string(err)}

	# Refresh editor filesystem so the file shows up + gets a type.
	var efs: EditorFileSystem = _editor_interface().get_resource_filesystem()
	if efs:
		efs.update_file(resource_path)

	return {
		"ok": true,
		"resource_path": resource_path,
		"resource_type": resource_type,
		"type": _file_type(resource_path),
		"props": _serialize_resource_props(res),
	}


func handle_read(args: Dictionary) -> Dictionary:
	var resource_path: String = str(args.get("resource_path", ""))
	if resource_path == "":
		return {"ok": false, "error": "resource_path required"}
	if not ResourceLoader.exists(resource_path):
		return {"ok": false, "error": "not_found: " + resource_path}

	# P0.7 (2026-09-03): forzar re-scan del EFS antes de load(). Si el archivo
	# es nuevo (recién creado por handle_create) o modificado a mano, el EFS
	# cache puede no haber reconocido el tipo → load() retorna Resource base
	# en lugar de PackedScene. update_file() refresca el cache.
	var ei := _editor_interface()
	if ei:
		var efs: EditorFileSystem = ei.get_resource_filesystem()
		if efs:
			efs.update_file(resource_path)

	var res: Resource = load(resource_path)
	# FAIL-FAST (2026-09-03): null guard. load() puede retornar null si el
	# archivo fue borrado entre exists check y load (race), o si la clase
	# registrada en .tres no se encuentra.
	if res == null:
		return {
			"ok": false,
			"error": "load_returned_null: %s existe pero load() falló (re-scan no ayudó)" % resource_path,
			"hint": "revisa que el class_name del recurso esté disponible (script compilado)",
		}
	# Fallback explícito para PackedScene: si load() devolvió Resource base
	# (raro pero posible tras crear .tscn sin scan completo), forzar el tipo.
	if res.get_class() == "Resource" and resource_path.ends_with(".tscn"):
		var typed: Resource = ResourceLoader.load(resource_path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
		if typed != null:
			res = typed
	return {
		"ok": true,
		"resource_path": resource_path,
		"resource_class": res.get_class(),
		"resource_name": res.resource_name,
		"type": _file_type(resource_path),
		"props": _serialize_resource_props(res),
	}


func handle_update(args: Dictionary) -> Dictionary:
	var resource_path: String = str(args.get("resource_path", ""))
	if resource_path == "":
		return {"ok": false, "error": "resource_path required"}
	if not ResourceLoader.exists(resource_path):
		return {"ok": false, "error": "not_found: " + resource_path}

	var res: Resource = load(resource_path)
	var properties := _args_dict(args, "properties")
	var applied: Array = []
	for key in properties.keys():
		if key in res:
			var prop_value: Variant = properties[key]
			# Curve._data: expandir posiciones [[x,y],...] al formato interno
			# (5 elementos/punto) — sin esto el setter de Curve los descarta.
			if res is Curve and key == "_data":
				prop_value = HerenCoordsScript.expand_curve_data(prop_value)
			else:
				var prop_type: int = TYPE_NIL
				for prop in res.get_property_list():
					if prop.name == key:
						prop_type = int(prop.type)
						break
				prop_value = HerenCoordsScript.deserialize_typed(prop_value, prop_type, res.get(key))
			res.set(key, prop_value)
			applied.append(key)

	_ensure_parent_dir(resource_path)
	var err := ResourceSaver.save(res, resource_path)
	if err != OK:
		return {"ok": false, "error": "save_failed: " + error_string(err)}
	return {
		"ok": true,
		"resource_path": resource_path,
		"applied": applied,
		"props": _serialize_resource_props(res),
	}


func handle_delete(args: Dictionary) -> Dictionary:
	var resource_path: String = str(args.get("resource_path", ""))
	if resource_path == "":
		return {"ok": false, "error": "resource_path required"}

	var dir := DirAccess.open(resource_path.get_base_dir())
	if dir == null:
		return {"ok": false, "error": "cannot_open_dir: " + resource_path.get_base_dir()}
	var err := dir.remove(resource_path.get_file())
	if err != OK:
		return {"ok": false, "error": "remove_failed: " + error_string(err)}

	# Let the editor forget the removed file.
	var efs: EditorFileSystem = _editor_interface().get_resource_filesystem()
	if efs:
		efs.update_file(resource_path)

	return {"ok": true, "removed": resource_path}


func handle_list(args: Dictionary) -> Dictionary:
	var directory: String = str(args.get("directory", "res://"))
	var extension: String = str(args.get("extension", ""))
	var recursive: bool = bool(args.get("recursive", false))
	if extension.begins_with("."):
		extension = extension.trim_prefix(".")

	var out: Array = []
	_walk(directory, extension, recursive, out)
	return {"ok": true, "directory": directory, "count": out.size(), "files": out}


func handle_create_script(args: Dictionary) -> Dictionary:
	var script_path: String = str(args.get("script_path", ""))
	if script_path == "":
		return {"ok": false, "error": "script_path required"}

	var content: String = str(args.get("content", ""))
	if content == "":
		var template: String = str(args.get("template", "Node"))
		content = _script_template(template)

	_ensure_parent_dir(script_path)
	var file := FileAccess.open(script_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot_open: " + script_path + " (" + str(FileAccess.get_open_error()) + ")"}
	file.store_string(content)
	file = null

	var efs: EditorFileSystem = _editor_interface().get_resource_filesystem()
	if efs:
		efs.update_file(script_path)

	return {"ok": true, "script_path": script_path, "content": content}


func handle_read_script(args: Dictionary) -> Dictionary:
	var script_path: String = str(args.get("script_path", ""))
	if script_path == "":
		return {"ok": false, "error": "script_path required"}

	if not FileAccess.file_exists(script_path):
		return {"ok": false, "error": "not_found: " + script_path}
	var file := FileAccess.open(script_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot_open: " + script_path}
	var content := file.get_as_text()
	file = null

	return {"ok": true, "script_path": script_path, "content": content, "type": _file_type(script_path)}


func handle_edit_script(args: Dictionary) -> Dictionary:
	var script_path: String = str(args.get("script_path", ""))
	if script_path == "":
		return {"ok": false, "error": "script_path required"}
	if not FileAccess.file_exists(script_path):
		return {"ok": false, "error": "not_found: " + script_path}

	var content: String = str(args.get("content", ""))
	var append: bool = bool(args.get("append", false))

	var file := FileAccess.open(script_path, FileAccess.READ_WRITE)
	if file == null:
		return {"ok": false, "error": "cannot_open: " + script_path}
	if append:
		file.seek_end()
	else:
		file.resize(0)
	file.store_string(content)
	file = null

	var efs: EditorFileSystem = _editor_interface().get_resource_filesystem()
	if efs:
		efs.update_file(script_path)

	return {"ok": true, "script_path": script_path, "appended": append}


## v4.9: set_script también funciona desde resource (fallback redirect).
## El agente suele llamar resource/set_script pensando que es operación de
## recurso. Implementamos directamente — es load() + node.set_script().
func handle_set_script(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "no editor interface"}

	var scene_path: String = str(args.get("scene_path", ""))
	var node_path: Variant = args.get("node_path", "")
	var script_path: String = str(args.get("script_path", ""))
	if node_path == "" or script_path == "":
		return {"ok": false, "error": "node_path and script_path required"}
	if not ResourceLoader.exists(script_path):
		return {"ok": false, "error": "script_not_found: " + script_path}

	# Resolver root: registry → pestaña → disco.
	var root: Node = HerenSceneRegistryScript.resolve_root(ei, scene_path)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	# Copiar la resolución de node_handlers: normalize + get_node + fallback por nombre.
	var normalized := HerenCoordsScript.normalize_node_path(node_path, root)
	var node: Node = null
	if normalized == ".":
		node = root
	elif normalized != "":
		node = root.get_node_or_null(NodePath(normalized))
		if node == null and not normalized.contains("/"):
			# Fallback: búsqueda recursiva por nombre (mismo patrón que node_handlers).
			node = _find_by_name(root, str(node_path))
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}

	var script: Script = load(script_path)
	if script == null:
		return {"ok": false, "error": "failed_to_load: " + script_path}
	node.set_script(script)
	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"script": script_path,
	}


func _find_by_name(node: Node, target_name: String) -> Node:
	for child in node.get_children():
		if child.name == target_name:
			return child
		var deep: Node = _find_by_name(child, target_name)
		if deep != null:
			return deep
	return null


func _node_path_relative(node: Node, root: Node) -> String:
	if node == root:
		return "."
	var path := node.get_path()
	var root_path := root.get_path()
	var path_str := str(path)
	if path_str.begins_with(str(root_path) + "/"):
		return path_str.substr(str(root_path).length() + 1)
	return path_str
