extends Node3D
## Active-ragdoll del personaje jugador.
##
## Doble skeleton (Animated invisible = pose via AnimationTree, Physical
## visible = simulacion), IK de brazos con TwoBoneIK3D, PD por hueso que
## arrastra el Physical hacia el Animated, lean por pitch de camara,
## grab con PinJoint3D. Mismas reglas que PiCode9560, adaptadas a Godot 4.7+.
##
## CONFIGURACION POR RIG (nuevo en 2026-09-22):
## Todo lo rig-especifico vive en `RagdollRigConfig` (Resource). Asi el
## script NO hardcodea nombres de huesos y un modelo nuevo (coneja) es
## solo otro `.tres` + su `.tscn`. Los defaults reproducen el rig viejo
## (Character.glb) para que la escena existente funcione sin tocar nada.

# === CONFIGURACION =====================================================
## Resource con los nombres de huesos, cadenas IK, clips y shapes del rig.
## Si queda null, se construye uno en runtime con los defaults (Character.glb).
@export var rig_config: RagdollRigConfig

# === MOVIMIENTO ========================================================
const JUMP_STRENGTH = 70
const SPEED = 50
const DAMPING = 0.9

@onready var physical_bone_body : PhysicalBone3D
@onready var body_mesh : MeshInstance3D
@onready var on_floor_left : ShapeCast3D
@onready var on_floor_right : ShapeCast3D
@onready var jump_timer : Timer

var can_jump := true
var is_on_floor := false
var walking := false

# === SPRING / RAGDOLL ==================================================
@export var angular_spring_stiffness: float = 4000.0
@export var angular_spring_damping: float = 80.0
@export var max_angular_force: float = 9999.0

var physics_bones: Array[PhysicalBone3D] = []
@export var ragdoll_mode := false

# === SKELETONS / CAMARA / ANIMATION ===================================
@onready var physical_skel : Skeleton3D
@onready var animated_skel : Skeleton3D
@onready var camera_pivot : Node3D
@onready var animation_tree : AnimationTree
@onready var animation_player: AnimationPlayer
@onready var arm_ik: TwoBoneIK3D
@onready var ik_pole_target_l: Node3D
@onready var ik_pole_target_r: Node3D
@onready var hand_target_l: Node3D
@onready var hand_target_r: Node3D

# === GRAB ==============================================================
var active_arm_left := false
var active_arm_right := false
var grabbed_object: Node3D = null
var grabbing_arm_left := false
var grabbing_arm_right := false
@onready var grab_joint_right: PinJoint3D
@onready var grab_joint_left: PinJoint3D
@onready var physical_bone_l_grab: PhysicalBone3D
@onready var physical_bone_r_grab: PhysicalBone3D
@onready var l_grab_area: Area3D
@onready var r_grab_area: Area3D

# === IK (estado) =======================================================
var _l_arm_id := -1
var _r_arm_id := -1
var _l_hand_id := -1
var _r_hand_id := -1
var _ik_mods := 0
## bone_id -> pose global del ANIMATED, cacheada en `modification_processed`.
var _anim_pose_cache: Dictionary = {}
var _rest_arm_len := 0.0

# === FP CLIP ===========================================================
@export var fp_clip_radius := 0.28

# === LEAN ==============================================================
@export var lean_max_degrees := 2.0
@export var lean_reference_degrees := 45.0
@export var lean_direction := 1.0
## Reparto del lean. Con la coneja tenemos mas candidatos del torso
## (espina*, cuello, cabeza) pero por defecto solo se aplican a Body/Head.
## Override por rig si tenes mas huesos del torso que quieras inclinar.
@export var lean_share_body := 0.75
@export var lean_share_head := 0.25
## Suffix para detectar el hueso fisico del cuerpo en el PD (default = rig viejo).
## En la coneja, el "body" fisico se llama `espina` o `espina2`. Lo override el config.
@export var lean_body_suffix_override: String = ""
@export var lean_head_suffix_override: String = ""

# === IK BRACE ==========================================================
@export var ik_enabled := true
@export var ik_influence := 1.0
@export var ik_influence_fade_speed := 12.0
## Polo del codo RELATIVO AL HOMBRO y en el espacio del esqueleto.
## Dos cosas aprendidas midiendo el rig viejo:
##   - TwoBoneIK3D requires a pole target: con solo `pole_direction_vector`
##     el solver procesa pero NO escribe pose.
##   - Hace falta UN POLO POR BRAZO: con uno solo, los codos caen en el mismo
##     plano y quedan como ala de pollo.
## Criterio: abajo + atras + afuera. +Z local del esqueleto = adelante.
@export var ik_pole_offset := Vector3(0.30, -0.50, -0.30)
@export var arm_reach := 1.28
@export var arm_reach_auto := true
@export var arm_reach_margin := 0.92
@export var hand_drop := 0.04
@export var arm_spring_scale := 0.25

# === GRAB DIR BLEND ====================================================
@export var grab_dir_reference_degrees := 45.0

# === GRAB HOLD (futuro: cerrar dedos) ==================================
## True mientras hay un objeto agarrado. La coneja lo lee para activar
## el clip `clip_grab_hold` cuando Bladi lo bakee. Mientras sea "" no hace nada.
@export var clip_grab_hold: StringName = &""

# === INTERNOS ==========================================================
var current_delta: float
var _simulator: PhysicalBoneSimulator3D = null
var _clip_applied := -1.0


func _ready() -> void:
	if rig_config == null:
		rig_config = RagdollRigConfig.new()
		print("[ragdoll_character] rig_config null -> defaults (Character.glb)")
	# Si la escena no cableo ciertos nodos, los resolvemos por nombre
	# (el `Animated` y el `Physical` son hijos directos con ese nombre).
	_ensure_node_refs()
	_simulator = _setup_physical_bone_simulator()
	_simulator.physical_bones_start_simulation()
	physics_bones.assign(_find_physics_bones())
	ragdoll_mode = false
	print("[ragdoll_character] READY ragdoll_mode=%s bones=%d simulator=%s config=%s" % [
		ragdoll_mode, physics_bones.size(), _simulator != null, rig_config.resource_path])
	var rd_events := InputMap.action_get_events("ragdoll").size() if InputMap.has_action("ragdoll") else -1
	print("[ragdoll_character] accion 'ragdoll' (R) -> %d evento(s)" % rd_events)
	_setup_arm_ik()
	_configure_animation_clips()
	if animation_tree:
		print("[ragdoll_character] clips en AnimationTree: walk=%s grab_lower=%s grab_middle=%s grab_upper=%s idle=%s" % [
			rig_config.clip_walk, rig_config.clip_grab_lower, rig_config.clip_grab_middle,
			rig_config.clip_grab_upper, rig_config.clip_idle])


## Resuelve las refs que el .tscn cablea y, si faltan, las busca por nombre
## y convencion (Animated/Physical son la estructura fija del sistema).
func _ensure_node_refs() -> void:
	if physical_skel == null:
		physical_skel = _find_skel("Physical")
	if animated_skel == null:
		animated_skel = _find_skel("Animated")
	if camera_pivot == null:
		camera_pivot = get_node_or_null("CameraPivot")
	if animation_tree == null:
		var a := get_node_or_null("Animated")
		if a: animation_tree = a.get_node_or_null("AnimationTree") as AnimationTree
	if animation_player == null:
		var a := get_node_or_null("Animated")
		if a: animation_player = a.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if arm_ik == null:
		arm_ik = get_node_or_null("Animated/Armature/Skeleton3D/ArmIK") as TwoBoneIK3D
	if ik_pole_target_l == null:
		ik_pole_target_l = get_node_or_null("Animated/Armature/Skeleton3D/PoleTargetL")
	if ik_pole_target_r == null:
		ik_pole_target_r = get_node_or_null("Animated/Armature/Skeleton3D/PoleTargetR")
	if hand_target_l == null:
		hand_target_l = get_node_or_null("HandTargetL")
	if hand_target_r == null:
		hand_target_r = get_node_or_null("HandTargetR")
	if jump_timer == null:
		jump_timer = get_node_or_null("Physical/JumpTimer")
	if grab_joint_left == null:
		grab_joint_left = get_node_or_null("Physical/GrabJointLeft") as PinJoint3D
	if grab_joint_right == null:
		grab_joint_right = get_node_or_null("Physical/GrabJointRight") as PinJoint3D
	# Hueso fisico del cuerpo (la "capsula"): se busca por nombre del config
	if physical_bone_body == null:
		physical_bone_body = physical_skel.find_child("Physical Bone " + String(rig_config.body_bone_name), true, false) as PhysicalBone3D
	if body_mesh == null:
		body_mesh = physical_skel.find_child("Character", true, false) as MeshInstance3D
		if body_mesh == null:
			body_mesh = physical_skel.find_child("*Cube*", true, false) as MeshInstance3D
	# Huesos de grab (antebrazo en el rig viejo, sobreescribible por rig)
	if physical_bone_l_grab == null:
		physical_bone_l_grab = physical_skel.find_child("Physical Bone " + String(rig_config.grab_bone_left_name), true, false) as PhysicalBone3D
	if physical_bone_r_grab == null:
		physical_bone_r_grab = physical_skel.find_child("Physical Bone " + String(rig_config.grab_bone_right_name), true, false) as PhysicalBone3D
	# GrabAreas son hijos del hueso fisico de grab
	if l_grab_area == null and physical_bone_l_grab:
		l_grab_area = physical_bone_l_grab.find_child("LGrabArea", true, false) as Area3D
	if r_grab_area == null and physical_bone_r_grab:
		r_grab_area = physical_bone_r_grab.find_child("RGrabArea", true, false) as Area3D
	# ShapeCast3D de los pies
	if on_floor_left == null:
		on_floor_left = physical_skel.find_child("Physical Bone " + String(rig_config.on_floor_left_bone_name) + "/OnFloorLeft", true, false) as ShapeCast3D
	if on_floor_right == null:
		on_floor_right = physical_skel.find_child("Physical Bone " + String(rig_config.on_floor_right_bone_name) + "/OnFloorRight", true, false) as ShapeCast3D
	# Lean suffixes (override por rig)
	if lean_body_suffix_override != "":
		# El script usa ends_with() contra un string; lo pasamos via state.
		# Truco: metemos el sufijo custom en una propiedad "privada" del config
		# para no contaminar mas el script. Aqui solo lo loggeamos.
		pass


func _find_skel(prefix: String) -> Skeleton3D:
	var p := get_node_or_null(prefix)
	if p == null: return null
	return p.find_child("Skeleton3D", true, false) as Skeleton3D


## Recorre todo el Skeleton3D fisico y junta los PhysicalBone3D (pueden
## estar reparentados bajo PhysicalBoneSimulator3D en runtime).
func _find_physics_bones() -> Array[PhysicalBone3D]:
	var out: Array[PhysicalBone3D] = []
	if physical_skel == null: return out
	for c in physical_skel.find_children("*", "PhysicalBone3D", true, false):
		out.append(c as PhysicalBone3D)
	return out


## Godot 4.4+ exige PhysicalBoneSimulator3D como PADRE de los PhysicalBone3D.
## Si no existe, lo crea y reparenta los bones. (Ver AGENTS.md FIX M3.5.)
func _setup_physical_bone_simulator() -> PhysicalBoneSimulator3D:
	if physical_skel == null: return null
	var existing := physical_skel.get_node_or_null("PhysicalBoneSimulator3D") as PhysicalBoneSimulator3D
	if existing: return existing
	var bones := physical_skel.get_children().filter(func(x): return x is PhysicalBone3D)
	var sim := PhysicalBoneSimulator3D.new()
	sim.name = "PhysicalBoneSimulator3D"
	physical_skel.add_child(sim)
	for b in bones:
		b.reparent(sim, true)
	print("[ragdoll_character] PhysicalBoneSimulator3D creado, %d bones reparentados" % bones.size())
	return sim


## Aplica LOOP_LINEAR a todos los clips con duracion real. Los .glb de glTF
## llegan con loop_mode=NONE (se reproduce una vez y se congela). Las
## "poses" (idle/grab_*) son de 1 key, asi que no entran en este filtro.
func _configure_animation_clips() -> void:
	if animation_player == null: return
	for anim_name in animation_player.get_animation_list():
		var a: Animation = animation_player.get_animation(anim_name)
		if a and a.length > 0.1:
			a.loop_mode = Animation.LOOP_LINEAR
			print("[ragdoll_character] clip '%s' -> LOOP_LINEAR (%.2fs)" % [anim_name, a.length])


func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("ragdoll"):
		ragdoll_mode = not ragdoll_mode
		print("[ragdoll_character] MODO RAGDOLL = %s" % ragdoll_mode)

	active_arm_left = Input.is_action_pressed("grab_left")
	active_arm_right = Input.is_action_pressed("grab_right")

	if (not active_arm_left and grabbing_arm_left) or ragdoll_mode:
		grabbing_arm_left = false
		grab_joint_left.node_a = NodePath()
		grab_joint_left.node_b = NodePath()
	if (not active_arm_right and grabbing_arm_right) or ragdoll_mode:
		grabbing_arm_right = false
		grab_joint_right.node_a = NodePath()
		grab_joint_right.node_b = NodePath()


func _process(_delta: float) -> void:
	_update_fp_clip()
	if animation_tree:
		var r := clampf(camera_pivot.rotation.x / deg_to_rad(grab_dir_reference_degrees), -1.0, 1.0)
		if active_arm_left or active_arm_right:
			animation_tree.set("parameters/grab_dir/blend_position", r)
		else:
			animation_tree.set("parameters/grab_dir/blend_position", 0)


func _update_fp_clip() -> void:
	var want: float = fp_clip_radius if (camera_pivot and camera_pivot.first_person) else 0.0
	if is_equal_approx(want, _clip_applied): return
	_clip_applied = want
	if body_mesh and body_mesh.material_override is ShaderMaterial:
		(body_mesh.material_override as ShaderMaterial).set_shader_parameter("clip_radius", want)


func _physics_process(delta: float) -> void:
	current_delta = delta
	if ragdoll_mode: return
	walking = false
	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		dir += animated_skel.global_transform.basis.z; walking = true
	if Input.is_action_pressed("move_left"):
		dir += animated_skel.global_transform.basis.x; walking = true
	if Input.is_action_pressed("move_right"):
		dir -= animated_skel.global_transform.basis.x; walking = true
	if Input.is_action_pressed("move_backward"):
		dir -= animated_skel.global_transform.basis.z; walking = true
	dir = dir.normalized()
	if physical_bone_body:
		physical_bone_body.linear_velocity += dir * SPEED * delta
		physical_bone_body.linear_velocity *= Vector3(DAMPING, 1, DAMPING)

	is_on_floor = false
	if on_floor_left and on_floor_left.is_colliding():
		for i in on_floor_left.get_collision_count():
			if on_floor_left.get_collision_normal(i).y > 0.5:
				is_on_floor = true; break
	if not is_on_floor and on_floor_right and on_floor_right.is_colliding():
		for i in on_floor_right.get_collision_count():
			if on_floor_right.get_collision_normal(i).y > 0.5:
				is_on_floor = true; break

	if Input.is_action_pressed("jump") and is_on_floor and can_jump and physical_bone_body:
		physical_bone_body.linear_velocity.y += JUMP_STRENGTH
		jump_timer.start()
		can_jump = false

	if animation_tree:
		animation_tree.set("parameters/walking/blend_amount", 1.0 if walking else 0.0)

	animated_skel.rotation.y = camera_pivot.rotation.y if camera_pivot else 0.0


## Hooke's law angular: torque de resorte amortiguado.
func hookes_law(displacement: Vector3, current_velocity: Vector3, stiffness: float, damping: float) -> Vector3:
	return (stiffness * displacement) - (damping * current_velocity)


func _on_r_grab_area_body_entered(body: Node3D) -> void:
	if body is PhysicsBody3D and body.get_parent() != physical_skel:
		if active_arm_right and not grabbing_arm_right and physical_bone_r_grab and grab_joint_right:
			grabbing_arm_right = true
			grab_joint_right.global_position = r_grab_area.global_position
			grab_joint_right.node_a = physical_bone_r_grab.get_path()
			grab_joint_right.node_b = body.get_path()


func _on_l_grab_area_body_entered(body: Node3D) -> void:
	if body is PhysicsBody3D and body.get_parent() != physical_skel:
		if active_arm_left and not grabbing_arm_left and physical_bone_l_grab and grab_joint_left:
			grabbing_arm_left = true
			grabbed_object = body
			grab_joint_left.global_position = l_grab_area.global_position
			grab_joint_left.node_a = physical_bone_l_grab.get_path()
			grab_joint_left.node_b = body.get_path()


func _on_jump_timer_timeout() -> void:
	can_jump = true


func _on_skeleton_3d_skeleton_updated() -> void:
	if ragdoll_mode: return
	var arm_tok := rig_config.arm_name_token
	var leg_tok := rig_config.leg_name_token
	for b: PhysicalBone3D in physics_bones:
		var stiff := angular_spring_stiffness
		var damp := angular_spring_damping
		# Brazo = contiene arm_token Y NO contiene leg_token. Asi 'LArm1'
		# matchea pero 'LLeg1' no (la 'L' de LArm1 no es el discriminante).
		var is_arm := b.name.contains(arm_tok) and not b.name.contains(leg_tok)
		if is_arm:
			var arm_active := false
			# Lado por el primer caracter del nombre del hueso fisico:
			# "Physical Bone LArm1" empieza con L; "Physical Bone RArm1" con R.
			# Para rigs en espanol (brazo1_L, brazo2_R) usamos el ultimo segmento
			# despues del guion bajo.
			if "_L" in b.name or b.name.ends_with(" L") or b.name.contains("LArm"):
				arm_active = active_arm_left
			elif "_R" in b.name or b.name.ends_with(" R") or b.name.contains("RArm"):
				arm_active = active_arm_right
			if not arm_active:
				stiff *= arm_spring_scale
				damp *= arm_spring_scale
		var anim_pose: Transform3D = _anim_pose_cache.get(b.get_bone_id(), animated_skel.get_bone_global_pose(b.get_bone_id()))
		var target_transform: Transform3D = animated_skel.global_transform * anim_pose
		target_transform = _apply_body_lean(b, target_transform)
		var current_transform: Transform3D = physical_skel.global_transform * physical_skel.get_bone_global_pose(b.get_bone_id())
		var rotation_difference: Basis = (target_transform.basis * current_transform.basis.inverse())
		var torque := hookes_law(rotation_difference.get_euler(), b.angular_velocity, stiff, damp)
		torque = torque.limit_length(max_angular_force)
		b.angular_velocity += torque * current_delta


## Lean del torso segun pitch de camara. Mira abajo -> inclina adelante.
## Es una ENTRADA DE CONTROL al spring, no una animacion por codigo.
func _apply_body_lean(bone: PhysicalBone3D, target: Transform3D) -> Transform3D:
	if lean_max_degrees <= 0.0: return target
	var body_suffix: String = lean_body_suffix_override if lean_body_suffix_override != "" else rig_config.lean_body_suffix
	var head_suffix: String = lean_head_suffix_override if lean_head_suffix_override != "" else rig_config.lean_head_suffix
	var share := 0.0
	if bone.name.ends_with(head_suffix):
		share = lean_share_head
	elif bone.name.ends_with(body_suffix):
		share = lean_share_body
	if is_zero_approx(share): return target
	var lean := clampf(camera_pivot.rotation.x / deg_to_rad(lean_reference_degrees), -1.0, 1.0) if camera_pivot else 0.0
	if is_zero_approx(lean): return target
	var angle := -lean * lean_direction * deg_to_rad(lean_max_degrees) * share
	var forward := animated_skel.global_transform.basis.z
	var right := forward.cross(Vector3.UP).normalized()
	if right.is_zero_approx(): return target
	return Transform3D(Basis(right, angle) * target.basis, target.origin)


## Configura el TwoBoneIK3D con las cadenas del rig. Las cadenas NO son
## propiedades serializables del nodo: se setean por metodo. Por eso va
## en codigo y no como data de escena.
func _setup_arm_ik() -> void:
	if arm_ik == null:
		push_warning("[ragdoll_character] ArmIK no encontrado: sin IK de brazos")
		return
	if hand_target_l == null or hand_target_r == null:
		push_warning("[ragdoll_character] HandTargetL/R no encontrados: sin IK de brazos")
		return
	arm_ik.setting_count = 0
	if not ik_enabled:
		print("[ragdoll_character] ArmIK desactivado por export")
		return
	arm_ik.setting_count = 2
	_place_poles_and_measure()
	var chains := [
		{ "cfg": rig_config.ik_arm_left,  "t": hand_target_l, "p": ik_pole_target_l },
		{ "cfg": rig_config.ik_arm_right, "t": hand_target_r, "p": ik_pole_target_r },
	]
	for i in chains.size():
		var c: Dictionary = chains[i]
		arm_ik.set_root_bone_name(i, c["cfg"]["root"])
		arm_ik.set_middle_bone_name(i, c["cfg"]["mid"])
		arm_ik.set_end_bone_name(i, c["cfg"]["end"])
		arm_ik.set_target_node(i, arm_ik.get_path_to(c["t"]))
		if c["p"] != null:
			arm_ik.set_pole_node(i, arm_ik.get_path_to(c["p"]))
		else:
			push_warning("[ragdoll_character] falta el polo de la cadena %d" % i)
	_l_arm_id = animated_skel.find_bone(rig_config.ik_arm_left["root"])
	_r_arm_id = animated_skel.find_bone(rig_config.ik_arm_right["root"])
	_l_hand_id = animated_skel.find_bone(rig_config.ik_arm_left["end"])
	_r_hand_id = animated_skel.find_bone(rig_config.ik_arm_right["end"])
	arm_ik.modification_processed.connect(_on_ik_modification)
	print("[ragdoll_character] ArmIK OK: %d cadenas | bone ids L=%d R=%d | brazo=%.3fm alcance=%.3fm | polos L=%s R=%s" % [
		arm_ik.setting_count, _l_arm_id, _r_arm_id, _rest_arm_len, arm_reach,
		str(ik_pole_target_l != null), str(ik_pole_target_r != null)])


## Mide el brazo y coloca el polo. Ver nota en el comentario del rig viejo.
func _place_poles_and_measure() -> void:
	var l_root_name: StringName = rig_config.ik_arm_left["root"]
	var l_end_name: StringName = rig_config.ik_arm_left["end"]
	var r_root_name: StringName = rig_config.ik_arm_right["root"]
	var l_sh: Vector3 = animated_skel.get_bone_global_rest(animated_skel.find_bone(l_root_name)).origin
	var l_wr: Vector3 = animated_skel.get_bone_global_rest(animated_skel.find_bone(l_end_name)).origin
	var r_sh: Vector3 = animated_skel.get_bone_global_rest(animated_skel.find_bone(r_root_name)).origin
	_rest_arm_len = (l_wr - l_sh).length()
	if arm_reach_auto and _rest_arm_len > 0.01:
		arm_reach = _rest_arm_len * arm_reach_margin
	if ik_pole_target_l != null:
		ik_pole_target_l.position = l_sh + ik_pole_offset
	if ik_pole_target_r != null:
		ik_pole_target_r.position = r_sh + Vector3(-ik_pole_offset.x, ik_pole_offset.y, ik_pole_offset.z)
	print("[ragdoll_character] rig medido: brazo=%.3fm auto=%s -> alcance=%.3fm | poloL=%s poloR=%s" % [
		_rest_arm_len, str(arm_reach_auto), arm_reach,
		str(ik_pole_target_l.position if ik_pole_target_l != null else Vector3.ZERO),
		str(ik_pole_target_r.position if ik_pole_target_r != null else Vector3.ZERO)])


## Cache de la pose modificada por el IK. Sin esto, el PD del spring lee
## la pose SIN IK y el brazo se queda tieso (errSig=0.000 vs err=0.848).
func _on_ik_modification() -> void:
	_ik_mods += 1
	if ragdoll_mode: return
	for b: PhysicalBone3D in physics_bones:
		var id := b.get_bone_id()
		_anim_pose_cache[id] = animated_skel.get_bone_global_pose(id)


## Actualiza los HandTarget del IK al punto del puntero. Se calcula en el
## espacio del esqueleto ANIMADO (que no se traslada). CLICK = influence 1;
## IDLE = influence 0 (los brazos siguen al clip idle, no se estiran).
func update_hand_targets(world_point: Vector3, _has_target: bool) -> void:
	if arm_ik == null or hand_target_l == null or hand_target_r == null: return
	if _l_arm_id < 0 or _r_arm_id < 0: return
	var clicked := active_arm_left or active_arm_right
	var want := ik_influence if clicked else 0.0
	var dt := get_physics_process_delta_time()
	arm_ik.set_influence(move_toward(arm_ik.get_influence(), want, ik_influence_fade_speed * dt))
	if not clicked: return
	var b := animated_skel.global_transform
	var inv := b.basis.inverse()
	var fwd: Vector3 = (inv * (-camera_pivot.global_transform.basis.z)).normalized()
	var reach := clampf(camera_pivot.global_position.distance_to(world_point), 0.0, arm_reach)
	var drop := Vector3(0.0, -hand_drop, 0.0)
	var l_root: Vector3 = animated_skel.get_bone_global_pose(_l_arm_id).origin
	var r_root: Vector3 = animated_skel.get_bone_global_pose(_r_arm_id).origin
	var l_goal: Vector3 = l_root + fwd * reach + drop
	var r_goal: Vector3 = r_root + fwd * reach + drop
	if not active_arm_left and _l_hand_id >= 0:
		l_goal = animated_skel.get_bone_global_pose(_l_hand_id).origin
	if not active_arm_right and _r_hand_id >= 0:
		r_goal = animated_skel.get_bone_global_pose(_r_hand_id).origin
	hand_target_l.global_position = b * l_goal
	hand_target_r.global_position = b * r_goal