extends Node
class_name RagdollSkeleton
## DUEÑO de los cuerpos fisicos del ragdoll.
##
## REGLA DURA (medida): los `PhysicalBone3D` y sus `CollisionShape3D` son
## DATOS DE ESCENA. Se authoran como hijos del `Skeleton3D`, con su
## `transform`, `body_offset`, `joint_offset`, `mass`, `joint_type` y
## `joint_constraints`, exactamente igual que
## `src/ragdoll/scenes/ragdoll_character.tscn`.
##
## Este nodo NO crea ni un solo hueso ni un solo simulador: crearlos por
## codigo dejo el ragdoll sin datos en la escena (invisible al editor y con
## los offsets calculados a mano). Solo:
##
##   1. recoge los cuerpos que YA estan en la escena,
##   2. arranca la simulacion en el simulador que Godot crea para el
##      esqueleto (`PhysicalBoneSimulator3D`, hijo del `Skeleton3D`),
##   3. normaliza la mascara de colision.
##
## El `transform`/`body_offset`/`joint_offset` los calcula el EDITOR de
## Godot (`PhysicalBone3D::update_offset`): el cuerpo va a MEDIA HUESO y el
## ancla del joint queda en la CABEZA del hueso, que es la anatomia real.

## El rig con los datos (nombres, grupos, clips).
var rig: RagdollRig
## El esqueleto FISICO (el que lleva los PhysicalBone3D).
var physical_skel: Skeleton3D
## El simulador de huesos fisicos (lo crea Godot, es hijo del esqueleto).
var simulator: PhysicalBoneSimulator3D
## Todos los cuerpos, en el orden en que estan en la escena.
var bones: Array[PhysicalBone3D] = []


## Recoge los cuerpos de la escena y arranca la simulacion.
func setup(p_rig: RagdollRig, p_skel: Skeleton3D) -> void:
	rig = p_rig
	physical_skel = p_skel
	if physical_skel == null:
		push_error("[RagdollSkeleton] no hay esqueleto fisico")
		return
	bones = _find_bones()
	if bones.is_empty():
		push_error("[RagdollSkeleton] el esqueleto '%s' no tiene NINGUN `PhysicalBone3D` en la escena. Los huesos fisicos se authoran en el .tscn (ver meta/docs/Sistema_Animacion_Ragdoll.md)." % physical_skel.name)
		return
	simulator = _buscar_simulador()
	if simulator == null:
		push_error("[RagdollSkeleton] el esqueleto no tiene `PhysicalBoneSimulator3D`")
		return
	# El simulador busca los cuerpos recorriendo el subarbol del esqueleto:
	# con los huesos authorados ahi, los encuentra y crea los joints.
	simulator.physical_bones_start_simulation()
	_resolver_colision_mascara()
	print("[RagdollSkeleton] cuerpos de escena: %d | simulador: %s" % [
		bones.size(), simulator.name])


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


## Devuelve el cuerpo cuyo bone_name coincide, buscandolo en el esqueleto.
func find_in_skeleton(nombre: StringName) -> PhysicalBone3D:
	if physical_skel == null:
		return null
	for n in physical_skel.find_children("*", "PhysicalBone3D", true, false):
		var pb := n as PhysicalBone3D
		if pb.bone_name == nombre:
			return pb
	return null


# --- Interno ---------------------------------------------------------------

## Los cuerpos que la ESCENA trae authorados (nada de crearlos aqui).
func _find_bones() -> Array[PhysicalBone3D]:
	var out: Array[PhysicalBone3D] = []
	if physical_skel == null:
		return out
	for c in physical_skel.find_children("*", "PhysicalBone3D", true, false):
		var pb := c as PhysicalBone3D
		if pb != null and pb.bone_name != &"":
			out.append(pb)
	return out


## El simulador que Godot crea para el esqueleto (hijo del `Skeleton3D`).
## Se busca por tipo, no por nombre: el nombre es autogenerado.
func _buscar_simulador() -> PhysicalBoneSimulator3D:
	for c in physical_skel.find_children("*", "PhysicalBoneSimulator3D", true, false):
		var s := c as PhysicalBoneSimulator3D
		if s != null:
			return s
	return null


## Los huesos colisionan ENTRE SI (para que los brazos no se metan en el
## cuerpo), pero los pares cuyos colliders se SOLAPAN en el reposo se
## excluyen por excepcion del servidor: son los vecinos de una
## articulacion (el codo, la rodilla, el torso) y si colisionaran entre si
## se atoran (el personaje "se descose" y se ve fatal).
##
## OJO (medido): antes los huesos NO colisionaban entre si (el mask no
## tenia el bit 2) y los brazos se metian por dentro del torso. En Godot
## 4.7 `PhysicalBone3D` NO tiene `exclude_parent`/`exclude_bone`, asi que
## la exclusion se hace con `body_add_collision_exception`, que Box3D
## respeta (medido: el ragdoll no se atora).
func _resolver_colision_mascara() -> void:
	# OJO (canonico 2026-11-04): NO se activa la auto-colision. La mascara de
	# la ESCENA manda (5 = mundo + interactuables). Auto-colisionar 15 cuerpos
	# es la fuente de la "sopa de excepciones" y de los atascos: el cuerpo
	# visual no necesita chocar consigo mismo, para eso esta la capsula del
	# CharacterBody3D. Si algun dia hace falta, se activa en la ESCENA
	# (mask |= 2) y se declaran las excepciones en el rig.
	if physical_skel == null:
		return
	# 1) Las REGLAS EXPLICITAS del rig (ganan a la regla automatica).
	#
	# OJO (medido 2026-11-04): la regla automatica ("si los colliders se
	# solapan en el reposo, no colisionan") metia los brazos DENTRO del
	# torso entero: el AABB del humero en T cruza el pecho y el torso bajo,
	# asi que el brazo no chocaba con NADA (y se veia clavado en la
	# cadera). Con las reglas por nombre del rig, el brazo choca con las
	# CADERAS y el torso bajo y NO con el pecho.
	#
	# OJO (medido 2026-11-04, otra vez): esas reglas MISMAS son las que
	# hacian que el personaje saliera disparado 2,4 m hacia arriba al
	# arrancar (medido: la pelvis subia de 0,86 a 2,41 m). La razon: en la
	# pose de JUEGO (el IDLE, con los brazos BAJADOS) el humero y el
	# antebrazo estan DENTRO de las cajas del torso, y con la regla
	# explicita ("el brazo choca con el torso") el solver los expulsa a
	# patadas. Por eso la regla de POSE (abajo) se aplica DESPUES y gana.
	for b in bones:
		for otro in bones:
			if otro == b:
				continue
			var nombre := String(otro.bone_name)
			var rb := _bone_del_rig(b)
			var sin: PackedStringArray = rb.sin_colision_con if rb != null else PackedStringArray()
			var con: PackedStringArray = rb.colision_con if rb != null else PackedStringArray()
			if _coincide(nombre, sin):
				_excepcion(b, otro)
			elif _coincide(nombre, con):
				# SI colisiona: se quita la excepcion automatica.
				PhysicsServer3D.body_remove_collision_exception(
					b.get_rid(), otro.get_rid())
				PhysicsServer3D.body_remove_collision_exception(
					otro.get_rid(), b.get_rid())


## La regla de POSE: los pares de huesos cuyos colliders se SOLAPAN en la
## pose de JUEGO no colisionan.
##
## Se evalua con las poses del esqueleto ANIMADO (la pose del clip, no la
## de reposo): en reposo (T) los brazos estan horizontales y su AABB
## cruza el pecho; en la pose de juego (IDLE, brazos bajos) estan DENTRO
## del torso. Con la regla de reposo, el solver los expandia y el
## personaje salia disparado hacia arriba (medido: la pelvis de 0,86 a
## 2,41 m en 0,8 s).
##
## Se llama cuando la animacion ya ha empezado (la pose del clip ya esta
## escrita), no en el `setup`: antes de eso el esqueleto animado esta en
## la pose de reposo y la regla no serviria para nada.
func aplicar_excepciones_por_pose(animated_skel: Skeleton3D) -> void:
	if animated_skel == null or physical_skel == null:
		return
	var cajas := {}
	for b in bones:
		cajas[b.get_bone_id()] = _aabb_en_pose(b, animated_skel)
	for i in range(bones.size()):
		for j in range(i + 1, bones.size()):
			var a: AABB = cajas.get(bones[i].get_bone_id(), AABB())
			var c: AABB = cajas.get(bones[j].get_bone_id(), AABB())
			if a.size == Vector3.ZERO or c.size == Vector3.ZERO:
				continue
			if a.intersects(c):
				_excepcion(bones[i], bones[j])


## El RagdollBone del rig que corresponde a un cuerpo de la escena.
## Las reglas de colision son DATOS DEL RIG (el .tres), no del nodo.
func _bone_del_rig(b: PhysicalBone3D) -> RagdollBone:
	if rig == null:
		return null
	return rig.bone(String(b.bone_name))


## La excepcion de colision entre dos cuerpos (en los dos sentidos).
func _excepcion(a: PhysicalBone3D, b: PhysicalBone3D) -> void:
	PhysicsServer3D.body_add_collision_exception(a.get_rid(), b.get_rid())
	PhysicsServer3D.body_add_collision_exception(b.get_rid(), a.get_rid())


## La clave de un par de huesos (independiente del orden).
func _clave(a: PhysicalBone3D, b: PhysicalBone3D) -> String:
	var x := str(a.get_bone_id())
	var y := str(b.get_bone_id())
	return x + "_" + y if x < y else y + "_" + x


## ¿El nombre coincide con alguno de los patrones? ("spine*" = prefijo).
static func _coincide(nombre: String, patrones: PackedStringArray) -> bool:
	for p in patrones:
		if p.ends_with("*"):
			if nombre.begins_with(p.substr(0, p.length() - 1)):
				return true
		elif nombre == p:
			return true
	return false


## El AABB (en el mundo) del collider de un hueso, en la pose DADA por el
## esqueleto (animado: la pose de juego).
func _aabb_en_pose(b: PhysicalBone3D, skel: Skeleton3D) -> AABB:
	var cs := b.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null or cs.shape == null:
		return AABB()
	var id := b.get_bone_id()
	if id < 0:
		return AABB()
	var boff: Transform3D = b.get("body_offset")
	var xf := skel.global_transform \
		* skel.get_bone_global_pose(id) * boff * cs.transform
	return xf * WaterShapeTest.aabb_de(cs.shape)
