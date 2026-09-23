extends SceneTree
func _initialize() -> void:
	var path := "res://src/ragdoll_character/scenes/coneja_player.tscn"
	print("Validando ", path, " ...")
	if not ResourceLoader.exists(path):
		print("FAIL: no existe")
		quit(1)
		return
	var ps: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if ps == null:
		print("FAIL: no se pudo cargar como PackedScene")
		quit(1)
		return
	var root: Node = ps.instantiate()
	if root == null:
		print("FAIL: no se pudo instanciar")
		quit(1)
		return
	print("OK: instanciado, nombre raiz=", root.name, " children=", root.get_child_count())
	# Contar PhysicalBone3D
	var physics_bones: Array = []
	for c in root.find_children("*", "PhysicalBone3D", true, false):
		physics_bones.append((c as PhysicalBone3D).bone_name)
	print("PhysicalBone3D encontrados: ", physics_bones.size())
	for n in physics_bones:
		print("  - ", n)
	# Verificar que el rig_config esta cargado
	if root.has_method("get"):
		var rc = root.get("rig_config")
		print("rig_config: ", rc)
	# Verificar que el Animated existe y es instancia del GLB
	var animated := root.get_node_or_null("Animated")
	if animated:
		print("Animated instanciado OK: ", animated.get_child_count(), " hijos")
		var skel := animated.find_child("Skeleton3D", true, false) as Skeleton3D
		if skel:
			print("  Animated Skeleton3D tiene ", skel.get_bone_count(), " huesos")
		else:
			print("  Animated NO tiene Skeleton3D")
	else:
		print("FAIL: no hay nodo Animated")
	# Verificar Camera
	var cam := root.find_child("Camera3D", true, false)
	print("Camera3D: ", cam != null)
	quit(0)