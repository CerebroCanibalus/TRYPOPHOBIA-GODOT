extends SceneTree
func _initialize() -> void:
	var path := "res://maps/misiones/petrolera_c1/petrolera.tscn"
	var ps: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var root: Node = ps.instantiate()
	get_root().add_child(root)
	await create_timer(0.1).timeout

	# Detectar jerarquia real de las repeticiones
	var gltf_groups: Dictionary = {}
	_collect_gltf_groups(root, "", gltf_groups)

	print("Top familias Gltf* (nodos padre del .gltf que tienen muchas MeshInstance):")
	var keys: Array = gltf_groups.keys()
	keys.sort_custom(func(a, b): return gltf_groups[a]["count"] > gltf_groups[b]["count"])
	print("%-50s %-8s %s" % ["Familia", "Count", "Sample transform"])
	print("-".repeat(90))
	for k in keys.slice(0, 15):
		var g: Dictionary = gltf_groups[k]
		var sample_xf: Transform3D = g["samples"][0]
		print("%-50s %-8d pos=(%.2f, %.2f, %.2f)" % [k.substr(0, 50), g["count"], sample_xf.origin.x, sample_xf.origin.y, sample_xf.origin.z])

	# Mostrar tambien el arbol de hijos de un GltfXxx (para ver que cada
	# repeticion es UN NODO con sus propios MeshInstance hijos)
	if keys.size() > 0:
		var biggest_key: String = keys[0]
		print("\nArbol del primer nodo '%s':" % biggest_key)
		var sample_parent: Node = gltf_groups[biggest_key]["nodes"][0].get_parent()
		# Subir hasta el Gltf root
		var p: Node = sample_parent
		while p != null and not String(p.name).begins_with("Gltf"):
			p = p.get_parent()
		if p:
			_print_tree(p, 0, 4)
	quit(0)

func _collect_gltf_groups(node: Node, parent_path: String, groups: Dictionary) -> void:
	if String(node.name).begins_with("Gltf"):
		var key: String = String(node.name)
		if not groups.has(key):
			groups[key] = {"count": 0, "nodes": [], "samples": []}
		groups[key]["count"] += 1
		groups[key]["nodes"].append(node)
		if groups[key]["samples"].size() < 3:
			groups[key]["samples"].append(node.transform)
	for c in node.get_children():
		_collect_gltf_groups(c, parent_path + "/" + String(node.name), groups)

func _print_tree(node: Node, depth: int, max_depth: int) -> void:
	if depth > max_depth: return
	var indent: String = "  ".repeat(depth)
	var info: String = indent + node.name + " [" + node.get_class() + "]"
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh:
			info += " mesh=" + mi.mesh.resource_path.substr(0, 60)
	print(info)
	for c in node.get_children():
		_print_tree(c, depth + 1, max_depth)