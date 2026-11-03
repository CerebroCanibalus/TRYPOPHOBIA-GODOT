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
@export var upright_strength := 1500.0
## Ganancia del desplazamiento del centro de masas (rad/s2 por metro).
@export var com_strength := 600.0
## Amortiguamiento de las dos ayudas (rad/s2 por rad/s).
@export var damping := 120.0
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
## Tope del empuje vertical (N) del muelle que sostiene al personaje.
## Tiene que superar el peso (50 kg ~ 490 N) o el personaje no se levanta.
@export var max_force := 1500.0
## Altura objetivo de la pelvis (metros). 0 = se captura sola.
@export var target_pelvis_height := 0.0

var _captured := false


## Captura la altura objetivo de la pelvis.
##
## Se calcula sobre el SUELO, no en el instante de aparecer: el span es
## (altura de la pelvis - altura de los pies) en la pose de reposo del
## clip, y se ancla al pie fisico mas bajo en el momento de capturar.
## Asi el objetivo es la altura de DE PIE sobre el suelo real, caiga el
## personaje de donde caiga (antes se capturaba al aparecer: en una caida
## libre se capturaba la altura de AIRE y el muelle colgaba al personaje).
## Se llama desde el personaje cuando toca suelo.
func capture_target(pelvis_body: PhysicalBone3D, feet: Array[PhysicalBone3D],
		animated_skel: Skeleton3D, pelvis_bone_id: int,
		foot_bone_ids: Array[int]) -> void:
	if target_pelvis_height > 0.0:
		_captured = true
		return
	if pelvis_body == null or animated_skel == null:
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
	var feet_y := INF
	for f in feet:
		if f == null:
			continue
		feet_y = minf(feet_y, RagdollMotor.body_transform(f).origin.y)
	if is_inf(feet_y):
		return
	target_pelvis_height = feet_y + span
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
	var arriba := xf.basis.y.normalized()
	var eje_up := arriba.cross(Vector3.UP)
	var ang := eje_up.length()
	var alpha := Vector3.ZERO
	if ang > 0.001:
		eje_up /= ang
		alpha += eje_up * minf(ang, deg_to_rad(45.0)) * upright_strength

	# --- 2) CoM SHIFT: el centro de masas sobre la base de apoyo -------
	var com := _centro_de_masas(bones)
	var apoyo := _base_de_apoyo(feet)
	if com != Vector3.ZERO and apoyo != Vector3.ZERO:
		var desvio := com - apoyo
		desvio.y = 0.0
		# El torso se inclina hacia el lado del desvio (el peso tira de vuelta).
		var fwd := xf.basis.z.normalized()
		var lateral := fwd.cross(Vector3.UP).normalized()
		alpha += lateral * desvio.dot(lateral) * com_strength

	alpha -= omega * damping
	alpha = alpha.limit_length(600.0)
	PhysicsServer3D.body_apply_torque(torso.get_rid(),
		RagdollMotor.torque_de(torso, alpha).limit_length(max_torque))

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
