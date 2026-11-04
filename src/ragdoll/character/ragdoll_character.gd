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
var motor: RagdollMotor             ## El servo que lleva los cuerpos a la pose.
var mirror: PoseMirror              ## Copia las poses de la fisica al mesh.
var driver: AnimationDriver         ## AnimationPlayer + AnimationTree.
var head_look: HeadLook             ## La cabeza que sigue a la camara.
var fp_clip: FpClip                 ## El recorte de 1a persona.
##
## NO hay componente de IK de brazos (`TwoBoneIK3D`): MEDIDO (2026-11-04) que
## el modificador de Godot NO escribe la pose en este esqueleto (con la
## influencia a 1,0 la mano del esqueleto animado se queda en la pose del
## clip: y=0,839 colgando). El estiron del brazo lo hace el SERVO, sobre el
## objetivo (`_estirar_brazo_agarrado`), que es lo que de verdad mueve al
## personaje. Y NO hay `BalanceController`: el servo con objetivo absoluto ya
## mantiene al personaje de pie, y el balance le devolvia a la pelvis el par
## de todos los hijos (medido: la pelvis giraba a 40 rad/s y se volcaba).

## === ESTADISTICAS (Yuki Romero: Velocidad Baja · Stamina 50 · Salud 300)
## Los valores viven en `stats_shiba.tres`; la escena la asigna.
@export var stats: CharacterStats

var current_stamina := 0.0
var health := 0.0
var is_sprinting := false

## === MOVIMIENTO ========================================================
## Autoridad de movimiento: un `CharacterBody3D` HERMANO del ragdoll (no
## cambia la jerarquia). El ragdoll (visual) lo sigue; el suelo, las
## paredes y las escaleras los resuelve `move_and_slide`.
const JUMP_SPEED := 5.0
## La amortiguacion horizontal del empuje (la de la referencia: 0,9).
const AMORTIGUACION := 0.9
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

## === MOTOR ===
##
## La ley, la rigidez, el amortiguamiento y los topes los gobierna el
## `RagdollMotor` (una sola fuente). El personaje NO los sobreescribe: si
## hay que afinarlos, se tocan en el motor.

## === MIRADA DE CABEZA ===================================================
@export var head_look_enabled := true
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
## NO hay componente de IK (`TwoBoneIK3D`): MEDIDO (2026-11-04) que el
## modificador de Godot NO escribe la pose en este esqueleto (con la
## influencia a 1,0 la mano del esqueleto animado se queda en la pose del
## clip: y=0,839 colgando). El estiron lo hace el SERVO, sobre el objetivo
## (`_estirar_brazo_agarrado`).
@export var ik_enabled := true

## === RECORTE DE 1a PERSONA ============================================
@export var fp_clip_radius := 0.20
@export var fp_clip_meshes := PackedStringArray()

## === ESTADO ===========================================================
var ragdoll_mode := false
var walking := false
var is_on_floor := false
var can_jump := true
var active_arm_left := false
## El ULTIMO punto que dio el puntero (y cuando): si nadie lo
## actualiza, el IK usa el punto por defecto de la camara.
var _puntero_punto := Vector3.ZERO
var _puntero_momento := -999.0
var active_arm_right := false
var grabbing_arm_left := false
var grabbing_arm_right := false
var grabbed_object: Node3D = null

var agua: WaterBody = null
## La AUTORIDAD de movimiento (CharacterBody3D). Es un nodo HERMANO del
## ragdoll: no cambia la jerarquia de la escena.
var logic: CharacterBody3D = null
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
	logic = get_node_or_null("Logic") as CharacterBody3D
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
	fp_clip = FpClip.new()
	fp_clip.name = "FpClip"
	add_child(fp_clip)

	# --- Motor ---------------------------------------------------------
	# La ley, la rigidez y los topes los gobierna el MOTOR (una sola fuente).

	# --- Mirada --------------------------------------------------------
	head_look.enabled = head_look_enabled
	head_look.yaw_max_degrees = head_yaw_max_degrees
	head_look.pitch_max_degrees = head_pitch_max_degrees
	head_look.smoothing = head_look_smoothing

	# --- IK ------------------------------------------------------------
	# No hay componente de IK: el estiron lo hace el servo (ver
	# `_estirar_brazo_agarrado`).

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
		_actualizar_logic(dir, delta)
		_mover_cuerpo(dir, delta)
	_calcular_suelo()
	_actualizar_agua()
	# Salto: lo lleva el RAGDOLL (la capsula es solo horizontal). El
	# `is_on_floor` sale de los ShapeCast de las espinillas.
	if Input.is_action_pressed("jump") and is_on_floor and can_jump and physical_bone_body:
		physical_bone_body.linear_velocity.y += JUMP_SPEED
		current_stamina = maxf(current_stamina - stats.jump_stamina_cost, 0.0)
		if jump_timer:
			jump_timer.start()
		can_jump = false
	driver.set_walking(walking, _velocidad_deseada())
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
		# La regla de colision por POSE (la que excluye los pares de
		# huesos que se solapan en la pose de JUEGO): se aplica ahora que
		# la animacion ya esta escribiendo la pose. Antes, el solver
		# expandia los brazos contra el torso y el personaje salia
		# disparado 2,4 m hacia arriba (medido).
		skeleton.aplicar_excepciones_por_pose(animated_skel)
		# Y se pone DE PIE sobre el suelo: sin esto el personaje nace
		# flotando medio metro (la pose del clip lo deja por encima de su
		# origen) y el golpe contra el suelo lo tumba (medido).
		_colocar_en_el_suelo()
		mirror.capture_offset(physical_skel, physical_bone_body)


## La velocidad horizontal que el personaje DEBERIA llevar (m/s).
##
## El ciclo de paso se escala con la velocidad DESEADA, no con la real: si
## se escala con la real, el ciclo se frena a si mismo (el cuerpo no
## avanza -> el ciclo va lento -> las piernas no giran al ritmo del
## cuerpo -> los joints se tensan -> el cuerpo no avanza). Medido: con la
## real el Shiba se quedaba en 0,9 m/s.
func _velocidad_deseada() -> float:
	var vel := stats.sprint_speed if is_sprinting else stats.walk_speed
	if agua != null and agua.sumergido:
		vel *= NADO_ESCALA
	return vel


## La velocidad horizontal REAL del cuerpo (m/s).
##
## El ciclo de paso se escala con la REAL, no con la objetivo: si el ciclo
## va mas rapido que el cuerpo, los pies patinan (el pie se planta en el
## suelo y el cuerpo se queda atras) y el rozamiento frena al personaje.
## (Con la velocidad REAL no hay circulo vicioso: el avance del cuerpo lo
## pone el EMPUJE a la pelvis, no el ciclo de paso.)
func _velocidad_horizontal() -> float:
	if physical_bone_body == null:
		return 0.0
	var v := RagdollMotor.body_linear_velocity(physical_bone_body)
	return Vector2(v.x, v.z).length()


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


## Mueve la AUTORIDAD (`CharacterBody3D`) en HORIZONTAL con `move_and_slide`.
##
## OJO (medido): la capsula NO lleva gravedad propia. La altura la fija un
## RAYCAST al suelo (`_suelo_logic`) 5 cm por encima: asi la capsula no
## penetra el `Floor` (1 cm dentro trababa `move_and_slide`: 6 contactos con
## normal UP, velocidad conservada y posicion quieta) y las rampas/escalones
## los sube el fondo redondeado de la capsula. El salto sigue siendo del
## ragdoll.
func _actualizar_logic(dir: Vector3, _delta: float) -> void:
	if logic == null:
		return
	# En el agua manda el ragdoll (nado); la capsula no empuja.
	if agua != null and agua.sumergido:
		return
	var vel := stats.sprint_speed if is_sprinting else stats.walk_speed
	logic.velocity.x = dir.x * vel
	logic.velocity.z = dir.z * vel
	logic.velocity.y = 0.0
	# Altura por raycast: la capsula queda 5 cm sobre el suelo real.
	var suelo := _suelo_logic()
	if not is_inf(suelo):
		logic.global_position.y = suelo + 0.05
	logic.move_and_slide()


## Altura del suelo debajo de la capsula (INF si no hay). Mascara 1 (mundo):
## los huesos (capa 2) y los props (capa 3) no cuentan como suelo.
func _suelo_logic() -> float:
	if logic == null:
		return INF
	var mundo := get_world_3d()
	if mundo == null:
		return INF
	var p := logic.global_position + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 2.0)
	q.collision_mask = 1
	q.collide_with_areas = false
	var hit := mundo.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return INF
	return float(hit["position"].y)


## El ragdoll SIGUE a la capsula en POSICION (es VISUAL): se traslada el
## mismo delta a todos los cuerpos, sin tocar velocidades ni orientaciones.
## El ciclo de paso (TimeScale = velocidad real / natural) hace que los pies
## parezcan plantados aunque el cuerpo avance. :v
func _seguir_logic(_delta: float) -> void:
	if logic == null or physical_bone_body == null:
		return
	var p := RagdollMotor.body_transform(physical_bone_body).origin
	var d := Vector3(logic.global_position.x - p.x, 0.0,
		logic.global_position.z - p.z)
	if d.length_squared() < 1e-10:
		return
	for b in skeleton.bones:
		var xf := RagdollMotor.body_transform(b)
		xf.origin += d
		PhysicsServer3D.body_set_state(b.get_rid(),
			PhysicsServer3D.BODY_STATE_TRANSFORM, xf)


func _mover_cuerpo(dir: Vector3, delta: float) -> void:
	# En el agua se nada: mas lento, y el arrastre del WaterBody (hijo,
	# corre DESPUES de este script) se encarga del resto.
	var en_agua := agua != null and agua.sumergido
	# En tierra, si hay `Logic` (CharacterBody3D), la autoridad es el: el
	# ragdoll solo lo sigue. Sin `Logic` (escenas viejas) se usa el empuje.
	if not en_agua and logic != null:
		_seguir_logic(delta)
		return
	# La velocidad sale de las STATS del personaje (3 m/s andando, 5,5
	# esprintando).
	var vel := stats.sprint_speed if is_sprinting else stats.walk_speed
	if en_agua:
		vel *= NADO_ESCALA
	#
	# EL EMPUJE ES ACUMULATIVO, como en la REFERENCIA: `v += dir*SPEED*dt`
	# y luego amortiguacion 0,9. Es ACUMULATIVO por una razon medida: el
	# solver de joints frena la pelvis cada tick (el cono de la columna
	# la inmoviliza), y con un `move_toward` (idempotente) el empuje se
	# pierde en cada frame: el personaje se quedaba en 0,4 m/s con un
	# objetivo de 1,7 (medido). Acumulando, la velocidad crece hasta el
	# equilibrio aunque el solver frene parte.
	#
	# El equilibrio es `v_obj * dt / (1 - amortiguacion)`: con la
	# amortiguacion 0,9 el factor es 10, asi que se empuja con
	# `v_obj * dt * 10` para que el equilibrio sea exactamente `v_obj`
	# (igual a 30 que a 144 fps).
	# El equilibrio es `v = a*D/(1-D)`: para que el equilibrio sea
	# exactamente `vel`, el paso que se suma tiene que ser
	# `a = vel*(1-D)/D` (un valor CONSTANTE, no depende del framerate).
	#
	# MEDIDO (2026-11-04): con `a = vel*delta/(1-D)` el equilibrio salia
	# 1,5 veces la velocidad pedida (medido: 1,54 m/s con un objetivo de
	# 1,1) y ademas dependia de los fps.
	var v := RagdollMotor.body_linear_velocity(physical_bone_body)
	var paso := vel * (1.0 - AMORTIGUACION) / AMORTIGUACION
	var vx := (v.x + dir.x * paso) * AMORTIGUACION
	var vz := (v.z + dir.z * paso) * AMORTIGUACION
	PhysicsServer3D.body_set_state(physical_bone_body.get_rid(),
		PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,
		Vector3(vx, v.y, vz))
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
	# La capsula (`Logic`) es la autoridad del suelo: si ella pisa, el
	# personaje esta en el suelo aunque los ShapeCast de las espinillas no
	# vean nada (escalones, bordes).
	if logic != null and logic.is_on_floor():
		is_on_floor = true


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
	# NO hay balance (upright + centro de masas + muelle de altura): la ley
	# del servo con objetivo absoluto ya mantiene al personaje de pie y el
	# balance le devolvia a la pelvis el par de todos los hijos (medido: la
	# pelvis giraba a 40 rad/s y el personaje se volcaba).
	motor.drive(skeleton.bones, objetivos, _grupos(), get_physics_process_delta_time(),
		physical_skel)
	mirror.mirror(physical_skel, animated_skel, skeleton.bones, physical_bone_body)


## Pose objetivo de cada cuerpo: la de la ANIMACION (con el IK si esta
## activo) mas el lean y la mirada de cabeza.
func _calcular_objetivos() -> Dictionary:
	var out := {}
	for b in skeleton.bones:
		var id := b.get_bone_id()
		if id < 0:
			continue
		# La pose objetivo es la de la ANIMACION (el esqueleto ANIMADO).
		var pose := driver.pose_of(id)
		# OJO — DOS REGLAS DE MARCO (medidas y documentadas por Godot):
		#   * `get_bone_global_pose()` es RELATIVA AL ESQUELETO, no al
		#     mundo ("it is not the actual global/world transform of the
		#     bone", class_skeleton3d).
		#   * El servidor de fisica devuelve transformaciones en MUNDO.
		# El marco es el del esqueleto maestro (ver `PoseMirror.follow_pelvis`:
		# el maestro SIGUE al cuerpo, no se coloca sobre el, asi que no hay
		# lazo y el objetivo es ABSOLUTO: la pose del clip en el mundo).
		var objetivo: Transform3D = animated_skel.global_transform * pose
		objetivo = _aplicar_lean(b, objetivo)
		objetivo = head_look.apply(b, objetivo)
		# PIE PLANTADO: si el pie toca el suelo, el objetivo es su PROPIA pose
		# fisica. Asi el servo no pelea con el suelo (medido: 96 grados de
		# error en foot.R y omega desperdiciada). En el aire vuelve al clip.
		if rig_config != null and rig_config.is_foot(b.bone_name) \
				and _pie_en_suelo(b):
			var boff: Transform3D = b.get("body_offset")
			objetivo = RagdollMotor.body_transform(b) * boff.affine_inverse()
		out[id] = objetivo
	_estirar_brazo_agarrado(out)
	return out


## El marco en el que se aplica la pose del clip: la ORIENTACION del
## esqueleto animado, pero con el ORIGEN en la pelvis del CUERPO.
##
## OJO (medido 2026-11-04) — POR QUE NO SE USA `animated_skel.global_transform`:
## el `PoseMirror` mueve el esqueleto (el fisico y el animado) para que
## sigan a la pelvis del cuerpo. Si el objetivo se calculara con la
## posicion REAL del esqueleto maestro, el lazo seria:
##   el servo lleva el cuerpo al objetivo -> el espejo mueve el maestro
##   -> el objetivo se mueve -> el servo lo persigue...
## Con un tick de retraso eso es una OSCILACION DE PERIODO 2: medido, la
## pelvis subia a 2,41 m y volvia a 0,30 m una y otra vez (el personaje
## "se movia horripilantemente").
##
## Anclando el origen a la pelvis del CUERPO, el objetivo depende del
## cuerpo y no del maestro: no hay lazo, y el clip sigue al personaje.
func _base_de_objetivos() -> Transform3D:
	var m := animated_skel.global_transform if animated_skel != null else Transform3D.IDENTITY
	if physical_bone_body == null or animated_skel == null or rig_config == null:
		return m
	var pelvis := RagdollMotor.body_transform(physical_bone_body).origin
	# La posicion del hueso de la pelvis DENTRO del esqueleto (la pose del
	# clip): para colocar el maestro sobre la pelvis del cuerpo.
	var pid := animated_skel.find_bone(rig_config.body_bone_name)
	var p_rel := Vector3.ZERO
	if pid >= 0:
		p_rel = animated_skel.get_bone_global_pose(pid).origin
	return Transform3D(m.basis, pelvis - m.basis * p_rel)


## ESTIRA el brazo que agarra hacia el puntero.
##
## MEDIDO (2026-11-04): el `TwoBoneIK3D` de Godot NO escribe la pose en
## este esqueleto (con la influencia a 1,0 la mano del esqueleto animado
## se queda en la pose del clip: y=0,839 colgando, medido). Por eso el
## estirón se hace AQUI, en el objetivo del servo, que es lo que de
## verdad mueve al personaje.
##
## Sin clic, los brazos se quedan en la pose del IDLE (el servo los
## sujeta: `arm_spring_scale = 1`). Con clic, la CADENA ENTERA del brazo
## (humero + antebrazo + mano) se rota alrededor del hombro para que
## apunte al puntero.
func _estirar_brazo_agarrado(out: Dictionary) -> void:
	if not (active_arm_left or active_arm_right):
		return
	if rig_config == null or animated_skel == null:
		return
	var punto := _puntero_punto
	if Time.get_ticks_msec() / 1000.0 - _puntero_momento > 0.5:
		punto = _punto_de_mano_por_defecto()
	for lado in ["L", "R"]:
		var agarra := active_arm_left if lado == "L" else active_arm_right
		if not agarra:
			continue
		var cadena: Dictionary = rig_config.ik_arm_left if lado == "L" \
			else rig_config.ik_arm_right
		var raiz := animated_skel.find_bone(cadena["root"])
		var medio := animated_skel.find_bone(cadena["mid"])
		var mano := animated_skel.find_bone(cadena["end"])
		if raiz < 0 or medio < 0 or mano < 0:
			continue
		if not (out.has(raiz) and out.has(medio) and out.has(mano)):
			continue
		# OJO (medido): `out[raiz].origin` es el maestro, que se queda en el
		# spawn. La direccion del brazo se mide con las posiciones FISICAS o,
		# al caminar, el hombro esta 1 m atras y el brazo apunta mal.
		var cuerpo_raiz := _cuerpo_de(raiz)
		var cuerpo_mano := _cuerpo_de(mano)
		var hombro: Vector3 = out[raiz].origin
		var mano_fisica: Vector3 = out[mano].origin
		if cuerpo_raiz != null:
			hombro = _posicion_fisica(cuerpo_raiz)
		if cuerpo_mano != null:
			mano_fisica = _posicion_fisica(cuerpo_mano)
		var dir_actual: Vector3 = (mano_fisica - hombro).normalized()
		var dir_objetivo: Vector3 = punto - hombro
		if dir_objetivo.length() < 0.05:
			continue
		dir_objetivo = dir_objetivo.normalized()
		# El puntero tiene que estar POR DELANTE del personaje: si esta
		# detras, el brazo no puede girar el ombro (medido: el brazo se
		# lanzaba hacia atras y el hombro se descoyuntaba).
		var frente: Vector3 = animated_skel.global_transform.basis.z
		if dir_objetivo.dot(frente) < 0.25:
			continue
		var eje: Vector3 = dir_actual.cross(dir_objetivo)
		if eje.length() < 0.0001:
			continue
		eje = eje.normalized()
		var ang := acos(clampf(dir_actual.dot(dir_objetivo), -1.0, 1.0))
		# TOPE del giro: el brazo es una articulacion, no una catapulta.
		#
		# MEDIDO (2026-11-04): sin tope, con el raton pulsado la mano se
		# iba a 4,6 m de altura (a 4 m del cuerpo) y el brazo entero
		# seguia el gesto: el personaje se descoyuntaba.
		ang = minf(ang, deg_to_rad(65.0))
		var rot := Transform3D(Basis(Quaternion(eje, ang)), hombro)
		var fija := Transform3D(Basis.IDENTITY, -hombro)
		for id in [raiz, medio, mano]:
			out[id] = rot * fija * out[id]


## El cuerpo fisico cuyo bone_id coincide (mismo id que el animado).
func _cuerpo_de(id: int) -> PhysicalBone3D:
	for b in skeleton.bones:
		if b.get_bone_id() == id:
			return b
	return null


## La pose del HUESO en mundo a partir del cuerpo (deshace `body_offset`).
func _posicion_fisica(b: PhysicalBone3D) -> Vector3:
	var boff: Transform3D = b.get("body_offset")
	return (RagdollMotor.body_transform(b) * boff.affine_inverse()).origin


## ¿El pie apoya en el suelo? Raycast desde el hueso del pie hacia abajo.
## La mascara 1 (mundo) ignora los propios huesos (capa 2). :v
func _pie_en_suelo(b: PhysicalBone3D) -> bool:
	if b == null:
		return false
	var mundo := get_world_3d()
	if mundo == null:
		return false
	var boff: Transform3D = b.get("body_offset")
	var p := (RagdollMotor.body_transform(b) * boff.affine_inverse()).origin
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 0.18)
	q.collision_mask = 1
	q.collide_with_areas = false
	return not mundo.direct_space_state.intersect_ray(q).is_empty()


## Los grupos de cada hueso (para el motor: los brazos se relajan).
func _grupos() -> Dictionary:
	var out := {}
	for b in skeleton.bones:
		out[b.get_bone_id()] = rig_config.group_of(b.bone_name) if rig_config != null else ""
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
## El punto es el que decide: con el raton pulsado el brazo se estira hacia
## el puntero; sin el, los brazos siguen el clip (la pose del IDLE).
func update_hand_targets(world_point: Vector3, _has_target: bool) -> void:
	_puntero_punto = world_point
	_puntero_momento = Time.get_ticks_msec() / 1000.0


## El punto al que apuntan las manos cuando NO hay puntero: por delante
## de la camara, a la altura de los hombros.
func _punto_de_mano_por_defecto() -> Vector3:
	if camera_pivot == null:
		return global_position
	var cam := camera_pivot.global_position
	var fwd := -camera_pivot.global_transform.basis.z
	return cam + fwd * 0.35


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
	print("[RagdollCharacter] colocar en el suelo: suelo_y=%.3f fondo_colliders=%.3f delta=%.3f" % [
		suelo_y, min_y, d])
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
		var local_min := INF
		for c in b.find_children("*", "CollisionShape3D", true, false):
			var cs := c as CollisionShape3D
			if cs == null or cs.shape == null:
				continue
			var local := cs.transform
			var aabb: AABB = WaterShapeTest.aabb_de(cs.shape)
			for i in 8:
				var esquina: Vector3 = aabb.get_endpoint(i)
				var mundo: float = (xf * local * esquina).y
				local_min = minf(local_min, mundo)
		print("[RagdollCharacter] collider %s: cuerpo.y=%.3f fondo=%.3f" % [
			String(b.bone_name), xf.origin.y, local_min])
		min_y = minf(min_y, local_min)
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
