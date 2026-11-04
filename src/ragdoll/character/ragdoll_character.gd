extends Node3D
class_name RagdollCharacter
## PERSONAJE RAGDOLL: la raiz que COMPONE los componentes de la libreria
## (`src/ragdoll/`) y a la vez lo que es de este personaje concreto: el
## input, el movimiento y el agarre.
##
## La idea de la libreria es que todo lo que es "sistema" (el esqueleto
## fisico, el motor, la animacion, la mirada, el IK, el recorte de 1a
## persona y el balance) viva en componentes que se pueden reusar con
## CUALQUIER rig. Aqui solo queda lo que es del juego.
##
## Montar un personaje nuevo = un `RagdollRig` (que genera el `RigForge`)
## + esta escena. Nada de tocar codigo.

## La salud llega a 0 → la muerte es local y cosmetica (decision D16 de la
## guia de red): se suelta el ragdoll y se emite `murio()`. Aún no hay
## fuentes de dano en el juego; es el gancho para cuando existan.
signal murio

## === NODOS DE LA ESCENA =================================================

@export var rig_config: RagdollRig
@export var camera_pivot: Node3D
@export var physical_skel: Skeleton3D
@export var animated_skel: Skeleton3D
@export var animation_player: AnimationPlayer
@export var animation_tree: AnimationTree
@export var hand_target_l: Node3D
@export var hand_target_r: Node3D
@export var jump_timer: Timer
@export var grab_joint_left: PinJoint3D
@export var grab_joint_right: PinJoint3D

## === COMPONENTES (se crean en runtime) ==================================
##
## Se crean aqui y no en la escena para que CUALQUIER escena que tenga el
## script funcione: la libreria se monta sola.

var skeleton: RagdollSkeleton       ## Cuerpos fisicos y simulator.
var motor: RagdollMotor             ## El PD que lleva los cuerpos a la pose.
var mirror: PoseMirror              ## Copia las poses de la fisica al mesh.
var driver: AnimationDriver         ## AnimationPlayer + AnimationTree.
var head_look: HeadLook             ## La cabeza que sigue a la camara.
var arm_ik: ArmIK                   ## Los brazos que se estiran al puntero.
var fp_clip: FpClip                 ## El recorte de 1a persona.
var balance: BalanceController      ## El equilibrio (upright + centro de masas).

## === ESTADISTICAS (Yuki Romero: Velocidad Baja · Stamina 50 · Salud 300)
## Los valores viven en `stats_shiba.tres`; la escena la asigna.
@export var stats: CharacterStats

var current_stamina := 0.0
var health := 0.0
var is_sprinting := false

## === MOVIMIENTO ========================================================
const JUMP_STRENGTH := 70.0
const SPEED := 50.0
const DAMPING := 0.9
## Escala de velocidad horizontal dentro del agua.
const NADO_ESCALA := 0.5
## Empuje vertical de nado en m/s2.
const NADO_EMPUJE := 12.0
## Impulso UNICO de salida del agua (m/s hacia arriba).
const SALIDA_AGUA := 8.0

## El cuerpo sigue a la camara (como el script ORIGINAL y la
## referencia) o mira hacia donde camina.
##
## Con true (original): `animated_skel.rotation.y = camera_pivot.rotation.y`.
## OJO: el modelo mira a +Z y la camara a -Z, pero el nodo Animated lleva
## un giro de 180 grados en Y, asi que con esta linea el modelo mira
## EXACTAMENTE donde mira la camara (medido: dot(frente, cam_fwd) = 1.000).
@export var body_follows_camera := true
## Velocidad de giro del cuerpo (rad/s).
@export var body_turn_speed := 7.0

## === MOTOR (ganos del servo) ===========================================
##
## La rigidez y el amortiguamiento NO se configuran aqui: los gobierna el
## `RagdollMotor` (una sola fuente).
##
## OJO — el tope de velocidad angular es de DECENAS de rad/s, no de 6: con
## 6 el servo no puede mover un hueso grande en un frame y el personaje se
## ve "aguado" (los brazos y el pecho parece que no siguen al ragdoll).
@export var max_angular_speed := 40.0
## Escala de los brazos que NO estan agarrando (1 = igual que el resto).
@export var arm_spring_scale := 0.5
## El controlador de balance (upright + centro de masas + muelle de
## altura) esta DESACTIVADO por defecto: la ley del servo (objetivo
## absoluto en mundo) ya mantiene al personaje de pie, y el balance le
## devolvia a la pelvis el par de todos los hijos: la ponia a girar a
## 40 rad/s y el personaje se volcaba (medido).
@export var balance_enabled := false

## === MIRADA DE CABEZA ===================================================
@export var head_look_enabled := false
@export var head_yaw_max_degrees := 55.0
@export var head_pitch_max_degrees := 30.0
@export var head_look_smoothing := 0.12

## === LEAN DEL TORSO ====================================================
@export var lean_max_degrees := 2.0
@export var lean_reference_degrees := 45.0
@export var lean_direction := 1.0
@export var lean_share_body := 0.75
@export var lean_share_head := 0.25

## === IK DE BRAZOS ======================================================
@export var ik_enabled := true
@export var ik_pole_offset := Vector3(0.30, -0.50, -0.30)
@export var ik_influence := 1.0
@export var ik_influence_fade_speed := 4.0
@export var arm_reach_auto := true
@export var arm_reach_margin := 0.92

## === RECORTE DE 1a PERSONA ============================================
@export var fp_clip_radius := 0.20
@export var fp_clip_meshes := PackedStringArray()

## === ESTADO ===========================================================
var ragdoll_mode := false
var walking := false
var is_on_floor := false
var can_jump := true
var active_arm_left := false
var active_arm_right := false
var grabbing_arm_left := false
var grabbing_arm_right := false
var grabbed_object: Node3D = null

var agua: WaterBody = null
var oxigeno: Oxygen = null
var _cabeza_fisica: Node3D = null
var _salto_evento := false
var _alineado := false
var _ik_mods := 0
var on_floor_left: ShapeCast3D = null
var on_floor_right: ShapeCast3D = null
var l_grab_area: Area3D = null
var r_grab_area: Area3D = null
var physical_bone_body: PhysicalBone3D = null
## Constante de calibracion del rumbo (ver `_calibrar_rumbo`).
var _yaw_gamma := 0.0


func _ready() -> void:
	_resolver_refs()
	_crear_componentes()
	_conectar_senales()
	_resolver_agua()
	_inicializar_stats()


## Stats del personaje (salud y stamina). Sin `stats` en la escena, se usan
## defaults de `CharacterStats` (no el del Shiba: hay que asignar la de cada
## personaje).
func _inicializar_stats() -> void:
	if stats == null:
		stats = CharacterStats.new()
	current_stamina = stats.max_stamina
	health = stats.max_health
	# Igual que Iza: el juego es de raton capturado; Esc lo suelta (ver
	# `_input`, accion `exit_camera`).
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Dano: baja la salud y, al llegar a 0, suelta el ragdoll.
func take_damage(amount: float) -> void:
	if health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	if health == 0.0:
		ragdoll_mode = true
		murio.emit()


## === ALTURAS Y VELOCIDADES (telemetria y pruebas) ======================
func altura_cuerpo() -> float:
	if physical_bone_body != null:
		return RagdollMotor.body_transform(physical_bone_body).origin.y
	return global_position.y


func velocidad_cuerpo() -> Vector3:
	if physical_bone_body != null:
		return RagdollMotor.body_linear_velocity(physical_bone_body)
	return Vector3.ZERO


## === MONTAJE ============================================================

## Altura del SUELO que hay debajo de la pelvis (raycast hacia abajo).
## INF si no hay suelo debajo.
##
## Se usa para anclar la altura objetivo del balance (ver
## `BalanceController.capture_target`): anclar al PIE fallaba cuando el
## personaje caia de espaldas (los pies quedan altos y el balance nunca
## se activaba, medido: el ragdoll se quedaba tumbado boca arriba).
func _suelo_bajo_pelvis() -> float:
	if physical_bone_body == null:
		return INF
	var mundo := get_world_3d()
	if mundo == null:
		return INF
	var p := RagdollMotor.body_transform(physical_bone_body).origin
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 3.0)
	q.collision_mask = 1  # solo el mundo
	q.collide_with_areas = false
	var hit := mundo.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return INF
	var pos: Vector3 = hit["position"]
	return pos.y


func _resolver_refs() -> void:
	if physical_skel == null:
		physical_skel = _buscar_esqueleto("Physical")
	if animated_skel == null:
		animated_skel = _buscar_esqueleto("Animated")
	if camera_pivot == null:
		camera_pivot = get_node_or_null("CameraPivot") as Node3D
	if animation_tree == null:
		animation_tree = _buscar_de_clase(self, "AnimationTree") as AnimationTree
	if animation_player == null and animation_tree != null:
		# OJO: el modelo (.glb) trae SU propio AnimationPlayer con los clips
		# importados. El que mueve la escena es el que apunta el
		# AnimationTree, asi que se pregunta ahi y no "por nombre".
		animation_player = animation_tree.get_node_or_null(
			animation_tree.anim_player) as AnimationPlayer
	if animation_player == null:
		animation_player = _buscar_de_clase(self, "AnimationPlayer") as AnimationPlayer
	if hand_target_l == null:
		hand_target_l = get_node_or_null("HandTargetL")
	if hand_target_r == null:
		hand_target_r = get_node_or_null("HandTargetR")
	if jump_timer == null:
		jump_timer = get_node_or_null("JumpTimer") as Timer
	if grab_joint_left == null:
		grab_joint_left = get_node_or_null("GrabJointLeft") as PinJoint3D
	if grab_joint_right == null:
		grab_joint_right = get_node_or_null("GrabJointRight") as PinJoint3D
	if rig_config == null:
		push_warning("[RagdollCharacter] sin rig_config: el personaje no se puede montar")


## Crea los componentes de la libreria y los monta.
func _crear_componentes() -> void:
	# --- Componentes ------------------------------------------------------
	# OJO: se instancian aqui (y no con ClassDB.instantiate, que no puede
	# crear scripts GDScript) para que el TIPO se conserve: si se crearan
	# como Node generico, las variables tipadas de abajo no los aceptarian.
	skeleton = RagdollSkeleton.new()
	skeleton.name = "RagdollSkeleton"
	add_child(skeleton)
	motor = RagdollMotor.new()
	motor.name = "RagdollMotor"
	add_child(motor)
	mirror = PoseMirror.new()
	mirror.name = "PoseMirror"
	add_child(mirror)
	driver = AnimationDriver.new()
	driver.name = "AnimationDriver"
	add_child(driver)
	head_look = HeadLook.new()
	head_look.name = "HeadLook"
	add_child(head_look)
	arm_ik = ArmIK.new()
	arm_ik.name = "ArmIK"
	add_child(arm_ik)
	fp_clip = FpClip.new()
	fp_clip.name = "FpClip"
	add_child(fp_clip)
	balance = BalanceController.new()
	balance.name = "BalanceController"
	add_child(balance)

	# --- Motor ---------------------------------------------------------
	# La rigidez y el amortiguamiento los gobierna el MOTOR (una sola
	# fuente): son los del servo de velocidad con objetivo absoluto.
	motor.max_angular_speed = max_angular_speed
	motor.arm_spring_scale = arm_spring_scale

	# --- Mirada --------------------------------------------------------
	head_look.enabled = head_look_enabled
	head_look.yaw_max_degrees = head_yaw_max_degrees
	head_look.pitch_max_degrees = head_pitch_max_degrees
	head_look.smoothing = head_look_smoothing

	# --- IK ------------------------------------------------------------
	arm_ik.enabled = ik_enabled
	arm_ik.pole_offset = ik_pole_offset
	arm_ik.influence = ik_influence
	arm_ik.influence_fade_speed = ik_influence_fade_speed
	arm_ik.reach_auto = arm_reach_auto
	arm_ik.reach_margin = arm_reach_margin

	# --- Recorte -------------------------------------------------------
	fp_clip.radius = fp_clip_radius

	# --- Esqueleto fisico ----------------------------------------------
	skeleton.setup(rig_config, physical_skel)
	physical_bone_body = skeleton.body_bone()
	if physical_bone_body == null and rig_config != null:
		physical_bone_body = skeleton.find_in_skeleton(rig_config.body_bone_name)
	_resolver_colisiones_de_suelo()

	# --- Animacion ------------------------------------------------------
	driver.setup(rig_config, animation_player, animation_tree, animated_skel,
		_ruta_del_esqueleto_animado(), self)
	head_look.setup(rig_config, animated_skel, camera_pivot)
	arm_ik.setup(rig_config, animated_skel, camera_pivot, hand_target_l, hand_target_r)

	# --- Recorte de 1a persona ------------------------------------------
	fp_clip.collect_meshes(physical_skel)
	fp_clip.setup()
	fp_clip.set_active(true)

	# --- Camara ---------------------------------------------------------
	_resolver_camara()
	_calibrar_rumbo()
	print("[RagdollCharacter] READY | huesos=%d | cuerpo=%s | config=%s" % [
		skeleton.bones.size(),
		str(rig_config.body_bone_name if rig_config != null else "-"),
		str(rig_config.resource_path if rig_config != null else "-")])


func _crear_componente(clase: String) -> Node:
	var n := Node.new()
	n.name = clase
	add_child(n)
	return n




## Conexiones de senales. Se hacen en CODIGO, no en la escena: asi todos los
## rigs funcionan igual y no dependemos de que la escena haya guardado las
## conexiones (las que van desde un nodo DENTRO de una instancia editable no
## siempre se serializan, y sin `skeleton_updated` el PD no corre).
func _conectar_senales() -> void:
	# OJO: NO se conecta a `skeleton_updated` del esqueleto fisico. Esa senal
	# solo se emite cuando las poses del esqueleto CAMBIAN: como las escribe
	# el propio mirror, la cadena se rompe (si el esqueleto no cambia, la
	# senal no vuelve a dispararse y el PD se congela). El PD corre en
	# `_physics_process` (ver `_actualizar_pd`).
	if l_grab_area != null and not l_grab_area.body_entered.is_connected(_on_l_grab_area_body_entered):
		l_grab_area.body_entered.connect(_on_l_grab_area_body_entered)
	if r_grab_area != null and not r_grab_area.body_entered.is_connected(_on_r_grab_area_body_entered):
		r_grab_area.body_entered.connect(_on_r_grab_area_body_entered)
	if jump_timer != null and not jump_timer.timeout.is_connected(_on_jump_timer_timeout):
		jump_timer.timeout.connect(_on_jump_timer_timeout)


func _resolver_agua() -> void:
	# El WaterBody es HIJO, asi que su _ready ya corrio y no encontro cuerpo
	# (la raiz es Node3D, no un PhysicsBody3D). El cuerpo real es el hueso
	# "cuerpo", recien resuelto: se le entrega aqui.
	agua = WaterBody.buscar_en(self)
	if agua != null and physical_bone_body != null:
		agua.fijar_cuerpo(physical_bone_body)
		# TODOS los huesos flotan, no solo el Body: con 21 kg repartidos en
		# 10 cuerpos, dejar 11 kg sin empuje hunde al personaje entero.
		agua.fijar_cuerpos_extra(skeleton.bones)
	oxigeno = Oxygen.buscar_en(self)
	if physical_skel != null and rig_config != null:
		_cabeza_fisica = skeleton.find_in_skeleton(rig_config.head_bone_name)


## === BUCLE ==============================================================
func _input(event: InputEvent) -> void:
	# Esc suelta/captura el raton (accion `exit_camera`).
	if event.is_action_pressed("exit_camera"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return
	# Captura del pulso de salto por DOS caminos: el evento real (fiable en
	# gameplay) y is_action_just_pressed (para input sintetizado).
	if event.is_action_pressed("jump") and not event.is_echo():
		_salto_evento = true
	if Input.is_action_just_pressed("jump"):
		_salto_evento = true
	if Input.is_action_just_pressed("ragdoll"):
		ragdoll_mode = not ragdoll_mode
		print("[RagdollCharacter] MODO RAGDOLL = %s" % ragdoll_mode)
	active_arm_left = Input.is_action_pressed("grab_left")
	active_arm_right = Input.is_action_pressed("grab_right")
	if (not active_arm_left and grabbing_arm_left) or ragdoll_mode:
		grabbing_arm_left = false
		if grab_joint_left:
			grab_joint_left.node_a = NodePath()
	if (not active_arm_right and grabbing_arm_right) or ragdoll_mode:
		grabbing_arm_right = false
		if grab_joint_right:
			grab_joint_right.node_a = NodePath()


func _physics_process(delta: float) -> void:
	if ragdoll_mode:
		return
	# El estado de los botones tambien se sondea aqui (y no solo en
	# _input): el input sintetico (Input.action_press) no dispara
	# eventos, asi que con el solo _input los brazos no se estiraban
	# nunca (medido).
	active_arm_left = Input.is_action_pressed("grab_left")
	active_arm_right = Input.is_action_pressed("grab_right")
	walking = false
	var dir := _direccion_de_movimiento()
	# Sprint: gasta stamina; si se acaba, vuelve a paso de tortuga.
	is_sprinting = Input.is_action_pressed("sprint") and current_stamina > 0.0 \
		and dir.length_squared() > 0.0
	if is_sprinting:
		current_stamina = maxf(current_stamina - stats.sprint_stamina_cost * delta, 0.0)
	else:
		current_stamina = minf(current_stamina + stats.stamina_regen_rate * delta,
			stats.max_stamina)
	if physical_bone_body != null:
		_mover_cuerpo(dir, delta)
	_calcular_suelo()
	_actualizar_agua()
	# La altura objetivo del balance se captura EN EL PRIMER CONTACTO CON
	# EL SUELO (no al aparecer): el objetivo es la altura de pie sobre el
	# suelo real. Se ancla al SUELO que hay DEBAJO de la pelvis (raycast),
	# no a la posicion de los pies: si el personaje se estrella de espaldas
	# los pies quedan altos y la captura nunca ocurriria (el balance entero
	# se quedaria apagado y el ragdoll se quedaria tumbado, medido).
	if balance != null and not balance.is_captured() \
			and animated_skel != null and rig_config != null:
		var suelo_y := _suelo_bajo_pelvis()
		if not is_inf(suelo_y):
			var pelvis_id := animated_skel.find_bone(rig_config.body_bone_name)
			var pie_ids: Array[int] = [
				animated_skel.find_bone(rig_config.on_floor_left_bone_name),
				animated_skel.find_bone(rig_config.on_floor_right_bone_name)]
			balance.capture_target(physical_bone_body, animated_skel,
				pelvis_id, pie_ids, suelo_y)
	if Input.is_action_pressed("jump") and is_on_floor and can_jump and physical_bone_body:
		physical_bone_body.linear_velocity.y += JUMP_STRENGTH
		current_stamina = maxf(current_stamina - stats.jump_stamina_cost, 0.0)
		if jump_timer:
			jump_timer.start()
		can_jump = false
	driver.set_walking(walking)
	_actualizar_rumbo_del_cuerpo(dir, delta)
	head_look.update(delta)
	# El PD (y el espejo de las poses) van en el tick de FISICA: es donde
	# se aplican los torques y donde se lee el estado de los cuerpos.
	_actualizar_pd()
	# Primera vez: los cuerpos se colocan en la pose de la ANIMACION.
	#
	# Si nacen en la pose de reposo (T), el spring tiene que girarlos 90
	# grados de golpe: con el tope de torque tarda una eternidad y sin tope
	# los dispara por los aires (medido: caia 3 m en 6 frames). Colocarlos
	# ya en la pose del clip deja al spring solo MANTENERLA.
	if not _alineado and driver.animation_started():
		_alineado = true
		_alinear_con_la_animacion()
		# Y se pone DE PIE sobre el suelo: sin esto el personaje nace
		# flotando medio metro (la pose del clip lo deja por encima de su
		# origen) y el golpe contra el suelo lo tumba (medido).
		_colocar_en_el_suelo()
		mirror.capture_offset(physical_skel, physical_bone_body)


## Direccion de movimiento en el espacio de la CAMARA (lo que espera un
## jugador de FPS: el input no se descuadra si el cuerpo mira a otro lado).
func _direccion_de_movimiento() -> Vector3:
	var cam_basis := Basis.IDENTITY
	if camera_pivot:
		cam_basis = camera_pivot.global_transform.basis
	var cam_fwd := -cam_basis.z
	var cam_right := cam_fwd.cross(Vector3.UP).normalized()
	if cam_right.is_zero_approx():
		cam_right = cam_basis.x
	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		dir += cam_fwd
		walking = true
	if Input.is_action_pressed("move_left"):
		dir -= cam_right
		walking = true
	if Input.is_action_pressed("move_right"):
		dir += cam_right
		walking = true
	if Input.is_action_pressed("move_backward"):
		dir -= cam_fwd
		walking = true
	return dir.normalized()


func _mover_cuerpo(dir: Vector3, delta: float) -> void:
	# En el agua se nada: mas lento, y el arrastre del WaterBody (hijo,
	# corre DESPUES de este script) se encarga del resto.
	var en_agua := agua != null and agua.sumergido
	# Yuki es de Velocidad Baja: el multiplicador va respecto a 5 m/s (que
	# es el walk_speed neutro de `CharacterStats`).
	var vel_mult := (stats.sprint_speed if is_sprinting else stats.walk_speed) / 5.0
	var vel := SPEED * (NADO_ESCALA if en_agua else 1.0) * vel_mult
	# La velocidad se lee del SERVIDOR de fisica: la del nodo no se actualiza
	# en este motor.
	var v := RagdollMotor.body_linear_velocity(physical_bone_body)
	v += dir * vel * delta
	v *= Vector3(DAMPING, 1, DAMPING)
	physical_bone_body.linear_velocity = v
	if not en_agua:
		return
	# Salida del agua: `jump` con la cabeza FUERA da un impulso UNICO hacia
	# arriba. Sin esto solo flotarias (el empuje sostenido topa en ~3 m/s
	# por el arrastre y nunca sales del agua).
	var pulso := _salto_evento or Input.is_action_just_pressed("jump")
	if pulso and not agua.cabeza_sumergida:
		# A TODOS los huesos, no solo al Body: las articulaciones se comen
		# el impulso si los otros se quedan quietos.
		agua.impulso_vertical(SALIDA_AGUA)
	if Input.is_action_pressed("jump"):
		physical_bone_body.linear_velocity.y += NADO_EMPUJE * delta
	elif Input.is_action_pressed("crouch"):
		physical_bone_body.linear_velocity.y -= NADO_EMPUJE * delta
	# El pulso NO se borra a ciegas: si un tick cae con la cabeza hundida
	# (ola a la baja) se lo comia y el salto no hacia nada. Vive hasta
	# usarse, hasta soltar la tecla, o hasta un tick FUERA del agua.
	if _salto_evento:
		if en_agua and not agua.cabeza_sumergida:
			_salto_evento = false
		elif not en_agua or not Input.is_action_pressed("jump"):
			_salto_evento = false
	# Ctrl = BUCEAR de verdad: anula el empuje.
	agua.empuje_suprimido = en_agua and Input.is_action_pressed("crouch")


func _calcular_suelo() -> void:
	is_on_floor = false
	if on_floor_left and on_floor_left.is_colliding():
		for i in on_floor_left.get_collision_count():
			if on_floor_left.get_collision_normal(i).y > 0.5:
				is_on_floor = true
				break
	if not is_on_floor and on_floor_right and on_floor_right.is_colliding():
		for i in on_floor_right.get_collision_count():
			if on_floor_right.get_collision_normal(i).y > 0.5:
				is_on_floor = true
				break


func _actualizar_agua() -> void:
	if agua == null:
		return
	# El WaterBody (hijo, corre despues) necesita saberlo: sin esto, el
	# ragdoll apoyado en el fondo del mar flotaria hacia arriba.
	agua.apoyado = is_on_floor
	# El punto de respiracion sigue al hueso de cabeza en cada pose, MEDIO
	# METRO por encima de su origen: el origen del hueso es el centro de su
	# capsula y en flotacion ese centro cae bajo el agua.
	if _cabeza_fisica != null and physical_bone_body != null:
		var cabeza_pos := _cabeza_fisica.global_position + Vector3.UP * 0.45
		agua.fijar_cabeza(physical_bone_body.global_transform.affine_inverse() * cabeza_pos)


## Rumbo del cuerpo.
##
## Modelo viejo (body_follows_camera): el cuerpo va pegado a la camara.
## Modelo natural (false): el cuerpo mira a donde camina y la CABEZA es la
## que sigue al raton (ver HeadLook).
func _actualizar_rumbo_del_cuerpo(dir: Vector3, delta: float) -> void:
	if camera_pivot == null or animated_skel == null:
		return
	if body_follows_camera:
		animated_skel.rotation.y = camera_pivot.rotation.y
		return
	animated_skel.rotation.y = _calcular_yaw_del_cuerpo(dir, walking, delta)


## Yaw objetivo del cuerpo: el de la direccion de marcha, con inercia.
##
## OJO — el yaw del esqueleto ANIMADO va AL REVES (medido: el personaje
## caminaba de espaldas, `dot(frente_del_modelo, camara) = -1`).
##
## El nodo `Animated` lleva un giro de 180 grados en Y (el modelo se
## importa con el frente en +Z y el juego mira hacia -Z), asi que el yaw
## GLOBAL del esqueleto es `gamma - rotation.y`, no `rotation.y`. La
## constante `gamma` se mide de la escena al montar (`_calibrar_rumbo`),
## para que elrumbo sea correcto en CUALQUIER rig, tenga el giro que tenga.
func _calcular_yaw_del_cuerpo(dir: Vector3, moving: bool, delta: float) -> float:
	var actual := animated_skel.rotation.y
	if not moving or dir.is_zero_approx():
		return actual
	# El frente del modelo es su +Z local: el yaw global que lo apunta a
	# `dir` es `atan2(dir.x, dir.z)`.
	var objetivo := _yaw_gamma - atan2(dir.x, dir.z)
	var d := wrapf(objetivo - actual, -PI, PI)
	return actual + clampf(d, -body_turn_speed * delta, body_turn_speed * delta)


## Mide la constante de rumbo del esqueleto animado.
##
## La relacion entre el yaw LOCAL (`rotation.y`) y el yaw GLOBAL es
## `global = gamma - local` (el signo lo pone el giro de 180 grados del
## nodo padre). Se mide con el esqueleto como esta y se aplica a todos los
## rigs.
func _calibrar_rumbo() -> void:
	if animated_skel == null:
		return
	var b := animated_skel.global_transform.basis
	# El yaw global se lee del eje Z de la base (una rotacion pura en Y).
	var yaw_global := atan2(b.z.x, b.z.z)
	_yaw_gamma = yaw_global + animated_skel.rotation.y


## === EL PD ==============================================================
##
## Corre en `_physics_process` (NO en la senal `skeleton_updated` del
## esqueleto): esa senal solo se emite cuando las poses del esqueleto
## CAMBIAN, asi que si nadie las escribe no vuelve a dispararse y el PD se
## queda congelado (medido: la malla se quedaba en la pose de reposo del
## modelo y el personaje no andaba). Ademas, aplicar torque en el frame y no
## en el tick de fisica descuadra el PD de la simulacion.
func _actualizar_pd() -> void:
	if ragdoll_mode or skeleton == null or driver == null:
		return
	var objetivos := _calcular_objetivos()
	# El balance (upright + centro de masas + muelle de altura) esta
	# DESACTIVADO por defecto: la ley del servo ya mantiene al personaje
	# de pie y el balance le devolvia a la pelvis el par de todos los
	# hijos (medido: la pelvis giraba a 40 rad/s y el personaje se
	# volcaba). El PD pone la pose; el balance solo estorba.
	if balance_enabled and balance != null:
		balance.apply(skeleton.bones, physical_bone_body, rig_config, _pies())
	motor.drive(skeleton.bones, objetivos, _grupos(), get_physics_process_delta_time(),
		_ganancias(), physical_skel)
	mirror.mirror(physical_skel, animated_skel, skeleton.bones, physical_bone_body)


## Pose objetivo de cada cuerpo: la de la ANIMACION (con el IK si esta
## activo) mas el lean y la mirada de cabeza.
func _calcular_objetivos() -> Dictionary:
	var out := {}
	for b in skeleton.bones:
		var id := b.get_bone_id()
		if id < 0:
			continue
		# TRAMPA: el cache del IK solo se llena cuando el IK escribe (con
		# influencia 0 no se dispara la senal y se queda congelado en la
		# pose del primer frame). Con el IK activo se usa el cache; si no,
		# la pose ACTUAL del esqueleto animado.
		var pose := driver.pose_of(id)
		if arm_ik != null and arm_ik.is_active():
			pose = driver.pose_of(id)
		# OJO — DOS REGLAS DE MARCO (medidas y documentadas por Godot):
		#   * `get_bone_global_pose()` es RELATIVA AL ESQUELETO, no al
		#     mundo ("it is not the actual global/world transform of the
		#     bone", class_skeleton3d).
		#   * El servidor de fisica devuelve transformaciones en MUNDO.
		# Para que el PD compare peras con peras, el objetivo se pasa a
		# MUNDO multiplicando por el transform global del esqueleto
		# animado. (quitar ese `global_transform` fue un error: la base
		# del esqueleto animado es identidad, por eso "tampoco cambiaba
		# nada" — el bug real estaba en el espejo, ver pose_mirror.gd).
		var objetivo: Transform3D = animated_skel.global_transform * pose
		objetivo = _aplicar_lean(b, objetivo)
		objetivo = head_look.apply(b, objetivo)
		out[id] = objetivo
	return out


## Los grupos de cada hueso (para el motor: los brazos se relajan).
func _grupos() -> Dictionary:
	var out := {}
	for b in skeleton.bones:
		out[b.get_bone_id()] = rig_config.group_of(b.bone_name) if rig_config != null else ""
	return out


## La ganancia del PD de cada hueso: un hueso que SOPORTA mas carga (la
## pelvis, el pecho) necesita un PD mas fuerte o la gravedad lo tumba.
func _ganancias() -> Dictionary:
	var out := {}
	if rig_config == null:
		return out
	for b in skeleton.bones:
		var bone := rig_config.bone(b.bone_name)
		out[b.get_bone_id()] = bone.pd_gain if bone != null else 1.0
	return out


func _pies() -> Array[PhysicalBone3D]:
	var out: Array[PhysicalBone3D] = []
	if rig_config == null:
		return out
	var l := skeleton.find_in_skeleton(rig_config.on_floor_left_bone_name)
	var r := skeleton.find_in_skeleton(rig_config.on_floor_right_bone_name)
	if l != null:
		out.append(l)
	if r != null:
		out.append(r)
	return out


## Lean del torso segun pitch de camara. Mira abajo -> inclina adelante.
## Es una ENTRADA DE CONTROL al PD, no una animacion por codigo.
func _aplicar_lean(bone: PhysicalBone3D, target: Transform3D) -> Transform3D:
	if lean_max_degrees <= 0.0 or rig_config == null or animated_skel == null:
		return target
	var share := 0.0
	if String(bone.bone_name).ends_with(rig_config.lean_head_suffix):
		share = lean_share_head
	elif String(bone.bone_name).ends_with(rig_config.lean_body_suffix):
		share = lean_share_body
	if is_zero_approx(share):
		return target
	var pitch := 0.0
	if camera_pivot:
		pitch = camera_pivot.rotation.x
	var deg := clampf(pitch * rad_to_deg(1.0) / lean_reference_degrees, -1.0, 1.0)
	var degs := deg * lean_max_degrees * share * lean_direction
	var body_fwd := animated_skel.global_transform.basis.z
	var body_right := body_fwd.cross(Vector3.UP).normalized()
	if body_right.is_zero_approx():
		return target
	var q := Quaternion(body_right, deg_to_rad(degs))
	return Transform3D(Basis(q) * target.basis, target.origin)


## Coloca los cuerpos fisicos en la pose global del esqueleto ANIMADO.
func _alinear_con_la_animacion() -> void:
	if physical_skel == null or animated_skel == null:
		return
	for b in skeleton.bones:
		var id := b.get_bone_id()
		if id < 0:
			continue
		# OJO (medido) — el cuerpo NO esta en el origen del hueso: esta a
		# MEDIA HUESO, y ese desplazamiento es el `body_offset` (en espacio
		# de hueso). Godot coloca el cuerpo como
		# `esqueleto * pose_del_hueso * body_offset`.
		#
		# Si se colocara en el origen del hueso, la cadena entera naceria
		# COMPRIMIDA (media hueso menos por eslabon) y los cuerpos se
		# solaparian: el solver los separaba a tiros y la pelvis saltaba
		# de 0,83 a 1,36 m en un frame (medido: el personaje se aplastaba
		# contra el suelo y el muelle de altura lo deformaba).
		var off: Transform3D = b.get("body_offset")
		var xf := animated_skel.global_transform \
			* animated_skel.get_bone_global_pose(id) * off
		PhysicsServer3D.body_set_state(b.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
		PhysicsServer3D.body_set_state(b.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(b.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)


## El PUNTERO avisa aqui (duck typing: `root.has_method("update_hand_targets")`).
##
## Sin este metodo el IK de brazos se queda con la influencia por defecto
## (1.0) y los brazos se estiran al puntero SIEMPRE: el personaje camina
## con el brazo derecho levantado y las manos parece que no estan
## conectadas con los brazos (medido).
##
## El  + "clic" +  es el que decide: con el raton pulsado el brazo se estira
## hacia el puntero; sin el, la influencia baja a 0 y los brazos siguen al
## clip (como en el script original).
func update_hand_targets(world_point: Vector3, _has_target: bool) -> void:
	if arm_ik == null:
		return
	arm_ik.update_targets(world_point, active_arm_left, active_arm_right,
		get_physics_process_delta_time())


## === AGARRE ============================================================
func _on_l_grab_area_body_entered(body: Node3D) -> void:
	if body is PhysicsBody3D and body.get_parent() != physical_skel:
		if active_arm_left and not grabbing_arm_left and grab_joint_left:
			grabbing_arm_left = true
			grabbed_object = body
			grab_joint_left.global_position = l_grab_area.global_position
			grab_joint_left.node_a = skeleton.find_in_skeleton(rig_config.grab_bone_left_name).get_path() if rig_config else NodePath()
			grab_joint_left.node_b = body.get_path()


func _on_r_grab_area_body_entered(body: Node3D) -> void:
	if body is PhysicsBody3D and body.get_parent() != physical_skel:
		if active_arm_right and not grabbing_arm_right and grab_joint_right:
			grabbing_arm_right = true
			grabbed_object = body
			grab_joint_right.global_position = r_grab_area.global_position
			grab_joint_right.node_a = skeleton.find_in_skeleton(rig_config.grab_bone_right_name).get_path() if rig_config else NodePath()
			grab_joint_right.node_b = body.get_path()


func _on_jump_timer_timeout() -> void:
	can_jump = true


## === UTILIDADES ========================================================
## Teletransporta el personaje: raiz + TODOS los cuerpos fisicos.
##
## Mover solo la raiz no sirve: los cuerpos se mueven desde el servidor de
## fisica, asi que lo que no se mueva ahi se queda donde estaba. El ancla
## es el HUESO "cuerpo", no la raiz (la raiz no sigue al ragdoll).
func teletransportar(destino: Vector3) -> void:
	var ancla := global_position
	if physical_bone_body != null:
		ancla = RagdollMotor.body_transform(physical_bone_body).origin
	var d := destino - ancla
	if d.length_squared() < 1e-10:
		return
	global_position += d
	for b in skeleton.bones:
		var xf := RagdollMotor.body_transform(b)
		xf.origin += d
		PhysicsServer3D.body_set_state(b.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
		PhysicsServer3D.body_set_state(b.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(b.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)


## Corta toda la velocidad (para pruebas y para frenar al aterrizar).
func parar() -> void:
	if physical_bone_body == null:
		return
	physical_bone_body.linear_velocity = Vector3.ZERO
	physical_bone_body.angular_velocity = Vector3.ZERO


## Coloca al personaje DE PIE sobre el suelo.
##
## MEDIDO: la pose de la ANIMACION deja al personaje 0,5 m por encima de
## su propio origen (el clip del modelo mueve el hueso raiz), asi que al
## nacer queda flotando medio metro: el muelle de altura lo tira contra el
## suelo a 5,7 m/s y el golpe lo tumba (medido: el tronco acababa
## INVERTIDO, con la cabeza 0,5 m por debajo de la pelvis).
##
## Se baja el personaje (raiz + TODOS los cuerpos) hasta que el pie de la
## pose de animacion apoya en el suelo real. Es la misma referencia que
## usa el muelle de altura para calcular su objetivo, asi que despues de
## colocarse el muelle queda en equilibrio y no golpea al personaje.
func _colocar_en_el_suelo() -> void:
	if skeleton == null or rig_config == null:
		return
	var pelvis := skeleton.bone_of(rig_config.body_bone_name)
	if pelvis == null:
		return
	var suelo_y := _suelo_bajo_pelvis()
	if is_inf(suelo_y):
		return
	# El punto MAS BAJO de los COLLIDERS (no de los huesos).
	#
	# MEDIDO: el collider va a MEDIA HUESO (ody_offset), asi que su
	# fondo queda centimetros por DEBAJO del origen del hueso. Si se
	# calcula el apoyo con los origenes de los huesos, el collider del
	# pie nace DENTRO del suelo y el solver lo expulsa de una patada: el
	# pie gira 50 grados y se pone a girar a 13 rad/s (medido en el frame
	# 3) y de ahi viene que el personaje se vea "aguado".
	var min_y := _fondo_de_los_colliders()
	if is_inf(min_y):
		return
	var d := suelo_y - min_y
	if absf(d) < 0.002:
		return
	_desplazar(Vector3(0.0, d, 0.0))


## El punto mas BAJO de todos los colliders del ragdoll (en mundo).
##
## Se lee del SERVIDOR de fisica (la transform del cuerpo) y de la forma
## de cada colision (el AABB local de la forma y su transform respecto al
## cuerpo, que es dato de la ESCENA y no cambia).
func _fondo_de_los_colliders() -> float:
	var min_y := INF
	for b in skeleton.bones:
		var xf := RagdollMotor.body_transform(b)
		if xf == Transform3D.IDENTITY:
			continue
		for c in b.find_children("*", "CollisionShape3D", true, false):
			var cs := c as CollisionShape3D
			if cs == null or cs.shape == null:
				continue
			var local := cs.transform
			var aabb: AABB = WaterShapeTest.aabb_de(cs.shape)
			for i in 8:
				var esquina: Vector3 = aabb.get_endpoint(i)
				var mundo: float = (xf * local * esquina).y
				min_y = minf(min_y, mundo)
	return min_y


## Desplaza la raiz y TODOS los cuerpos fisicos (la raiz sola no mueve el
## ragdoll: los cuerpos viven en el servidor de fisica).
func _desplazar(d: Vector3) -> void:
	if d.length_squared() < 1e-10:
		return
	global_position += d
	for b in skeleton.bones:
		var xf := RagdollMotor.body_transform(b)
		xf.origin += d
		PhysicsServer3D.body_set_state(b.get_rid(),
			PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
		PhysicsServer3D.body_set_state(b.get_rid(),
			PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(b.get_rid(),
			PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)


## Hooke's law angular: torque de resorte amortiguado (delegado al motor).
func hookes_law(displacement: Vector3, current_velocity: Vector3, stiffness: float,
		damping: float) -> Vector3:
	return RagdollMotor.hookes_law(displacement, current_velocity, stiffness, damping)


## === RESOLUCION DE NODOS ===============================================
func _buscar_esqueleto(prefijo: String) -> Skeleton3D:
	var n := get_node_or_null(prefijo)
	if n == null:
		return null
	return n.find_child("Skeleton3D", true, false) as Skeleton3D


func _buscar_de_clase(n: Node, clase: String) -> Node:
	for c in n.get_children():
		if c.is_class(clase):
			return c
		var r := _buscar_de_clase(c, clase)
		if r != null:
			return r
	return null


## Le pasa a la camara el hueso fisico de la CABEZA.
##
## El hueso se crea en runtime (o se authora en la escena), asi que la
## camara no puede encontrarlo sola por su nombre: sin esto se queda en el
## origen de la escena.
func _resolver_camara() -> void:
	if camera_pivot == null or rig_config == null or physical_skel == null:
		return
	var cabeza := skeleton.find_in_skeleton(rig_config.head_bone_name)
	if cabeza:
		camera_pivot.set("target_node", cabeza)
		camera_pivot.set("physical_skel", physical_skel)


## Ruta del esqueleto animado DESDE el personaje (para las pistas del
## AnimationTree: "Animated/metag/Skeleton3D:spine").
##
## Es RELATIVA al personaje y no a la escena: el `root_node` del AnimationMixer
## apunta al personaje, asi que las pistas tienen que ser relativas a el.
func _ruta_del_esqueleto_animado() -> String:
	if animated_skel == null:
		return ""
	var partes: Array[String] = []
	var n: Node = animated_skel
	while n != null and n != self:
		partes.push_front(n.name)
		n = n.get_parent()
	return "/".join(partes)


## Busca los ShapeCast3D de suelo y las Area3D de agarre en los cuerpos.
func _resolver_colisiones_de_suelo() -> void:
	if rig_config == null:
		return
	var pie_l := skeleton.find_in_skeleton(rig_config.on_floor_left_bone_name)
	var pie_r := skeleton.find_in_skeleton(rig_config.on_floor_right_bone_name)
	if pie_l:
		on_floor_left = pie_l.find_child("OnFloorL", true, false) as ShapeCast3D
	if pie_r:
		on_floor_right = pie_r.find_child("OnFloorR", true, false) as ShapeCast3D
	var g_l := skeleton.find_in_skeleton(rig_config.grab_bone_left_name)
	var g_r := skeleton.find_in_skeleton(rig_config.grab_bone_right_name)
	if g_l:
		l_grab_area = g_l.find_child("LGrabArea", true, false) as Area3D
	if g_r:
		r_grab_area = g_r.find_child("RGrabArea", true, false) as Area3D
