extends SceneTree
func _initialize():
	var path := "res://assets/players/coneja_p/coneja_idle.fbx"
	var ps: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var root: Node = ps.instantiate()
	# Ver la jerarquía y transformaciones del Armature root
	print("JERARQUIA del coneja_idle.fbx:")
	print("=========================\n")
	_print_node(root, 0, "")
	quit(0)

func _print_node(node: Node, depth: int, path: String) -> void:
	var indent := "  ".repeat(depth)
	var info := node.name
	if node is Node3D:
		var t := (node as Node3D).transform
		var q := t.basis.get_rotation_quaternion()
		var w_abs := abs(q.w)
		var angle := rad_to_deg(2.0 * acos(min(1.0, w_abs)))
		var xyz_mag := sqrt(q.x*q.x + q.y*q.y + q.z*q.z)
		var flag := "T" if xyz_mag < 0.01 else ("R%.0f°" % angle)
		info += " [T(%.3f,%.3f,%.3f) Q(%.3f,%.3f,%.3f,%.3f) %s]" % [
			t.origin.x, t.origin.y, t.origin.z, q.w, q.x, q.y, q.z, flag]
	elif node is Skeleton3D:
		var skel := node as Skeleton3D
		info += " [Skeleton3D %d bones]" % skel.get_bone_count()
	print("%s%s" % [indent, info])
	for c in node.get_children():
		_print_node(c, depth + 1, path + "/" + str(node.name))