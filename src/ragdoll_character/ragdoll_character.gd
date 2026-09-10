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


# 1a persona: recorte de la geometria propia alrededor de la camara. Evita ver
# el interior del craneo y limpia el hocico de las fursonas. El ShaderMaterial
# lo asigna el .tscn como material_override; aca solo se muta su parametro.
# Mantenerlo LO MAS CHICO POSIBLE: cuanto mas lejos del craneo este la camara
# (`head_distance` en ragdoll_camera.gd), menos geometria tiene que borrar. Solo
# subirlo lo justo para que no se cuele el hocico en pantalla.
@export var fp_clip_radius := 0.15


# Inclinacion del torso segun el pitch de la camara. Es una ENTRADA DE CONTROL
# al spring, no una animacion por codigo.
@export var lean_max_degrees := 12.0
@export var lean_reference_degrees := 45.0
## Si el cuerpo se inclina al reves (mirar abajo lo tira para atras), poner -1.
@export var lean_direction := 1.0


# Direccion del blend de agarre de los brazos (grab_lower .. grab_upper) segun
# el pitch de la camara.
@export var grab_dir_reference_degrees := 45.0


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
	if Input.is_action_just_pressed("ragdoll"): ragdoll_mode = bool(1-int(ragdoll_mode)) # toggle ragdoll mode

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
			if not active_arm_left and b.name.contains("LArm"): continue # only rotated the arms if its activated
			if not active_arm_right and b.name.contains("RArm"): continue # only rotated the arms if its activated
			var target_transform: Transform3D = animated_skel.global_transform * animated_skel.get_bone_global_pose(b.get_bone_id())
			target_transform = _apply_body_lean(b, target_transform)
			var current_transform: Transform3D = physical_skel.global_transform * physical_skel.get_bone_global_pose(b.get_bone_id())
			var rotation_difference: Basis = (target_transform.basis * current_transform.basis.inverse())
			var torque = hookes_law(rotation_difference.get_euler(), b.angular_velocity, angular_spring_stiffness, angular_spring_damping)
			torque = torque.limit_length(max_angular_force)
			
			b.angular_velocity += torque * current_delta


## Inclinacion del torso por pitch de camara: mirar abajo -> el personaje se
## inclina hacia adelante; mirar arriba -> hacia atras. El target del master se
## rota y la fisica hace el resto: es una ENTRADA DE CONTROL al spring, no una
## animacion por codigo (el cuerpo conserva su peso y puede ser detenido por una
## pared).
func _apply_body_lean(bone: PhysicalBone3D, target: Transform3D) -> Transform3D:
	if lean_max_degrees <= 0.0 or not bone.name.contains("Body"):
		return target
	var lean := clampf(camera_pivot.rotation.x / deg_to_rad(lean_reference_degrees), -1.0, 1.0)
	if is_zero_approx(lean):
		return target
	var angle := -lean * lean_direction * deg_to_rad(lean_max_degrees)
	var forward := animated_skel.global_transform.basis.z
	var right := forward.cross(Vector3.UP).normalized()
	if right.is_zero_approx():
		return target
	return Transform3D(Basis(right, angle) * target.basis, target.origin)
