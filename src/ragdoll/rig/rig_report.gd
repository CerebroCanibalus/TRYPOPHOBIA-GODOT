extends RefCounted
class_name RigReport
## VALIDA un `RagdollRig` contra el modelo que dice usar, y explica que
## falta. Sirve para: (a) revisar un rig escrito a mano, (b) completar un
## rig con los huesos-puente que le falten, (c) documentar el estado de un
## rig en el informe de la escena.
##
## El error que mas veces ha costado tiempo es el de la CADENA INCOMPLETA
## (un joint que no se crea porque al padre no le falta cuerpo), asi que
## esa comprobacion es la primera y la mas Detailed.

## Errores: ROMPEN el rig (el personaje se rompe de forma visible).
var errors: PackedStringArray = []
## Avisos: el rig funciona pero algo es raro o poco optimo.
var warnings: PackedStringArray = []
## Info: lo que se ha deduced.
var info: PackedStringArray = []
## Huesos-puente que FALTAN para que la cadena este completa.
var missing_bridges: Array[StringName] = []


## Valida el rig contra el modelo. Devuelve true si no hay errores.
static func validate(rig: RagdollRig) -> RigReport:
	var rep := RigReport.new()
	if rig == null:
		rep.errors.append("el rig es null")
		return rep
	if rig.model_path == "" or not ResourceLoader.exists(rig.model_path):
		rep.errors.append("el rig no dice que modelo usa (model_path vacio o inexistente)")
		return rep
	var packed: PackedScene = load(rig.model_path)
	if packed == null:
		rep.errors.append("no se pudo cargar el modelo '%s'" % rig.model_path)
		return rep
	var inst := packed.instantiate()
	var skel := _esqueleto_de(inst, rig)
	if skel == null:
		rep.errors.append("no se encontro el esqueleto en '%s' (ruta dentro del modelo: '%s')" % [
			rig.model_path, rig.skeleton_path_in_model])
		inst.free()
		return rep

	# --- 1) Los huesos declarados existen ------------------------------
	for h in [rig.body_bone_name, rig.head_bone_name, rig.grab_bone_left_name,
			rig.grab_bone_right_name, rig.on_floor_left_bone_name,
			rig.on_floor_right_bone_name]:
		if h == &"":
			continue
		if skel.find_bone(h) < 0:
			rep.errors.append("el modelo no tiene el hueso '%s'" % h)
	for bone in rig.physical_bones:
		if skel.find_bone(bone.bone_name) < 0:
			rep.errors.append("el modelo no tiene el hueso '%s' (de la tabla)" % bone.bone_name)

	# --- 2) LA CADENA (lo importante) -----------------------------------
	var con_cuerpo := {}
	for bone in rig.physical_bones:
		con_cuerpo[bone.bone_name] = true
	for h in con_cuerpo.keys():
		var padre := skel.get_bone_parent(skel.find_bone(h))
		if padre < 0:
			continue
		var pn := StringName(skel.get_bone_name(padre))
		if con_cuerpo.has(pn):
			continue
		# El padre no tiene cuerpo: hay que meter un puente.
		var puente := _primer_puente(skel, skel.find_bone(h), con_cuerpo)
		if puente == &"":
			rep.warnings.append("el hueso '%s' no tiene cuerpo en su padre '%s' y no hay puente" % [h, pn])
		else:
			rep.missing_bridges.append(puente)
			rep.errors.append("CADENA ROTA: '%s' necesita el cuerpo de '%s' (y el de '%s')" % [h, puente, pn])

	# --- 3) Masas y limites --------------------------------------------
	for bone in rig.physical_bones:
		if bone.mass <= 0.0:
			rep.errors.append("el hueso '%s' tiene masa 0 (el PD no lo puede sostener)" % bone.bone_name)
		if bone.swing < 10.0 or bone.twist < 10.0:
			rep.warnings.append("el hueso '%s' tiene limites muy cerrados (%.0f/%.0f): el cono pelea con el PD" % [
				bone.bone_name, bone.swing, bone.twist])
		if bone.joint_type == 5:
			rep.errors.append("el hueso '%s' usa Generic6DOF (tipo 5): Box3D no lo soporta" % bone.bone_name)
		if bone.joint_type == 2 and (bone.swing < 90.0 or bone.twist < 90.0):
			rep.warnings.append("el hueso '%s' limita el cono a %.0f/%.0f: el clip puede no llegar a la pose" % [
				bone.bone_name, bone.swing, bone.twist])

	# --- 4) Grupos ------------------------------------------------------
	for bone in rig.physical_bones:
		if bone.group == "":
			rep.warnings.append("el hueso '%s' no tiene grupo (el PD lo tratara como neutro)" % bone.bone_name)

	rep.info.append("huesos con cuerpo: %d" % rig.physical_bones.size())
	var total := 0.0
	for bone in rig.physical_bones:
		total += bone.mass
	rep.info.append("masa total: %.1f kg" % total)
	inst.free()
	return rep


## Texto del informe, para el log o para un panel del editor.
static func to_text(rep: RigReport) -> String:
	var t := "INFORME DEL RIG\n"
	for e in rep.errors:
		t += "  ERROR  " + e + "\n"
	for w in rep.warnings:
		t += "  aviso  " + w + "\n"
	for i in rep.info:
		t += "  info   " + i + "\n"
	if rep.errors.is_empty() and rep.warnings.is_empty():
		t += "  OK: el rig esta completo\n"
	return t


static func _esqueleto_de(inst: Node, rig: RagdollRig) -> Skeleton3D:
	if rig.skeleton_path_in_model != "":
		# OJO: find_child() busca por NOMBRE, no por ruta. Para una ruta
		# hay que usar get_node_or_null().
		var skel := inst.get_node_or_null(NodePath(rig.skeleton_path_in_model)) as Skeleton3D
		if skel != null:
			return skel
		# Fallback: el ultimo segmento de la ruta.
		var ultimo := rig.skeleton_path_in_model.get_file()
		if ultimo != "":
			for n in inst.find_children("*", "Skeleton3D", true, false):
				if n.name == ultimo:
					return n as Skeleton3D
		return null
	for n in inst.find_children("*", "Skeleton3D", true, false):
		return n as Skeleton3D
	return null


## El primer ancestro del hueso que no tiene cuerpo (el puente que falta).
static func _primer_puente(skel: Skeleton3D, idx: int, con_cuerpo: Dictionary) -> StringName:
	var p := skel.get_bone_parent(idx)
	while p >= 0:
		var n := StringName(skel.get_bone_name(p))
		if con_cuerpo.has(n):
			return n
		p = skel.get_bone_parent(p)
	return &""
