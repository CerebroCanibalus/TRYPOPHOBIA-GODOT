@tool
extends "res://addons/heren/handlers/animation_handlers.gd"

# Heren MCP v4 - ARCHIVADO 2026-09-09 (§0.12 W4 cleanup).
# AnimationTree handlers: tree_activate/travel/set_param/get_param/add_blend_node/
# connect_blend_nodes/set_anim_player. Reemplazados por scene_script workers.
#
# Hereda de animation_handlers.gd (que sigue activo) para reutilizar helpers
# (_scene_root, _resolve_node, _resolve_tree, _node_path_relative, etc.).
# Para restaurar, ver addons/heren/archive/handlers/README.md.

func handle_tree_activate(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var tree := _resolve_tree(root, args)
	if tree == null:
		return {"ok": false, "error": "animation_tree_not_found"}
	tree.active = bool(args.get("active", true))
	# Si se pide reproducir un estado concreto, travel.
	if args.has("state") and str(args.get("state", "")) != "":
		var playback: Variant = tree.get("parameters/playback")
		if playback != null and playback is AnimationNodeStateMachinePlayback:
			playback.travel(str(args.get("state")))
	return {
		"ok": true,
		"active": tree.active,
		"tree_path": _node_path_relative(tree, root),
	}


func handle_tree_travel(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var tree := _resolve_tree(root, args)
	if tree == null:
		return {"ok": false, "error": "animation_tree_not_found"}
	var state: String = str(args.get("state", ""))
	if state == "":
		return {"ok": false, "error": "state required"}
	var playback: Variant = tree.get("parameters/playback")
	if playback == null or not playback is AnimationNodeStateMachinePlayback:
		return {"ok": false, "error": "no state_machine_playback (graph_type debe ser state_machine)"}
	playback.travel(state)
	return {"ok": true, "traveled_to": state, "current_state": str(playback.get_current_node())}


func handle_tree_set_param(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var tree := _resolve_tree(root, args)
	if tree == null:
		return {"ok": false, "error": "animation_tree_not_found"}
	# Acepta 'param_name' (planning) o alias 'name' (compat).
	var name: String = str(args.get("param_name", args.get("name", "")))
	if name == "":
		return {"ok": false, "error": "param_name required"}
	var param_name := "parameters/" + name
	if tree.get(param_name) == null:
		return {"ok": false, "error": "parameter_not_found: " + param_name}
	tree.set(param_name, HerenCoordsScript.deserialize_value(args.get("value")))
	return {"ok": true, "parameter": param_name, "value": HerenCoordsScript.serialize_value(tree.get(param_name), true)}


func handle_tree_get_param(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var tree := _resolve_tree(root, args)
	if tree == null:
		return {"ok": false, "error": "animation_tree_not_found"}
	var name: String = str(args.get("param_name", args.get("name", "")))
	if name == "":
		# Devuelve todos los parámetros.
		var all := {}
		for p in tree.get_parameter_list():
			all[str(p)] = HerenCoordsScript.serialize_value(tree.get(str(p)), true)
		return {"ok": true, "parameters": all}
	var param_name := "parameters/" + name
	if tree.get(param_name) == null:
		return {"ok": false, "error": "parameter_not_found: " + param_name}
	return {"ok": true, "parameter": param_name, "value": HerenCoordsScript.serialize_value(tree.get(param_name), true)}


## P-B2 (P-B2): add_blend_node — usa bt.add_node(name, node, position). El tree_root
## debe ser un AnimationNodeBlendTree. Si no existe todavía, lo crea.
func handle_tree_add_blend_node(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var tree := _resolve_tree(root, args)
	if tree == null:
		return {"ok": false, "error": "animation_tree_not_found"}
	var bt: AnimationNodeBlendTree = tree.tree_root as AnimationNodeBlendTree
	if bt == null:
		# Auto-crear un BlendTree vacío la primera vez.
		bt = AnimationNodeBlendTree.new()
		tree.tree_root = bt

	var node_name: String = str(args.get("node_name", ""))
	if node_name == "":
		return {"ok": false, "error": "node_name required"}
	# Si ya existe, lo reemplazamos.
	if bt.has_node(node_name):
		bt.remove_node(node_name)

	var node_type: String = str(args.get("node_type", "AnimationNodeAnimation"))
	var anim_node: AnimationNode = null
	match node_type:
		"AnimationNodeAnimation", "animation":
			var an := AnimationNodeAnimation.new()
			an.animation = str(args.get("animation", ""))
			anim_node = an
		"AnimationNodeOneShot", "one_shot":
			anim_node = AnimationNodeOneShot.new()
		"AnimationNodeBlend2", "blend2":
			anim_node = AnimationNodeBlend2.new()
		"AnimationNodeBlend3", "blend3":
			anim_node = AnimationNodeBlend3.new()
		"AnimationNodeAdd2", "add2":
			anim_node = AnimationNodeAdd2.new()
		"AnimationNodeAdd3", "add3":
			anim_node = AnimationNodeAdd3.new()
		"AnimationNodeSub2", "sub2":
			anim_node = AnimationNodeSub2.new()
		"AnimationNodeSync", "sync":
			anim_node = AnimationNodeSync.new()
		"AnimationNodeTimeScale", "time_scale":
			anim_node = AnimationNodeTimeScale.new()
		"AnimationNodeTimeSeek", "time_seek":
			anim_node = AnimationNodeTimeSeek.new()
		"AnimationNodeTransition", "transition":
			anim_node = AnimationNodeTransition.new()
		"AnimationNodeOutput", "output":
			anim_node = AnimationNodeOutput.new()
		_:
			return {"ok": false, "error": "unknown_node_type: " + node_type}

	var pos_dict: Dictionary = _args_dict(args, "graph_position")
	var pos := Vector2(float(pos_dict.get("x", 0.0)), float(pos_dict.get("y", 0.0)))
	bt.add_node(node_name, anim_node, pos)

	return {
		"ok": true,
		"tree_path": _node_path_relative(tree, root),
		"node_name": node_name,
		"node_type": node_type,
		"animation": anim_node.animation if anim_node is AnimationNodeAnimation else "",
	}


## P-B3: connect_blend_nodes — usa bt.connect_node(input_node, input_index, output_node).
## Godot 4 usa 3 args: el port de salida se asigna automáticamente por bt.
func handle_tree_connect_blend_nodes(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var tree := _resolve_tree(root, args)
	if tree == null:
		return {"ok": false, "error": "animation_tree_not_found"}
	var bt: AnimationNodeBlendTree = tree.tree_root as AnimationNodeBlendTree
	if bt == null:
		return {"ok": false, "error": "tree_root_must_be_blend_tree"}

	var from_node: String = str(args.get("from_node", ""))
	var to_node: String = str(args.get("to_node", ""))
	var from_port: int = int(args.get("from_port", 0))
	if from_node == "" or to_node == "":
		return {"ok": false, "error": "from_node and to_node required"}
	if not bt.has_node(from_node):
		return {"ok": false, "error": "source_node_not_found: " + from_node}
	if not bt.has_node(to_node):
		return {"ok": false, "error": "target_node_not_found: " + to_node}

	bt.connect_node(from_node, from_port, to_node)
	return {
		"ok": true,
		"tree_path": _node_path_relative(tree, root),
		"from": from_node,
		"from_port": from_port,
		"to": to_node,
	}


## P-B5: set_anim_player — asigna el NodePath del AnimationPlayer que el tree usa.
func handle_tree_set_anim_player(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var tree := _resolve_tree(root, args)
	if tree == null:
		return {"ok": false, "error": "animation_tree_not_found"}
	var player_path: String = str(args.get("player_path", ""))
	if player_path == "":
		return {"ok": false, "error": "player_path required"}
	var player := _resolve_node(root, player_path) as AnimationPlayer
	if player == null:
		return {"ok": false, "error": "animation_player_not_found: " + player_path}
	tree.anim_player = player.get_path()
	return {
		"ok": true,
		"tree_path": _node_path_relative(tree, root),
		"player_path": player_path,
	}
