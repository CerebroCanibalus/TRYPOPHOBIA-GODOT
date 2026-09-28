extends SceneTree
## Analiza petrolera.tscn: cuenta instancias de GLTF/mesh repetidas y estima
## el costo actual vs el costo si se reemplaza cada familia por una MultiMesh.
## USO:
##   godot --headless --path . --quit-after 5 --script tools/analizar_petrolera.gd

func _initialize() -> void:
	print("=== ANALISIS DE PETROLERA.TSCN ===\n")
	var path := "res://maps/misiones/petrolera_c1/petrolera.tscn"
	if not ResourceLoader.exists(path):
		print("FAIL: no existe ", path)
		quit(1)
		return
	var ps: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if ps == null:
		print("FAIL: no se pudo cargar")
		quit(1)
		return
	var root: Node = ps.instantiate()
	get_root().add_child(root)
	await create_timer(0.1).timeout

	# Inventario: agrupar por (mesh path, material path)
	# Cada instancia de un GLTF tiene un MeshInstance3D hijo con un Mesh.
	# Agrupamos por "origen GLTF" (se ve en el nombre del padre o en la metadata).
	var instances: Array = []
	_collect_meshes(root, "", instances)
	print("Total MeshInstance3D en escena: %d\n" % instances.size())

	# Agrupar por path del mesh (el recurso compartido es la unica senial real)
	var by_mesh: Dictionary = {}
	var total_tris := 0
	for inst in instances:
		var mi: MeshInstance3D = inst["node"]
		var mesh: Mesh = mi.mesh
		if mesh == null: continue
		var key: String = mesh.resource_path if mesh.resource_path else "<instance %d>" % mi.get_instance_id()
		var tris: int = _triangle_count(mesh)
		total_tris += tris
		if not by_mesh.has(key):
			by_mesh[key] = {"count": 0, "tris_per": tris, "nodes": [], "name": mi.name}
		by_mesh[key]["count"] += 1
		by_mesh[key]["nodes"].append(mi)

	# Ordenar por count descendente (los mas repetidos primero)
	var keys: Array = by_mesh.keys()
	keys.sort_custom(func(a, b): return by_mesh[a]["count"] > by_mesh[b]["count"])

	print("Top 20 meshes mas instanciados:")
	print("%-8s %-10s %-60s" % ["Count", "Tris/c/u", "Mesh path / nombre"])
	print("-".repeat(90))
	for k in keys.slice(0, 20):
		var info: Dictionary = by_mesh[k]
		var savings: int = info["count"] - 1  # -1 porque 1 instancia base se queda
		print("%-8d %-10d %s" % [info["count"], info["tris_per"], k.substr(0, 60)])
		if savings > 0:
			print("  -> convertir a MultiMesh: ahorra %d draw calls (de %d a 1)" % [savings, info["count"]])

	# Buscar instancias que son hijos directos de un nodo "GltfXxx" (las que vienen
	# del import del .gltf). Esas son las candidatas naturales para MultiMesh.
	print("\nInstancias que cuelgan de un nodo 'Gltf*' (candidatas naturales para MultiMesh):")
	var gltf_groups: Dictionary = {}
	for inst in instances:
		var mi: MeshInstance3D = inst["node"]
		var parent: Node = mi.get_parent()
		# Buscar el primer ancestro cuyo nombre empieza con "Gltf"
		var p: Node = parent
		while p != null and not p.name.begins_with("Gltf"):
			p = p.get_parent()
		if p != null:
			var key: String = String(p.name)
			if not gltf_groups.has(key):
				gltf_groups[key] = {"count": 0, "sample": mi, "positions": []}
			gltf_groups[key]["count"] += 1
			gltf_groups[key]["positions"].append(mi.global_position)

	var gkeys: Array = gltf_groups.keys()
	gkeys.sort_custom(func(a, b): return gltf_groups[a]["count"] > gltf_groups[b]["count"])
	for k in gkeys:
		var g: Dictionary = gltf_groups[k]
		if g["count"] >= 3:
			print("  %s: %d instancias" % [k, g["count"]])

	# Total tris renderizados (estimado, contando cada instancia)
	print("\nTotal triangulos renderizados (estimado): %d" % total_tris)
	print("Si se MultiMeshea el top-N mas repetidos, los tris no bajan pero los draw calls si.")
	quit(0)

func _collect_meshes(node: Node, parent_path: String, out: Array) -> void:
	var path: String = parent_path + "/" + String(node.name)
	if node is MeshInstance3D:
		out.append({"node": node, "path": path})
	for c in node.get_children():
		_collect_meshes(c, path, out)

func _triangle_count(mesh: Mesh) -> int:
	if mesh is ArrayMesh:
		var am: ArrayMesh = mesh
		var total: int = 0
		for i in am.get_surface_count():
			var arr: Array = am.surface_get_arrays(i)
			if arr.size() > 0 and arr[Mesh.ARRAY_INDEX] is PackedInt32Array:
				total += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			elif arr.size() > 0 and arr[Mesh.ARRAY_INDEX] is PackedInt32Array:
				total += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		return total
	elif mesh is PrimitiveMesh:
		return 0  # calculo costoso, lo dejamos
	return 0