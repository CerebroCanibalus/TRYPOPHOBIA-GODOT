extends SceneTree
## Vuelca las rotaciones REST exactas de los huesos del coneja.glb como
## las ve Godot. Esto se usa para inicializar los PhysicalBone3D.

func _initialize() -> void:
	var path := "res://assets/players/coneja_p/coneja.glb"
	var ps: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var root: Node = ps.instantiate()
	var skel: Skeleton3D = root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		print("ERROR: sin Skeleton3D")
		quit(1)
		return

	# Huesos fisicos del ragdoll (10 totales)
	var targets := {
		"espina2": "cuerpo (capsula central)",
		"cabeza": "cabeza (capsula vertical)",
		"brazo1_L": "brazo izquierdo (upper)",
		"brazo2_L": "antebrazo izquierdo (c/ grab area)",
		"mano_L": "mano izquierda (end-effector IK)",
		"brazo1_R": "brazo derecho (upper)",
		"brazo2_R": "antebrazo derecho (c/ grab area)",
		"mano_R": "mano derecha (end-effector IK)",
		"pierna1_L": "muslo izquierdo (capsula vertical)",
		"pierna2_L": "pantorrilla izquierda",
		"pie_L": "pie izquierdo (c/ on_floor_left)",
		"pierna1_R": "muslo derecho",
		"pierna2_R": "pantorrilla derecha",
		"pie_R": "pie derecho (c/ on_floor_right)",
	}

	print("REST transforms de los huesos fisicos del ragdoll:")
	print("(en el espacio del Skeleton3D, que es lo que usa el PhysicalBone3D)\n")
	for bone_name in targets:
		var idx: int = skel.find_bone(bone_name)
		if idx < 0:
			print("  [SKIP] %s no existe en el skeleton" % bone_name)
			continue
		var rest: Transform3D = skel.get_bone_rest(idx)
		var q: Quaternion = rest.basis.get_rotation_quaternion()
		# Formato como aparece en un .tscn de Godot 4
		print("  %s = Transform3D(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)  # %s" % [
			bone_name,
			rest.basis.x.x, rest.basis.x.y, rest.basis.x.z,
			rest.basis.y.x, rest.basis.y.y, rest.basis.y.z,
			rest.basis.z.x, rest.basis.z.y, rest.basis.z.z,
			rest.origin.x, rest.origin.y, rest.origin.z,
			targets[bone_name]
		])

	# También imprimir la jerarquia padre->hijo de los huesos fisicos
	print("\nJerarquia (Physical Bone X va como hijo de Skeleton3D):")
	for bone_name in targets:
		var idx: int = skel.find_bone(bone_name)
		if idx < 0: continue
		var parent_idx: int = skel.get_bone_parent(idx)
		var parent_name: String = skel.get_bone_name(parent_idx) if parent_idx >= 0 else "(root)"
		print("  %s -> padre: %s" % [bone_name, parent_name])

	# Y medir el largo total del brazo para calibrar ik_pole_offset
	print("\nMedidas para IK de brazos (coneja):")
	var l_root: Vector3 = skel.get_bone_global_rest(skel.find_bone("brazo1_L")).origin
	var l_end: Vector3 = skel.get_bone_global_rest(skel.find_bone("mano_L")).origin
	print("  brazo izquierdo hombro->mano: %.3f m" % l_root.distance_to(l_end))
	var r_root: Vector3 = skel.get_bone_global_rest(skel.find_bone("brazo1_R")).origin
	var r_end: Vector3 = skel.get_bone_global_rest(skel.find_bone("mano_R")).origin
	print("  brazo derecho hombro->mano: %.3f m" % r_root.distance_to(r_end))
	# Posicion global de la cabeza (para la camara FP)
	var head_pos: Vector3 = skel.get_bone_global_rest(skel.find_bone("cabeza")).origin
	print("  cabeza global pos: (%.3f, %.3f, %.3f)" % [head_pos.x, head_pos.y, head_pos.z])
	# Piernas: largo total
	var l_pie: Vector3 = skel.get_bone_global_rest(skel.find_bone("pie_L")).origin
	print("  cadera (espina2) global: (%.3f, %.3f, %.3f)" % [skel.get_bone_global_rest(skel.find_bone("espina2")).origin.x, skel.get_bone_global_rest(skel.find_bone("espina2")).origin.y, skel.get_bone_global_rest(skel.find_bone("espina2")).origin.z])
	print("  pie izquierdo global: (%.3f, %.3f, %.3f)" % [l_pie.x, l_pie.y, l_pie.z])
	print("  altura total: %.3f m" % l_pie.y)
	quit(0)