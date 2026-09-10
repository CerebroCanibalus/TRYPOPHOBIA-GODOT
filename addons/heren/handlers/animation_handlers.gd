@tool
extends "res://addons/heren/handlers/heren_handler.gd"
# Heren MCP v4 - Animation + Skeleton handlers (Fase 2).
# Animaciones (AnimationPlayer + AnimationLibrary), state machines
# (AnimationTree + AnimationNodeStateMachine) y esqueletos (Skeleton2D/3D).
# Todas las mutaciones contra la escena viva con EditorUndoRedoManager.
#
# Actions (heredadas de v3 animation_tool.py + skeleton_tool.py, adaptadas):
#   create_player  -> AnimationPlayer en escena viva (undoable)
#   create         -> Animation en AnimationLibrary del player
#   add_track      -> track en animación (value/position_3d/rotation_3d/scale_3d/method)
#   add_key        -> key en track (time, value, transition)
#   state_machine  -> AnimationTree + AnimationNodeStateMachine
#   skeleton_create -> Skeleton2D/3D en escena viva (undoable)
#   skeleton_add_bone -> Bone2D / Skeleton3D.add_bone
#   skeleton_set_rest -> set_bone_rest
#   skeleton_skin  -> Polygon2D.skeleton + weights
#   skeleton_attachment -> BoneAttachment3D en bone
#   tree_set_param -> asigna parámetro de AnimationTree (acepta param_name|name)
#   tree_add_blend_node -> bt.add_node(name, node, pos) [planning P-B2]
#   tree_connect_blend_nodes -> bt.connect_node(from, port, to) [planning P-B3]
#   tree_set_anim_player -> tree.anim_player = NodePath [planning P-B5]

const HerenCoordsScript := preload("coords.gd")
const HerenSceneRegistryScript := preload("../scene_registry.gd")

var _undo_redo: Node


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin
	_undo_redo = plugin.get_undo_redo_wrapper()


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


func _get_animation_player(root: Node, player_path: Variant) -> AnimationPlayer:
	var player := _resolve_node(root, player_path) as AnimationPlayer
	return player


## Resuelve el skeleton objetivo. Si `skeleton_path` viene vacío, auto-detecta:
## 1. El skeleton cuyo nombre coincide con `skeleton_name`.
## 2. El PRIMER Skeleton2D/Skeleton3D en profundidad de la escena.
## Evita el clásico "skeleton_not_found" cuando el agente solo sabe el nombre.
func _resolve_skeleton(root: Node, skeleton_path: Variant, skeleton_name: String = "") -> Node:
	var explicit := _resolve_node(root, skeleton_path)
	if explicit != null:
		return explicit
	if root == null:
		return null
	var name_filter := skeleton_name.strip_edges()
	var queue: Array = [root]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		if n is Skeleton2D or n is Skeleton3D:
			if name_filter == "" or str(n.name) == name_filter:
				return n
		for child in n.get_children():
			queue.append(child)
	return null


## Accepts a Dictionary directly, or a JSON string.
func _args_dict(args: Dictionary, key: String) -> Dictionary:
	var raw: Variant = args.get(key, {})
	if raw is Dictionary:
		return raw
	if raw is String:
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
	return {}


# ---------------------------------------------------------------- animation

func handle_create_player(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	# P2 (E2E 2026-08-15): respetar `player_path` como parent. El agente pasa
	# player_path:"Robot" esperando que el player se cree DENTRO de Robot, no
	# en el root. `parent_path` sigue siendo el alias canónico; si no viene,
	# player_path actúa como parent (y si termina en /AnimationPlayer, el
	# nombre del player se deriva del path).
	var parent_arg: String = str(args.get("parent_path", ""))
	var player_path_arg: String = str(args.get("player_path", ""))
	var parent: Node = root
	var player_name: String = str(args.get("player_name", "AnimationPlayer"))
	if parent_arg != "":
		parent = _resolve_node(root, parent_arg)
		if parent == null:
			return {"ok": false, "error": "parent_not_found: " + parent_arg}
	elif player_path_arg != "":
		# player_path puede ser "Robot" (parent) o "Robot/AnimationPlayer" (path completo)
		var pp := player_path_arg.trim_suffix("/")
		var last_slash := pp.rfind("/")
		if last_slash != -1:
			var parent_part := pp.substr(0, last_slash)
			var name_part := pp.substr(last_slash + 1)
			if parent_part != "":
				parent = _resolve_node(root, parent_part)
				if parent == null:
					return {"ok": false, "error": "parent_not_found: " + parent_part}
			if name_part != "":
				player_name = name_part
		else:
			parent = _resolve_node(root, pp)
			if parent == null:
				return {"ok": false, "error": "parent_not_found: " + pp}

	if parent.get_node_or_null(NodePath(player_name)) != null:
		return {"ok": false, "error": "node_exists: " + player_name}

	var player := AnimationPlayer.new()
	player.name = player_name

	_undo_redo.begin_action("Heren Add AnimationPlayer")
	_undo_redo.add_do_method(parent, &"add_child", [player])
	_undo_redo.add_do_property(player, &"owner", root)
	_undo_redo.add_undo_method(parent, &"remove_child", [player])
	_undo_redo.commit_action()

	return {
		"ok": true,
		"player_name": player.name,
		"player_path": _node_path_relative(parent, root) + "/" + player.name,
	}


func handle_create(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var player: AnimationPlayer = _get_animation_player(root, args.get("player_path", ""))
	if player == null:
		return {"ok": false, "error": "animation_player_not_found"}
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}

	var anim := Animation.new()
	anim.length = float(args.get("length", 1.0))
	anim.loop_mode = Animation.LOOP_LINEAR if bool(args.get("loop", false)) else Animation.LOOP_NONE

	var anim_lib := player.get_animation_library("")
	if anim_lib == null:
		anim_lib = AnimationLibrary.new()
		player.add_animation_library("", anim_lib)
	anim_lib.add_animation(anim_name, anim)

	return {
		"ok": true,
		"player_path": _node_path_relative(player, root),
		"anim_name": anim_name,
		"length": anim.length,
	}


func handle_add_key(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var player: AnimationPlayer = _get_animation_player(root, args.get("player_path", ""))
	if player == null:
		return {"ok": false, "error": "animation_player_not_found"}
	var anim_name: String = str(args.get("anim_name", ""))
	var track_idx: int = int(args.get("track_idx", 0))
	var time: float = float(args.get("time", 0.0))
	var transition: float = float(args.get("transition", 1.0))

	var anim: Animation = player.get_animation(anim_name) if player.has_animation(anim_name) else null
	if anim == null:
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"ok": false, "error": "invalid_track_idx: " + str(track_idx)}

	var value: Variant = HerenCoordsScript.deserialize_value(args.get("value"))

	# P3+P11 (E2E 2026-08-15): validar tipo de valor por track + auto-convertir.
	# - rotation_3d exige Quaternion NORMALIZADO (norma=1). Vector3 falla
	#   silencioso (key_idx:-1) y Quaternion sin normalizar da warning Godot.
	# - position_3d/scale_3d exigen Vector3.
	var track_type := anim.track_get_type(track_idx)
	match track_type:
		Animation.TYPE_ROTATION_3D:
			# rotation_3d exige Quaternion NORMALIZADO (norma≈1).
			# Vector3 NO se auto-convierte (Godot track_insert_key lo rechaza).
			# El agente debe pasar Quaternion {x,y,z,w} directamente.
			if not (value is Quaternion):
				return {"ok": false, "error": "rotation_3d track requires normalized Quaternion {x,y,z,w}; got: " + str(typeof(value))}
			# E4 (2026-08-24): comparar con tolerancia, no exacta.
			# value.normalized() crea float ligeramente distinto → != siempre true.
			var len: float = value.length()
			if abs(len - 1.0) > 0.01:
				return {"ok": false, "error": "rotation_3d track requires normalized Quaternion (|q|≈1); got |q|=" + str(len)}
			# Normalizar por consistencia (por si no estaba exactamente unitario)
			value = value.normalized()
		Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D:
			if not (value is Vector3):
				return {"ok": false, "error": "position_3d/scale_3d track requires Vector3 {x,y,z}; got: " + str(typeof(value))}
		Animation.TYPE_VALUE:
			# value track: cualquier Variant es válido (pero no Quaternion suelto)
			pass
		_:
			pass

	var key_idx := anim.track_insert_key(track_idx, time, value, transition)
	if key_idx < 0:
		return {"ok": false, "error": "track_insert_key failed (tipo de valor incompatible con el track)"}

	return {"ok": true, "key_idx": key_idx, "track_idx": track_idx, "time": time}


func handle_state_machine(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var player: AnimationPlayer = _get_animation_player(root, args.get("player_path", ""))
	if player == null:
		return {"ok": false, "error": "animation_player_not_found"}

	# Fase 3: soporta AnimationNodeStateMachine (default) o AnimationNodeBlendTree
	# con blend spaces 1D/2D, one-shot, time-scale, transición y parámetros.
	var graph_type: String = str(args.get("graph_type", "state_machine"))
	var graph_root: AnimationNode

	match graph_type:
		"blend_tree":
			graph_root = _build_blend_tree(args)
		"blend_space_1d":
			graph_root = _build_blend_space_1d(args)
		"blend_space_2d":
			graph_root = _build_blend_space_2d(args)
		_:
			graph_root = _build_state_machine(args)

	if graph_root == null:
		return {"ok": false, "error": "failed to build graph"}

	var tree := AnimationTree.new()
	tree.tree_root = graph_root
	tree.anim_player = player.get_path()

	# Parámetros iniciales (si el grafo los expone).
	var params: Dictionary = _args_dict(args, "parameters")
	if not params.is_empty():
		for key in params.keys():
			var param_name := "parameters/" + str(key)
			if tree.get(param_name) != null:
				tree.set(param_name, HerenCoordsScript.deserialize_value(params[key]))

	_undo_redo.begin_action("Heren Create AnimationTree")
	_undo_redo.add_do_method(player, &"add_child", [tree])
	_undo_redo.add_do_property(tree, &"owner", root)
	_undo_redo.add_undo_method(player, &"remove_child", [tree])
	_undo_redo.commit_action()

	return {
		"ok": true,
		"state_machine": true,
		"graph_type": graph_type,
		"tree_path": _node_path_relative(player, root) + "/" + tree.name,
		"parameters": params.size(),
	}


func _build_state_machine(args: Dictionary) -> AnimationNodeStateMachine:
	var state_machine := AnimationNodeStateMachine.new()
	var states: Array = args.get("states", [])
	for state in states:
		var state_dict: Dictionary = state if state is Dictionary else {}
		var state_name: String = str(state_dict.get("name", ""))
		var anim_name: String = str(state_dict.get("animation", ""))
		if state_name != "" and anim_name != "":
			var anim_node := AnimationNodeAnimation.new()
			anim_node.animation = anim_name
			state_machine.add_node(state_name, anim_node)

	var transitions: Array = args.get("transitions", [])
	for transition in transitions:
		var trans_dict: Dictionary = transition if transition is Dictionary else {}
		var from_state: String = str(trans_dict.get("from", ""))
		var to_state: String = str(trans_dict.get("to", ""))
		var condition: String = str(trans_dict.get("condition", ""))
		if from_state != "" and to_state != "":
			var trans := AnimationNodeStateMachineTransition.new()
			if condition != "":
				trans.advance_condition = condition
			state_machine.add_transition(from_state, to_state, trans)
	return state_machine


func _build_blend_tree(args: Dictionary) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var nodes: Array = args.get("nodes", [])
	for n in nodes:
		var nd: Dictionary = n if n is Dictionary else {}
		var name: String = str(nd.get("name", ""))
		var node_type: String = str(nd.get("type", ""))
		if name == "" or node_type == "":
			continue
		var anim_node: AnimationNode = null
		match node_type:
			"animation":
				var an := AnimationNodeAnimation.new()
				an.animation = str(nd.get("animation", ""))
				anim_node = an
			"blend2":
				anim_node = AnimationNodeBlend2.new()
			"blend3":
				anim_node = AnimationNodeBlend3.new()
			"add2":
				anim_node = AnimationNodeAdd2.new()
			"add3":
				anim_node = AnimationNodeAdd3.new()
			"sub2":
				anim_node = AnimationNodeSub2.new()
			"sync":
				anim_node = AnimationNodeSync.new()
			"one_shot":
				anim_node = AnimationNodeOneShot.new()
			"time_scale":
				anim_node = AnimationNodeTimeScale.new()
			"time_seek":
				anim_node = AnimationNodeTimeSeek.new()
			"transition":
				anim_node = AnimationNodeTransition.new()
			"output":
				anim_node = AnimationNodeOutput.new()
			_:
				continue
		bt.add_node(name, anim_node)

	var connections: Array = args.get("connections", [])
	for c in connections:
		var cd: Dictionary = c if c is Dictionary else {}
		var from_node: String = str(cd.get("from", ""))
		var from_port: int = int(cd.get("from_port", 0))
		var to_node: String = str(cd.get("to", ""))
		var to_port: int = int(cd.get("to_port", 0))
		if from_node != "" and to_node != "":
			bt.connect_node(from_node, from_port, to_node)
	return bt


func _build_blend_space_1d(args: Dictionary) -> AnimationNodeBlendSpace1D:
	var bs := AnimationNodeBlendSpace1D.new()
	bs.min_space = float(args.get("min", 0.0))
	bs.max_space = float(args.get("max", 1.0))
	bs.blend_mode = int(args.get("blend_mode", 0))
	bs.snap = float(args.get("snap", 0.1))
	var points: Array = args.get("points", [])
	for p in points:
		var pd: Dictionary = p if p is Dictionary else {}
		var anim_name: String = str(pd.get("animation", ""))
		var pos: float = float(pd.get("position", 0.0))
		if anim_name != "":
			var an := AnimationNodeAnimation.new()
			an.animation = anim_name
			bs.add_blend_point(an, pos)
	return bs


func _build_blend_space_2d(args: Dictionary) -> AnimationNodeBlendSpace2D:
	var bs := AnimationNodeBlendSpace2D.new()
	bs.min_space = Vector2(float(args.get("min_x", -1.0)), float(args.get("min_y", -1.0)))
	bs.max_space = Vector2(float(args.get("max_x", 1.0)), float(args.get("max_y", 1.0)))
	bs.blend_mode = int(args.get("blend_mode", 0))
	bs.snap = Vector2(float(args.get("snap_x", 0.1)), float(args.get("snap_y", 0.1)))
	bs.x_label = str(args.get("x_label", "x"))
	bs.y_label = str(args.get("y_label", "y"))
	var points: Array = args.get("points", [])
	for p in points:
		var pd: Dictionary = p if p is Dictionary else {}
		var anim_name: String = str(pd.get("animation", ""))
		var pos := Vector2(float(pd.get("x", 0.0)), float(pd.get("y", 0.0)))
		if anim_name != "":
			var an := AnimationNodeAnimation.new()
			an.animation = anim_name
			bs.add_blend_point(an, pos)
	return bs


# ---------------------------------------------------------------- edición (Fase 2)

func handle_remove_track(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	var anim: Animation = player.get_animation(anim_name)
	var track_idx: int = int(args.get("track_idx", -1))
	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"ok": false, "error": "invalid_track_idx: " + str(track_idx)}
	anim.remove_track(track_idx)
	return {"ok": true, "anim_name": anim_name, "removed_track": track_idx, "tracks_left": anim.get_track_count()}


func handle_remove_key(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	var anim: Animation = player.get_animation(anim_name)
	var track_idx: int = int(args.get("track_idx", -1))
	var key_idx: int = int(args.get("key_idx", -1))
	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"ok": false, "error": "invalid_track_idx: " + str(track_idx)}
	if key_idx < 0 or key_idx >= anim.track_get_key_count(track_idx):
		return {"ok": false, "error": "invalid_key_idx: " + str(key_idx)}
	anim.track_remove_key(track_idx, key_idx)
	return {"ok": true, "anim_name": anim_name, "track_idx": track_idx, "removed_key": key_idx}


func handle_update_key(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	var anim: Animation = player.get_animation(anim_name)
	var track_idx: int = int(args.get("track_idx", -1))
	var key_idx: int = int(args.get("key_idx", -1))
	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"ok": false, "error": "invalid_track_idx: " + str(track_idx)}
	if key_idx < 0 or key_idx >= anim.track_get_key_count(track_idx):
		return {"ok": false, "error": "invalid_key_idx: " + str(key_idx)}

	if args.has("time"):
		anim.track_set_key_time(track_idx, key_idx, float(args.get("time")))
	if args.has("value"):
		anim.track_set_key_value(track_idx, key_idx, HerenCoordsScript.deserialize_value(args.get("value")))
	if args.has("transition"):
		anim.track_set_key_transition(track_idx, key_idx, float(args.get("transition")))

	return {"ok": true, "anim_name": anim_name, "track_idx": track_idx, "key_idx": key_idx}


func handle_update_props(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	var anim: Animation = player.get_animation(anim_name)

	if args.has("length"):
		anim.length = float(args.get("length"))
	if args.has("loop"):
		anim.loop_mode = Animation.LOOP_LINEAR if bool(args.get("loop")) else Animation.LOOP_NONE
	if args.has("loop_mode"):
		match str(args.get("loop_mode")):
			"linear":
				anim.loop_mode = Animation.LOOP_LINEAR
			"pingpong":
				anim.loop_mode = Animation.LOOP_PINGPONG
			_:
				anim.loop_mode = Animation.LOOP_NONE

	return {"ok": true, "anim_name": anim_name, "length": anim.length, "loop_mode": _loop_mode_str(anim.loop_mode)}


# ---------------------------------------------------------------- one_shot (Fase 2)

func handle_one_shot(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}

	var anim := Animation.new()
	anim.length = float(args.get("length", 1.0))
	if args.has("loop_mode"):
		match str(args.get("loop_mode")):
			"linear":
				anim.loop_mode = Animation.LOOP_LINEAR
			"pingpong":
				anim.loop_mode = Animation.LOOP_PINGPONG
			_:
				anim.loop_mode = Animation.LOOP_NONE
	else:
		anim.loop_mode = Animation.LOOP_LINEAR if bool(args.get("loop", false)) else Animation.LOOP_NONE

	var tracks: Array = args.get("tracks", [])
	var track_count := 0
	var key_count := 0
	var key_failures: Array = []
	for t in tracks:
		var td: Dictionary = t if t is Dictionary else {}
		var node_path: String = str(td.get("node", ""))
		var property: String = str(td.get("property", ""))
		var track_type: String = str(td.get("track_type", "value"))
		if node_path == "":
			continue

		var track_idx := -1
		match track_type:
			"value":
				track_idx = anim.add_track(Animation.TYPE_VALUE)
				anim.track_set_path(track_idx, node_path + ":" + property)
			"position_3d", "rotation_3d", "scale_3d":
				track_idx = anim.add_track(Animation.TYPE_POSITION_3D if track_type == "position_3d" else Animation.TYPE_ROTATION_3D if track_type == "rotation_3d" else Animation.TYPE_SCALE_3D)
				anim.track_set_path(track_idx, node_path)
			"method":
				track_idx = anim.add_track(Animation.TYPE_METHOD)
				anim.track_set_path(track_idx, node_path)
			"bezier":
				track_idx = anim.add_track(Animation.TYPE_BEZIER)
				anim.track_set_path(track_idx, node_path + ":" + property)
			"audio":
				track_idx = anim.add_track(Animation.TYPE_AUDIO)
				anim.track_set_path(track_idx, node_path)
			_:
				continue
		track_count += 1

		var keys: Array = td.get("keys", [])
		for k in keys:
			var kd: Dictionary = k if k is Dictionary else {}
			var time: float = float(kd.get("time", 0.0))
			var transition: float = float(kd.get("transition", 1.0))
			var inserted: int
			if track_type == "method":
				var method_name: String = str(kd.get("method", ""))
				var method_args: Array = kd.get("args", [])
				var m := {"method": method_name, "args": method_args}
				inserted = anim.track_insert_key(track_idx, time, m, transition)
			else:
				var value: Variant = HerenCoordsScript.deserialize_value(kd.get("value"))
				inserted = anim.track_insert_key(track_idx, time, value, transition)
			# FAIL-FAST (2026-09-03): track_insert_key retorna -1 si el tipo de
			# valor es incompatible con el track (ej: Vector3 en rotation_3d).
			# Antes se incrementaba key_count incondicionalmente → falseaba.
			if inserted < 0:
				key_failures.append({"track": node_path, "time": time, "type": track_type})
				continue
			key_count += 1

	var anim_lib := player.get_animation_library("")
	if anim_lib == null:
		anim_lib = AnimationLibrary.new()
		player.add_animation_library("", anim_lib)
	anim_lib.add_animation(anim_name, anim)

	if key_failures.size() > 0:
		return {
			"ok": false,
			"error": "one_shot_partial_failure: %d keys rechazados por tipo incompatible" % key_failures.size(),
			"anim_name": anim_name,
			"tracks": track_count,
			"keys": key_count,
			"key_failures": key_failures,
		}
	return {
		"ok": true,
		"anim_name": anim_name,
		"length": anim.length,
		"loop_mode": _loop_mode_str(anim.loop_mode),
		"tracks": track_count,
		"keys": key_count,
		"player_path": _node_path_relative(player, root),
	}


# ---------------------------------------------------------------- tween (Fase 3)

func handle_tween(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node := _resolve_node(root, args.get("node_path", ""))
	if node == null:
		return {"ok": false, "error": "node_not_found"}
	var property: String = str(args.get("property", ""))
	if property == "":
		return {"ok": false, "error": "property required"}

	var duration: float = float(args.get("duration", 1.0))
	var to_value: Variant = HerenCoordsScript.deserialize_value(args.get("to"))
	var from_value: Variant = HerenCoordsScript.deserialize_value(args.get("from", null))
	var easing: String = str(args.get("easing", "linear"))
	var transition: String = str(args.get("transition", "linear"))

	var tween := node.create_tween()
	var tween_prop: PropertyTweener
	if from_value != null:
		tween_prop = tween.tween_property(node, property, to_value, duration).from(from_value)
	else:
		tween_prop = tween.tween_property(node, property, to_value, duration)
	tween_prop.set_trans(_tween_transition(transition))
	tween_prop.set_ease(_tween_ease(easing))

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"property": property,
		"duration": duration,
		"to": HerenCoordsScript.serialize_value(to_value, true),
		"easing": easing,
		"transition": transition,
	}


func _tween_transition(name: String) -> int:
	match name:
		"quad": return Tween.TRANS_QUAD
		"cubic": return Tween.TRANS_CUBIC
		"quart": return Tween.TRANS_QUART
		"quint": return Tween.TRANS_QUINT
		"sine": return Tween.TRANS_SINE
		"expo": return Tween.TRANS_EXPO
		"circ": return Tween.TRANS_CIRC
		"elastic": return Tween.TRANS_ELASTIC
		"back": return Tween.TRANS_BACK
		"bounce": return Tween.TRANS_BOUNCE
		_:
			return Tween.TRANS_LINEAR


func _tween_ease(name: String) -> int:
	match name:
		"in": return Tween.EASE_IN
		"out": return Tween.EASE_OUT
		"in_out": return Tween.EASE_IN_OUT
		"out_in": return Tween.EASE_OUT_IN
		_:
			return Tween.EASE_IN_OUT


# ---------------------------------------------------------------- skeleton pose/ik (Fase 3)

func _find_first_animation_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	var queue: Array = [root]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		if n is AnimationPlayer:
			return n
		for child in n.get_children():
			queue.append(child)
	return null


func handle_record(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	var node_path: String = str(args.get("node_path", ""))
	if node_path == "":
		return {"ok": false, "error": "node_path required"}
	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found"}
	var property: String = str(args.get("property", "position"))
	var fps: float = float(args.get("fps", 30.0))
	var duration: float = float(args.get("duration", 1.0))

	# Graba el estado del nodo cada frame durante `duration` segundos.
	var anim := Animation.new()
	anim.length = duration
	anim.loop_mode = Animation.LOOP_LINEAR if bool(args.get("loop", false)) else Animation.LOOP_NONE
	var track_idx := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track_idx, node_path + ":" + property)

	var steps: int = int(duration * fps)
	var dt: float = 1.0 / fps
	for i in steps + 1:
		var t: float = i * dt
		var value: Variant = node.get(property)
		anim.track_insert_key(track_idx, t, value, 1.0)
		# Avanzar un frame del editor para capturar el siguiente estado.
		await _editor_interface().get_base_control().get_tree().process_frame

	var anim_lib := player.get_animation_library("")
	if anim_lib == null:
		anim_lib = AnimationLibrary.new()
		player.add_animation_library("", anim_lib)
	anim_lib.add_animation(anim_name, anim)

	return {
		"ok": true,
		"anim_name": anim_name,
		"node_path": node_path,
		"property": property,
		"fps": fps,
		"duration": duration,
		"keys": steps + 1,
	}


func handle_from_path(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	var path_node := _resolve_node(root, args.get("path_path", ""))
	if path_node == null:
		return {"ok": false, "error": "path_not_found"}
	var node_path: String = str(args.get("node_path", ""))
	if node_path == "":
		return {"ok": false, "error": "node_path required"}

	var is_3d: bool = path_node is Path3D
	var curve: Variant = null
	if path_node is Path2D:
		curve = (path_node as Path2D).curve
	elif path_node is Path3D:
		curve = (path_node as Path3D).curve
	if curve == null:
		return {"ok": false, "error": "path_has_no_curve"}

	var duration: float = float(args.get("duration", 1.0))
	var fps: float = float(args.get("fps", 30.0))

	var anim := Animation.new()
	anim.length = duration
	anim.loop_mode = Animation.LOOP_LINEAR if bool(args.get("loop", false)) else Animation.LOOP_NONE
	var track_idx := anim.add_track(Animation.TYPE_POSITION_3D if is_3d else Animation.TYPE_VALUE)
	var prop: String = "position" if is_3d else "position"
	anim.track_set_path(track_idx, node_path + (":" + prop if not is_3d else ""))

	var steps: int = int(duration * fps)
	var dt: float = 1.0 / fps
	for i in steps + 1:
		var t: float = i * dt
		var offset: float = t / duration
		if is_3d:
			var pos3: Vector3 = (path_node as Path3D).curve.sample_baked(offset * (path_node as Path3D).curve.get_baked_length())
			anim.track_insert_key(track_idx, t, pos3, 1.0)
		else:
			var pos2: Vector2 = (path_node as Path2D).curve.sample_baked(offset * (path_node as Path2D).curve.get_baked_length())
			anim.track_insert_key(track_idx, t, pos2, 1.0)

	var anim_lib := player.get_animation_library("")
	if anim_lib == null:
		anim_lib = AnimationLibrary.new()
		player.add_animation_library("", anim_lib)
	anim_lib.add_animation(anim_name, anim)

	return {
		"ok": true,
		"anim_name": anim_name,
		"node_path": node_path,
		"path": _node_path_relative(path_node, root),
		"duration": duration,
		"keys": steps + 1,
		"is_3d": is_3d,
	}


func handle_loop_pose(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	var node_path: String = str(args.get("node_path", ""))
	if node_path == "":
		return {"ok": false, "error": "node_path required"}
	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found"}

	# Genera keyframes de bucle procedural (idle bob / breathing / walk simple).
	var property: String = str(args.get("property", "position"))
	var amplitude: float = float(args.get("amplitude", 10.0))
	var frequency: float = float(args.get("frequency", 2.0))
	var duration: float = float(args.get("duration", 1.0))
	var fps: float = float(args.get("fps", 30.0))
	var axis: String = str(args.get("axis", "y"))
	var base_value: Variant = node.get(property)

	var anim := Animation.new()
	anim.length = duration
	anim.loop_mode = Animation.LOOP_LINEAR
	var track_idx := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track_idx, node_path + ":" + property)

	var steps: int = int(duration * fps)
	var dt: float = 1.0 / fps
	for i in steps + 1:
		var t: float = i * dt
		var phase: float = t * frequency * TAU
		var offset: float = sin(phase) * amplitude
		var value: Variant = base_value
		if value is Vector2:
			var v2 := value as Vector2
			if axis == "x":
				v2.x += offset
			else:
				v2.y += offset
			value = v2
		elif value is Vector3:
			var v3 := value as Vector3
			if axis == "x":
				v3.x += offset
			elif axis == "z":
				v3.z += offset
			else:
				v3.y += offset
			value = v3
		elif value is float:
			value = float(value) + offset
		anim.track_insert_key(track_idx, t, value, 1.0)

	var anim_lib := player.get_animation_library("")
	if anim_lib == null:
		anim_lib = AnimationLibrary.new()
		player.add_animation_library("", anim_lib)
	anim_lib.add_animation(anim_name, anim)

	return {
		"ok": true,
		"anim_name": anim_name,
		"node_path": node_path,
		"property": property,
		"amplitude": amplitude,
		"frequency": frequency,
		"axis": axis,
		"keys": steps + 1,
	}


func handle_curve(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	var anim: Animation = player.get_animation(anim_name)
	var track_idx: int = int(args.get("track_idx", -1))
	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"ok": false, "error": "invalid_track_idx: " + str(track_idx)}

	# Aplica easing a todos los keyframes del track (Fase 4: animation/curve).
	var easing: String = str(args.get("easing", "linear"))
	var transition: float = _easing_transition(easing)
	for k in anim.track_get_key_count(track_idx):
		anim.track_set_key_transition(track_idx, k, transition)

	return {
		"ok": true,
		"anim_name": anim_name,
		"track_idx": track_idx,
		"easing": easing,
		"keys_updated": anim.track_get_key_count(track_idx),
	}


func _easing_transition(easing: String) -> float:
	# Mapea nombres de easing a valores de transition de Godot (0..1).
	match easing:
		"linear": return 0.0
		"ease_in": return 0.2
		"ease_out": return 0.8
		"ease_in_out": return 0.5
		"elastic": return 0.9
		"bounce": return 0.7
		_:
			return 0.0


# ------------------------------------------------- playback + inspección (Fase 1)

func _player_or_error(root: Node, args: Dictionary) -> Dictionary:
	var player: AnimationPlayer = _get_animation_player(root, args.get("player_path", ""))
	if player == null:
		return {"ok": false, "error": "animation_player_not_found"}
	return {"ok": true, "player": player}


func handle_play(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	var custom_blend: float = float(args.get("custom_blend", -1.0))

	if anim_name != "":
		if not player.has_animation(anim_name):
			return {"ok": false, "error": "animation_not_found: " + anim_name}
		if custom_blend >= 0.0:
			player.play(anim_name, custom_blend)
		else:
			player.play(anim_name)
	else:
		# Reproduce la animación actual (o la primera si no hay ninguna).
		player.play()

	return {
		"ok": true,
		"playing": player.is_playing(),
		"current_animation": player.current_animation,
		"position": player.current_animation_position,
		"player_path": _node_path_relative(player, root),
	}


func handle_stop(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	player.stop()
	return {
		"ok": true,
		"playing": false,
		"player_path": _node_path_relative(player, root),
	}


func handle_seek(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var time: float = float(args.get("time", 0.0))
	player.seek(time, true)
	return {
		"ok": true,
		"position": player.current_animation_position,
		"player_path": _node_path_relative(player, root),
	}


func handle_speed(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var speed: float = float(args.get("speed", 1.0))
	player.speed_scale = speed
	return {
		"ok": true,
		"speed_scale": player.speed_scale,
		"player_path": _node_path_relative(player, root),
	}


func handle_get_animations(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player

	var libs: Array = []
	for lib_name in player.get_animation_library_list():
		var lib := player.get_animation_library(lib_name)
		var anims: Array = []
		for anim_name in lib.get_animation_list():
			var anim := lib.get_animation(anim_name)
			anims.append({
				"name": anim_name,
				"length": anim.length,
				"loop_mode": _loop_mode_str(anim.loop_mode),
				"tracks": anim.get_track_count(),
			})
		libs.append({"library": lib_name if lib_name != "" else "<default>", "animations": anims})

	return {
		"ok": true,
		"current_animation": player.current_animation,
		"playing": player.is_playing(),
		"position": player.current_animation_position,
		"libraries": libs,
		"player_path": _node_path_relative(player, root),
	}


func handle_get_tracks(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	var anim: Animation = player.get_animation(anim_name)

	var tracks: Array = []
	for i in anim.get_track_count():
		var track_type: int = anim.track_get_type(i)
		var track_path: String = str(anim.track_get_path(i))
		tracks.append({
			"idx": i,
			"type": _track_type_str(track_type),
			"path": track_path,
			"keys": anim.track_get_key_count(i),
			"enabled": anim.track_is_enabled(i),
		})

	return {
		"ok": true,
		"anim_name": anim_name,
		"length": anim.length,
		"loop_mode": _loop_mode_str(anim.loop_mode),
		"tracks": tracks,
	}


func handle_get_keyframes(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	var anim: Animation = player.get_animation(anim_name)

	var track_idx: int = int(args.get("track_idx", -1))
	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"ok": false, "error": "invalid_track_idx: " + str(track_idx)}

	var keys: Array = []
	for k in anim.track_get_key_count(track_idx):
		var key := {
			"idx": k,
			"time": anim.track_get_key_time(track_idx, k),
			"transition": anim.track_get_key_transition(track_idx, k),
		}
		if anim.track_get_type(track_idx) != Animation.TYPE_METHOD:
			key["value"] = HerenCoordsScript.serialize_value(anim.track_get_key_value(track_idx, k))
		else:
			var m: Dictionary = anim.track_get_key_value(track_idx, k)
			key["method"] = str(m.get("method", ""))
			key["args"] = HerenCoordsScript.serialize_value(m.get("args", []))
		keys.append(key)

	return {
		"ok": true,
		"anim_name": anim_name,
		"track_idx": track_idx,
		"track_type": _track_type_str(anim.track_get_type(track_idx)),
		"keys": keys,
	}


func handle_get_state_machine(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var tree_path: Variant = args.get("tree_path", "")
	var tree: AnimationTree = null
	if tree_path != null and str(tree_path) != "":
		tree = _resolve_node(root, tree_path) as AnimationTree
	else:
		# Buscar el AnimationTree hijo del player (o cualquier AnimationTree del root).
		var resolved := _player_or_error(root, args)
		if resolved.ok:
			var player: AnimationPlayer = resolved.player
			for child in player.get_children():
				if child is AnimationTree:
					tree = child as AnimationTree
					break
		if tree == null:
			for child in root.get_children():
				if child is AnimationTree:
					tree = child as AnimationTree
					break
	if tree == null:
		return {"ok": false, "error": "animation_tree_not_found"}

	var graph_root: AnimationNode = tree.tree_root
	var info := {
		"root_type": graph_root.get_class() if graph_root != null else "",
		"tree_path": _node_path_relative(tree, root),
		"parameters": [],
	}

	if graph_root is AnimationNodeStateMachine:
		var sm := graph_root as AnimationNodeStateMachine
		var states: Array = []
		for state_name in sm.get_node_list():
			var state_node: AnimationNode = sm.get_node(state_name)
			var state_info := {"name": str(state_name), "type": state_node.get_class()}
			if state_node is AnimationNodeAnimation:
				state_info["animation"] = (state_node as AnimationNodeAnimation).animation
			states.append(state_info)
		info["states"] = states

		var transitions: Array = []
		for t in sm.get_transition_list():
			transitions.append({
				"from": str(t.get("from", "")),
				"to": str(t.get("to", "")),
				"advance_condition": str(t.get("advance_condition", "")),
			})
		info["transitions"] = transitions
	elif graph_root is AnimationNodeBlendSpace2D:
		var bs := graph_root as AnimationNodeBlendSpace2D
		var points: Array = []
		for p in bs.get_blend_points():
			var anim_node := bs.get_blend_point_node(p) as AnimationNodeAnimation
			points.append({
				"point": bs.get_blend_point_position(p),
				"animation": anim_node.animation if anim_node else "",
			})
		info["blend_space_2d"] = {
			"blend_positions": bs.blend_positions,
			"blend_point_count": points.size(),
			"x_label": bs.x_label, "y_label": bs.y_label,
		}
		info["points"] = points
	elif graph_root is AnimationNodeBlendTree:
		var bt := graph_root as AnimationNodeBlendTree
		var nodes: Array = []
		for n in bt.get_node_list():
			nodes.append({"name": str(n), "type": bt.get_node(n).get_class()})
		info["blend_tree"] = {"nodes": nodes, "connections": bt.get_connection_list().size()}

	for p in tree.get_parameter_list():
		info["parameters"].append(str(p))
	if graph_root != null:
		info["root_parameters"] = tree.get_parameter_list().size()

	return {"ok": true, "state_machine": info}


func _loop_mode_str(mode: int) -> String:
	match mode:
		Animation.LOOP_LINEAR:
			return "linear"
		Animation.LOOP_PINGPONG:
			return "pingpong"
		Animation.LOOP_NONE:
			return "none"
	return "none"


func _track_type_str(type_id: int) -> String:
	match type_id:
		Animation.TYPE_VALUE:
			return "value"
		Animation.TYPE_POSITION_3D:
			return "position_3d"
		Animation.TYPE_ROTATION_3D:
			return "rotation_3d"
		Animation.TYPE_SCALE_3D:
			return "scale_3d"
		Animation.TYPE_BEZIER:
			return "bezier"
		Animation.TYPE_AUDIO:
			return "audio"
		Animation.TYPE_METHOD:
			return "method"
	return "unknown"


# ---------------------------------------------------------------- skeleton

func handle_add_track(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var player: AnimationPlayer = _get_animation_player(root, args.get("player_path", ""))
	if player == null:
		return {"ok": false, "error": "animation_player_not_found"}
	var anim_name: String = str(args.get("anim_name", ""))
	var track_type: String = str(args.get("track_type", "value"))
	var node_path: String = str(args.get("node_path", ""))
	var property: String = str(args.get("property", ""))

	var anim: Animation = player.get_animation(anim_name) if player.has_animation(anim_name) else null
	# S3 (2026-08-24): auto-crear animación si no existe.
	if anim == null:
		anim = Animation.new()
		anim.resource_name = anim_name
		player.add_animation(anim_name, anim)

	# P1: track_type="bone" — resuelve el path del hueso por nombre.
	if track_type == "bone":
		# E1 (2026-08-24): usar _resolve_skeleton (auto-detect) en vez de _resolve_node.
		var skeleton_path: Variant = args.get("skeleton_path", "")
		var skeleton := _resolve_skeleton(root, skeleton_path)
		if skeleton == null:
			return {"ok": false, "error": "skeleton_not_found"}
		if skeleton is Skeleton3D:
			var skel := skeleton as Skeleton3D
			var idx: int = skel.find_bone(node_path)
			if idx < 0:
				return {"ok": false, "error": "bone_not_found: " + node_path}
			var track_idx := anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(track_idx, str(skeleton.get_path()) + ":bones/" + str(idx) + "/pose")
			return {"ok": true, "track_idx": track_idx, "track_type": "bone", "bone": node_path, "bone_idx": idx, "anim_name": anim_name}
		elif skeleton is Skeleton2D:
			var skel := skeleton as Skeleton2D
			var bone: Bone2D = null
			for i in skel.get_bone_count():
				if skel.get_bone(i).name == node_path:
					bone = skel.get_bone(i)
					break
			if bone == null:
				return {"ok": false, "error": "bone_not_found: " + node_path}
			var bone_prop: String = property if property != "" else "rotation"
			var track_idx := anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(track_idx, str(bone.get_path()) + ":" + bone_prop)
			return {"ok": true, "track_idx": track_idx, "track_type": "bone", "bone": node_path, "bone_prop": bone_prop, "anim_name": anim_name}
		return {"ok": false, "error": "invalid_skeleton_type"}

	var track_idx := -1
	# property vacío = no concatenar ":" (track raíz apunta solo a node_path).
	var sub := "" if property.is_empty() else ":" + property
	match track_type:
		"value":
			track_idx = anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(track_idx, node_path + sub)
		"position_3d", "rotation_3d", "scale_3d", "method":
			track_idx = anim.add_track(Animation.TYPE_POSITION_3D if track_type == "position_3d" else Animation.TYPE_ROTATION_3D if track_type == "rotation_3d" else Animation.TYPE_SCALE_3D if track_type == "scale_3d" else Animation.TYPE_METHOD)
			anim.track_set_path(track_idx, node_path)
		"bezier":
			track_idx = anim.add_track(Animation.TYPE_BEZIER)
			anim.track_set_path(track_idx, node_path + sub)
		"audio":
			track_idx = anim.add_track(Animation.TYPE_AUDIO)
			anim.track_set_path(track_idx, node_path)
		_:
			return {"ok": false, "error": "invalid_track_type: " + track_type}

	return {"ok": true, "track_idx": track_idx, "track_type": track_type, "anim_name": anim_name}


# ---------------------------------------------------------------- P1: AnimationTree runtime control

func _resolve_tree(root: Node, args: Dictionary) -> AnimationTree:
	var tree_path: Variant = args.get("tree_path", "")
	if tree_path != null and str(tree_path) != "":
		return _resolve_node(root, tree_path) as AnimationTree
	# Buscar cualquier AnimationTree del root.
	for child in root.get_children():
		if child is AnimationTree:
			return child as AnimationTree
	return null


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


# ---------------------------------------------------------------- P1: IK a profundidad (procedural)

## Amplía skeleton_ik con magnet/influence y soporta "weights" por hueso.
func handle_preview(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}

	var time: float = float(args.get("time", 0.0))
	player.seek(time, true)
	player.pause()

	var out := {
		"ok": true,
		"anim_name": anim_name,
		"time": time,
		"position": player.current_animation_position,
	}
	return out


# ---------------------------------------------------------------- P2: gestión de animaciones (duplicate/delete/rename)

func _get_library(player: AnimationPlayer, library: String) -> AnimationLibrary:
	var lib_name := library if library != "" else ""
	var lib := player.get_animation_library(lib_name)
	if lib == null and lib_name == "":
		return null
	return lib


func handle_duplicate(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}

	var library: String = str(args.get("library", ""))
	var lib := _get_library(player, library)
	if lib == null:
		return {"ok": false, "error": "library_not_found: " + (library if library != "" else "<default>")}

	var new_name: String = str(args.get("new_name", ""))
	if new_name == "":
		new_name = anim_name + "_copy"
	if lib.has_animation(new_name):
		return {"ok": false, "error": "animation_exists: " + new_name}

	# duplicate() copia length, loop_mode y TODOS los tracks/keys.
	var copy: Animation = player.get_animation(anim_name).duplicate()
	lib.add_animation(new_name, copy)

	return {
		"ok": true,
		"anim_name": anim_name,
		"new_name": new_name,
		"tracks": copy.get_track_count(),
		"length": copy.length,
	}


func handle_delete(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}

	var library: String = str(args.get("library", ""))
	var lib := _get_library(player, library)
	if lib == null:
		return {"ok": false, "error": "library_not_found: " + (library if library != "" else "<default>")}

	# Si está reproduciéndose, parar antes de borrar.
	if player.current_animation == anim_name:
		player.stop()
	lib.remove_animation(anim_name)

	return {"ok": true, "deleted": anim_name}


func handle_rename(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	var new_name: String = str(args.get("new_name", ""))
	if new_name == "":
		return {"ok": false, "error": "new_name required"}
	if new_name == anim_name:
		return {"ok": false, "error": "new_name equals anim_name"}

	var library: String = str(args.get("library", ""))
	var lib := _get_library(player, library)
	if lib == null:
		return {"ok": false, "error": "library_not_found: " + (library if library != "" else "<default>")}
	if lib.has_animation(new_name):
		return {"ok": false, "error": "animation_exists: " + new_name}

	lib.rename_animation(anim_name, new_name)
	return {"ok": true, "renamed": anim_name, "to": new_name}


# ---------------------------------------------------------------- P3: avanzado (reverse/blend_pose/retarget)

## Crea una copia invertida de la animación (walk → walk_rev). Util para ciclos.
func handle_reverse(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}

	var library: String = str(args.get("library", ""))
	var lib := _get_library(player, library)
	if lib == null:
		return {"ok": false, "error": "library_not_found: " + (library if library != "" else "<default>")}
	var new_name: String = str(args.get("new_name", ""))
	if new_name == "":
		new_name = anim_name + "_rev"
	if lib.has_animation(new_name):
		return {"ok": false, "error": "animation_exists: " + new_name}

	var src: Animation = player.get_animation(anim_name)
	var rev: Animation = src.duplicate()
	var length: float = src.length

	# Invertir keys de cada track: t' = length - t. Reordenar por tiempo.
	for t in src.get_track_count():
		var key_count: int = src.track_get_key_count(t)
		# Eliminar keys de la copia y re-insertar invertidas.
		while rev.track_get_key_count(t) > 0:
			rev.track_remove_key(t, 0)
		var pairs: Array = []
		for k in key_count:
			var time: float = src.track_get_key_time(t, k)
			var value: Variant = src.track_get_key_value(t, k)
			var transition: float = src.track_get_key_transition(t, k)
			pairs.append({"t": length - time, "v": value, "tr": transition})
		pairs.sort_custom(func(a, b): return a.t < b.t)
		for p in pairs:
			rev.track_insert_key(t, p.t, p.v, p.tr)

	lib.add_animation(new_name, rev)
	return {"ok": true, "anim_name": anim_name, "new_name": new_name, "length": length}


## P3: blend procedural — interpola la pose actual del skeleton hacia una pose
## objetivo por hueso con factor t (0..1). Útil para transiciones suaves.
