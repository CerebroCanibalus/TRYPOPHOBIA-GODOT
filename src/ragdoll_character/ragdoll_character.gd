extends Node3D


# movement/walking/jumping stuff
const JUMP_STRENGTH = 70
const SPEED = 50
const DAMPING = 0.9
@onready var on_floor_left = $"Physical/Armature/Skeleton3D/Physical Bone LLeg2/OnFloorLeft" # shapecast on the feet to check if its on floor
@onready var on_floor_right = $"Physical/Armature/Skeleton3D/Physical Bone RLeg2/OnFloorRight" # shapecast on the feet to check if its on floor
@onready var jump_timer = $Physical/JumpTimer # timer to stop excidental double jump
var can_jump = true
var is_on_floor = false
var walking = false # if it is walking


# spring stuff
@export var angular_spring_stiffness: float = 4000.0
@export var angular_spring_damping: float = 80.0
@export var max_angular_force: float = 9999.0

var physics_bones = [] # all physical bones

# turn it into ragdoll
@export var ragdoll_mode := false


@onready var physical_skel : Skeleton3D = $Physical/Armature/Skeleton3D
@onready var animated_skel : Skeleton3D = $Animated/Armature/Skeleton3D
@onready var camera_pivot = $CameraPivot
@onready var animation_tree = $Animated/AnimationTree
@onready var animation_player: AnimationPlayer = $Animated/AnimationPlayer
@onready var physical_bone_body : PhysicalBone3D = $"Physical/Armature/Skeleton3D/Physical Bone Body"
@onready var body_mesh : MeshInstance3D = $"Physical/Armature/Skeleton3D/Character"
@onready var arm_ik: TwoBoneIK3D = get_node_or_null("Animated/Armature/Skeleton3D/ArmIK") as TwoBoneIK3D
@onready var ik_pole_target_l: Node3D = get_node_or_null("Animated/Armature/Skeleton3D/PoleTargetL")
@onready var ik_pole_target_r: Node3D = get_node_or_null("Animated/Armature/Skeleton3D/PoleTargetR")
@onready var hand_target_l: Node3D = get_node_or_null("HandTargetL")
@onready var hand_target_r: Node3D = get_node_or_null("HandTargetR")

var _l_arm_id := -1
var _r_arm_id := -1
var _l_hand_id := -1
var _r_hand_id := -1
var _ik_mods := 0
## bone_id -> pose global del ANIMATED, cacheada en `modification_processed`.
var _anim_pose_cache: Dictionary = {}
var _rest_arm_len := 0.0


# 1a persona: recorte de la geometria propia alrededor de la camara. Evita ver
# el interior del craneo y limpia el hocico de las fursonas. El ShaderMaterial
# lo asigna el .tscn como material_override; aca solo se muta su parametro.
# Mantenerlo LO MAS CHICO POSIBLE: cuanto mas lejos del craneo este la camara
# (`head_distance` en ragdoll_camera.gd), menos geometria tiene que borrar. Solo
# subirlo lo justo para que no se cuele el hocico en pantalla.
## Radio (m) del volumen que se DESCARTA alrededor de la camara, para que no se
## cuele la cabeza ni el hocico en pantalla. Medido en el rig: el reposo es una
## T-POSE y el hueso Head esta a 1.339 m del origen; el craneo tiene ~0.15 m de
## radio, asi que con la camara encima (head_distance chico) hace falta ~0.25-0.30.
## El volumen es un elipsoide alargado hacia adelante (clip_forward_scale), asi
## que mata el hocico de frente sin comerse los brazos, que van mas atras.
@export var fp_clip_radius := 0.28


# Inclinacion del torso segun el pitch de la camara. Es una ENTRADA DE CONTROL
# al spring, no una animacion por codigo.
@export var lean_max_degrees := 2.0
@export var lean_reference_degrees := 45.0
## Si el cuerpo se inclina al reves (mirar abajo lo tira para atras), poner -1.
@export var lean_direction := 1.0
## Reparto del lean por hueso. OJO (verificado 2026-09-10): el ragdoll tiene 10
## huesos fisicos (Body, LArm1/2, RArm1/2, LLeg1/2, RLeg1/2, Head) y **NO hay
## Neck**: los unicos del torso son Body y Head. El lean se reparte entre esos dos.
## Los pesos suman 1 => el tilt total del craneo = lean_max_degrees.
@export var lean_share_body := 0.75
@export var lean_share_head := 0.25


# Direccion del blend de agarre de los brazos (grab_lower .. grab_upper) segun
# el pitch de la camara.
@export var grab_dir_reference_degrees := 45.0


# IK de brazos: hace que el MASTER (Animated) apunte al puntero; el spring PD
# arrastra los huesos fisicos.
# OJO: el esqueleto ANIMADO **no se traslada**, solo rota (el que camina es el
# Physical). Por eso el target se calcula en SU espacio (hombro + direccion de la
# camara * alcance) y NO desde el punto del mundo: usar el punto del mundo tiraria
# de los brazos hacia un lugar a metros de distancia.
@export var ik_enabled := true
## Influence del modificador de IK cuando SI hay objetivo (0..1). Con 0 el IK no
## escribe pose aunque haya objetivo. Util para medir cuanto inclina el brazo.
@export var ik_influence := 1.0
## Velocidad de interpolacion del influence (por segundo). Evita que el brazo de
## un tiron al apretar y, sobre todo, al SOLTAR (vuelve al idle suavemente).
@export var ik_influence_fade_speed := 12.0
## Polo del codo, RELATIVO AL HOMBRO y en el espacio del esqueleto. Dos cosas
## aprendidas midiendo el rig:
##  - TwoBoneIK3D "requires a pole target": con SOLO una direccion custom
##    (SECONDARY_DIRECTION_CUSTOM) el solver procesa pero NO escribe ninguna pose.
##  - Hace falta UN POLO POR BRAZO: con uno solo, los dos codos caen en el mismo
##    plano y quedan como ala de pollo.
## Criterio: abajo + atras + afuera. El reposo del modelo es una T-POSE perfecta
## (codo sin curvatura), asi que la direccion natural NO se puede derivar del rig:
## se pone a mano. +Z local del esqueleto = adelante (medido), asi que atras = -Z.
## La X se espeja sola para el brazo derecho.
@export var ik_pole_offset := Vector3(0.30, -0.50, -0.30)
## Alcance maximo del brazo (m). OJO: el rig mide 1.397 m de hombro a muneca, y un
## valor CORTO no "acorta" el brazo: lo PLEGA entero (el codo hace tope). Con
## arm_reach_auto=true este valor se SOBRESCRIBE midiendo el esqueleto.
@export var arm_reach := 1.28
## Deriva arm_reach del rig (hombro->muneca en reposo * arm_reach_margin).
@export var arm_reach_auto := true
## Margen sobre la longitud real, para que el codo nunca quede del todo recto
## (una cadena 100% extendida es donde el solver tiembla y el polo da vueltas).
@export var arm_reach_margin := 0.92
## Caida del target para que el codo no quede recto.
@export var hand_drop := 0.04
## (B) Escala de rigidez de los brazos cuando NO estan agarrando. Los brazos
## reciben PD SIEMPRE, pero flojo, para que se vean sueltos SIN derivar: antes se
## salteaban por completo y derivaban 90 grados (medido con body_debugger), y al
## agarrar el PD los arrancaba de golpe. Al agarrar usan la rigidez plena.
@export var arm_spring_scale := 0.25


# grabbing related stuff
var active_arm_left = false
var active_arm_right = false
var grabbed_object = null
var grabbing_arm_left = false
var grabbing_arm_right = false
@onready var grab_joint_right = $Physical/GrabJointRight
@onready var grab_joint_left = $Physical/GrabJointLeft
@onready var physical_bone_l_arm_2 = $"Physical/Armature/Skeleton3D/Physical Bone LArm2"
@onready var physical_bone_r_arm_2 = $"Physical/Armature/Skeleton3D/Physical Bone RArm2"
@onready var l_grab_area = $"Physical/Armature/Skeleton3D/Physical Bone LArm2/LGrabArea"
@onready var r_grab_area = $"Physical/Armature/Skeleton3D/Physical Bone RArm2/RGrabArea"

var current_delta:float
var _simulator: PhysicalBoneSimulator3D = null
var _clip_applied := -1.0

func _ready():
	_simulator = _setup_physical_bone_simulator()
	# IMPORTANTE (Godot 4.3+): la simulacion debe arrancarse en el
	# PhysicalBoneSimulator3D, NO en el Skeleton3D (metodo deprecado que NO
	# hace nada y no emite warning). Ref: godot#100843, godot#94831.
	_simulator.physical_bones_start_simulation()
	physics_bones = physical_skel.find_children("*", "PhysicalBone3D", true, false)
	# Forzar ragdoll_mode=false: que el personaje SIEMPRE arranque en modo
	# controlado (movimiento + spring). Sin esto, si alguien presiono R en una
	# sesion anterior, arrancaba en ragdoll_mode=true y solo se inclinaba.
	ragdoll_mode = false
	print("[ragdoll_character] READY ragdoll_mode=%s bones=%d simulator=%s" % [ragdoll_mode, physics_bones.size(), _simulator != null])
	# Diagnostico: si la accion no tiene eventos, R no hace NADA (fue el caso
	# tras vaciarla). Ver project.godot -> [input] -> ragdoll.
	var rd_events := InputMap.action_get_events("ragdoll").size() if InputMap.has_action("ragdoll") else -1
	print("[ragdoll_character] accion 'ragdoll' (R) -> %d evento(s)" % rd_events)
	_setup_arm_ik()
	# El clip Walk importado del GLB trae loop_mode=NONE -> se reproduce UNA vez
	# (0.83s) y se congela, por eso "el walk cycle no funciona bien". Forzamos
	# loop continuo en los clips con duracion real (idle/grab son poses fijas).
	if animation_player:
		for anim_name in animation_player.get_animation_list():
			var a: Animation = animation_player.get_animation(anim_name)
			if a and a.length > 0.1:
				a.loop_mode = Animation.LOOP_LINEAR
				print("[ragdoll_character] clip '%s' -> LOOP_LINEAR (%.2fs)" % [anim_name, a.length])


## Godot 4.4+ exige un PhysicalBoneSimulator3D como PADRE de los PhysicalBone3D
## para sincronizar el Skeleton3D con la simulacion fisica. La escena de
## referencia (PiCode9560) es de Godot 4.3, donde el Skeleton3D lo hacia solo;
## al portarla a 4.7 el mesh se quedaba en la pose de reposo ("piernas tiesas").
func _setup_physical_bone_simulator() -> PhysicalBoneSimulator3D:
	var existing := physical_skel.get_node_or_null("PhysicalBoneSimulator3D") as PhysicalBoneSimulator3D
	if existing:
		return existing
	var bones := physical_skel.get_children().filter(func(x): return x is PhysicalBone3D)
	var sim := PhysicalBoneSimulator3D.new()
	sim.name = "PhysicalBoneSimulator3D"
	physical_skel.add_child(sim)
	for b in bones:
		b.reparent(sim, true)
	print("[ragdoll_character] PhysicalBoneSimulator3D creado, %d bones reparentados" % bones.size())
	return sim


func _input(event):
	# La accion `ragdoll` quedo VACIA en project.godot cuando se arreglo el
	# toggle accidental (R estaba mapeada y el personaje arrancaba en ragdoll).
	# Ahora R vuelve a estar mapeada A PROPOSITO: es la tecla de full ragdoll.
	if Input.is_action_just_pressed("ragdoll"):
		ragdoll_mode = not ragdoll_mode
		print("[ragdoll_character] MODO RAGDOLL = %s" % ragdoll_mode)

	active_arm_left = Input.is_action_pressed("grab_left")# activate left arm with mouse left click
	active_arm_right = Input.is_action_pressed("grab_right")# activate right arm with mouse right click
	
	if (not active_arm_left and grabbing_arm_left) or ragdoll_mode:
		#release whatever the arm is holding when ragdoll mode or the arm is deactivate
		grabbing_arm_left = false
		grab_joint_left.node_a = NodePath()
		grab_joint_left.node_b = NodePath()
		
	if (not active_arm_right and grabbing_arm_right) or ragdoll_mode:
		#release whatever the arm is holding when ragdoll mode or the arm is deactivate
		grabbing_arm_right = false
		grab_joint_right.node_a = NodePath()
		grab_joint_right.node_b = NodePath()

func _process(delta):
	# (sync manual desactivado: usaba offset incorrecto y torsionaba los huesos)
	# _sync_skeleton_from_physics()
	_update_fp_clip()
	# Direccion de agarre de los brazos segun el pitch de la camara. En 1a
	# persona el pitch llega a +-85 grados: se normaliza contra una referencia
	# para no saturar el BlendSpace (antes saturaba a los ~43 grados).
	var r = clampf(camera_pivot.rotation.x / deg_to_rad(grab_dir_reference_degrees), -1.0, 1.0)
	if active_arm_left or active_arm_right:
		animation_tree.set("parameters/grab_dir/blend_position",r) # move the arms toward the direction you're looking at
	else:
		animation_tree.set("parameters/grab_dir/blend_position",0)


## Activa/desactiva el recorte de la geometria propia segun el modo de camara:
## en 1a persona hay que borrar el craneo/hocico de delante de la camara, en la
## 3a de debug hay que verse entero.
func _update_fp_clip() -> void:
	var want: float = fp_clip_radius if camera_pivot.first_person else 0.0
	if is_equal_approx(want, _clip_applied):
		return
	_clip_applied = want
	if body_mesh and body_mesh.material_override is ShaderMaterial:
		(body_mesh.material_override as ShaderMaterial).set_shader_parameter("clip_radius", want)


func _physics_process(delta):
	current_delta = delta
	if not ragdoll_mode:# if not in ragdoll mode
		
		# walking control
		walking = false
		var dir = Vector3.ZERO
		if Input.is_action_pressed("move_forward"):
			dir += animated_skel.global_transform.basis.z
			walking = true
		if Input.is_action_pressed("move_left"):
			dir += animated_skel.global_transform.basis.x
			walking = true
		if Input.is_action_pressed("move_right"):
			dir -= animated_skel.global_transform.basis.x
			walking = true
		if Input.is_action_pressed("move_backward"):
			dir -= animated_skel.global_transform.basis.z
			walking = true
		dir = dir.normalized()

		physical_bone_body.linear_velocity += dir*SPEED*delta #move character
		physical_bone_body.linear_velocity *= Vector3(DAMPING,1,DAMPING)# add damping to make it less slippery
		
		
		#check if is on floor
		is_on_floor = false
		if on_floor_left.is_colliding():
			for i in on_floor_left.get_collision_count():
				if on_floor_left.get_collision_normal(i).y > 0.5:
					is_on_floor = true
					break
		if not is_on_floor: 
			if on_floor_right.is_colliding():
				for i in on_floor_right.get_collision_count():
					if on_floor_right.get_collision_normal(i).y > 0.5:
						is_on_floor = true
						break
		
		#jump
		if Input.is_action_pressed("jump"):
			if is_on_floor and can_jump:
				physical_bone_body.linear_velocity.y += JUMP_STRENGTH
				jump_timer.start()
				can_jump = false
		
		#play walking animation/idle
		if walking:animation_tree.set("parameters/walking/blend_amount",1)
		else:animation_tree.set("parameters/walking/blend_amount",0)

		#rotate the character toward the camera direction
		animated_skel.rotation.y = camera_pivot.rotation.y
# spring related function
func hookes_law(displacement: Vector3, current_velocity: Vector3, stiffness: float, damping: float) -> Vector3:
	return (stiffness * displacement) - (damping * current_velocity)


## Copia las transformadas de los PhysicalBone3D (fisica) al Skeleton3D (visual).
func _sync_skeleton_from_physics() -> void:
	if not physical_skel:
		return
	var inv := physical_skel.global_transform.affine_inverse()
	for b: PhysicalBone3D in physics_bones:
		physical_skel.set_bone_global_pose_override(b.get_bone_id(), inv * b.global_transform, 1.0, true)


func _on_r_grab_area_body_entered(body:Node3D):
	# check if the arm is touching something for grabbing
	if body is PhysicsBody3D and body.get_parent() != physical_skel:
		if active_arm_right and not grabbing_arm_right:
			grabbing_arm_right = true
			grab_joint_right.global_position = r_grab_area.global_position
			grab_joint_right.node_a = physical_bone_r_arm_2.get_path()
			grab_joint_right.node_b = body.get_path()


func _on_l_grab_area_body_entered(body:Node3D):
	# check if the arm is touching something for grabbing
	if body is PhysicsBody3D and body.get_parent() != physical_skel:
		if active_arm_left and not grabbing_arm_left:
			grabbing_arm_left = true
			grabbed_object = body
			grab_joint_left.global_position = l_grab_area.global_position
			grab_joint_left.node_a = physical_bone_l_arm_2.get_path()
			grab_joint_left.node_b = body.get_path()



func _on_jump_timer_timeout():
	# jump timer to avoid spamming jump and then fly away
	can_jump = true


func _on_skeleton_3d_skeleton_updated() -> void:
	if not ragdoll_mode:# if not in ragdoll mode
		# rotate the physical bones toward the animated bones rotations using hookes law
		for b:PhysicalBone3D in physics_bones:
			# (B) Los brazos reciben PD SIEMPRE, pero mas suave mientras no agarran:
			# asi se ven sueltos sin derivar. Antes se salteaban enteros y derivaban
			# 90 grados (medido con body_debugger) -> al agarrar el PD los arrancaba
			# de golpe (el "flexiona raro" / "se inclina al clickear").
			var stiff := angular_spring_stiffness
			var damp := angular_spring_damping
			if b.name.contains("LArm") or b.name.contains("RArm"):
				var arm_active := (active_arm_left and b.name.contains("LArm")) \
					or (active_arm_right and b.name.contains("RArm"))
				if not arm_active:
					stiff *= arm_spring_scale
					damp *= arm_spring_scale
			# Del cache (unico lugar donde la pose refleja el IK), con fallback a
			# la lectura directa mientras no haya corrido ninguna modificacion.
			var anim_pose: Transform3D = _anim_pose_cache.get(b.get_bone_id(), animated_skel.get_bone_global_pose(b.get_bone_id()))
			var target_transform: Transform3D = animated_skel.global_transform * anim_pose
			target_transform = _apply_body_lean(b, target_transform)
			var current_transform: Transform3D = physical_skel.global_transform * physical_skel.get_bone_global_pose(b.get_bone_id())
			var rotation_difference: Basis = (target_transform.basis * current_transform.basis.inverse())
			var torque = hookes_law(rotation_difference.get_euler(), b.angular_velocity, stiff, damp)
			torque = torque.limit_length(max_angular_force)
			
			b.angular_velocity += torque * current_delta


## Inclinacion del torso por pitch de camara: mirar abajo -> el personaje se
## inclina hacia adelante; mirar arriba -> hacia atras. El target del master se
## rota y la fisica hace el resto: es una ENTRADA DE CONTROL al spring, no una
## animacion por codigo (el cuerpo conserva su peso y puede ser detenido por una
## pared).
func _apply_body_lean(bone: PhysicalBone3D, target: Transform3D) -> Transform3D:
	if lean_max_degrees <= 0.0:
		return target
	# Que parte del lean le toca a este hueso (ver lean_share_*). ends_with() y no
	# contains(): asi "Physical Bone Head" entra y un futuro "Head.001" (hocico) no.
	var share := 0.0
	if bone.name.ends_with("Head"):
		share = lean_share_head
	elif bone.name.ends_with("Body"):
		share = lean_share_body
	if is_zero_approx(share):
		return target
	var lean := clampf(camera_pivot.rotation.x / deg_to_rad(lean_reference_degrees), -1.0, 1.0)
	if is_zero_approx(lean):
		return target
	var angle := -lean * lean_direction * deg_to_rad(lean_max_degrees) * share
	var forward := animated_skel.global_transform.basis.z
	var right := forward.cross(Vector3.UP).normalized()
	if right.is_zero_approx():
		return target
	return Transform3D(Basis(right, angle) * target.basis, target.origin)


## Configura el TwoBoneIK3D. El nodo SOLO exporta `setting_count`: las cadenas se
## setean por metodos, no hay propiedades serializables en el .tscn, por eso va en
## codigo y no como data de escena.
## Cadena del brazo confirmada leyendo el GLB: LArm1 -> LArm2 -> LArm2.001
## (hombro -> brazo -> antebrazo -> mano).
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
		{ "root": "LArm1", "mid": "LArm2", "end": "LArm2.001", "t": hand_target_l, "p": ik_pole_target_l },
		{ "root": "RArm1", "mid": "RArm2", "end": "RArm2.001", "t": hand_target_r, "p": ik_pole_target_r },
	]
	for i in chains.size():
		var c: Dictionary = chains[i]
		arm_ik.set_root_bone_name(i, c["root"])
		arm_ik.set_middle_bone_name(i, c["mid"])
		arm_ik.set_end_bone_name(i, c["end"])
		# get_path_to() y no get_path(): el NodePath debe ser relativo al nodo que
		# lo guarda, o se rompe si el ragdoll se instancia dentro de otra escena.
		arm_ik.set_target_node(i, arm_ik.get_path_to(c["t"]))
		# Polo POR BRAZO. Con un solo polo los dos codos caen en el mismo plano.
		if c["p"] != null:
			arm_ik.set_pole_node(i, arm_ik.get_path_to(c["p"]))
		else:
			push_warning("[ragdoll_character] falta el polo de la cadena %d" % i)
	_l_arm_id = animated_skel.find_bone("LArm1")
	_r_arm_id = animated_skel.find_bone("RArm1")
	_l_hand_id = animated_skel.find_bone("LArm2.001")
	_r_hand_id = animated_skel.find_bone("RArm2.001")
	arm_ik.modification_processed.connect(_on_ik_modification)
	print("[ragdoll_character] ArmIK OK: %d cadenas | bone ids L=%d R=%d | brazo=%.3fm alcance=%.3fm | polos L=%s R=%s" % [
		arm_ik.setting_count, _l_arm_id, _r_arm_id, _rest_arm_len, arm_reach,
		str(ik_pole_target_l != null), str(ik_pole_target_r != null)])


## Mide el rig y coloca el polo de cada codo.
## OJO (medido 2026-09-10): el reposo del modelo es una T-POSE perfecta y las
## longitudes de hueso son DESIGUALES (brazo 0.638 + antebrazo 0.760), asi que el
## "codo desviado del punto medio" da (-1,0,0) por puro artefacto aritmetico:
## NO sirve como direccion de codo. Por eso el polo va a mano (ik_pole_offset,
## relativo al HOMBRO) y la X se espeja para el derecho.
## El alcance, en cambio, SI se mide (nada de numeros inventados: un alcance corto
## no acorta el brazo, lo pliega entero).
func _place_poles_and_measure() -> void:
	var l_sh: Vector3 = animated_skel.get_bone_global_rest(animated_skel.find_bone("LArm1")).origin
	var l_wr: Vector3 = animated_skel.get_bone_global_rest(animated_skel.find_bone("LArm2.001")).origin
	var r_sh: Vector3 = animated_skel.get_bone_global_rest(animated_skel.find_bone("RArm1")).origin
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


## El doc de SkeletonModifier3D es explicito: la pose MODIFICADA por un modifier
## solo es valida EN EL MOMENTO en que se emite `modification_processed`. Fuera de
## esa señal, Skeleton3D devuelve la pose SIN modificar (la que dejo el
## AnimationMixer). Por eso cacheamos aca y el spring PD lee del cache: sin esto
## el IK calcula perfecto pero el cuerpo fisico nunca lo ve (verificado:
## errSig=0.000 con el IK, err=0.848 leyendo fuera).
func _on_ik_modification() -> void:
	_ik_mods += 1
	if ragdoll_mode:
		return
	for b: PhysicalBone3D in physics_bones:
		var id := b.get_bone_id()
		_anim_pose_cache[id] = animated_skel.get_bone_global_pose(id)


## Mueve los HandTarget del IK al punto que el jugador esta mirando.
## Se calcula en el espacio del esqueleto ANIMADO (que no se traslada): se toma
## su hombro y se avanza en la direccion de la camara el alcance pedido. El
## alcance es el del objeto apuntado, topeado al largo del brazo: si esta mas
## lejos, la mano apunta pero NO llega, y sin contacto no hay interaccion.
func update_hand_targets(world_point: Vector3, _has_target: bool) -> void:
	if arm_ik == null or hand_target_l == null or hand_target_r == null:
		return
	if _l_arm_id < 0 or _r_arm_id < 0:
		return
	# CLICK vs IDLE (pedido del General):
	#   sin click -> influence 0: el IK NO escribe pose y los brazos siguen la
	#                ANIMACION (idle). No se estiran ni apuntan a nada.
	#   con click -> influence 1: el brazo apretado se ESTIRA hacia el puntero
	#                (haya o no impacto); el otro queda donde esta (su objetivo es
	#                su propia mano, asi el IK no lo mueve).
	# El influence se INTERPOLA para que soltar no de un tiron.
	var clicked := active_arm_left or active_arm_right
	var want := ik_influence if clicked else 0.0
	var dt := get_physics_process_delta_time()
	arm_ik.set_influence(move_toward(arm_ik.get_influence(), want, ik_influence_fade_speed * dt))
	if not clicked:
		return
	var b := animated_skel.global_transform
	var inv := b.basis.inverse()
	var fwd: Vector3 = (inv * (-camera_pivot.global_transform.basis.z)).normalized()
	# Distancia al objetivo con tope = alcance REAL del brazo. Si el rayo no golpeo,
	# el puntero igual manda un punto al final del alcance (interact_range), asi que
	# la mano se estira hacia ahi en vez de quedarse quieta.
	var reach := clampf(camera_pivot.global_position.distance_to(world_point), 0.0, arm_reach)
	var drop := Vector3(0.0, -hand_drop, 0.0)
	var l_root: Vector3 = animated_skel.get_bone_global_pose(_l_arm_id).origin
	var r_root: Vector3 = animated_skel.get_bone_global_pose(_r_arm_id).origin
	var l_goal: Vector3 = l_root + fwd * reach + drop
	var r_goal: Vector3 = r_root + fwd * reach + drop
	# Brazo NO apretado: su objetivo queda donde YA esta la mano, asi el IK no lo
	# mueve. De este modo solo alcanza el brazo del click.
	if not active_arm_left and _l_hand_id >= 0:
		l_goal = animated_skel.get_bone_global_pose(_l_hand_id).origin
	if not active_arm_right and _r_hand_id >= 0:
		r_goal = animated_skel.get_bone_global_pose(_r_hand_id).origin
	hand_target_l.global_position = b * l_goal
	hand_target_r.global_position = b * r_goal
