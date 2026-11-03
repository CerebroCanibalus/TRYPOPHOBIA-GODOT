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


## Los huesos NO colisionan entre si (capa 2): los colliders de huesos
## vecinos se solapan y se empujarian entre si (el ragdoll se desgarra).
func _resolver_colision_mascara() -> void:
	for b in bones:
		b.collision_mask = b.collision_mask & ~2
