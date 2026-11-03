extends Node
class_name BalanceController
## CONTROLADOR DE EQUILIBRIO del ragdoll.
##
## El PD lleva cada hueso a la pose de la animacion, pero la GRAVEDAD lo
## hunde: el error de equilibrio del PD es `τ_gravedad/(I·rigidez)` y con un
## personaje de 50 kg el torso se queda ~25 grados torcido y la pelvis baja
## de 0,83 m a 0,55 m (medido: el personaje queda agachado).
##
## Esto no se arregla con mas rigidez (el PD se limitaria a pelear con el
## suelo). Lo arregla un controlador de balance de verdad, que es lo que
## hace un humano: cuando el centro de masas se sale de la base de
## apoyo, el cuerpo se inclina para que el peso tire de vuelta.
##
## Son DOS ayudas, ambas como TORQUE (no como empuje lineal: un empuje
## sobre la pelvis la haria flotar):
##
## 1. **UPRIGHT**: el torso se endereza hacia la vertical del mundo.
## 2. **CoM SHIFT**: si el centro de masas se sale de la base de apoyo, el
##    torso se inclina hacia ese lado para que la gravedad compense.
##
## Las dos se suman al torque del PD (no lo sustituyen): el PD pone la
## pose, el balance decide si se aguanta.

@export var enabled := true
## Ganancia del enderezado (rad/s2 por radian de desvio de la vertical).
## Tiene que ser comparable a la rigidez del PD (2500): si no, el PD
## "gana" y el torso se queda ladeado (medido: el personaje agachado y
## con los brazos abiertos).
## Ganancia del torque UPRIGHT (N*m por radian de error). El torso se
## endereza hacia la vertical del mundo.
@export var upright_strength := 150.0
## Ganancia del torque de desplazamiento del centro de masas (N*m por metro).
@export var com_strength := 15000.0
## Amortiguamiento angular (N*m*s/rad).
##
## OJO: el amortiguamiento es EXPLICITO, asi que tiene que cumplir
## `c * dt / I <= 2` para ser estable. Con la inercia del tronco (0,012)
## eso da `c <= 1,5`: por eso es 1,2 y no 120 (medido: con 120 el torso
## se ponia a vibrar y no se sostenia).
@export var damping := 1.2
## Rigidez del muelle vertical que SOSTIENE al personaje (N/m). El PD solo
## controla la ORIENTACION: sin este muelle el torso queda erguido pero
## tumbado en el suelo (medido: pelvis a 0,18 m en vez de 0,83).
##
## OJO: el tope de fuerza tiene que SUPERAR el peso del personaje (50 kg
## son ~490 N). Con un tope de 400 N el muelle no llega a levantarlo y el
## personaje se queda en el suelo (medido).
@export var height_stiffness := 9000.0
## Amortiguamiento de ese muelle (N/(m/s)).
@export var height_damping := 700.0
## Tope del torque de las ayudas (N*m). Imprescindible: sin tope, el
## torso (inercia 0,17) recibe 0,17*600 = 102 N*m y se pone a girar como
## un trompo (medido: el pecho y la cabeza bailando entre -180 y +180).
@export var max_torque := 120.0
## Tope de aceleracion angular del torso (rad/s2). El torque del
## balance se limita con I * este valor.
@export var max_accel := 300.0
## Tope del empuje vertical (N) del muelle que sostiene al personaje.
## Tiene que superar el peso (50 kg ~ 490 N) o el personaje no se levanta.
@export var max_force := 1500.0
## Altura objetivo de la pelvis (metros). 0 = se captura sola.
@export var target_pelvis_height := 0.0

var _captured := false


## Captura la altura objetivo de la pelvis.
##
## Se calcula sobre el SUELO real, no en el instante de aparecer: el span es
## (altura de la pelvis - altura de los pies) en la pose de reposo del
## clip, y se ancla al SUELO que hay DEBAJO de la pelvis (`suelo_y`, que
## mide el personaje con un raycast).
##
## OJO (medido): antes se ancla a la posicion del PIE mas bajo y solo se
## capturaba si ese pie estaba a menos de 0,3 m del suelo. Si el personaje
## se estrella de espaldas, los pies quedan a 0,5-0,8 m y la captura NUNCA
## ocurre: el balance entero (upright + centro de masas + muelle vertical)
## se queda apagado y el ragdoll se queda tumbado boca arriba para siempre
## (medido: `up_col` = -0,99 durante 4 s).
##
## Con el raycast al suelo la captura es correcta tumbo o de pie.
## Se llama desde el personaje cuando toca suelo.
func capture_target(pelvis_body: PhysicalBone3D, animated_skel: Skeleton3D,
		pelvis_bone_id: int, foot_bone_ids: Array[int], suelo_y: float) -> void:
	if target_pelvis_height > 0.0:
		_captured = true
		return
	if pelvis_body == null or animated_skel == null:
		return
	if is_inf(suelo_y):
		return
	var pose_pelvis: float = animated_skel.get_bone_global_pose(pelvis_bone_id).origin.y
	var pose_pies := INF
	for fid in foot_bone_ids:
		if fid < 0:
			continue
		pose_pies = minf(pose_pies, animated_skel.get_bone_global_pose(fid).origin.y)
	if is_inf(pose_pies):
		return
	var span := pose_pelvis - pose_pies
	target_pelvis_height = suelo_y + span
	_captured = true


## ¿Ya esta capturado el objetivo? (el personaje lo usa para capturar
## en el primer contacto con el suelo).
func is_captured() -> bool:
	return _captured


## Aplica las ayudas de balance.
##
## `bones` = todos los cuerpos. `rig` = los datos (para saber cual es el
## torso). `pelvis_body` = el cuerpo "cuerpo".
func apply(bones: Array[PhysicalBone3D], pelvis_body: PhysicalBone3D,
		rig: RagdollRig, feet: Array[PhysicalBone3D]) -> void:
	if not enabled or not _captured or pelvis_body == null:
		return
	var torso := _torso(bones, rig)
	if torso == null:
		return
	var xf := RagdollMotor.body_transform(torso)
	var omega := RagdollMotor.body_angular_velocity(torso)

	# --- 1) UPRIGHT: el torso hacia la vertical ------------------------
	#
	# OJO (medido) — dos trampas:
	# a) Si el torso esta INVERTIDO (180 grados), `arriba.cross(UP)` da
	#    vector CERO: el eje de correccion se anula y el torso se queda
	#    boca arriba para siempre (medido: `up_col` = -0,98 durante 4 s).
	#    Para ese caso se usa el "adelante" del torso como eje.
	# b) El torque sale de `torque_de()` (I * alpha), asi que con una
	#    inertia de 0,012 el tope de 600 rad/s2 daba 7,4 N*m, menos de
	#    los ~15 N*m que el tronco tiene que sostener: no lo erguia.
	var arriba := xf.basis.y.normalized()
	var ang := arriba.angle_to(Vector3.UP)
	var eje_up := arriba.cross(Vector3.UP)
	if eje_up.length() < 0.001:
		# Invertido: el eje de giro puede ser cualquiera horizontal.
		eje_up = xf.basis.z.normalized().cross(Vector3.UP)
		if eje_up.length() < 0.001:
			eje_up = Vector3.RIGHT
	else:
		eje_up = eje_up.normalized()
	var torque := eje_up * minf(ang, deg_to_rad(60.0)) * upright_strength

	# --- 2) CoM SHIFT: el centro de masas sobre la base de apoyo -------
	var com := _centro_de_masas(bones)
	var apoyo := _base_de_apoyo(feet)
	if com != Vector3.ZERO and apoyo != Vector3.ZERO:
		var desvio := com - apoyo
		desvio.y = 0.0
		# El torso se inclina hacia el lado del desvio (el peso tira de vuelta).
		var fwd := xf.basis.z.normalized()
		var lateral := fwd.cross(Vector3.UP).normalized()
		torque += lateral * desvio.dot(lateral) * com_strength

	torque -= omega * damping
	# Tope por ACELERACION (igual que el PD): el torque del balance se
	# limita con la inercia del torso. Sin este tope, 120 N*m sobre un
	# torso de I=0,03 son 4000 rad/s2 y el torso sale disparado (medido).
	var inercia := RagdollMotor.inercia_media(torso)
	torque = torque.limit_length(minf(max_torque, inercia * max_accel))
	PhysicsServer3D.body_apply_torque(torso.get_rid(), torque)

	# --- 3) HEIGHT ASSIST: el muelle que lo mantiene de pie ------------
	# El PD solo controla la ORIENTACION: con el torso erguido pero tumbado
	# en el suelo (medido: pelvis a 0,18 m), hacia falta algo que lo
	# levante. Este muelle vertical sobre la pelvis lo deja a la altura de
	# la pose (0,83 m) sin que el PD tenga que pelear con el suelo.
	var pelvis_xf := RagdollMotor.body_transform(pelvis_body)
	var error_h := target_pelvis_height - pelvis_xf.origin.y
	if absf(error_h) > 0.01:
		var vy := RagdollMotor.body_linear_velocity(pelvis_body).y
		var f := error_h * height_stiffness - vy * height_damping
		PhysicsServer3D.body_apply_force(pelvis_body.get_rid(), Vector3.UP * clampf(f, -max_force, max_force))


## El TORSO: el hueso de la columna con mas masa (el pecho). Es el que hay
## que enderezar: los mas altos (cuello, cabeza) no.
func _torso(bones: Array[PhysicalBone3D], rig: RagdollRig) -> PhysicalBone3D:
	if rig == null:
		return null
	var mejor: PhysicalBone3D = null
	var mejor_masa := -1.0
	for b in bones:
		if String(rig.group_of(b.bone_name)) != "column":
			continue
		if b.bone_name == rig.body_bone_name:
			continue
		if b.mass > mejor_masa:
			mejor_masa = b.mass
			mejor = b
	return mejor


## Centro de masas (media ponderada por la masa de los cuerpos).
func _centro_de_masas(bones: Array[PhysicalBone3D]) -> Vector3:
	var suma := Vector3.ZERO
	var total := 0.0
	for b in bones:
		var m := b.mass
		if m <= 0.0:
			continue
		suma += RagdollMotor.body_transform(b).origin * m
		total += m
	if total <= 0.0:
		return Vector3.ZERO
	return suma / total


## Base de apoyo: el centro de los pies que tocan el suelo (o el primero).
func _base_de_apoyo(feet: Array[PhysicalBone3D]) -> Vector3:
	var suma := Vector3.ZERO
	var n := 0
	for f in feet:
		if f == null:
			continue
		suma += RagdollMotor.body_transform(f).origin
		n += 1
	if n == 0:
		return Vector3.ZERO
	return suma / float(n)


func _profundidad_de_columna(bone_name: StringName) -> int:
	# Cuenta los puntos del nombre ("spine.003" = 3). Es una aproximacion
	# barata de "cuanto arriba esta en la columna".
	var n := String(bone_name)
	var d := 0
	for i in n.length():
		if n[i] == '.':
			d += 1
	return d
