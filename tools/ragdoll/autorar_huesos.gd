extends SceneTree
## Autorado de los `PhysicalBone3D` DENTRO de la escena (texto .tscn), con el
## mismo formato que `src/ragdoll/scenes/ragdoll_character.tscn`.
##
## No usa `PackedScene.pack()` (exigiria meter el nodo en el arbol y
## dispararia `_ready`): escribe los bloques `[node ...]` y `[sub_resource ...]`
## directamente, y marca el `Physical` como editable.

const ESCENA := "res://src/player/shiba_player.tscn"
const SKEL_PATH := "Physical/metarig/Skeleton3D"
## Ids de los nodos de la instancia (Physical y metarig) en esta
## escena: los usa el parent_id_path de los huesos.
const PHYS_ID := 496104838
const METARIG_ID := 6778697


func _initialize() -> void:
	var esc: PackedScene = load(ESCENA)
	var root: Node = esc.instantiate()
	var rig: RagdollRig = root.get("rig_config")
	var skel: Skeleton3D = root.get_node_or_null(SKEL_PATH) as Skeleton3D
	if rig == null or skel == null:
		print("ERROR: rig=%s skel=%s" % [str(rig), str(skel)])
		quit(1)
		return
	print("rig: %d huesos | esqueleto: %d" % [rig.physical_bones.size(), skel.get_bone_count()])
	_informe_geometria(skel, rig)

	# El archivo se lee ANTES: de el salen las CABECERAS originales de los
	# nodos (con parent_id_path e index). Sin ellas el editor no sabe
	# que el hueso es hijo de un esqueleto DENTRO de una instancia.
	var ff := FileAccess.open(ESCENA, FileAccess.READ)
	var texto := ""
	if ff != null:
		texto = ff.get_as_text()
		ff.close()
	var cabeceras := {}
	for l in texto.split("\n"):
		if l.begins_with("[node name=\"Physical Bone "):
			var ini := l.find("\"", 15)
			cabeceras[l.substr(12, ini - 12)] = l + "\n"

	var nodos := ""
	var subrec := ""
	var cuerpos := {}
	var n := 0
	# El indice del nodo entre los hijos del esqueleto: los huesos fisicos
	# van DESPUES de las mallas del modelo.
	var offset_indice := _offset_del_indice(rig)
	print("los huesos fisicos empiezan en el indice ", offset_indice)
	for bone in rig.physical_bones:
		var bi := skel.find_bone(bone.bone_name)
		if bi < 0:
			print("  AVISO: '%s' no esta en el esqueleto" % bone.bone_name)
			continue
		var rest := skel.get_bone_global_rest(bi)
		var pid := skel.get_bone_parent(bi)
		# El CUERPO va en el ORIGEN del hueso y el COLLIDER donde dice el RIG.

		# CONVENCION DE GODOT (la del EDITOR, medida en el codigo de
		# Godot 4.7 `PhysicalBone3D::update_offset`):
		#
		#   body_offset = (esqueleto * pose_del_hueso)^-1 * transform_del_nodo
		#
		# Si el nodo esta en la pose del hueso (que es donde lo pone el
		# editor), `body_offset` es la IDENTIDAD: el CUERPO va en el ORIGEN
		# del hueso. Y la FORMA (la `CollisionShape3D` hija) es lo que se
		# desplaza: su `transform` va en el marco del nodo (= del hueso).
		#
		# El joint: Godot calcula `joint_offset.origin = body_offset^-1.origin`
		# (= 0 con body_offset identidad) y ancla el joint en el ORIGEN del
		# hueso hijo, tanto en el padre como en el hijo: el hijo pivota
		# sobre su propia "cabeza", que es el final del padre. Correcto.
		#
		# MEDIDO (2026-11-04): con el collider desplazado `+largo/2` (que
		# es lo que hacia esta herramienta antes) TODOS los colliders iban
		# medio hueso de mas: el pie se enganchaba con su propia espinilla,
		# el muslo no llegaba a la cadera y el apoyo lo hacia la rodilla.
		# El desplazamiento del collider es el del RIG (`offset`), no otro.
		#
		# EL SIGNO: en ESTE modelo (FBX/Blender) el eje +Y del hueso apunta
		# hacia el HIJO, no hacia el padre (medido: el eje Y del hueso
		# "shin" es (0,086,-0,983,-0,164), o sea, hacia abajo). Asi que el
		# collider va en +Y local: el del hueso N cubre el TRAMO N -> hijo.
		#
		# Con el signo BUENO la pierna sale bien: el collider del "thigh"
		# es el MUSLO (thigh -> shin), el del "shin" es la ESPINILLA
		# (shin -> foot) y el del "foot" es el pie (foot -> toe). El
		# apoyo lo hace la punta del pie, como en la referencia.
		var cuerpo := rest
		var forma_xf := Transform3D(Basis.IDENTITY, Vector3(0.0, bone.offset, 0.0))
		if bone.orientacion_modelo:
			# La forma va en el punto que dice el RIG, en los Ejes del
			# MODELO (para el PIE: una esfera en el tobillo).
			forma_xf = Transform3D(rest.basis.inverse(),
				rest.basis.inverse() * bone.offset_modelo)
		var boff := Transform3D.IDENTITY
		var joff := Transform3D.IDENTITY

		var sid := "Shape_%d" % n
		var shape := bone.make_shape()
		var bloque := ""
		if shape is BoxShape3D:
			var bx := shape as BoxShape3D
			bloque = "[sub_resource type=\"BoxShape3D\" id=\"%s\"]\nsize = Vector3(%s, %s, %s)\n\n" % [
				sid, _n(bx.size.x), _n(bx.size.y), _n(bx.size.z)]
		elif shape is CapsuleShape3D:
			var cp := shape as CapsuleShape3D
			bloque = "[sub_resource type=\"CapsuleShape3D\" id=\"%s\"]\nradius = %s\nheight = %s\n\n" % [
				sid, _n(cp.radius), _n(cp.height)]
		elif shape is SphereShape3D:
			var sp := shape as SphereShape3D
			bloque = "[sub_resource type=\"SphereShape3D\" id=\"%s\"]\nradius = %s\n\n" % [sid, _n(sp.radius)]
		if bloque == "":
			continue
		subrec += bloque

		var nombre := "Physical Bone " + String(bone.bone_name).replace(".", "_")
		# El indice del nodo entre los hijos del esqueleto: los huesos
		# fisicos van DESPUES de las mallas del modelo. Se cuenta aqui
		# (antes de cualquier `continue`) para que el indice no se
		# desplace si un hueso se salta.
		n += 1
		# Se conserva la CABECERA original del nodo (con parent_id_path e
		# index): sin ellos el editor no sabe que el hueso es hijo de
		# un esqueleto DENTRO de una instancia y no lo deja editar.
		# parent_id_path e index son los que hacen que el editor sepa
		# que el hueso es hijo de un esqueleto DENTRO de una instancia
		# (y lo deje editar). Los ids los pone el editor al guardar; si
		# cambian, el editor los vuelve a poner.
		#
		# EL INDEX: es la posicion del nodo entre los hijos del esqueleto.
		# Los huesos fisicos van DESPUES de las mallas del modelo, asi que
		# el indice es `hijos_del_esqueleto + posicion_en_la_lista`.
		#
		# MEDIDO (2026-11-04): con un indice inventado (un contador) los
		# `PhysicalBone3D` acababan en un orden que NO era el del esqueleto
		# y al guardar el editor los reordenaba: los joints se
		# emparejaban con el hueso equivocado ("todo esta mal hecho").
		var uid := ""
		if cabeceras.has(nombre):
			var orig: String = cabeceras[nombre]
			var iu := orig.find("unique_id=")
			if iu >= 0:
				var fin := orig.find(" ", iu)
				uid = " " + orig.substr(iu, (fin if fin > 0 else orig.length()) - iu)
		var cabecera := "[node name=\"%s\" type=\"PhysicalBone3D\" parent=\"%s\" parent_id_path=PackedInt32Array(%d, %d) index=\"%d\"%s]\n" % [nombre, SKEL_PATH, PHYS_ID, METARIG_ID, offset_indice + n, uid]
		nodos += cabecera
		nodos += "transform = %s\n" % _t3(cuerpo)
		if bone.sin_collider:
			nodos += "collision_layer = 0\ncollision_mask = 0\n"
		else:
			nodos += "collision_layer = %d\ncollision_mask = %d\n" % [bone.collision_layer, bone.collision_mask]
		# La RAIZ del rig (el hueso sin padre en el esqueleto) NO tiene
		# articulacion: no hay de quien colgarse. Con un cono puesto, Godot
		# busca un padre que no existe y lo deja sin joint (medido: el
		# nodo sale con `joint_type = 2` y es ruido).
		var es_raiz := skel.get_bone_parent(bi) < 0
		if es_raiz:
			nodos += "joint_type = 0\n"
		else:
			nodos += "joint_type = %d\n" % bone.joint_type
		nodos += "joint_offset = %s\nbody_offset = %s\n" % [_t3(joff), _t3(boff)]
		nodos += "mass = %s\nfriction = %s\nlinear_damp_mode = 1\nangular_damp = 1.0\ncan_sleep = false\n" % [_n(bone.mass), _n(bone.friction)]
		nodos += "bone_name = &\"%s\"\n" % String(bone.bone_name)
		if bone.joint_type == 2 and not es_raiz:
			nodos += "joint_constraints/swing_span = %s\n" % _n(bone.swing)
			nodos += "joint_constraints/twist_span = %s\n" % _n(bone.twist)
			nodos += "joint_constraints/bias = 0.0\njoint_constraints/softness = 6.0\njoint_constraints/relaxation = 1.0\n"
		nodos += "\n[node name=\"CollisionShape3D\" type=\"CollisionShape3D\" parent=\"%s/%s\"]\n" % [SKEL_PATH, nombre]
		nodos += "transform = %s\n" % _t3(forma_xf)
		nodos += "shape = SubResource(\"%s\")\n\n" % sid
		cuerpos[bone.bone_name] = cuerpo
	# --- LAS PIEZAS QUE FALTABAN: area de agarre y cast de suelo ------
	#
	# Son HIJOS de los huesos fisicos, asi que tambien son DATOS DE
	# ESCENA (regla dura). El script los busca por nombre:
	#   * "LGrabArea"/"RGrabArea" -> Area3D en el antebrazo (el del
	#     ragdoll original: al tocar un cuerpo, el brazo lo agarra con
	#     un PinJoint).
	#   * "OnFloorL"/"OnFloorR" -> ShapeCast3D en el pie (el "raycast del
	#     original"): dice si el personaje esta en el suelo (sin el, el
	#     salto NUNCA funciona y el agua no sabe que hay apoyo).
	var extra := _autorar_agarre_y_suelo(skel, rig, cuerpos)
	nodos += extra[0]
	subrec += extra[1]
	print("huesos a authorar: %d" % n)

	if texto.is_empty():
		print("ERROR: no abre")
		quit(1)
		return
	if texto.contains("Physical Bone "):
		# Re-autorado: los datos del rig (masas, colliders, limites del
		# joint) son de la ESCENA, asi que al cambiarlos hay que
		# reescribir los bloques. Se limpian los anteriores.
		texto = _limpiar_huesos(texto)

	var pos_raiz := texto.find("[node name=\"Shiba\"")
	if pos_raiz < 0:
		print("ERROR: sin nodo raiz")
		quit(1)
		return
	texto = texto.substr(0, pos_raiz) + subrec + texto.substr(pos_raiz)

	var pos_corte := texto.find("[connection")
	if pos_corte < 0:
		pos_corte = texto.find("[editable")
	if pos_corte < 0:
		pos_corte = texto.length()
	texto = texto.substr(0, pos_corte) + nodos + texto.substr(pos_corte)

	if not texto.contains("[editable path=\"Physical\"]"):
		texto += "\n[editable path=\"Physical\"]\n"

	var out := FileAccess.open(ESCENA, FileAccess.WRITE)
	if out == null:
		print("ERROR: no escribe")
		quit(1)
		return
	out.store_string(texto)
	out.close()
	print("=== OK: %d huesos escritos ===" % n)
	quit()


## Cuantos hijos tiene el ESQUELETO en el modelo (las mallas): los
## huesos fisicos van despues de ellos, y su `index` es la posicion entre
## los hijos del esqueleto.
func _offset_del_indice(rig: RagdollRig) -> int:
	var modelo := load(rig.model_path) as PackedScene
	if modelo == null:
		return 1
	var inst := modelo.instantiate()
	var skel := inst.get_node_or_null(rig.skeleton_path_in_model) as Skeleton3D
	if skel == null:
		inst.free()
		return 1
	var n := skel.get_child_count()
	var nombres := PackedStringArray()
	for c in skel.get_children():
		nombres.append(String(c.name))
	print("hijos del esqueleto en el modelo (", n, "): ", ", ".join(nombres))
	inst.free()
	return n


## INFORME de la geometria del esqueleto: de cada hueso con cuerpo, su
## posicion en reposo, la distancia a su padre y a su hijo, y el collider
## que el RIG le asigna.
##
## Es la verificacion del rig: si la longitud del collider no es la del
## tramo que el hueso representa, la anatomia esta mal (y el personaje se
## comporta como un muñeco roto: el pie se engancha con su propia
## espinilla, el muslo no llega a la cadera, el apoyo lo hace la rodilla).
##
## CONVENCION (la del rig y la de la referencia): el collider del hueso N
## cubre el TRAMO N -> hijo. O sea, el collider va hacia el HIJO, que en
## Godot es la direccion -Y del hueso (el eje +Y de un hueso apunta a su
## PADRE).
func _informe_geometria(skel: Skeleton3D, rig: RagdollRig) -> void:
	print("--- GEOMETRIA COMPLETA (todo hueso del esqueleto) ---")
	for i in skel.get_bone_count():
		var nombre := skel.get_bone_name(i)
		var p := skel.get_bone_global_rest(i)
		var pid := skel.get_bone_parent(i)
		var padre := "-" if pid < 0 else skel.get_bone_name(pid)
		var d_padre := -1.0
		if pid >= 0:
			d_padre = p.origin.distance_to(skel.get_bone_global_rest(pid).origin)
		print("  %-16s padre=%-16s (%6.3f,%6.3f,%6.3f) ejeY=(%5.2f,%5.2f,%5.2f) distPadre=%6.3f" % [
			nombre, padre, p.origin.x, p.origin.y, p.origin.z,
			p.basis.y.x, p.basis.y.y, p.basis.y.z, d_padre])
	print("--- COLLIDERS DEL RIG ---")
	for bone in rig.physical_bones:
		var bi := skel.find_bone(bone.bone_name)
		if bi < 0:
			continue
		var p := skel.get_bone_global_rest(bi).origin
		var pid := skel.get_bone_parent(bi)
		var d_padre := -1.0
		if pid >= 0:
			d_padre = p.distance_to(skel.get_bone_global_rest(pid).origin)
		var d_hijo := -1.0
		var hijos := skel.get_bone_children(bi)
		if hijos.size() > 0:
			d_hijo = p.distance_to(skel.get_bone_global_rest(hijos[0]).origin)
		var forma := "-"
		if bone.shape == RagdollBone.Shape.CAPSULE:
			forma = "capsula h=%.3f" % bone.height
		elif bone.shape == RagdollBone.Shape.BOX:
			forma = "caja %.2fx%.2fx%.2f" % [bone.size.x, bone.size.y, bone.size.z]
		else:
			forma = "esfera r=%.3f" % bone.radius
		print("  %-14s (%6.3f,%6.3f,%6.3f) | padre %6.3f | hijo %6.3f | %s off=%.3f" % [
			bone.bone_name, p.x, p.y, p.z, d_padre, d_hijo, forma, bone.offset])


## Authora las `Area3D` de agarre y los `ShapeCast3D` de suelo, que son
## HIJOS de los huesos fisicos (y por tanto datos de ESCENA, regla dura).
##
## Devuelve [nodos, sub_recursos].
func _autorar_agarre_y_suelo(skel: Skeleton3D, rig: RagdollRig,
		cuerpos: Dictionary) -> Array:
	var nodos := ""
	var subrec := ""
	var tareas := [
		{"hueso": rig.grab_bone_left_name, "nombre": "LGrabArea",
			"tipo": "agarre", "mano": StringName(str(rig.ik_arm_left.get("end", &"")))},
		{"hueso": rig.grab_bone_right_name, "nombre": "RGrabArea",
			"tipo": "agarre", "mano": StringName(str(rig.ik_arm_right.get("end", &"")))},
		{"hueso": rig.on_floor_left_bone_name, "nombre": "OnFloorL",
			"tipo": "suelo", "mano": &""},
		{"hueso": rig.on_floor_right_bone_name, "nombre": "OnFloorR",
			"tipo": "suelo", "mano": &""},
	]
	var i := 0
	for t in tareas:
		var bone_name: StringName = t["hueso"]
		if bone_name == &"" or not cuerpos.has(bone_name):
			continue
		var cuerpo: Transform3D = cuerpos[bone_name]
		var parent := "%s/Physical Bone %s" % [SKEL_PATH, String(bone_name).replace(".", "_")]
		if String(t["tipo"]) == "agarre":
			# El area va en la MANO (el extremo del antebrazo).
			var bi := skel.find_bone(t["mano"])
			if bi < 0:
				continue
			var xf := cuerpo.affine_inverse() * skel.get_bone_global_rest(bi)
			var sid := "GrabShape_%d" % i
			subrec += "[sub_resource type=\"SphereShape3D\" id=\"%s\"]\nradius = 0.11\n\n" % sid
			nodos += "[node name=\"%s\" type=\"Area3D\" parent=\"%s\"]\n" % [t["nombre"], parent]
			nodos += "transform = %s\n" % _t3(xf)
			nodos += "collision_layer = 0\ncollision_mask = 5\nmonitoring = true\n\n"
			nodos += "[node name=\"CollisionShape3D\" type=\"CollisionShape3D\" parent=\"%s/%s\"]\n" % [
				parent, t["nombre"]]
			nodos += "shape = SubResource(\"%s\")\n\n" % sid
		else:
			# El cast va en el origen del pie y barre ABAJO (el "raycast
			# del original"): sirve para saber si hay suelo (el salto) y
			# para el apoyo.
			var sid := "FloorShape_%d" % i
			subrec += "[sub_resource type=\"SphereShape3D\" id=\"%s\"]\nradius = 0.07\n\n" % sid
			nodos += "[node name=\"%s\" type=\"ShapeCast3D\" parent=\"%s\"]\n" % [t["nombre"], parent]
			nodos += "transform = %s\n" % _t3(Transform3D(Basis.IDENTITY,
				_planta_del_pie(skel, cuerpo, bone_name)))
			nodos += "shape = SubResource(\"%s\")\n" % sid
			nodos += "target_position = %s\n" % _v3(_abajo_en_el_marco(skel, cuerpo) * 0.25)
			nodos += "collision_mask = 1\nenabled = true\n\n"
		i += 1
	return [nodos, subrec]


## Quita los bloques de los `PhysicalBone3D` y sus `CollisionShape3D`
## (y las sub-recursos de forma) para poder re-autorarlos.
func _limpiar_huesos(texto: String) -> String:
	var lineas := texto.split("\n")
	var salida := PackedStringArray()
	var saltando := false
	for l in lineas:
		var es_bloque := l.begins_with("[node name=\"Physical Bone ") \
			or l.begins_with("[node name=\"CollisionShape3D\" type=\"CollisionShape3D\" parent=\"Physical/metarig/Skeleton3D/Physical Bone ") \
			or l.begins_with("[node name=\"LGrabArea\"") \
			or l.begins_with("[node name=\"RGrabArea\"") \
			or l.begins_with("[node name=\"OnFloorL\"") \
			or l.begins_with("[node name=\"OnFloorR\"") \
			or (l.begins_with("[node name=\"CollisionShape3D\" type=\"CollisionShape3D\" parent=\"Physical/metarig/Skeleton3D/Physical Bone ") \
				and l.contains("LGrabArea")) \
			or (l.begins_with("[sub_resource type=") and (l.contains("id=\"Shape_") \
				or l.contains("id=\"GrabShape_") or l.contains("id=\"FloorShape_")))
		if es_bloque:
			saltando = true
			continue
		if saltando:
			# El bloque termina en una linea vacia.
			if l.strip_edges() == "":
				saltando = false
			continue
		salida.append(l)
	return "\n".join(salida)


## La PLANTA del pie, en el marco del hueso: es el hijo del hueso (el
## hueso "foot"), que es el que toca el suelo.
##
## OJO: el pie es un hueso SIN cuerpo (como en la referencia) y el cast
## cuelga del hueso que SI lo tiene (la espinilla).
func _planta_del_pie(skel: Skeleton3D, cuerpo: Transform3D, bone_name: StringName) -> Vector3:
	var hijos := skel.get_bone_children(skel.find_bone(bone_name))
	var planta := cuerpo.origin
	if hijos.size() > 0:
		planta = skel.get_bone_global_rest(hijos[0]).origin
	return cuerpo.affine_inverse() * planta


## La direccion "ABAJO" del MUNDO, expresada en el marco del hueso.
##
## OJO: en los huesos de la PIERNA el eje +Y local apunta hacia ABAJO
## (hacia el hijo), asi que "abajo" NO es -Y local. Con el cast en -Y
## local apuntaba hacia ARRIBA y el personaje nunca encontraba el suelo.
func _abajo_en_el_marco(skel: Skeleton3D, cuerpo: Transform3D) -> Vector3:
	var mundo := skel.global_transform.basis * cuerpo.basis
	return mundo.inverse() * Vector3.DOWN


func _n(v: float) -> String:
	return String.num(v, 6)


func _t3(xf: Transform3D) -> String:
	var b := xf.basis
	var o := xf.origin
	return "Transform3D(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)" % [
		_n(b.x.x), _n(b.x.y), _n(b.x.z), _n(b.y.x), _n(b.y.y), _n(b.y.z),
		_n(b.z.x), _n(b.z.y), _n(b.z.z), _n(o.x), _n(o.y), _n(o.z)]


func _v3(v: Vector3) -> String:
	return "Vector3(%s, %s, %s)" % [_n(v.x), _n(v.y), _n(v.z)]
