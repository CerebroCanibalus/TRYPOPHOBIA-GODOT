@tool
extends "res://addons/heren/handlers/heren_handler.gd"
# Heren MCP v4 - Signal handlers (Fase 2).
# Señales y scripts entre nodos de la escena viva (ADR-002).
# connect usa CONNECT_PERSIST para que pack() serialice la conexión al guardar.
#
# Actions (heredadas de v3 signal_tool.py, adaptadas a editor vivo):
#   connect      -> node.connect(signal, target, method, CONNECT_PERSIST)
#   disconnect   -> node.disconnect(...)
#   list         -> señales del nodo + conexiones activas
#   set_script   -> node.set_script(load(path))

const HerenCoordsScript := preload("coords.gd")
const HerenSceneRegistryScript := preload("../scene_registry.gd")



func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_editor_interface()


func _scene_root(args: Dictionary = {}) -> Node:
	var ei := _editor_interface()
	if ei == null:
		return null
	# Registry (escena creada por MCP en memoria) → pestaña → disco.
	return HerenSceneRegistryScript.resolve_root(ei, str(args.get("scene_path", "")))


func _resolve_node(root: Node, node_path: Variant) -> Node:
	if root == null or node_path == null:
		return null
	var normalized := HerenCoordsScript.normalize_node_path(node_path, root)
	if normalized == ".":
		return root
	if normalized == "":
		return null
	return root.get_node_or_null(NodePath(normalized))


func _node_path_relative(node: Node, root: Node) -> String:
	if node == root:
		return "."
	var path := node.get_path()
	var root_path := root.get_path()
	var path_str := str(path)
	if path_str.begins_with(str(root_path) + "/"):
		return path_str.substr(str(root_path).length() + 1)
	return path_str


# ---------------------------------------------------------------- handlers

func handle_connect(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var from_node: Variant = args.get("from_node", "")
	var to_node: Variant = args.get("to_node", "")
	var signal_name: String = str(args.get("signal_name", ""))
	var method: String = str(args.get("method", ""))
	if from_node == "" or to_node == "" or signal_name == "" or method == "":
		return {"ok": false, "error": "from_node, to_node, signal_name, method required"}

	var source: Node = _resolve_node(root, from_node)
	var target: Node = _resolve_node(root, to_node)
	if source == null:
		return {"ok": false, "error": "source_not_found: " + str(from_node)}
	if target == null:
		return {"ok": false, "error": "target_not_found: " + str(to_node)}

	if not source.has_signal(signal_name):
		return {"ok": false, "error": "signal_not_found: " + signal_name}
	if not target.has_method(method):
		return {"ok": false, "error": "method_not_found: " + method}

	var err := source.connect(signal_name, Callable(target, method), CONNECT_PERSIST)
	if err != OK:
		return {"ok": false, "error": "connect_failed: " + error_string(err)}

	return {
		"ok": true,
		"from": _node_path_relative(source, root),
		"signal": signal_name,
		"to": _node_path_relative(target, root),
		"method": method,
	}


func handle_disconnect(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var from_node: Variant = args.get("from_node", "")
	var to_node: Variant = args.get("to_node", "")
	var signal_name: String = str(args.get("signal_name", ""))
	var method: String = str(args.get("method", ""))
	if from_node == "" or to_node == "" or signal_name == "" or method == "":
		return {"ok": false, "error": "from_node, to_node, signal_name, method required"}

	var source: Node = _resolve_node(root, from_node)
	var target: Node = _resolve_node(root, to_node)
	if source == null:
		return {"ok": false, "error": "source_not_found: " + str(from_node)}
	if target == null:
		return {"ok": false, "error": "target_not_found: " + str(to_node)}

	if source.is_connected(signal_name, Callable(target, method)):
		source.disconnect(signal_name, Callable(target, method))
	else:
		return {"ok": false, "error": "connection_not_found"}

	return {
		"ok": true,
		"disconnected": true,
		"from": _node_path_relative(source, root),
		"signal": signal_name,
		"to": _node_path_relative(target, root),
		"method": method,
	}


func handle_list(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var node_path: Variant = args.get("node_path", "")
	if node_path == "":
		return {"ok": false, "error": "node_path required"}
	var node: Node = _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}

	var signals: Array = []
	for sig in node.get_signal_list():
		signals.append({"name": str(sig.name), "args": sig.args.size()})

	# Fix H1: fully defensive — each connection is a Dictionary; access via
	# .get() and isolate per-connection so a malformed/odd entry can never
	# crash the whole handler into "Unknown error".
	var connections: Array = []
	for conn_raw in node.get_incoming_connections():
		var conn: Dictionary = conn_raw as Dictionary if conn_raw is Dictionary else {}
		var from_desc: String = ""
		var src: Variant = conn.get("source", null)
		if src is Node:
			from_desc = _node_path_relative(src as Node, root)
		else:
			from_desc = str(src)
		var to_method: String = ""
		var callable: Variant = conn.get("callable", null)
		if callable is Callable and (callable as Callable).get_object() != null:
			to_method = str((callable as Callable).get_method())
		var conn_entry: Dictionary = {
			"from": from_desc,
			"signal": str(conn.get("signal", "")),
			"to_method": to_method,
		}
		connections.append(conn_entry)

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"signals": signals,
		"incoming_connections": connections,
	}


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
		return {"ok": false, "error": "node_not_found: " + str(node_path)}

	node.set_script(load(script_path))
	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"script": script_path,
	}
