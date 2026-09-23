@tool
extends "res://addons/heren/handlers/animation_handlers.gd"

# Heren MCP v4 - ARCHIVADO 2026-09-09 (§0.12 W4 cleanup).
# Skeleton handlers completos (incluye skeleton/* + capture_pose + blend_pose +
# retarget). Reemplazados por scene_script workers — el agente habla directo
# con la API de Godot para tree manipulation, IK, FABRIK, skin, attachment, etc.
#
# Para restaurar, ver addons/heren/archive/handlers/README.md.

func handle_skeleton_get_bones(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node := _resolve_node(root, args.get("skeleton_path", ""))
	if node == null:
		return {"ok": false, "error": "skeleton_not_found"}

	var bones: Array = []
	if node is Skeleton2D:
		var skel2d := node as Skeleton2D
		for i in skel2d.get_bone_count():
			var b := skel2d.get_bone(i)
			bones.append({
				"idx": i,
				"name": b.name,
				"rest": HerenCoordsScript.serialize_value(b.rest, true),
				"default_length": b.default_length,
			})
	elif node is Skeleton3D:
		var skel3d := node as Skeleton3D
		for i in skel3d.get_bone_count():
			bones.append({
				"idx": i,
				"name": skel3d.get_bone_name(i),
				"rest": HerenCoordsScript.serialize_value(skel3d.get_bone_rest(i), true),
				"parent": skel3d.get_bone_parent(i),
			})
	else:
		return {"ok": false, "error": "invalid_skeleton_type"}

	return {"ok": true, "skeleton_path": _node_path_relative(node, root), "bones": bones}




func handle_skeleton_get_pose(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node := _resolve_skeleton(root, args.get("skeleton_path", ""), str(args.get("skeleton_name", "")))
	if node == null:
		return {"ok": false, "error": "skeleton_not_found"}

	# SMART por defecto: cada hueso devuelve delta_vs_rest (rotación en GRADOS
	# + delta de origen) — el agente lee "hand.r rotó +12° en X" sin calcular.
	# compact=false devuelve además pose/global_transform completos (backward).
	# Filtrar por bone_name (1) o bones (lista); con bone_name se incluye la
	# cadena de ancestros (2 niveles) para contexto espacial sin llamada extra.
	var compact: bool = bool(args.get("compact", true))
	var include_context: bool = bool(args.get("context", true))
	var filter_names: Array = []
	var single: String = str(args.get("bone_name", ""))
	if single != "":
		filter_names.append(single)
	var bones_arg: Array = args.get("bones", [])
	if bones_arg is Array and not bones_arg.is_empty():
		for b in bones_arg:
			filter_names.append(str(b))

	# Si pedimos un solo hueso, añadir ancestros (hasta 2 niveles) como contexto.
	var context_extra: Array = []
	if include_context and filter_names.size() == 1:
		var target := single
		if node is Skeleton3D:
			var skel3d := node as Skeleton3D
			var idx := skel3d.find_bone(target)
			var parent := skel3d.get_bone_parent(idx) if idx >= 0 else -1
			var depth := 0
			while parent >= 0 and depth < 2:
				var pname: String = skel3d.get_bone_name(parent)
				if not filter_names.has(pname):
					context_extra.append(pname)
				parent = skel3d.get_bone_parent(parent)
				depth += 1
		elif node is Skeleton2D:
			var skel2d := node as Skeleton2D
			for i in skel2d.get_bone_count():
				var b := skel2d.get_bone(i)
				if str(b.name) == target and b.get_parent() is Bone2D:
					var p: Bone2D = b.get_parent()
					if not filter_names.has(str(p.name)):
						context_extra.append(str(p.name))
					if p.get_parent() is Bone2D:
						var gp: Bone2D = p.get_parent()
						if not filter_names.has(str(gp.name)):
							context_extra.append(str(gp.name))
					break
		for c in context_extra:
			filter_names.append(c)

	var pose: Array = []
	var world_positions: Array = []
	var compare_out := {}
	var compare_arg: Dictionary = args.get("compare", {})
	if compare_arg is Dictionary and not compare_arg.is_empty() and node is Skeleton3D:
		compare_out = _compare_skeleton_pose(node, compare_arg)
	if node is Skeleton2D:
		var skel2d := node as Skeleton2D
		for i in skel2d.get_bone_count():
			var b := skel2d.get_bone(i)
			if not filter_names.is_empty() and not filter_names.has(str(b.name)):
				continue
			var entry := {
				"name": b.name,
				"global": HerenCoordsScript.serialize_value(b.global_position, true),
				"parent": b.get_parent().name if b.get_parent() is Bone2D else "",
			}
			if compact:
				entry["delta_vs_rest"] = {
					"rotation_deg": HerenCoordsScript.rotation_delta_deg(b.rest, b.transform),
					"origin_delta": HerenCoordsScript.origin_delta(b.rest, b.transform),
				}
			else:
				entry["transform"] = HerenCoordsScript.serialize_value(b.transform, true)
			pose.append(entry)
			world_positions.append(b.global_position)
	elif node is Skeleton3D:
		var skel3d := node as Skeleton3D
		for i in skel3d.get_bone_count():
			var bone_name: String = skel3d.get_bone_name(i)
			if not filter_names.is_empty() and not filter_names.has(bone_name):
				continue
			var global_pose: Transform3D = skel3d.get_bone_global_pose(i)
			var rest_pose: Transform3D = skel3d.get_bone_rest(i)
			var entry := {
				"name": bone_name,
				"global": HerenCoordsScript.serialize_value(global_pose.origin, true),
				"parent": skel3d.get_bone_parent(i),
			}
			if compact:
				entry["delta_vs_rest"] = {
					"rotation_deg": HerenCoordsScript.rotation_delta_deg(rest_pose, global_pose),
					"origin_delta": HerenCoordsScript.origin_delta(rest_pose, global_pose),
				}
			else:
				entry["pose"] = HerenCoordsScript.serialize_value(skel3d.get_bone_pose(i), true)
				entry["global_transform"] = HerenCoordsScript.serialize_value(global_pose, true)
			pose.append(entry)
			world_positions.append(global_pose.origin)
	else:
		return {"ok": false, "error": "invalid_skeleton_type"}

	# AABB de la pose actual (bounding box de las posiciones mundiales de los huesos).
	var aabb := {}
	if not world_positions.is_empty():
		var min_x := INF; var min_y := INF; var min_z := INF
		var max_x := -INF; var max_y := -INF; var max_z := -INF
		for p in world_positions:
			min_x = min(min_x, p.x); min_y = min(min_y, p.y); min_z = min(min_z, p.z)
			max_x = max(max_x, p.x); max_y = max(max_y, p.y); max_z = max(max_z, p.z)
		aabb = {
			"min": {"x": min_x, "y": min_y, "z": min_z},
			"max": {"x": max_x, "y": max_y, "z": max_z},
			"size": {"x": max_x - min_x, "y": max_y - min_y, "z": max_z - min_z},
		}

	var out := {"ok": true, "skeleton_path": _node_path_relative(node, root), "pose": pose, "aabb": aabb}
	if not compare_out.is_empty():
		out["compare"] = compare_out
	return out


## Compara la pose del skeleton en dos tiempos de una animación (seek automático).
## Devuelve el delta por hueso: rotación en grados + delta de origen entre
## t1 y t2 — el agente ve "hand.r rotó +28° al pasar de idle a pico" SIN
## tener que hacer dos llamadas ni calcular él la resta (donde se equivoca).
## SÍNCRONO: en el editor, player.seek aplica la pose inmediatamente (sin
## esperar frame), así que el handler no necesita await.


func _compare_skeleton_pose(skeleton: Node, compare: Dictionary) -> Dictionary:
	var root := _scene_root()
	var player: AnimationPlayer = _get_animation_player(root, compare.get("player_path", ""))
	# Auto-detección: si no hay player explícito, buscar el AnimationPlayer más
	# cercano al skeleton (ascendente) — automaticidad sin llamada extra.
	if player == null and skeleton != null:
		var p := skeleton.get_parent()
		while p != null:
			if p is AnimationPlayer:
				player = p
				break
			p = p.get_parent()
	if player == null and root != null:
		player = _find_first_animation_player(root)
	var anim_name: String = str(compare.get("anim", ""))
	var t1: float = float(compare.get("t1", 0.0))
	var t2: float = float(compare.get("t2", 0.0))
	if player == null or anim_name == "" or not player.has_animation(anim_name):
		return {"error": "compare requires anim y t1/t2 (AnimationPlayer auto-detectado si no se da player_path)"}

	var anim: Animation = player.get_animation(anim_name)
	var skel3d := skeleton as Skeleton3D
	if skel3d == null:
		return {"error": "compare solo soporta Skeleton3D"}

	# Guardar playback actual para restaurarlo.
	var was_playing: bool = player.is_playing()
	var was_time: float = player.current_animation_position

	var deltas: Dictionary = {}
	for i in skel3d.get_bone_count():
		var bone_name: String = skel3d.get_bone_name(i)
		player.play(anim_name)
		player.seek(t1, true)
		var p1: Transform3D = skel3d.get_bone_global_pose(i)
		player.seek(t2, true)
		var p2: Transform3D = skel3d.get_bone_global_pose(i)
		deltas[bone_name] = {
			"rotation_deg": HerenCoordsScript.rotation_delta_deg(p1, p2),
			"origin_delta": HerenCoordsScript.origin_delta(p1, p2),
		}

	# Restaurar playback.
	if was_playing:
		player.play(anim_name)
		player.seek(was_time, true)
	else:
		player.stop()
	return deltas


## Primer AnimationPlayer en profundidad (BFS) de la escena.


func handle_skeleton_set_pose(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node := _resolve_skeleton(root, args.get("skeleton_path", ""), str(args.get("skeleton_name", "")))
	if node == null:
		return {"ok": false, "error": "skeleton_not_found"}
	var bone_name: String = str(args.get("bone_name", ""))
	if bone_name == "":
		return {"ok": false, "error": "bone_name required"}

	if node is Skeleton2D:
		var skel2d := node as Skeleton2D
		for i in skel2d.get_bone_count():
			var b := skel2d.get_bone(i)
			if b.name == bone_name:
				var t: Dictionary = _args_dict(args, "transform")
				var angle: float = float(t.get("angle", t.get("rotation", 0.0)))
				var origin := Vector2(float(t.get("x", 0)), float(t.get("y", 0)))
				b.transform = Transform2D(angle, origin)
				return {"ok": true, "bone_name": bone_name, "type": "Skeleton2D",
					"coords": {
						"global": HerenCoordsScript.serialize_value(b.global_position, true),
						"delta_vs_rest": {
							"rotation_deg": HerenCoordsScript.rotation_delta_deg(b.rest, b.transform),
							"origin_delta": HerenCoordsScript.origin_delta(b.rest, b.transform),
						},
					}}
		return {"ok": false, "error": "bone_not_found: " + bone_name}
	elif node is Skeleton3D:
		var skel3d := node as Skeleton3D
		var bone_idx: int = skel3d.find_bone(bone_name)
		if bone_idx < 0:
			return {"ok": false, "error": "bone_not_found: " + bone_name}
		var t: Dictionary = _args_dict(args, "transform")
		var origin := Vector3(float(t.get("x", 0)), float(t.get("y", 0)), float(t.get("z", 0)))
		var basis := Basis()
		if t.has("rotation"):
			var rot: Dictionary = t["rotation"] if t["rotation"] is Dictionary else {}
			basis = Basis.from_euler(Vector3(float(rot.get("x", 0)), float(rot.get("y", 0)), float(rot.get("z", 0))))
		skel3d.set_bone_pose(bone_idx, Transform3D(basis, origin))
		var global_pose: Transform3D = skel3d.get_bone_global_pose(bone_idx)
		var rest_pose: Transform3D = skel3d.get_bone_rest(bone_idx)
		return {"ok": true, "bone_name": bone_name, "bone_idx": bone_idx, "type": "Skeleton3D",
			"coords": {
				"global": HerenCoordsScript.serialize_value(global_pose.origin, true),
				"delta_vs_rest": {
					"rotation_deg": HerenCoordsScript.rotation_delta_deg(rest_pose, global_pose),
					"origin_delta": HerenCoordsScript.origin_delta(rest_pose, global_pose),
				},
			}}
	return {"ok": false, "error": "invalid_skeleton_type"}


# ---------------------------------------------------------------- innovación (Fase 4)



func handle_skeleton_create(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var parent: Node = root
	if args.has("parent_path") and str(args.get("parent_path", "")) != "":
		parent = _resolve_node(root, args.get("parent_path"))
		if parent == null:
			return {"ok": false, "error": "parent_not_found: " + str(args.get("parent_path"))}

	var skeleton_name: String = str(args.get("skeleton_name", "Skeleton2D"))
	var is_3d: bool = bool(args.get("is_3d", false))
	if parent.get_node_or_null(NodePath(skeleton_name)) != null:
		return {"ok": false, "error": "node_exists: " + skeleton_name}

	var skeleton: Node
	if is_3d:
		skeleton = Skeleton3D.new()
	else:
		skeleton = Skeleton2D.new()
	skeleton.name = skeleton_name

	_undo_redo.begin_action("Heren Add Skeleton")
	_undo_redo.add_do_method(parent, &"add_child", [skeleton])
	_undo_redo.add_do_property(skeleton, &"owner", root)
	_undo_redo.add_undo_method(parent, &"remove_child", [skeleton])
	_undo_redo.commit_action()

	return {
		"ok": true,
		"skeleton_path": _node_path_relative(parent, root) + "/" + skeleton.name,
		"skeleton_type": "Skeleton3D" if is_3d else "Skeleton2D",
	}




func handle_skeleton_add_bone(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var skeleton_path: Variant = args.get("skeleton_path", "")
	var skeleton := _resolve_node(root, skeleton_path)
	if skeleton == null:
		return {"ok": false, "error": "skeleton_not_found"}
	var bone_name: String = str(args.get("bone_name", ""))
	if bone_name == "":
		return {"ok": false, "error": "bone_name required"}

	var rest_transform: Dictionary = _args_dict(args, "rest_transform")

	if skeleton is Skeleton2D:
		var bone := Bone2D.new()
		bone.name = bone_name
		var angle: float = float(args.get("bone_angle", 0.0))
		bone.rest = Transform2D(angle, Vector2(
			float(rest_transform.get("x", 0)),
			float(rest_transform.get("y", 0))
		))
		bone.default_length = float(args.get("length", 32.0))
		skeleton.add_child(bone)
		bone.owner = root
		return {"ok": true, "bone_name": bone_name, "type": "Bone2D"}
	return {"ok": false, "error": "unsupported_skeleton_type"}


## P-M11 (Round-3): remove_bone — Borra un hueso del skeleton.
## Para Skeleton2D: elimina el Bone2D hijo por nombre.
## Para Skeleton3D: Godot 4 NO expone remove_bone(name); workaround: clear_bones +
## re-add preservando rest poses (parent indices se pierden en el re-add porque
## add_bone(name) solo toma 1 arg; la jerarquía queda plana pero los huesos existen).
func handle_skeleton_remove_bone(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node := _resolve_node(root, args.get("skeleton_path", ""))
	if node == null:
		return {"ok": false, "error": "skeleton_not_found"}
	var bone_name: String = str(args.get("bone_name", ""))
	if bone_name == "":
		return {"ok": false, "error": "bone_name required"}
	if node is Skeleton2D:
		for child in node.get_children():
			if child is Bone2D and child.name == bone_name:
				node.remove_child(child)
				child.queue_free()
				return {"ok": true, "bone_name": bone_name, "type": "Skeleton2D"}
		return {"ok": false, "error": "bone_not_found: " + bone_name}
	if node is Skeleton3D:
		var skel := node as Skeleton3D
		var idx := skel.find_bone(bone_name)
		if idx < 0:
			return {"ok": false, "error": "bone_not_found: " + bone_name}
		# Snapshot todos los huesos (incluyendo parent indices) ANTES de clear.
		var snap := []  # [{name, rest, parent_old_idx}]
		var old_name_by_idx := {}
		for i in skel.get_bone_count():
			old_name_by_idx[i] = skel.get_bone_name(i)
			if i == idx:
				continue
			snap.append({
				"name": skel.get_bone_name(i),
				"rest": skel.get_bone_rest(i),
				"parent_old_idx": skel.get_bone_parent(i),
			})
		skel.clear_bones()
		# Re-add preservando rest pose. add_bone(name) en Godot 4 acepta solo
		# 1 argumento. set_bone_parent se llama después para la jerarquía.
		var new_idx_by_name := {}
		for d in snap:
			var new_i := skel.add_bone(d["name"])
			new_idx_by_name[d["name"]] = new_i
			skel.set_bone_rest(new_i, d["rest"])
		# Restaurar parent indices (mapeando old_idx → new_idx).
		for d in snap:
			var new_i: int = new_idx_by_name[d["name"]]
			var old_parent: int = d["parent_old_idx"]
			if old_parent >= 0:
				var parent_name: String = old_name_by_idx.get(old_parent, "")
				if parent_name != "" and new_idx_by_name.has(parent_name):
					skel.set_bone_parent(new_i, new_idx_by_name[parent_name])
		return {"ok": true, "bone_name": bone_name, "type": "Skeleton3D", "bones_remaining": skel.get_bone_count()}
	return {"ok": false, "error": "invalid_skeleton_type"}




func handle_skeleton_set_rest(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var node := _resolve_node(root, args.get("skeleton_path", ""))
	if node == null:
		return {"ok": false, "error": "skeleton_not_found"}
	var bone_name: String = str(args.get("bone_name", ""))
	var rest_transform: Dictionary = _args_dict(args, "rest_transform")

	# Fix H4: branch by actual type (Skeleton2D vs Skeleton3D) instead of
	# forcing Skeleton3D.
	#
	# IMPORTANT (Godot 4.7): Skeleton2D has NO set_bone_rest / find_bone
	# (those are Skeleton3D methods). In Skeleton2D each bone IS a Bone2D
	# child node; the rest pose is `bone.rest = Transform2D(...)`. So we
	# find the Bone2D child by name and set its .rest directly.
	if node is Skeleton2D:
		var skel2d := node as Skeleton2D
		var angle: float = float(rest_transform.get("angle", rest_transform.get("rotation", 0.0)))
		var origin := Vector2(
			float(rest_transform.get("x", 0)),
			float(rest_transform.get("y", 0))
		)
		var bone: Node = null
		for child in skel2d.get_children():
			if child is Bone2D and child.name == bone_name:
				bone = child
				break
		if bone == null:
			return {"ok": false, "error": "bone_not_found: " + bone_name}
		(bone as Bone2D).rest = Transform2D(angle, origin)
		return {"ok": true, "bone_name": bone_name, "type": "Skeleton2D"}

	var skeleton := node as Skeleton3D
	if skeleton == null:
		return {"ok": false, "error": "invalid_skeleton_type"}
	var bone_idx: int = skeleton.find_bone(bone_name)
	if bone_idx < 0:
		return {"ok": false, "error": "bone_not_found: " + bone_name}

	var origin := Vector3(
		float(rest_transform.get("x", 0)),
		float(rest_transform.get("y", 0)),
		float(rest_transform.get("z", 0))
	)
	var basis := Basis()
	if rest_transform.has("rotation"):
		var rot: Dictionary = rest_transform["rotation"] if rest_transform["rotation"] is Dictionary else {}
		basis = Basis.from_euler(Vector3(
			float(rot.get("x", 0)),
			float(rot.get("y", 0)),
			float(rot.get("z", 0))
		))
	skeleton.set_bone_rest(bone_idx, Transform3D(basis, origin))

	return {"ok": true, "bone_name": bone_name, "bone_idx": bone_idx, "type": "Skeleton3D"}




func handle_skeleton_skin(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var polygon := _resolve_node(root, args.get("polygon_path", "")) as Polygon2D
	var skeleton := _resolve_node(root, args.get("skeleton_path", "")) as Skeleton2D
	if polygon == null:
		return {"ok": false, "error": "polygon2d_not_found"}
	if skeleton == null:
		return {"ok": false, "error": "skeleton2d_not_found"}

	polygon.skeleton = skeleton.get_path()

	var bone_weights: Dictionary = _args_dict(args, "bone_weights")
	var bones: Array = []
	for bone_name in bone_weights.keys():
		var weights: Array = bone_weights[bone_name]
		# Fix H3: `set_bone_weights` (not `set_bone_weigths`) and it takes
		# a bone INDEX (int), not a bone name (String).
		#
		# Fix H4: Skeleton2D has NO find_bone (Skeleton3D method) — locate the
		# Bone2D child index by iterating get_bone_count()/get_bone().
		var bone_idx := -1
		for i in skeleton.get_bone_count():
			if skeleton.get_bone(i).name == str(bone_name):
				bone_idx = i
				break
		if bone_idx == -1:
			return {"ok": false, "error": "bone_not_found: " + str(bone_name)}
		polygon.set_bone_weights(bone_idx, PackedFloat32Array(weights))
		bones.append(bone_name)

	return {"ok": true, "polygon": polygon.name, "skeleton": skeleton.name, "bones": bones}




func handle_skeleton_attachment(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var node := _resolve_node(root, args.get("skeleton_path", ""))
	if node == null:
		return {"ok": false, "error": "skeleton_not_found"}
	var bone_name: String = str(args.get("bone_name", ""))
	var attachment_name: String = str(args.get("attachment_name", "Attachment"))

	# Fix H4: branch by type. 2D uses a plain Node2D child of the Bone2D
	# (BoneAttachment2D does NOT exist in Godot 4); 3D uses BoneAttachment3D.
	# Skeleton2D has no find_bone (Skeleton3D method) — find the Bone2D child.
	if node is Skeleton2D:
		var skel2d := node as Skeleton2D
		var bone: Node = null
		var bone_idx := -1
		for i in skel2d.get_bone_count():
			var b := skel2d.get_bone(i)
			if b.name == bone_name:
				bone = b
				bone_idx = i
				break
		if bone == null:
			return {"ok": false, "error": "bone_not_found: " + bone_name}
		var att2d := Node2D.new()
		att2d.name = attachment_name
		bone.add_child(att2d)
		att2d.owner = root
		return {"ok": true, "attachment": att2d.name, "bone": bone_name, "bone_idx": bone_idx, "type": "BoneAttachment2D"}

	var skeleton := node as Skeleton3D
	if skeleton == null:
		return {"ok": false, "error": "invalid_skeleton_type"}
	var bone_idx: int = skeleton.find_bone(bone_name)
	if bone_idx < 0:
		return {"ok": false, "error": "bone_not_found: " + bone_name}
	var attachment := BoneAttachment3D.new()
	attachment.name = attachment_name
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	attachment.owner = root

	return {"ok": true, "attachment": attachment.name, "bone": bone_name, "bone_idx": bone_idx, "type": "BoneAttachment3D"}


# ---------------------------------------------------------------- P1: capture_pose + bone tracks + tree control

## Resuelve los huesos a capturar: bones (lista exacta) → chain (cadena ordenada)
## → from_bone+depth (desde un hueso hacia abajo) → todos si nada se especifica.


func _resolve_capture_bones(args: Dictionary, skeleton: Node) -> Array:
	var names: Array = []
	if args.has("bones"):
		var raw: Variant = args.get("bones", [])
		if raw is Array:
			for b in raw:
				names.append(str(b))
	if names.is_empty() and args.has("chain"):
		var raw_chain: Variant = args.get("chain", [])
		if raw_chain is Array:
			for b in raw_chain:
				names.append(str(b))
	if names.is_empty() and args.has("from_bone"):
		var start_name: String = str(args.get("from_bone", ""))
		var depth: int = int(args.get("depth", -1))
		names = _bone_chain_from(skeleton, start_name, depth)
	if names.is_empty():
		# Todos los huesos en orden jerárquico (padre→hijo).
		if skeleton is Skeleton2D:
			var sk2 := skeleton as Skeleton2D
			for i in sk2.get_bone_count():
				names.append(str(sk2.get_bone(i).name))
		else:
			var sk3 := skeleton as Skeleton3D
			for i in sk3.get_bone_count():
				names.append(sk3.get_bone_name(i))
	return names


## Cadena de huesos desde un hueso raíz hacia abajo (BFS, parent→child).


func _bone_chain_from(skeleton: Node, start_name: String, depth: int) -> Array:
	var all_bones: Array = []
	var children_of := {}
	var root_bone_idx := -1
	if skeleton is Skeleton3D:
		var skel := skeleton as Skeleton3D
		for i in skel.get_bone_count():
			var n := skel.get_bone_name(i)
			all_bones.append(n)
			var parent := skel.get_bone_parent(i)
			if parent >= 0:
				children_of[skel.get_bone_name(parent)] = (children_of.get(skel.get_bone_name(parent), []) as Array) + [n]
			if n == start_name:
				root_bone_idx = i
		if root_bone_idx < 0:
			return []
	elif skeleton is Skeleton2D:
		var skel := skeleton as Skeleton2D
		for i in skel.get_bone_count():
			var b := skel.get_bone(i)
			all_bones.append(str(b.name))
			if b.get_parent() is Bone2D:
				children_of[str(b.get_parent().name)] = (children_of.get(str(b.get_parent().name), []) as Array) + [str(b.name)]
		if not all_bones.has(start_name):
			return []

	var result: Array = [start_name]
	var frontier: Array = [start_name]
	var visited := {start_name: true}
	var level := 0
	while not frontier.is_empty() and (depth < 0 or level < depth):
		var next: Array = []
		for f in frontier:
			var kids: Array = children_of.get(f, [])
			for k in kids:
				if not visited.has(k):
					visited[k] = true
					result.append(k)
					next.append(k)
		frontier = next
		level += 1
	return result


## Inserta (o reusa) un track de pose de hueso en la animación.
## 3D: track TYPE_VALUE con path "Skeleton:bones/<idx>/pose" y valor Transform3D.
## 2D: track TYPE_VALUE con path "Bone2D:rotation" o "Bone2D:position".


func _ensure_bone_track(anim: Animation, skeleton: Node, bone_name: String, dim: String) -> int:
	var track_idx := -1
	if skeleton is Skeleton3D:
		var skel := skeleton as Skeleton3D
		var idx: int = skel.find_bone(bone_name)
		if idx < 0:
			return -1
		var path := str(skeleton.get_path()) + ":bones/" + str(idx) + "/pose"
		for i in anim.get_track_count():
			if str(anim.track_get_path(i)) == path:
				return i
		track_idx = anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(track_idx, path)
	elif skeleton is Skeleton2D:
		var skel := skeleton as Skeleton2D
		var bone: Bone2D = null
		for i in skel.get_bone_count():
			if skel.get_bone(i).name == bone_name:
				bone = skel.get_bone(i)
				break
		if bone == null:
			return -1
		var prop: String = "rotation" if dim == "2d_rotation" else "position"
		var path := str(bone.get_path()) + ":" + prop
		for i in anim.get_track_count():
			if str(anim.track_get_path(i)) == path:
				return i
		track_idx = anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(track_idx, path)
	return track_idx


## P1: snapshot de la pose actual del esqueleto como keyframes en un tiempo dado.
## Captura "en cadena" soportada: bones|chain|from_bone+depth.


func handle_capture_pose(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var resolved := _player_or_error(root, args)
	if not resolved.ok:
		return resolved
	var player: AnimationPlayer = resolved.player
	var skeleton := _resolve_node(root, args.get("skeleton_path", ""))
	if skeleton == null:
		return {"ok": false, "error": "skeleton_not_found"}
	var anim_name: String = str(args.get("anim_name", ""))
	if anim_name == "":
		return {"ok": false, "error": "anim_name required"}
	if not player.has_animation(anim_name):
		return {"ok": false, "error": "animation_not_found: " + anim_name}
	var anim: Animation = player.get_animation(anim_name)
	var time: float = float(args.get("time", 0.0))
	var dim: String = str(args.get("dim", "3d"))
	if skeleton is Skeleton2D:
		dim = "2d"

	var bone_names: Array = _resolve_capture_bones(args, skeleton)
	if bone_names.is_empty():
		return {"ok": false, "error": "no_bones_resolved"}
	var keys_inserted := 0
	var captured_coords: Array = []

	for bone_name in bone_names:
		if skeleton is Skeleton3D:
			var skel := skeleton as Skeleton3D
			var idx: int = skel.find_bone(str(bone_name))
			if idx < 0:
				continue
			var track_idx := _ensure_bone_track(anim, skeleton, str(bone_name), "3d")
			if track_idx < 0:
				continue
			var pose: Transform3D = skel.get_bone_pose(idx)
			anim.track_insert_key(track_idx, time, pose, 1.0)
			keys_inserted += 1
			# Coords proactivas: delta de la pose capturada vs rest, en grados.
			var global_pose: Transform3D = skel.get_bone_global_pose(idx)
			var rest_pose: Transform3D = skel.get_bone_rest(idx)
			captured_coords.append({
				"name": bone_name,
				"global": HerenCoordsScript.serialize_value(global_pose.origin, true),
				"delta_vs_rest": {
					"rotation_deg": HerenCoordsScript.rotation_delta_deg(rest_pose, global_pose),
					"origin_delta": HerenCoordsScript.origin_delta(rest_pose, global_pose),
				},
			})
		if skeleton is Skeleton2D:
			var skel := skeleton as Skeleton2D
			var bone: Bone2D = null
			for i in skel.get_bone_count():
				if skel.get_bone(i).name == bone_name:
					bone = skel.get_bone(i)
					break
			if bone == null:
				continue
			# Captura rotación y posición del Bone2D.
			var rot_track := _ensure_bone_track(anim, skeleton, str(bone_name), "2d_rotation")
			if rot_track >= 0:
				anim.track_insert_key(rot_track, time, bone.rotation, 1.0)
				keys_inserted += 1
			var pos_track := _ensure_bone_track(anim, skeleton, str(bone_name), "2d_position")
			if pos_track >= 0:
				anim.track_insert_key(pos_track, time, bone.position, 1.0)
				keys_inserted += 1
			captured_coords.append({
				"name": bone_name,
				"global": HerenCoordsScript.serialize_value(bone.global_position, true),
				"delta_vs_rest": {
					"rotation_deg": HerenCoordsScript.rotation_delta_deg(bone.rest, bone.transform),
					"origin_delta": HerenCoordsScript.origin_delta(bone.rest, bone.transform),
				},
			})

	return {
		"ok": true,
		"anim_name": anim_name,
		"time": time,
		"bones_captured": bone_names.size(),
		"keys_inserted": keys_inserted,
		"bones": bone_names,
		"coords": captured_coords,
	}


## Amplía add_track para soportar track_type="bone" (resuelve path por nombre).


func handle_skeleton_ik(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	# P-B6 (2026-09-03): dispatch según dimension o tipo real del nodo.
	# "2d" → Skeleton2D (FABRIK); "3d" → Skeleton3D (SkeletonIK3D).
	# Default: detectar por tipo del nodo resuelto.
	var dimension: String = str(args.get("dimension", ""))
	var skeleton_path: String = str(args.get("skeleton_path", ""))
	var node: Node = _resolve_node(root, skeleton_path)
	if node == null:
		return {"ok": false, "error": "skeleton_not_found: " + skeleton_path}
	var is_2d: bool = dimension == "2d" or (dimension == "" and node is Skeleton2D)
	if is_2d:
		return _ik_2d(root, node as Skeleton2D, args)
	if not (node is Skeleton3D):
		return {"ok": false, "error": "not_skeleton3d: " + skeleton_path}
	var skeleton := node as Skeleton3D

	var ik_name: String = str(args.get("ik_name", "SkeletonIK3D"))
	var ik := SkeletonIK3D.new()
	ik.name = ik_name
	ik.skeleton = skeleton.get_path()
	ik.root_bone = str(args.get("root_bone", ""))
	ik.tip_bone = str(args.get("tip_bone", ""))
	ik.interpolation = float(args.get("interpolation", 1.0))
	ik.max_iterations = int(args.get("max_iterations", 10))
	ik.override_tip_basis = bool(args.get("override_tip_basis", false))
	ik.influence = float(args.get("influence", 1.0))
	ik.min_distance = float(args.get("min_distance", 0.001))
	ik.use_magnet = bool(args.get("use_magnet", false))
	if args.has("magnet"):
		var magnet_dict: Dictionary = _args_dict(args, "magnet")
		ik.magnet = Vector3(float(magnet_dict.get("x", 0)), float(magnet_dict.get("y", 0)), float(magnet_dict.get("z", 0)))

	var target_path: String = str(args.get("target_path", ""))
	if target_path != "":
		var target := _resolve_node(root, target_path)
		if target != null:
			ik.target_node = target.get_path()
	# target_position alternativo (sin nodo target, usa posición absoluta).
	elif args.has("target_position"):
		var tp: Dictionary = _args_dict(args, "target_position")
		var target := Node3D.new()
		target.name = ik_name + "_Target"
		target.position = Vector3(float(tp.get("x", 0)), float(tp.get("y", 0)), float(tp.get("z", 0)))
		skeleton.add_child(target)
		target.owner = root
		ik.target_node = target.get_path()

	skeleton.add_child(ik)
	ik.owner = root

	if bool(args.get("start", true)):
		ik.start()

	return {
		"ok": true,
		"ik_name": ik_name,
		"skeleton_path": _node_path_relative(skeleton, root),
		"root_bone": ik.root_bone,
		"tip_bone": ik.tip_bone,
		"influence": ik.influence,
		"running": ik.running,
	}


## P-B6: IK 2D vía FABRIK — no hay BoneAttachment2D, se usa la cadena
## declarada en args (chain: ["Arm", "Forearm", "Hand"]) y un target.
func _ik_2d(root: Node, skel: Skeleton2D, args: Dictionary) -> Dictionary:
	if skel == null:
		return {"ok": false, "error": "skeleton2d_not_found"}
	var ik_name: String = str(args.get("ik_name", "IK2D"))
	var chain: Array = args.get("chain", [])
	if chain.is_empty():
		return {"ok": false, "error": "chain required (lista de nombres de hueso en orden)"}
	# El FABRIK real está en skeleton_fabrik — aquí solo creamos el marker
	# del target (BoneAttachment2D no existe en Godot 4).
	var target := Node2D.new()
	target.name = ik_name + "_Target"
	if args.has("target_position"):
		var tp: Dictionary = _args_dict(args, "target_position")
		target.position = Vector2(float(tp.get("x", 0.0)), float(tp.get("y", 0.0)))
	elif args.has("target_path"):
		var t := _resolve_node(root, str(args.get("target_path", "")))
		if t != null:
			target.position = (t as Node2D).global_position
	skel.add_child(target)
	target.owner = root
	return {
		"ok": true,
		"ik_name": ik_name,
		"dimension": "2d",
		"chain": chain,
		"tip_target": target.name,
		"note": "usar skeleton_fabrik para resolver la cadena hacia el target",
	}


## P1: FABRIK 2D procedural — resuelve una cadena de Bone2D hacia un objetivo.
## Útil para animación procedural (brazos/piernas siguiendo un punto).


func handle_skeleton_fabrik(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var skeleton := _resolve_node(root, args.get("skeleton_path", "")) as Skeleton2D
	if skeleton == null:
		return {"ok": false, "error": "skeleton2d_not_found"}

	var target_pos := Vector2(float(args.get("target_x", 0)), float(args.get("target_y", 0)))
	var chain_names: Array = args.get("chain", [])
	if chain_names.is_empty():
		return {"ok": false, "error": "chain required (lista de nombres de hueso en orden)"}
	var max_iterations: int = int(args.get("max_iterations", 10))
	var tolerance: float = float(args.get("tolerance", 1.0))
	var weights: Dictionary = _args_dict(args, "weights")

	# Colectar huesos de la cadena.
	var bones: Array[Bone2D] = []
	for name in chain_names:
		var found: Bone2D = null
		for i in skeleton.get_bone_count():
			var b := skeleton.get_bone(i)
			if b.name == name:
				found = b
				break
		if found == null:
			return {"ok": false, "error": "bone_not_found: " + str(name)}
		bones.append(found)
	if bones.size() < 2:
		return {"ok": false, "error": "chain needs at least 2 bones"}

	# Guardar poses originales para restaurar en undo.
	var original_rests := {}
	for b in bones:
		original_rests[b.get_instance_id()] = b.transform

	# Posiciones globales de los pivotes (FABRIK clásico).
	var pts: Array[Vector2] = []
	for b in bones:
		pts.append(b.global_position)
	pts.append(target_pos)

	var converged := false
	for _it in max_iterations:
		# Backward (desde el final hacia la raíz).
		pts[pts.size() - 1] = target_pos
		for i in range(pts.size() - 2, -1, -1):
			var seg_len := (pts[i] - pts[i + 1]).length()
			var weight: float = float(weights.get(str(bones[i].name), 1.0))
			pts[i] = pts[i + 1] + (pts[i] - pts[i + 1]).normalized() * seg_len * weight
		# Forward (desde la raíz hacia el final).
		pts[0] = bones[0].global_position
		for i in range(1, pts.size()):
			var seg_len := (pts[i - 1] - pts[i]).length()
			var weight: float = float(weights.get(str(bones[i - 1].name), 1.0))
			pts[i] = pts[i - 1] + (pts[i] - pts[i - 1]).normalized() * seg_len * weight
		if (pts[pts.size() - 1] - target_pos).length() < tolerance:
			converged = true
			break

	# Aplicar: cada hueso apunta al siguiente punto (su rotación local).
	for i in bones.size():
		var b: Bone2D = bones[i]
		var p_cur: Vector2 = pts[i]
		var p_next: Vector2 = pts[i + 1]
		var parent_rot: float = b.get_parent().global_rotation if b.get_parent() is Node2D else 0.0
		var target_angle: float = (p_next - p_cur).angle()
		b.transform = Transform2D(target_angle - parent_rot, b.position)

	return {
		"ok": true,
		"skeleton_path": _node_path_relative(skeleton, root),
		"chain": chain_names,
		"target": {"x": target_pos.x, "y": target_pos.y},
		"iterations": max_iterations,
		"converged": converged,
	}


## P1: preview con imagen — seek + captura del viewport (agente VE el frame).


func handle_blend_pose(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var skeleton := _resolve_node(root, args.get("skeleton_path", ""))
	if skeleton == null:
		return {"ok": false, "error": "skeleton_not_found"}
	var factor: float = clampf(float(args.get("factor", 0.5)), 0.0, 1.0)
	var target_pose: Dictionary = _args_dict(args, "target_pose")
	if target_pose.is_empty():
		return {"ok": false, "error": "target_pose required (map bone_name → transform)"}
	var rest_mode: bool = bool(args.get("rest", true))

	var blended: Array = []
	if skeleton is Skeleton3D:
		var skel := skeleton as Skeleton3D
		for bone_name in target_pose.keys():
			var idx: int = skel.find_bone(str(bone_name))
			if idx < 0:
				continue
			var base: Transform3D = skel.get_bone_rest(idx) if rest_mode else skel.get_bone_pose(idx)
			var target: Variant = HerenCoordsScript.deserialize_value(target_pose[bone_name])
			if target is Transform3D:
				base = base.interpolate_with(target as Transform3D, factor)
				skel.set_bone_pose(idx, base)
				blended.append(str(bone_name))
	elif skeleton is Skeleton2D:
		var skel := skeleton as Skeleton2D
		for bone_name in target_pose.keys():
			var bone: Bone2D = null
			for i in skel.get_bone_count():
				if skel.get_bone(i).name == bone_name:
					bone = skel.get_bone(i)
					break
			if bone == null:
				continue
			var base: Transform2D = bone.rest if rest_mode else bone.transform
			var target: Variant = HerenCoordsScript.deserialize_value(target_pose[bone_name])
			if target is Transform2D:
				base = base.interpolate_with(target as Transform2D, factor)
				bone.transform = base
				blended.append(str(bone_name))

	return {
		"ok": true,
		"skeleton_path": _node_path_relative(skeleton, root),
		"factor": factor,
		"bones_blended": blended.size(),
		"bones": blended,
	}


## P3: retarget básico — copia una animación de un skeleton fuente a otro
## mapeando por NOMBRE de hueso (3D). Reutiliza animaciones entre personajes
## que comparten rig (hips, spine, upper_arm_L...).


func handle_retarget(args: Dictionary) -> Dictionary:
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

	var source := _resolve_node(root, args.get("source_skeleton", "")) as Skeleton3D
	var target := _resolve_node(root, args.get("target_skeleton", "")) as Skeleton3D
	if source == null or target == null:
		return {"ok": false, "error": "source_skeleton and target_skeleton required (Skeleton3D)"}

	var library: String = str(args.get("library", ""))
	var lib := _get_library(player, library)
	if lib == null:
		return {"ok": false, "error": "library_not_found: " + (library if library != "" else "<default>")}
	var new_name: String = str(args.get("new_name", ""))
	if new_name == "":
		new_name = anim_name + "_rt"
	if lib.has_animation(new_name):
		return {"ok": false, "error": "animation_exists: " + new_name}

	var src_anim: Animation = player.get_animation(anim_name)
	var dst_anim := Animation.new()
	dst_anim.length = src_anim.length
	dst_anim.loop_mode = src_anim.loop_mode

	# Mapa nombre de hueso source → índice de hueso target.
	var target_idx_by_name := {}
	for i in target.get_bone_count():
		target_idx_by_name[target.get_bone_name(i)] = i

	var mapped := 0
	for t in src_anim.get_track_count():
		var path_str: String = str(src_anim.track_get_path(t))
		if not path_str.contains(":bones/"):
			continue
		var bone_name: String = path_str.split(":bones/")[1].split("/")[0]
		if not target_idx_by_name.has(bone_name):
			continue
		var t_idx := dst_anim.add_track(Animation.TYPE_VALUE)
		dst_anim.track_set_path(t_idx, str(target.get_path()) + ":bones/" + str(target_idx_by_name[bone_name]) + "/pose")
		for k in src_anim.track_get_key_count(t):
			dst_anim.track_insert_key(t_idx, src_anim.track_get_key_time(t, k),
				src_anim.track_get_key_value(t, k), src_anim.track_get_key_transition(t, k))
		mapped += 1

	lib.add_animation(new_name, dst_anim)
	return {
		"ok": true,
		"anim_name": anim_name,
		"new_name": new_name,
		"tracks_mapped": mapped,
		"source_skeleton": source.name,
		"target_skeleton": target.name,
	}
