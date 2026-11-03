extends Node
class_name RagdollSkeleton
## Dueño de los CUERPOS FISICOS del ragdoll: el simulador, los
## `PhysicalBone3D` y sus colliders.
##
## Separa esta responsabilidad del personaje (que mueve, agarrar y nada
## mas) para que poner un rig nuevo sea solo cambiar el `RagdollRig`.
##
## TRAMPA (medida): el joint de un `PhysicalBone3D` se crea en `_ready`.
## Si el hueso entra al arbol fuera del esqueleto (o antes que su padre),
## el joint NUNCA se crea y el hueso queda como un cuerpo suelto (medido:
## la cadena de la columna se abria 0,8 m). Por eso los cuerpos se crean
## EN RUNTIME dentro del simulador, en orden de jerarquia (padre antes
## que hijo, por indice de hueso ascendente), y la escena no authora
## huesos fisicos.

## El rig con los datos (nombres, masas, limites, formas).
var rig: RagdollRig
## El esqueleto FISICO (el que lleva los PhysicalBone3D).
var physical_skel: Skeleton3D
## El simulador de huesos fisicos.
var simulator: PhysicalBoneSimulator3D
## Todos los cuerpos, en orden de jerarquia.
var bones: Array[PhysicalBone3D] = []


## Prepara el esqueleto: crea el simulador, reparenta los huesos
## authored y configura cada cuerpo.
func setup(p_rig: RagdollRig, p_skel: Skeleton3D) -> void:
	rig = p_rig
	physical_skel = p_skel
	if physical_skel == null:
		push_error("[RagdollSkeleton] no hay esqueleto fisico")
		return
	simulator = _setup_simulator()
	if simulator != null:
		simulator.physical_bones_start_simulation()
	bones = _find_bones()
	_resolver_colision_mascara()


## El cuerpo del hueso indicado (null si no tiene).
func bone_of(nombre: StringName) -> PhysicalBone3D:
	for b in bones:
		if b.bone_name == nombre:
			return b
	return null


## El cuerpo "cuerpo" (el que recibe la velocidad de caminar).
func body_bone() -> PhysicalBone3D:
	if rig == null:
		return null
	return bone_of(rig.body_bone_name)


## Devuelve el cuerpo cuyo bone_name coincide, buscandolo en el
## esqueleto (util si la tabla no lo declara).
func find_in_skeleton(nombre: StringName) -> PhysicalBone3D:
	if physical_skel == null:
		return null
	for n in physical_skel.find_children("*", "PhysicalBone3D", true, false):
		var pb := n as PhysicalBone3D
		if pb.bone_name == nombre:
			return pb
	return null


# --- Interno ---------------------------------------------------------------

## Godot 4.4+ exige `PhysicalBoneSimulator3D` como PADRE de los
## `PhysicalBone3D`. Los cuerpos NO se authoran en la escena: se crean
## aqui dentro del simulador (ver `_crear_huesos_fisicos`).
func _setup_simulator() -> PhysicalBoneSimulator3D:
	var existing := physical_skel.get_node_or_null("PhysicalBoneSimulator3D") as PhysicalBoneSimulator3D
	if existing:
		_crear_huesos_fisicos(existing)
		return existing
	var sim := PhysicalBoneSimulator3D.new()
	sim.name = "PhysicalBoneSimulator3D"
	physical_skel.add_child(sim)
	_crear_huesos_fisicos(sim)
	print("[RagdollSkeleton] simulador creado")
	return sim


## Crea los cuerpos en orden de JERARQUIA (padres antes que hijos). El
## joint se crea en `_ready` contra el cuerpo del padre: si el padre no
## esta en el arbol todavia, el joint no se crea y el hueso queda suelto.
## El indice del hueso en el esqueleto es siempre ascendente en la cadena
## (spine=0 < .001 < .002 ... thigh=57 < shin=58 < foot=59), asi que
## ordenar por indice garantiza padres antes que hijos.
func _ordenar_por_jerarquia() -> Array[RagdollBone]:
	var out: Array[RagdollBone] = rig.physical_bones.duplicate()
	out.sort_custom(func(a: RagdollBone, b: RagdollBone) -> bool:
		return physical_skel.find_bone(a.bone_name) < physical_skel.find_bone(b.bone_name))
	return out


## Crea los cuerpos que el rig declara y que no estan authored.
func _crear_huesos_fisicos(sim: PhysicalBoneSimulator3D) -> void:
	if rig == null or physical_skel == null:
		return
	var creados := 0
	var usados := 0
	for bone in _ordenar_por_jerarquia():
		if bone == null or bone.bone_name == &"":
			continue
		var idx := physical_skel.find_bone(bone.bone_name)
		if idx < 0:
			push_warning("[RagdollSkeleton] el rig no tiene el hueso '%s'" % bone.bone_name)
			continue
		# El cuerpo nace en el REST del hueso: esa es la pose de bind del
		# skinning (si se pone en la pose, la malla se estira).
		#
		# OJO — `pb.transform` es LOCAL respecto a su padre (el simulador,
		# que cuelga del esqueleto): hay que poner el REST **LOCAL**
		# (`get_bone_rest`), NO el global (el global aplica dos veces la
		# transformacion del esqueleto; el modelo tiene un giro de 180
		# grados, medido).
		#
		# OJO — TODO se configura ANTES de `add_child`: el joint se crea
		# en `_ready`, cuando el nodo entra al arbol. Si entra con
		# `joint_type == NONE` (el default), el joint NUNCA se crea y el
		# hueso queda suelto (medido: la cadena de la columna se abrio
		# 0,55 m entre padre e hijo).
		var rest: Transform3D = physical_skel.get_bone_rest(idx)
		var pb := find_in_skeleton(bone.bone_name)
		if pb == null:
			pb = PhysicalBone3D.new()
			pb.name = "Physical Bone " + String(bone.bone_name)
			pb.bone_name = bone.bone_name
			pb.transform = rest
			_configurar(pb, bone)
			_añadir_extras(pb, bone, idx)
			sim.add_child(pb)
			creados += 1
		else:
			pb.transform = rest
			_configurar(pb, bone)
			_añadir_extras(pb, bone, idx)
			usados += 1
	print("[RagdollSkeleton] huesos fisicos: %d authorados/reusados, %d creados en runtime" % [
		usados, creados])


func _configurar(pb: PhysicalBone3D, bone: RagdollBone) -> void:
	pb.collision_layer = bone.collision_layer
	pb.collision_mask = bone.collision_mask
	pb.mass = bone.mass
	pb.set("joint_type", bone.joint_type)
	pb.set("joint_constraints/swing_span", bone.swing)
	pb.set("joint_constraints/twist_span", bone.twist)
	pb.set("joint_constraints/bias", 0.3)
	pb.set("joint_constraints/softness", 0.8)
	pb.set("joint_constraints/relaxation", 1.0)
	pb.friction = 0.2
	pb.linear_damp_mode = 1
	pb.angular_damp = 1.0
	pb.can_sleep = false


func _añadir_extras(pb: PhysicalBone3D, bone: RagdollBone, idx: int) -> void:
	# --- Collider -------------------------------------------------------
	if pb.find_child("CollisionShape3D", true, false) == null:
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var shape := bone.make_shape()
		if shape != null:
			cs.shape = shape
			# El collider va sobre el eje +Y del hueso (la longitud del hueso).
			cs.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, bone.offset, 0.0))
		pb.add_child(cs)
	# --- Zona de agarre (en el antebrazo) ------------------------------
	if rig == null:
		return
	if bone.bone_name == rig.grab_bone_left_name or bone.bone_name == rig.grab_bone_right_name:
		if pb.find_child("LGrabArea", true, false) == null and pb.find_child("RGrabArea", true, false) == null:
			var lado := "L" if String(bone.bone_name).ends_with(".L") else "R"
			var area := Area3D.new()
			area.name = lado + "GrabArea"
			area.collision_layer = 0
			area.collision_mask = 4
			area.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, _longitud_hueso(bone.bone_name), 0.0))
			pb.add_child(area)
			var acs := CollisionShape3D.new()
			acs.name = "CollisionShape3D"
			var sph := SphereShape3D.new()
			sph.radius = float(rig.grab_sphere.get("radius", 0.15))
			acs.shape = sph
			area.add_child(acs)
	# --- Rayo de suelo (en el pie) --------------------------------------
	if bone.bone_name == rig.on_floor_left_bone_name or bone.bone_name == rig.on_floor_right_bone_name:
		if pb.find_child("OnFloorL", true, false) == null and pb.find_child("OnFloorR", true, false) == null:
			var lado2 := "L" if String(bone.bone_name).ends_with(".L") else "R"
			var cast := ShapeCast3D.new()
			cast.name = "OnFloor" + lado2
			var fs := SphereShape3D.new()
			fs.radius = 0.14
			cast.shape = fs
			cast.max_results = 10
			var local_down := physical_skel.get_bone_global_rest(idx).basis.inverse() * Vector3.DOWN
			cast.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 0.0))
			cast.target_position = local_down.normalized() * 0.45
			pb.add_child(cast)


func _longitud_hueso(bone_name: StringName) -> float:
	if physical_skel == null:
		return 0.0
	var idx := physical_skel.find_bone(bone_name)
	if idx < 0:
		return 0.0
	var padre := physical_skel.get_bone_parent(idx)
	if padre < 0:
		return 0.0
	return physical_skel.get_bone_global_rest(idx).origin.distance_to(
		physical_skel.get_bone_global_rest(padre).origin)


func _find_bones() -> Array[PhysicalBone3D]:
	var out: Array[PhysicalBone3D] = []
	if physical_skel == null:
		return out
	for c in physical_skel.find_children("*", "PhysicalBone3D", true, false):
		out.append(c as PhysicalBone3D)
	return out


## La mascara de colision se normaliza: los huesos NO colisionan entre
## si (capa 2), porque los colliders de huesos vecinos se solapan y se
## empujarian entre si (el ragdoll se desgarra y se hunde).
func _resolver_colision_mascara() -> void:
	for pb in bones:
		if (pb.collision_mask & 2) != 0:
			pb.collision_mask = pb.collision_mask & ~2
