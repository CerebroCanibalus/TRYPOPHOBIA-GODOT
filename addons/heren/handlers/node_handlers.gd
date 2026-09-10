@tool
extends "res://addons/heren/handlers/heren_handler.gd"
# Heren MCP v4 - Node handlers (Fase 2).
# CRUD completo de nodos sobre la escena VIVA del editor (ADR-002):
# la escena editada es el cache â€” no hay scene_cache aparte.
# Todas las mutaciones pasan por EditorUndoRedoManager (Ctrl+Z undoable).
#
# Actions (heredadas de v3 node_tool.py, sin session_id/scene_path:
# el editor ya sabe en quÃ© escena estÃ¡):
#   add, remove, set_prop, set_props, get_prop, get_info, get_children,
#   find, duplicate, rename, move, set_owner, reorder,
#   array_append, array_remove

const HerenCoordsScript := preload("coords.gd")
const HerenSceneRegistryScript := preload("../scene_registry.gd")
const HerenTemplateRegistryScript := preload("../template_registry.gd")

var _undo_redo: Node


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin
	_undo_redo = plugin.get_undo_redo_wrapper()


# ---------------------------------------------------------------- helpers

func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_editor_interface()


func _scene_root(args: Dictionary = {}) -> Node:
	var ei := _editor_interface()
	if ei == null:
		return null
	# Registry (escena creada por MCP en memoria) â†’ pestaÃ±a â†’ disco.
	return HerenSceneRegistryScript.resolve_root(ei, str(args.get("scene_path", "")))


func _resolve_node(root: Node, node_path: Variant) -> Node:
	if root == null or node_path == null:
		return null
	var normalized := HerenCoordsScript.normalize_node_path(node_path, root)
	if normalized == ".":
		return root
	if normalized == "":
		return null
	var found: Node = root.get_node_or_null(NodePath(normalized))
	if found != null:
		return found
	# P1a (2026-08-24): fallback — búsqueda recursiva por NOMBRE. El agente
	# suele pedir "Grunt_3" (bare) cuando el path real es "Enemies/Grunt_3".
	if not normalized.contains("/"):
		return _find_by_name_recursive(root, str(node_path))
	return null


func _find_by_name_recursive(node: Node, target_name: String) -> Node:
	for child in node.get_children():
		if child.name == target_name:
			return child
		var deep: Node = _find_by_name_recursive(child, target_name)
		if deep != null:
			return deep
	return null


## v4.6 (orientaciÃ³n continua): si `node_path` no resuelve, devuelve los hijos
## del padre MÃS CERCANO resoluble â€” el agente se recupera sin llamada extra.
func _not_found_hint(root: Node, node_path: Variant) -> Dictionary:
	var hint := {"ok": false, "error": "node_not_found: " + str(node_path)}
	if root == null or node_path == null:
		return hint
	var normalized := HerenCoordsScript.normalize_node_path(node_path, root)
	if normalized == "" or normalized == ".":
		return hint
	# Recortar segmentos de atrÃ¡s hasta encontrar un padre resoluble.
	var segments: Array = normalized.split("/")
	while segments.size() > 1:
		segments.pop_back()
		var parent := root.get_node_or_null(NodePath("/".join(segments)))
		if parent != null:
			var children: Array = []
			for child in parent.get_children():
				children.append(_node_path_relative(child, root))
			hint["parent"] = _node_path_relative(parent, root)
			hint["parent_children"] = children
			return hint
	return hint


func _node_path_relative(node: Node, root: Node) -> String:
	if node == root:
		return "."
	var path := node.get_path()
	var root_path := root.get_path()
	var path_str := str(path)
	if path_str.begins_with(str(root_path) + "/"):
		return path_str.substr(str(root_path).length() + 1)
	return path_str


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


func _serialize_props(node: Node, keys: Array) -> Dictionary:
	var out := {}
	for key in keys:
		if key in node:
			out[key] = HerenCoordsScript.serialize_value(node.get(key), true)
	return out


func _get_children_list(root: Node, node: Node, recursive: bool, out: Array, depth: int = 0) -> void:
	for child in node.get_children():
		var entry := {
			"name": child.name,
			"type": child.get_class(),
			"path": _node_path_relative(child, root),
		}
		# owner vacÃ­o es el caso comÃºn â†’ omitirlo (ahorra ~10B/nodo en listas grandes)
		var owner_path := _node_path_relative(child.get_owner(), root) if child.get_owner() else ""
		if owner_path != "":
			entry["owner"] = owner_path
		out.append(entry)
		if recursive:
			_get_children_list(root, child, true, out, depth + 1)


# ---------------------------------------------------------------- handlers

func handle_add(args: Dictionary) -> Dictionary:
	# BUG 1 fix: si viene instance_path, delegar a handle_instantiate.
	# El usuario puede llamar node/add con instance_path esperando instanciar una escena.
	if args.has("instance_path") and str(args.get("instance_path", "")) != "":
		return handle_instantiate(args)

	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var node_type: String = str(args.get("node_type", "Node"))
	var node_name: String = str(args.get("node_name", ""))
	if node_name == "":
		return {"ok": false, "error": "node_name required"}

	var parent: Node = root
	if args.has("parent_path") and str(args.get("parent_path", "")) != "":
		parent = _resolve_node(root, args.get("parent_path"))
		if parent == null:
			return {"ok": false, "error": "parent_not_found: " + str(args.get("parent_path"))}

	if parent.get_node_or_null(NodePath(node_name)) != null:
		return {"ok": false, "error": "node_exists: " + node_name}

	var new_node: Variant = ClassDB.instantiate(node_type)
	if new_node == null or not new_node is Node:
		return {"ok": false, "error": "invalid_node_type: " + node_type}
	var node := new_node as Node
	node.name = node_name

	# Apply properties (deserialized via unified coords).
	var properties := _args_dict(args, "properties")
	var inline_warnings: Array[String] = []
	for prop_name in properties.keys():
		if prop_name in node:
			var raw_value: Variant = properties[prop_name]
			var prop_value: Variant = HerenCoordsScript.deserialize_value(raw_value)
			if prop_value is Resource and prop_value.resource_path == "" \
					and raw_value is Dictionary and raw_value.get("__type", "") == "Resource":
				# v4.6: recurso inline â†’ se incrustarÃ¡ al guardar (sub_resource).
				inline_warnings.append("resource_incrusted_inline: %s â€” pasa path string (res://...) para ext_resource" % prop_name)
			node.set(prop_name, prop_value)

	# Optional script.
	if args.has("script") and str(args.get("script", "")) != "":
		var script_path: String = str(args.get("script"))
		if ResourceLoader.exists(script_path):
			node.set_script(load(script_path))

	# Canonical editor pattern: add_child + owner INSIDE the undo action.
	# (callv in the wrapper makes add_child receive the node, not an Array.)
	_undo_redo.begin_action("Heren Add %s" % node_name)
	_undo_redo.add_do_method(parent, &"add_child", [node])
	_undo_redo.add_do_property(node, &"owner", root)
	_undo_redo.add_undo_method(parent, &"remove_child", [node])
	_undo_redo.commit_action()

	# Registrar op para commit inteligente (dirty flag).
	var scene_path := str(root.scene_file_path)
	if scene_path != "":
		HerenSceneRegistryScript.record_op(scene_path, {
			"kind": "add",
			"node_path": _node_path_relative(node, root),
			"node_type": node_type,
		})

	return {
		"ok": true,
		"node_name": node.name,
		"node_type": node_type,
		"parent_path": _node_path_relative(parent, root),
		"node_path": _node_path_relative(node, root),
		"count": _count_scene_nodes(root),
		"coords": _node_coords(node, root),
		"inline_resources": inline_warnings,
	}


# ------------------------------------------------------------- coords proactivas (Fase A)
# Toda mutación devuelve `coords` del nodo afectado vía HerenCoords.coords_of_node.
# FUENTE ÚNICA DE VERDAD — NO duplicar aquí. Si necesitas un campo nuevo,
# añádelo en `coords.gd::coords_of_node` (tier apropiado).
# Tier 2 = el dataset completo que el agente necesita "casi en tiempo real":
# pos/scale/rotation kind-specific + bbox/aabb + modulate/material +
# collision/render layers + Control: anchors/offsets/effective_rect/size_flags.

## Helper interno: parent_path relativo al root, "" si no tiene padre.
func _parent_path(node: Node, root: Node) -> String:
	if node.get_parent() == null:
		return ""
	return _node_path_relative(node.get_parent(), root)

## Coord snapshot del nodo post-mutación. Reemplaza el antiguo `_node_coords`.
## Tier 3 (proactivo, Fase C): incluye resumen dynamic state (animation,
## animation_tree con anim_player snapshot, skeleton, light, audio, camera).
## Tier 4 (opt-in): SOLO vía `visual/coords` con tier=4 — emite las poses
## completas y params de AnimationTree.
func _node_coords(node: Node, root: Node) -> Dictionary:
	return HerenCoordsScript.coords_of_node(node, _parent_path(node, root), 3)


func _count_scene_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_scene_nodes(child)
	return total


func handle_remove(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	if node_path == "":
		return {"ok": false, "error": "node_path required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return _not_found_hint(root, node_path)
	if node == root:
		return {"ok": false, "error": "cannot_remove_root"}

	var parent := node.get_parent()
	if parent == null:
		return {"ok": false, "error": "no_parent"}
	var index := node.get_index()
	var had_children := node.get_child_count() > 0
	var node_path_str := _node_path_relative(node, root)

	_undo_redo.begin_action("Heren Remove %s" % node.name)
	_undo_redo.add_do_method(parent, &"remove_child", [node])
	_undo_redo.add_undo_method(parent, &"add_child", [node])
	_undo_redo.add_undo_method(parent, &"move_child", [node, index])
	_undo_redo.commit_action()

	# Registrar op para commit inteligente (dirty flag).
	var scene_path := str(root.scene_file_path)
	if scene_path != "":
		HerenSceneRegistryScript.record_op(scene_path, {
			"kind": "remove",
			"node_path": node_path_str,
		})

	return {
		"ok": true,
		"removed": node_path_str,
		"had_children": had_children,
		"parent_path": _node_path_relative(parent, root),
		"coords": _node_coords(node, root),
	}


func handle_set_prop(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var property: String = str(args.get("property", args.get("property_name", "")))
	if node_path == "" or property == "":
		return {"ok": false, "error": "node_path and property (or property_name) required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return _not_found_hint(root, node_path)
	if property not in node:
		return {"ok": false, "error": "property_not_found: " + property}

	var old_value: Variant = node.get(property)
	var prop_type: int = TYPE_NIL
	for prop in node.get_property_list():
		if prop.name == property:
			prop_type = int(prop.type)
			break
	var new_value: Variant = HerenCoordsScript.deserialize_typed(args.get("value", null), prop_type, old_value)
	var warning: String = ""
	if new_value is Resource and new_value.resource_path == "":
		# v4.6: recurso inline SIN resource_path → Godot lo INCUSTRA al guardar
		# (sub_resource). Si el agente quería referencia externa, debió pasar
		# el path string "res://...". Avisamos, no fallamos.
		warning = "resource_incrusted_inline: %s — pasa un path string (res://...) para referencia externa (ext_resource)" % property
	# 🚨 NO marcar resource_local_to_scene: bug conocido de Godot (#44008)
	# "Local to Scene doesn't work on PackedScene objects" — el recurso se
	# serializa como sub_resource PERO pierde sus props modificadas (ej:
	# CircleShape2D sin radius). Los sub-recursos sin resource_path se
	# serializan inline naturalmente al guardar con pack().

	_undo_redo.begin_action("Heren Set %s.%s" % [node.name, property])
	_undo_redo.add_do_property(node, property, new_value)
	_undo_redo.add_undo_property(node, property, old_value)
	_undo_redo.commit_action()

	# Fase 3 (rediseño 2026-08-15): VERIFICAR que el valor se aplicó realmente.
	# El agente necesita saber INMEDIATAMENTE si su cambio no persistió (ej:
	# NodePath que quedó ""), no descubrirlo 3 saves después.
	var applied: Variant = node.get(property)
	var applied_ok := _values_match(applied, new_value)

	# Registrar la op para replay (si el disco cambia antes del save).
	# Usamos el scene_path del root para identificar la escena.
	var scene_path := str(root.scene_file_path)
	if scene_path != "":
		HerenSceneRegistryScript.record_op(scene_path, {
			"kind": "set_prop",
			"node_path": _node_path_relative(node, root),
			"property": property,
			"value": new_value,
		})

	var result := {
		"ok": applied_ok,
		"node_path": _node_path_relative(node, root),
		"property": property,
		"old_value": HerenCoordsScript.serialize_value(old_value, true),
		"new_value": HerenCoordsScript.serialize_value(new_value, true),
		"applied_value": HerenCoordsScript.serialize_value(applied, true),
		"coords": _node_coords(node, root),
	}
	if not applied_ok:
		result["error"] = "set_prop_failed: value not applied — expected %s, got %s" % [
			str(new_value), str(applied)]
	if warning != "":
		result["warning"] = warning
	return result


## Compara dos valores para verificar que un set_prop se aplicó.
## Godot puede normalizar el valor (int→float, Vector2→Vector3, NodePath
## absoluto vs relativo), así que comparamos de forma tolerante.
static func _values_match(a: Variant, b: Variant) -> bool:
	if a == b:
		return true
	# Comparar por serialización compacta (tolera normalización de tipos).
	var sa := HerenCoordsScript.serialize_value(a, true)
	var sb := HerenCoordsScript.serialize_value(b, true)
	if typeof(sa) != typeof(sb):
		return false
	if sa is Dictionary and sb is Dictionary:
		if (sa as Dictionary).size() != (sb as Dictionary).size():
			return false
		for key in (sa as Dictionary).keys():
			if not (sb as Dictionary).has(key):
				return false
			var va: Variant = sa[key]
			var vb: Variant = sb[key]
			if va is float and vb is float:
				if absf(va - vb) > 0.0001:
					return false
			elif va != vb:
				return false
		return true
	if sa is Array and sb is Array:
		if (sa as Array).size() != (sb as Array).size():
			return false
		for i in (sa as Array).size():
			if sa[i] != sb[i]:
				return false
		return true
	return false


func handle_set_props(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var properties := _args_dict(args, "properties")
	if node_path == "" or properties.is_empty():
		return {"ok": false, "error": "node_path and properties (dict) required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return _not_found_hint(root, node_path)

	var applied: Array = []
	var requested: Array = []
	_undo_redo.begin_action("Heren Set Props %s" % node.name)
	for prop_name in properties.keys():
		requested.append(prop_name)
		if prop_name in node:
			var new_value: Variant = HerenCoordsScript.deserialize_value(properties[prop_name])
			var old_value: Variant = node.get(prop_name)
			_undo_redo.add_do_property(node, prop_name, new_value)
			_undo_redo.add_undo_property(node, prop_name, old_value)
			applied.append(prop_name)
	_undo_redo.commit_action()

	# FAIL-FAST (2026-09-03): verificar que cada prop aplicado tiene el valor
	# esperado. Si set() falló silenciosamente (tipo incompatible, write-only
	# via script), el agente aún ve "applied:N" y cree éxito.
	var mismatches: Array = []
	for prop_name in applied:
		var expected: Variant = HerenCoordsScript.deserialize_value(properties[prop_name])
		var actual: Variant = node.get(prop_name)
		if not _values_match(actual, expected):
			mismatches.append(prop_name)
	if mismatches.size() > 0:
		return {
			"ok": false,
			"error": "set_props_failed: %d/%d props no tomaron el valor esperado" % [mismatches.size(), applied.size()],
			"applied": applied,
			"mismatches": mismatches,
		}
	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"applied": applied,
		"requested": requested,
		"skipped": requested.filter(func(n): return n not in applied),
		"count": applied.size(),
		"coords": _node_coords(node, root),
		"scene_node_count": _count_scene_nodes(root),
	}


func handle_get_prop(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var property: String = str(args.get("property", args.get("property_name", "")))
	if node_path == "" or property == "":
		return {"ok": false, "error": "node_path and property required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return _not_found_hint(root, node_path)
	if property not in node:
		return {"ok": false, "error": "property_not_found: " + property}

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"property": property,
		"value": HerenCoordsScript.serialize_value(node.get(property), true),
	}


func handle_get_info(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	if node_path == "":
		return {"ok": false, "error": "node_path required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return _not_found_hint(root, node_path)

	var children := []
	_get_children_list(root, node, false, children)

	var result := {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"node_type": node.get_class(),
		"properties": _serialize_props(node, ["position", "rotation", "scale", "modulate", "visible", "text"]),
		"children": children,
		"child_count": children.size(),
		"owner": _node_path_relative(node.get_owner(), root) if node.get_owner() else "",
		"groups": node.get_groups(),
		"scene_file_path": node.scene_file_path if node.scene_file_path != "" else "",
	}
	# v4.7 (Fase UI-2): info de UI para Control (anchors/offsets/size_flags).
	if node is Control:
		var ctl := node as Control
		result["ui"] = {
			"anchors": {
				"left": ctl.anchor_left, "top": ctl.anchor_top,
				"right": ctl.anchor_right, "bottom": ctl.anchor_bottom,
			},
			"offsets": {
				"left": ctl.offset_left, "top": ctl.offset_top,
				"right": ctl.offset_right, "bottom": ctl.offset_bottom,
			},
			"size": {"x": ctl.size.x, "y": ctl.size.y},
			"min_size": {"x": ctl.custom_minimum_size.x, "y": ctl.custom_minimum_size.y},
			"size_flags": {
				"horizontal": ctl.size_flags_horizontal,
				"vertical": ctl.size_flags_vertical,
				"stretch_ratio": ctl.size_flags_stretch_ratio,
			},
			"parent_is_container": ctl.get_parent() is Container,
		}
	return result


func handle_get_children(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", ".")
	var recursive: bool = bool(args.get("recursive", false))

	var node := _resolve_node(root, node_path)
	if node == null:
		return _not_found_hint(root, node_path)

	var children := []
	_get_children_list(root, node, recursive, children)

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"children": children,
		"count": children.size(),
	}


func handle_find(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var query: String = str(args.get("query", ""))
	var by: String = str(args.get("by", "name"))  # name | type | property
	if query == "":
		return {"ok": false, "error": "query required"}

	var property_name: String = str(args.get("property_name", ""))
	var property_value: Variant = args.get("property_value", null)
	var results := []

	# Iterative stack traversal (no recursive lambdas â€” GDScript limitation).
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node := stack.pop_back()
		var is_match := false
		match by:
			"name":
				is_match = query in str(node.name)
			"type":
				is_match = query in node.get_class()
			"property":
				is_match = property_name in node and node.get(property_name) == property_value
			_:
				return {"ok": false, "error": "invalid 'by': " + by}
		if is_match:
			results.append({
				"name": node.name,
				"type": node.get_class(),
				"path": _node_path_relative(node, root),
				"owner": _node_path_relative(node.get_owner(), root) if node.get_owner() else "",
			})
		for child in node.get_children():
			stack.append(child)

	return {
		"ok": true,
		"query": query,
		"by": by,
		"results": results,
		"count": results.size(),
	}


func handle_duplicate(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	if node_path == "":
		return {"ok": false, "error": "node_path required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return _not_found_hint(root, node_path)
	if node == root:
		return {"ok": false, "error": "cannot_duplicate_root"}

	var duplicate: Node = node.duplicate()
	var new_name: String = str(args.get("new_name", ""))
	if new_name == "":
		new_name = str(node.name) + "_dup"
	duplicate.name = new_name

	var parent := node.get_parent()
	var index := node.get_index()

	_undo_redo.begin_action("Heren Duplicate %s" % node.name)
	_undo_redo.add_do_method(parent, &"add_child", [duplicate])
	_undo_redo.add_do_method(parent, &"move_child", [duplicate, index + 1])
	_undo_redo.add_do_property(duplicate, &"owner", root)
	_undo_redo.add_undo_method(parent, &"remove_child", [duplicate])
	_undo_redo.commit_action()

	return {
		"ok": true,
		"original": _node_path_relative(node, root),
		"duplicate": _node_path_relative(duplicate, root),
		"name": duplicate.name,
		"coords": _node_coords(duplicate, root),
		"scene_node_count": _count_scene_nodes(root),
	}


## Instancia una escena .tscn (o PackedScene .res) como hijo del árbol.
## GEN_EDIT_STATE_INSTANCE → el editor la trata como instancia externa editable
## (ExtResource en pack, no copia inline). owner = root para que pack() la incluya.
## v4.7: acepta `template` (sistema transversal HerenTemplateRegistry). Si viene
## `template` usa el registry (.tscn + params por metadata); si no, `instance_path`
## como siempre. Los params del template viajan en `properties` (dict).
func handle_instantiate(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var template_name: String = str(args.get("template", ""))
	var instance: Node = null
	var instance_source := ""

	if template_name != "":
		# Template del sistema transversal: params por nombre de nodo canónico.
		var template_params := _args_dict(args, "properties")
		instance = HerenTemplateRegistryScript.instantiate(template_name, template_params)
		if instance == null:
			return {"ok": false, "error": "template_not_found: " + template_name}
		instance_source = "template:" + template_name
	else:
		var instance_path: String = str(args.get("instance_path", ""))
		if instance_path == "":
			return {"ok": false, "error": "instance_path or template required"}
		if not ResourceLoader.exists(instance_path):
			return {"ok": false, "error": "instance_not_found: " + instance_path}

		var packed: PackedScene = load(instance_path)
		if packed == null:
			return {"ok": false, "error": "not_packed_scene: " + instance_path}
		instance = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		if instance == null:
			return {"ok": false, "error": "instantiate_failed: " + instance_path}
		instance_source = instance_path

		# Propiedades post-instanciación (coords unificadas).
		var properties := _args_dict(args, "properties")
		for prop_name in properties.keys():
			if prop_name in instance:
				instance.set(prop_name, HerenCoordsScript.deserialize_value(properties[prop_name]))

	var parent: Node = root
	if args.has("parent_path") and str(args.get("parent_path", "")) != "":
		parent = _resolve_node(root, args.get("parent_path"))
		if parent == null:
			return {"ok": false, "error": "parent_not_found: " + str(args.get("parent_path"))}

	var node_name: String = str(args.get("node_name", ""))
	if node_name != "":
		instance.name = node_name

	# Script override opcional.
	if args.has("script") and str(args.get("script", "")) != "":
		var script_path: String = str(args.get("script"))
		if ResourceLoader.exists(script_path):
			instance.set_script(load(script_path))

	_undo_redo.begin_action("Heren Instantiate %s" % instance.name)
	_undo_redo.add_do_method(parent, &"add_child", [instance])
	_undo_redo.add_do_property(instance, &"owner", root)
	_undo_redo.add_undo_method(parent, &"remove_child", [instance])
	_undo_redo.commit_action()

	return {
		"ok": true,
		"instance_path": instance_source,
		"template": template_name if template_name != "" else "",
		"node_name": instance.name,
		"node_type": instance.get_class(),
		"parent_path": _node_path_relative(parent, root),
		"node_path": _node_path_relative(instance, root),
		"count": _count_scene_nodes(root),
		"coords": _node_coords(instance, root),
	}


func handle_rename(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var new_name: String = str(args.get("new_name", ""))
	if node_path == "" or new_name == "":
		return {"ok": false, "error": "node_path and new_name required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return _not_found_hint(root, node_path)
	var old_name := node.name

	_undo_redo.begin_action("Heren Rename %s" % old_name)
	_undo_redo.add_do_property(node, &"name", new_name)
	_undo_redo.add_undo_property(node, &"name", old_name)
	_undo_redo.commit_action()

	# Registrar op para commit inteligente (dirty flag).
	var scene_path := str(root.scene_file_path)
	if scene_path != "":
		HerenSceneRegistryScript.record_op(scene_path, {
			"kind": "rename",
			"node_path": _node_path_relative(node, root),
			"old_name": old_name,
			"new_name": new_name,
		})

	return {
		"ok": true,
		"old_name": old_name,
		"new_name": new_name,
		"previous_path": str(node_path),
		"node_path": _node_path_relative(node, root),
		"coords": _node_coords(node, root),
		"scene_node_count": _count_scene_nodes(root),
	}


func handle_move(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var new_parent_path: Variant = args.get("new_parent", "")
	if node_path == "" or new_parent_path == "":
		return {"ok": false, "error": "node_path and new_parent required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return _not_found_hint(root, node_path)
	if node == root:
		return {"ok": false, "error": "cannot_move_root"}

	var new_parent := _resolve_node(root, new_parent_path)
	if new_parent == null:
		return {"ok": false, "error": "parent_not_found: " + str(new_parent_path)}

	var old_parent := node.get_parent()
	if old_parent == null:
		return {"ok": false, "error": "no_parent"}
	var old_index := node.get_index()

	_undo_redo.begin_action("Heren Move %s" % node.name)
	_undo_redo.add_do_method(old_parent, &"remove_child", [node])
	_undo_redo.add_do_method(new_parent, &"add_child", [node])
	_undo_redo.add_do_property(node, &"owner", root)
	_undo_redo.add_undo_method(new_parent, &"remove_child", [node])
	_undo_redo.add_undo_method(old_parent, &"add_child", [node])
	_undo_redo.add_undo_method(old_parent, &"move_child", [node, old_index])
	_undo_redo.commit_action()

	# Registrar op para commit inteligente (dirty flag).
	var scene_path := str(root.scene_file_path)
	if scene_path != "":
		HerenSceneRegistryScript.record_op(scene_path, {
			"kind": "move",
			"node_path": _node_path_relative(node, root),
			"old_parent": _node_path_relative(old_parent, root),
			"new_parent": _node_path_relative(new_parent, root),
		})

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"previous_path": str(node_path),
		"new_parent": _node_path_relative(new_parent, root),
		"old_parent": _node_path_relative(old_parent, root),
		"coords": _node_coords(node, root),
		"scene_node_count": _count_scene_nodes(root),
	}


func handle_set_owner(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var owner_path: Variant = args.get("owner_path", ".")
	if node_path == "":
		return {"ok": false, "error": "node_path required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return _not_found_hint(root, node_path)
	var owner := _resolve_node(root, owner_path)
	if owner == null:
		return {"ok": false, "error": "owner_not_found: " + str(owner_path)}
	var old_owner: Node = node.owner

	_undo_redo.begin_action("Heren Set Owner %s" % node.name)
	_undo_redo.add_do_property(node, &"owner", owner)
	_undo_redo.add_undo_property(node, &"owner", old_owner)
	_undo_redo.commit_action()

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"owner_path": _node_path_relative(owner, root),
		"coords": _node_coords(node, root),
		"scene_node_count": _count_scene_nodes(root),
	}


func handle_reorder(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var new_index: int = int(args.get("index", args.get("new_index", -1)))
	if node_path == "":
		return {"ok": false, "error": "node_path required"}
	if new_index < 0:
		return {"ok": false, "error": "index >= 0 required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return _not_found_hint(root, node_path)
	var parent := node.get_parent()
	if parent == null:
		return {"ok": false, "error": "no_parent"}
	var old_index := node.get_index()

	_undo_redo.begin_action("Heren Reorder %s" % node.name)
	_undo_redo.add_do_method(parent, &"move_child", [node, new_index])
	_undo_redo.add_undo_method(parent, &"move_child", [node, old_index])
	_undo_redo.commit_action()

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"new_index": new_index,
		"old_index": old_index,
		"coords": _node_coords(node, root),
		"scene_node_count": _count_scene_nodes(root),
	}


func handle_array_append(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var property_name: String = str(args.get("property_name", ""))
	if node_path == "" or property_name == "":
		return {"ok": false, "error": "node_path and property_name required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return _not_found_hint(root, node_path)
	var current: Variant = node.get(property_name)
	if current == null or not (current is Array or current is PackedInt32Array):
		return {"ok": false, "error": "property_not_array: " + property_name}

	var value: Variant = HerenCoordsScript.deserialize_value(args.get("value", null))
	var old_value: Variant = node.get(property_name)

	_undo_redo.begin_action("Heren Array Append %s.%s" % [node.name, property_name])
	_undo_redo.add_do_property(node, property_name, _array_with_append(current, value))
	_undo_redo.add_undo_property(node, property_name, old_value)
	_undo_redo.commit_action()

	# FAIL-FAST (2026-09-03): leer el array NUEVO post-commit. Antes reportaba
	# `current.size()` que era el tamaño VIEJO — el agente pensaba que no había
	# appendeado nada.
	var new_array: Variant = node.get(property_name)
	var new_size: int = new_array.size() if new_array != null else -1
	if new_array == null or new_size != current.size() + 1:
		return {
			"ok": false,
			"error": "array_append_failed",
			"expected_size": current.size() + 1,
			"actual_size": new_size,
		}
	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"property_name": property_name,
		"value_added": HerenCoordsScript.serialize_value(value, true),
		"array_size": new_size,
		"coords": _node_coords(node, root),
	}


func handle_array_remove(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var property_name: String = str(args.get("property_name", ""))
	if node_path == "" or property_name == "":
		return {"ok": false, "error": "node_path and property_name required"}

	var node := _resolve_node(root, node_path)
	if node == null:
		return _not_found_hint(root, node_path)
	var current: Variant = node.get(property_name)
	if current == null or not (current is Array or current is PackedInt32Array):
		return {"ok": false, "error": "property_not_array: " + property_name}

	var index: int = int(args.get("index", -1))
	var value: Variant = args.get("value", null)
	var old_value: Variant = node.get(property_name)
	var removed_value: Variant = null

	if index >= 0 and index < current.size():
		removed_value = current[index]
	elif value != null:
		var found: int = current.find(HerenCoordsScript.deserialize_value(value))
		if found >= 0:
			index = found
			removed_value = current[found]
		else:
			return {"ok": false, "error": "value_not_found"}
	else:
		return {"ok": false, "error": "index or value required"}

	_undo_redo.begin_action("Heren Array Remove %s.%s" % [node.name, property_name])
	_undo_redo.add_do_property(node, property_name, _array_without_at(current, index))
	_undo_redo.add_undo_property(node, property_name, old_value)
	_undo_redo.commit_action()

	# FAIL-FAST (2026-09-03): leer array nuevo. Antes reportaba `old_value.size()`
	# (tamaño VIEJO) — el agente pensaba que no había removido nada.
	var new_array: Variant = node.get(property_name)
	var new_size: int = new_array.size() if new_array != null else -1
	if new_array == null or new_size != old_value.size() - 1:
		return {
			"ok": false,
			"error": "array_remove_failed",
			"expected_size": old_value.size() - 1,
			"actual_size": new_size,
		}
	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"property_name": property_name,
		"removed_value": HerenCoordsScript.serialize_value(removed_value, true),
		"array_size": new_size,
		"coords": _node_coords(node, root),
	}


# ---------------------------------------------------------------- array utils

func _array_with_append(arr: Variant, value: Variant) -> Variant:
	if arr is PackedInt32Array:
		var packed := (arr as PackedInt32Array).duplicate()
		packed.append(int(value))
		return packed
	var out: Array = (arr as Array).duplicate(true)
	out.append(value)
	return out


func _array_without_at(arr: Variant, index: int) -> Variant:
	if arr is PackedInt32Array:
		var packed := (arr as PackedInt32Array).duplicate()
		packed.remove_at(index)
		return packed
	var out: Array = (arr as Array).duplicate(true)
	out.remove_at(index)
	return out


## v4.9: set_script como acción de nodo (alias para signal/set_script).
## El agente suele llamar node/set_script o resource/set_script — es más
## intuitivo que signal/set_script para esta operación.
func handle_set_script(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var node_path: Variant = args.get("node_path", "")
	var script_path: String = str(args.get("script_path", ""))
	if node_path == "" or script_path == "":
		return {"ok": false, "error": "node_path and script_path required"}
	if not ResourceLoader.exists(script_path):
		return {"ok": false, "error": "script_not_found: " + script_path}

	var node: Node = _resolve_node(root, node_path)
	if node == null:
		return _not_found_hint(root, node_path)

	node.set_script(load(script_path))
	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"script": script_path,
		"coords": _node_coords(node, root),
	}
