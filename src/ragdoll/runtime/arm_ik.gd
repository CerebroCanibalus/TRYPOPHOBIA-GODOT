extends Node
class_name ArmIK
## IK DE BRAZOS: los brazos se estiran hacia donde apunta el puntero.
##
## TRAMPAS del TwoBoneIK3D (todas medidas):
##
## 1. **Necesita un NODO POLO.** Con solo `pole_direction_vector` el solver
##    procesa pero NO escribe pose. Y hace falta **UN POLO POR BRAZO**: con
##    uno solo los dos codos caen en el mismo plano (ala de pollo).
##
## 2. **La pose solo es valida en `modification_processed`.** Fuera de esa
##    senal el `Skeleton3D` devuelve la del AnimationMixer. Por eso el PD
##    lee un CACHE de la pose, no el esqueleto en caliente.
##
## 3. **Con influencia 0 el modificador no escribe y NO dispara la
##    senal**: el cache se queda congelado en la pose del primer frame.
##    Por eso el driver de animacion lee la pose DIRECTA del esqueleto
##    cuando el IK no esta activo (ver `AnimationDriver`).
##
## 4. **El alcance se MIDE del rig**: hombro->muneca. Un valor corto no
##    acorta el brazo: lo PLOGA entero (el codo hace tope).

@export var enabled := true
## Margen sobre el alcance medido (1 = el brazo llega justo).
@export var reach_margin := 0.92
## Si es true, el alcance se calcula del rig; si no, usa `reach`.
@export var reach_auto := true
## Alcance manual (metros), si `reach_auto` es false.
@export var reach := 0.5
## Desplazamiento del polo respecto al hombro (x, y, z).
@export var pole_offset := Vector3(0.30, -0.50, -0.30)
## Influencia objetivo cuando el brazo esta agarrando.
@export var influence := 1.0
## Velocidad de fundido de la influencia (por segundo).
@export var influence_fade_speed := 4.0
## Cuanto baja la mano del objetivo (metros).
@export var hand_drop := 0.05

var rig: RagdollRig
var animated_skel: Skeleton3D
var camera_pivot: Node3D

## Un modificador POR BRAZO: la influencia de un TwoBoneIK3D es una sola
## para todas sus cadenas, asi que con un unico modificador al hacer clic
## en un brazo el otro tambien se re-resolvia (medido: el brazo que no
## agarra se movia y se deformaba). Con dos, cada uno tiene su influencia.
var ik_l: TwoBoneIK3D
var ik_r: TwoBoneIK3D
var pole_l: Node3D
var pole_r: Node3D
var target_l: Node3D
var target_r: Node3D

var _rest_arm_length := 0.0
var _l_arm_id := -1
var _r_arm_id := -1
var _l_hand_id := -1
var _r_hand_id := -1


## Monta el IK: crea los nodos que falten y configura las cadenas.
func setup(p_rig: RagdollRig, p_skel: Skeleton3D, p_camera: Node3D,
		p_target_l: Node3D, p_target_r: Node3D) -> void:
	rig = p_rig
	animated_skel = p_skel
	camera_pivot = p_camera
	target_l = p_target_l
	target_r = p_target_r
	if animated_skel == null:
		return
	# El TwoBoneIK3D TIENE que ser hijo DIRECTO del Skeleton3D (el esqueleto
	# solo busca modificadores entre sus hijos). Como el esqueleto animado
	# vive dentro de una instancia del GLB, anadirlo en la escena obligaria
	# a marcar esa instancia como editable -> al guardar, Godot INLINEA las
	# mallas y el Skin deja de enlazar (la malla sale estirada).
	# Anadiendolo aqui, en runtime, la instancia se queda intacta.
	_crear_nodos()
	if ik_l == null or ik_r == null:
		push_warning("[ArmIK] no se encontraron los TwoBoneIK3D: sin IK de brazos")
		return
	if target_l == null or target_r == null:
		push_warning("[ArmIK] faltan los HandTarget: sin IK de brazos")
		return
	if not enabled:
		print("[ArmIK] desactivado por export")
		return
	_place_poles_and_measure()
	_configurar_cadena(ik_l, rig.ik_arm_left, target_l, pole_l)
	_configurar_cadena(ik_r, rig.ik_arm_right, target_r, pole_r)
	_l_arm_id = animated_skel.find_bone(rig.ik_arm_left["root"])
	_r_arm_id = animated_skel.find_bone(rig.ik_arm_right["root"])
	_l_hand_id = animated_skel.find_bone(rig.ik_arm_left["end"])
	_r_hand_id = animated_skel.find_bone(rig.ik_arm_right["end"])


## ¿El IK esta escribiendo pose ahora mismo?
func is_active() -> bool:
	return (ik_l != null and ik_l.get_influence() > 0.001) \
		or (ik_r != null and ik_r.get_influence() > 0.001)


## Longitud real del brazo (hombro -> muneca), medida del rig.
func rest_arm_length() -> float:
	return _rest_arm_length


## Alcance actual (metros).
func current_reach() -> float:
	return reach


## Actualiza los objetivos de las manos y la influencia.
##
## `world_point` = punto del puntero.
## `clicked_l` / `clicked_r` = si ese brazo esta agarrando (con el raton
## pulsado el brazo se estira hacia el puntero; sin el, los brazos siguen
## al clip).
##
## OJO: el brazo que NO esta agarrando NO se estira: su objetivo es SU
## propia mano (la del clip). Si no, los dos brazos se estiran siempre y el
## personaje camina con los brazos por delante (medido).
func update_targets(world_point: Vector3, clicked_l: bool, clicked_r: bool,
		delta: float) -> void:
	if (ik_l == null and ik_r == null) or target_l == null or target_r == null:
		return
	if _l_arm_id < 0 or _r_arm_id < 0:
		return
	# La influencia es POR BRAZO: el que agarra se estira hacia el
	# puntero y el otro se queda en la pose del clip (lo que pedia el
	# General: "que se queden mayormente en la posicion de la animacion
	# idle a menos que estiren el brazo").
	var fade := influence_fade_speed * delta
	if ik_l != null:
		var want_l := influence if clicked_l else 0.0
		ik_l.set_influence(move_toward(ik_l.get_influence(), want_l, fade))
	if ik_r != null:
		var want_r := influence if clicked_r else 0.0
		ik_r.set_influence(move_toward(ik_r.get_influence(), want_r, fade))
	if not (clicked_l or clicked_r):
		return
	if camera_pivot == null:
		return
	var b := animated_skel.global_transform
	var inv := b.basis.inverse()
	var fwd: Vector3 = (inv * (-camera_pivot.global_transform.basis.z)).normalized()
	var alcance := clampf(camera_pivot.global_position.distance_to(world_point), 0.0, reach)
	var drop := Vector3(0.0, -hand_drop, 0.0)
	var l_root: Vector3 = animated_skel.get_bone_global_pose(_l_arm_id).origin
	var r_root: Vector3 = animated_skel.get_bone_global_pose(_r_arm_id).origin
	var l_goal: Vector3 = l_root + fwd * alcance + drop
	var r_goal: Vector3 = r_root + fwd * alcance + drop
	if not clicked_l and _l_hand_id >= 0:
		l_goal = animated_skel.get_bone_global_pose(_l_hand_id).origin
	if not clicked_r and _r_hand_id >= 0:
		r_goal = animated_skel.get_bone_global_pose(_r_hand_id).origin
	target_l.global_position = b * l_goal
	target_r.global_position = b * r_goal


# --- Interno ---------------------------------------------------------------

func _crear_nodos() -> void:
	if ik_l == null:
		ik_l = TwoBoneIK3D.new()
		ik_l.name = "ArmIK_L"
		animated_skel.add_child(ik_l)
	if ik_r == null:
		ik_r = TwoBoneIK3D.new()
		ik_r.name = "ArmIK_R"
		animated_skel.add_child(ik_r)
	if pole_l == null:
		pole_l = Node3D.new()
		pole_l.name = "PoleTargetL"
		animated_skel.add_child(pole_l)
	if pole_r == null:
		pole_r = Node3D.new()
		pole_r.name = "PoleTargetR"
		animated_skel.add_child(pole_r)


func _configurar_cadena(mod: TwoBoneIK3D, cfg: Dictionary, target: Node3D, polo: Node3D) -> void:
	if mod == null:
		return
	mod.setting_count = 1
	mod.set_root_bone_name(0, cfg["root"])
	mod.set_middle_bone_name(0, cfg["mid"])
	mod.set_end_bone_name(0, cfg["end"])
	mod.set_target_node(0, mod.get_path_to(target))
	if polo != null:
		mod.set_pole_node(0, mod.get_path_to(polo))
	else:
		push_warning("[ArmIK] falta el polo de la cadena")


## Mide el brazo y coloca los polos.
func _place_poles_and_measure() -> void:
	if animated_skel == null or rig == null:
		return
	var l_root_name: StringName = rig.ik_arm_left["root"]
	var l_end_name: StringName = rig.ik_arm_left["end"]
	var r_root_name: StringName = rig.ik_arm_right["root"]
	var l_sh: Vector3 = animated_skel.get_bone_global_rest(animated_skel.find_bone(l_root_name)).origin
	var l_wr: Vector3 = animated_skel.get_bone_global_rest(animated_skel.find_bone(l_end_name)).origin
	var r_sh: Vector3 = animated_skel.get_bone_global_rest(animated_skel.find_bone(r_root_name)).origin
	_rest_arm_length = (l_wr - l_sh).length()
	if reach_auto and _rest_arm_length > 0.01:
		reach = _rest_arm_length * reach_margin
	if pole_l != null:
		pole_l.position = l_sh + pole_offset
	if pole_r != null:
		pole_r.position = r_sh + Vector3(-pole_offset.x, pole_offset.y, pole_offset.z)
	print("[ArmIK] rig medido: brazo=%.3fm auto=%s -> alcance=%.3fm | poloL=%s poloR=%s" % [
		_rest_arm_length, str(reach_auto), reach,
		str(pole_l.position if pole_l != null else Vector3.ZERO),
		str(pole_r.position if pole_r != null else Vector3.ZERO)])
