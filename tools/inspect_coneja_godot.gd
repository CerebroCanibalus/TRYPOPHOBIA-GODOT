extends SceneTree
## Script auxiliar: abre coneja.glb como PackedScene y muestra la jerarquia
## de huesos con sus posiciones GLOBALES y ROTACIONES REALES.
## Uso:
##   godot --headless --script tools/inspect_coneja_godot.gd

func _initialize() -> void:
	print("=== INSPECCION DE coneja.glb (vía PackedScene real de Godot) ===")
	var path := "res://assets/players/coneja_p/coneja.glb"
	if not ResourceLoader.exists(path):
		printerr("No existe: ", path)
		quit(1)
		return
	var ps: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if ps == null:
		printerr("No se pudo cargar como PackedScene")
		quit(1)
		return
	var root: Node = ps.instantiate()
	if root == null:
		printerr("No se pudo instanciar")
		quit(1)
		return
	root.add_to_tree = false  # evitar que se monte al SceneTree
	# Buscar Skeleton3D
	var skel: Skeleton3D = root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		# A veces el nombre es distinto
		skel = root.find_child("*Skeleton3D*", true, false) as Skeleton3D
	if skel == null:
		printerr("No se encontro Skeleton3D")
		quit(1)
		return
	print("Skeleton3D encontrado: ", skel.get_path())
	print("Total bones: ", skel.get_bone_count())
	print("")
	# Dump todos los huesos con sus posiciones globales (REST pose)
	var bones_of_interest := ["espina", "espina1", "espina2", "cuello", "cabeza",
		"hombro_L", "brazo1_L", "brazo2_L", "mano_L",
		"hombro_R", "brazo1_R", "brazo2_R", "mano_R",
		"pierna1_L", "pierna2_L", "rodilla_L", "pie_L",
		"pierna1_R", "pierna2_R", "rodilla_R", "pie_R"]
	print("Huesos relevantes (REST pose = T-pose de export):")
	for i in skel.get_bone_count():
		var name: String = skel.get_bone_name(i)
		if name in bones_of_interest:
			var rest: Transform3D = skel.get_bone_rest(i)
			var global_rest: Transform3D = skel.get_bone_global_rest(i)
			print("  [%2d] %-12s rest.origin=(%.4f, %.4f, %.4f) | global=(%.4f, %.4f, %.4f) rest.basis=(%s)" % [
				i, name,
				rest.origin.x, rest.origin.y, rest.origin.z,
				global_rest.origin.x, global_rest.origin.y, global_rest.origin.z,
				str(rest.basis.get_rotation_quaternion()).substr(0, 60)
			])
	# También: huesos SIN track en animation (los 9 del rig viejo no animaban)
	print("")
	print("PADRE->HIJO de toda la jerarquia:")
	_print_hierarchy(skel, "", 0)
	quit(0)

func _print_hierarchy(node: Node, prefix: String, depth: int) -> void:
	var indent := "  ".repeat(depth)
	print("%s%s [%d]" % [indent, node.name, node.get_child_count()])
	for c in node.get_children():
		_print_hierarchy(c, prefix + "/" + str(node.name), depth + 1)