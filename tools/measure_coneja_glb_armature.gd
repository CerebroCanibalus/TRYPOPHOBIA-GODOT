extends SceneTree
func _initialize() -> void:
	var path := "res://assets/players/coneja_p/coneja.glb"
	var ps: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var root: Node = ps.instantiate()
	print("JERARQUIA + transforms de coneja.glb:")
	_print_node(root, 0)
	quit(0)

func _print_node(node: Node, depth: int) -> void:
	var indent: String = "  ".repeat(depth)
	var info: String = node.name
	if node is Node3D:
		var t: Transform3D = (node as Node3D).transform
		var q: Quaternion = t.basis.get_rotation_quaternion()
		var w_abs: float = abs(q.w)
		var angle: float = rad_to_deg(2.0 * acos(min(1.0, w_abs)))
		var xyz_mag: float = sqrt(q.x*q.x + q.y*q.y + q.z*q.z)
		var flag: String = "T" if xyz_mag < 0.01 else ("R%.2f° eje(%.2f,%.2f,%.2f)" % [angle, q.x/xyz_mag if xyz_mag > 0.01 else 0.0, q.y/xyz_mag if xyz_mag > 0.01 else 0.0, q.z/xyz_mag if xyz_mag > 0.01 else 0.0])
		info += " [T(%.3f,%.3f,%.3f) Q(%.3f,%.3f,%.3f,%.3f) %s]" % [
			t.origin.x, t.origin.y, t.origin.z, q.w, q.x, q.y, q.z, flag]
	elif node is Skeleton3D:
		var skel: Skeleton3D = node as Skeleton3D
		info += " [Skeleton3D %d bones]" % skel.get_bone_count()
	print(indent + info)
	for c in node.get_children():
		_print_node(c, depth + 1)