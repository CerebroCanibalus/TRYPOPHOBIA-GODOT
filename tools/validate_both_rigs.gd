extends SceneTree
func _initialize() -> void:
	for path in [
		"res://src/ragdoll_character/scenes/ragdoll_character.tscn",
		"res://src/ragdoll_character/scenes/coneja_player.tscn",
	]:
		print("\n=== ", path, " ===")
		if not ResourceLoader.exists(path):
			print("FAIL: no existe"); continue
		var ps: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		if ps == null:
			print("FAIL: no se carga"); continue
		var root: Node = ps.instantiate()
		var rc = root.get("rig_config")
		print("rig_config = ", rc)
		print("PhysicalBone3D count = ", root.find_children("*", "PhysicalBone3D", true, false).size())
		print("Animated Skeleton3D bones = ", (root.find_child("Skeleton3D", true, false) as Skeleton3D).get_bone_count() if root.find_child("Skeleton3D", true, false) else "N/A")
	quit(0)