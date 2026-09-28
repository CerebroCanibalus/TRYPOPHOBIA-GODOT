extends SceneTree
func _initialize() -> void:
	var path := "res://maps/misiones/petrolera_c1/petrolera.tscn"
	var ps: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var root: Node = ps.instantiate()
	get_root().add_child(root)
	await create_timer(0.1).timeout

	# Buscar todos los nodos, contar por nombre + path completo del mesh
	var by_name_mesh: Dictionary = {}
	_walk(root, "", by_name_mesh)

	print("Top 20 por (nombre de nodo, mesh path):")
	var keys: Array = by_name_mesh.keys()
	keys.sort_custom(func(a, b): return by_name_mesh[a]["count"] > by_name_mesh[b]["count"])
	for k in keys.slice(0, 20):
		var info: Dictionary = by_name_mesh[k]
		print("  %5d x  %s  mesh=%s" % [info["count"], info["name"], info["mesh"].substr(0, 60)])

	# Mostrar nombres unicos de nodos top-level repetidos
	print("\nNombres de nodo padre (1 nivel arriba de MeshInstance) mas repetidos:")
	var by_parent_name: Dictionary = {}
	_walk2(root, by_parent_name)
	var pkeys: Array = by_parent_name.keys()
	pkeys.sort_custom(func(a, b): return by_parent_name[a] > by_parent_name[b])
	for k in pkeys.slice(0, 15):
		print("  %5d x  %s" % [by_parent_name[k], k])
	quit(0)

func _walk(node: Node, parent_path: String, groups: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh and node.mesh.resource_path != "":
		var key: String = "%s::%s" % [node.name, node.mesh.resource_path]
		if not groups.has(key):
			groups[key] = {"count": 0, "name": node.name, "mesh": node.mesh.resource_path}
		groups[key]["count"] += 1
	for c in node.get_children():
		_walk(c, parent_path + "/" + String(node.name), groups)

func _walk2(node: Node, groups: Dictionary) -> void:
	if node is MeshInstance3D:
		var p: Node = node.get_parent()
		if p != null:
			var k: String = String(p.name)
			groups[k] = (groups.get(k, 0) as int) + 1
	for c in node.get_children():
		_walk2(c, groups)