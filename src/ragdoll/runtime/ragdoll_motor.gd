extends Node
class_name RagdollMotor
## El MOTOR del ragdoll: el controlador PD que lleva cada cuerpo fisico a
## la pose de la animacion.
##
## Es un componente puro: no sabe nada de animacion, camara ni IK. Solo
## recibe "para cada cuerpo, cual es su pose objetivo" y aplica la fuerza
## necesaria. Asi se puede reusar con cualquier rig y probar aislado.
##
## TRAMPA 1 — hay que aplicar TORQUE, no escribir la velocidad angular.
## Escribir la velocidad de cada hueso por separado hace que CADA
## articulacion pelee con el PD: el solver de joints proyecta las
## velocidades para cumplir las restricciones y el PD las sobrescribe ->
## la cadena se embala y el personaje sale disparado (medido: la pelvis de
## 0,46 m a 13,6 m en 5 s).
##
## TRAMPA 2 — el error de orientacion va en AXIS-ANGLE, no en euler. El
## euler reparte el angulo entre los tres ejes y el vector resultante NO
## apunta en la direccion real de la rotacion: con el euler los brazos se
## quedaban a 116 grados del clip (medido con body_debugger) mientras el
## torso iba bien.
##
## TRAMPA 3 — la rigidez tiene un techo. La frecuencia natural del spring
## es `w_n = sqrt(rigidez)` y a 60 Hz hace falta `w_n*dt < 1`, o sea
## rigidez < 3600. Con 8000 el sistema es inestable (el personaje sale
## volando a 28 m).

## Rigidez del spring (rad/s2 por radian de error).
@export var stiffness := 2500.0
## Amortiguamiento (rad/s2 por rad/s). Para zeta ~ 1: 2*sqrt(rigidez).
@export var damping := 100.0
## Tope de la aceleracion angular que se puede pedir (rad/s2).
@export var max_angular_accel := 1500.0
## Tope de la velocidad angular (rad/s). Sin el, un frame puede dar 40
## rad/s y la cadena se convierte en un latigazo.
@export var max_angular_speed := 6.0
## Tope del TORQUE (N*m) que se puede aplicar a un hueso. Imprescindible:
## con el tope de aceleracion (1500 rad/s2) y un hueso de 10 kg (inercia
## 0,17) salen 255 N*m y el torso se pone a girar como un trompo (medido:
## el pecho y la cabeza bailando entre -180 y +180 grados, y el giro de
## cabeza medido daba 0 porque era ruido).
@export var max_torque := 400.0
## Escala de rigidez y amortiguamiento de los brazos que NO estan
## agarrando (1 = igual que el resto).
@export var arm_spring_scale := 1.0
## Si es true, el motor ignora los cuerpos con velocidad angular extrema
## (evita que un cuerpo ya disparado se lleve a los demas).
@export var cap_velocity := true


## Lleva los cuerpos a sus poses objetivo.
##
## `objetivos` = { bone_id : Transform3D en espacio MUNDO }.
## `grupos` = { bone_id : "arm" | "leg" | "column" | "" }.
## `ganancias` = { bone_id : multiplicador del PD } (opcional): un hueso que
## SOPORTA mas carga necesita un PD mas fuerte para que la gravedad no lo
## gane (medido: sin esto el torso se queda con 90 grados de error).
func drive(bones: Array[PhysicalBone3D], objetivos: Dictionary, grupos: Dictionary,
		delta: float, ganancias: Dictionary = {}) -> void:
	for b in bones:
		var id := b.get_bone_id()
		if id < 0 or not objetivos.has(id):
			continue
		var objetivo: Transform3D = objetivos[id]
		var stiff := stiffness
		var damp := damping
		if String(grupos.get(id, "")) == "arm":
			stiff *= arm_spring_scale
			damp *= arm_spring_scale
		# La ganancia del PD segun la carga que soporta el hueso.
		var gain := float(ganancias.get(id, 1.0))
		stiff *= gain
		damp *= gain
		# La pose REAL del cuerpo, YA EN ESPACIO MUNDO (el nodo no se
		# actualiza: ver body_transform).
		var actual := body_transform(b)
		# OJO: el giro que lleva de `actual` a `objetivo` es
	# `actual⁻¹ * objetivo`. Al reves (`objetivo * actual⁻¹`) sale el
	# conjugado: el mismo angulo con el EJE OPUESTO, y el PD empuja en
	# sentido contrario -> diverge y el cuerpo se queda girando (medido: el
	# pecho y la cabeza bailando entre -180 y +180 grados).
		var diferencia := actual.basis.inverse() * objetivo.basis
		var error := error_de_rotacion(diferencia)
		var max_err := deg_to_rad(90.0)
		if error.length() > max_err:
			error = error.normalized() * max_err
		var alpha := hookes_law(error, body_angular_velocity(b), stiff, damp)
		# TORQUE (no servo de velocidad): el PD tiene que SOSTENER al
		# personaje contra la gravedad. Un servo de velocidad converge
		# mejor (el error tiende a cero) pero no aplica un torque
		# sostenido: en reposo el torso se cae (medido: el personaje queda
		# tumbado en el suelo).
		alpha = alpha.limit_length(max_angular_accel)
		# OJO: PhysicalBone3D NO hereda de RigidBody3D (extiende de
		# PhysicsBody3D) y no tiene apply_torque(): se usa la API del
		# servidor de fisica, que es la misma ruta que usa RigidBody3D.
		PhysicsServer3D.body_apply_torque(b.get_rid(),
			torque_de(b, alpha).limit_length(max_torque))
		if cap_velocity:
			var omega := body_angular_velocity(b)
			if omega.length() > max_angular_speed:
				PhysicsServer3D.body_set_state(b.get_rid(),
					PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,
					omega.limit_length(max_angular_speed))


## Ley de Hooke con amortiguamiento: `k·x - c·v`.
static func hookes_law(desplazamiento: Vector3, velocidad: Vector3,
		rigidez: float, amortiguamiento: float) -> Vector3:
	return (rigidez * desplazamiento) - (amortiguamiento * velocidad)


## Vector de error de una rotacion (eje * angulo), en espacio MUNDO.
##
## Es el vector de error correcto para un PD de orientacion (ver TRAMPA 2).
static func error_de_rotacion(diferencia: Basis) -> Vector3:
	var q := diferencia.get_rotation_quaternion()
	# Camino corto: si el cuaternion es negativo, su inverso es el mas corto.
	if q.w < 0.0:
		q = -q
	var ang := q.get_angle()
	if ang < 0.0001:
		return Vector3.ZERO
	return q.get_axis() * ang


## Convierte una aceleracion angular (rad/s2, en espacio MUNDO) en un
## torque (N*m) usando la inercia real del cuerpo.
##
## Godot aplica el torque como aceleracion = torque / inercia, y la inercia
## esta en el eje LOCAL del cuerpo: hay que pasar al espacio local, aplicar
## el producto componente a componente y volver al mundo.
## (Medido: apply_torque(0,0,1) sobre una caja de 0,4x0,5x0,3 con masa 1
## -> 0,4878 rad/s = 1/0,034167 exacto.)
static func torque_de(b: PhysicalBone3D, alpha: Vector3) -> Vector3:
	var inercia: Vector3 = PhysicsServer3D.body_get_param(b.get_rid(), PhysicsServer3D.BODY_PARAM_INERTIA)
	if inercia == Vector3.ZERO:
		# Si el motor no da la inercia, se usa una constante.
		return alpha * TORQUE_SIN_INERCIA
	var xf := body_transform(b)
	var a_local := xf.basis.inverse() * alpha
	var t_local := Vector3(a_local.x * inercia.x, a_local.y * inercia.y, a_local.z * inercia.z)
	return xf.basis * t_local


## Transform REAL del cuerpo (en espacio MUNDO).
##
## NO se usa `b.global_transform`: el nodo PhysicalBone3D solo se actualiza
## con el callback de sincronizacion de estado del cuerpo, y ese callback NO
## se dispara en este motor de fisica (medido: el nodo se queda con la pose
## inicial). El servidor de fisica SI tiene la transform buena.
static func body_transform(b: PhysicalBone3D) -> Transform3D:
	if b == null:
		return Transform3D.IDENTITY
	return PhysicsServer3D.body_get_state(b.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)


## Velocidad angular REAL del cuerpo (por el mismo motivo que body_transform).
static func body_angular_velocity(b: PhysicalBone3D) -> Vector3:
	if b == null:
		return Vector3.ZERO
	return PhysicsServer3D.body_get_state(b.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)


## Velocidad lineal REAL del cuerpo.
static func body_linear_velocity(b: PhysicalBone3D) -> Vector3:
	if b == null:
		return Vector3.ZERO
	return PhysicsServer3D.body_get_state(b.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)


## Torque de reserva cuando el motor de fisica no devuelve la inercia del
## cuerpo.
const TORQUE_SIN_INERCIA := 0.03
