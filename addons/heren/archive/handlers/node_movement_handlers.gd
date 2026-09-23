@tool
extends "res://addons/heren/handlers/node_handlers.gd"

# Heren MCP v4 - ARCHIVADO 2026-09-09 (§0.12 W4 cleanup).
# node/move + node/set_owner + node/reorder. Reemplazados por scene_script
# workers — la manipulación de árbol (parent change, owner rewrite, child
# reorder) es trivial con node.reparent / node.set_owner / move_child.
#
# Hereda de node_handlers.gd (que sigue activo) para reutilizar helpers
# (_scene_root, _resolve_node, _node_coords, _count_scene_nodes, etc.).
# Para restaurar, ver addons/heren/archive/handlers/README.md.

## Mueve un nodo a otro parent (UndoRedo + return old_parent).
## Args: node_path (str), new_parent_path (str), keep_global_transform (bool, default true).
func handle_move(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var new_parent_path: Variant = args.get("new_parent_path", "")
	if node_path == "" or new_parent_path == "":
		return {"ok": false, "error": "node_path and new_parent_path required"}
	var node: Node = _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}
	var new_parent: Node = _resolve_node(root, new_parent_path)
	if new_parent == null:
		return {"ok": false, "error": "parent_not_found: " + str(new_parent_path)}
	var old_parent := node.get_parent()
	if old_parent == new_parent:
		return {"ok": false, "error": "already_at_parent"}
	var old_path := _node_path_relative(node, root)
	var keep_global: bool = bool(args.get("keep_global_transform", true))
	_undo_redo("heren:move_node", {
		"node": node,
		"old_parent": old_parent,
		"new_parent": new_parent,
		"keep_global": keep_global,
		"root": root,
	})
	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"old_parent": old_path,
		"new_parent": str(new_parent_path),
		"coords": _node_coords(node, root),
		"scene_node_count": _count_scene_nodes(root),
	}


## Reescribe el owner de un nodo (importante para PackedScene: solo se guardan
## nodos con owner != null fuera del root). Si recursive=true, todo el subárbol.
func handle_set_owner(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var owner_path: Variant = args.get("owner_path", "")
	if node_path == "":
		return {"ok": false, "error": "node_path required"}
	var node: Node = _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}
	var owner: Node
	if owner_path == "" or str(owner_path) == "<root>":
		owner = root
	else:
		owner = _resolve_node(root, owner_path)
		if owner == null:
			return {"ok": false, "error": "owner_not_found: " + str(owner_path)}
	# El owner debe ser ancestro de node (regla de Godot).
	if not _is_ancestor_of(owner, node) and owner != node:
		return {"ok": false, "error": "owner_must_be_ancestor"}
	_undo_redo("heren:set_owner", {
		"node": node,
		"old_owner": node.owner,
		"new_owner": owner,
		"recursive": bool(args.get("recursive", true)),
		"root": root,
	})
	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"owner": "<root>" if owner == root else _node_path_relative(owner, root),
		"recursive": bool(args.get("recursive", true)),
		"coords": _node_coords(node, root),
		"scene_node_count": _count_scene_nodes(root),
	}


## Reordena un nodo entre sus hermanos (move_child).
## to_index: -1 = al final, 0 = primero, etc.
func handle_reorder(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	if node_path == "":
		return {"ok": false, "error": "node_path required"}
	var node: Node = _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}
	var parent := node.get_parent()
	if parent == null:
		return {"ok": false, "error": "no_parent"}
	var to_index: int = int(args.get("to_index", -1))
	var siblings := parent.get_child_count()
	if to_index < 0:
		to_index = siblings - 1
	if to_index >= siblings:
		to_index = siblings - 1
	_undo_redo("heren:reorder_node", {
		"node": node,
		"parent": parent,
		"to_index": to_index,
		"root": root,
	})
	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"parent": _node_path_relative(parent, root),
		"to_index": to_index,
		"siblings": siblings,
		"coords": _node_coords(node, root),
		"scene_node_count": _count_scene_nodes(root),
	}
