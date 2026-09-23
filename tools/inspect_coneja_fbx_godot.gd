extends SceneTree
func _initialize():
	var path := "res://assets/players/coneja_p/coneja_idle.fbx"
	if not ResourceLoader.exists(path):
		print("ERROR: no existe ", path)
		quit(1)
		return
	var ps: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if ps == null:
		print("ERROR: no se pudo cargar como PackedScene")
		quit(1)
		return
	var root: Node = ps.instantiate()
	var skel: Skeleton3D = root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		print("ERROR: sin Skeleton3D")
		quit(1)
		return
	print("Skeleton3D con ", skel.get_bone_count(), " huesos")
	var target_names := ["espina","espina1","espina2","cuello","cabeza",
		"hombro_L","brazo1_L","brazo2_L","mano_L",
		"hombro_R","brazo1_R","brazo2_R","mano_R",
		"pierna1_L","pierna2_L","rodilla_L","pie_L",
		"pierna1_R","pierna2_R","rodilla_R","pie_R"]
	print("\nPose REST de los huesos del coneja_idle.fbx (lo que ve Godot):\n")
	print("%-12s %-25s %s" % ["Hueso", "Translation (x,y,z)", "Quaternion (w,x,y,z)"])
	print("-".repeat(80))
	for i in skel.get_bone_count():
		var n: String = skel.get_bone_name(i)
		if n in target_names:
			var rest: Transform3D = skel.get_bone_rest(i)
			var q: Quaternion = rest.basis.get_rotation_quaternion()
			# angulo minimo
			var w_abs: float = abs(q.w)
			var angle: float = rad_to_deg(2.0 * acos(min(1.0, w_abs)))
			var xyz_mag: float = sqrt(q.x*q.x + q.y*q.y + q.z*q.z)
			var flag: String = "T-POSE" if xyz_mag < 0.01 else "ROTA %.1f°" % angle
			print("%-12s (%7.3f,%7.3f,%7.3f) (%7.4f,%7.4f,%7.4f,%7.4f) %s" % [
				n, rest.origin.x, rest.origin.y, rest.origin.z,
				q.w, q.x, q.y, q.z, flag])
	quit(0)