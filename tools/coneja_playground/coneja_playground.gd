extends SceneTree
## Playground minimo para probar la coneja_player.tscn sin tocar el playground viejo.
## 5 segundos, WASD + space, y vuelca stats al final.

func _initialize() -> void:
	print("[coneja_pg] creando escena...")
	var root: Node = Node3D.new()
	root.name = "Playground"

	# Suelo
	var floor := StaticBody3D.new()
	floor.name = "Floor"
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	cs.shape = shape
	floor.add_child(cs)
	root.add_child(floor)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	(floor_mesh.mesh as BoxMesh).size = Vector3(200, 1, 200)
	floor_mesh.position = Vector3(0, -0.5, 0)
	root.add_child(floor_mesh)

	# Sol
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.5
	root.add_child(sun)

	# Environment
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.4, 0.45, 0.5)
	env_node.environment = env
	root.add_child(env_node)

	# Cargar la coneja_player.tscn
	var ps: PackedScene = ResourceLoader.load("res://src/ragdoll_character/scenes/coneja_player.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if ps == null:
		print("FAIL: no se pudo cargar coneja_player.tscn")
		quit(1)
		return
	var player: Node = ps.instantiate()
	player.position = Vector3(0, 5, 0)  # arrancar arriba para que caiga
	root.add_child(player)

	get_root().add_child(root)

	# Esperar 5 segundos y leer stats
	await create_timer(5.0).timeout

	var body_bone: PhysicalBone3D = player.find_child("Physical Bone espina2", true, false) as PhysicalBone3D
	if body_bone:
		print("[coneja_pg] t=5s pos=(%.2f,%.2f,%.2f) vel=%.2f angvel=%.2f" % [
			body_bone.global_position.x, body_bone.global_position.y, body_bone.global_position.z,
			body_bone.linear_velocity.length(), body_bone.angular_velocity.length()])
	else:
		print("[coneja_pg] no se encontro Physical Bone espina2")

	# Print todo el arbol de huesos fisicos
	print("\n[coneja_pg] jerarquia de PhysicalBone3D en runtime:")
	for b in player.find_children("*", "PhysicalBone3D", true, false):
		print("  ", (b as PhysicalBone3D).bone_name, " global pos=(%.2f,%.2f,%.2f)" % [
			b.global_position.x, b.global_position.y, b.global_position.z])

	quit(0)