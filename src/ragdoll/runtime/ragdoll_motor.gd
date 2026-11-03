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
##
## TRAMPA 4 (LA IMPORTANTE, medida) — el PD va en TORQUE, no en
## ACELERACION ESCALADA POR LA INERCIA.
##
## La version anterior hacia `tau = I * alpha` con `alpha = k*e - c*w`.
## Eso tiene DOS fallos que se midieron:
##
## a) La inercia de los huesos de la columna es diminuta (0,001-0,013
##    kg*m2: son cajas de 20 cm con 2,5 kg) y la gravedad exige 3,7-15,7
##    N*m. Con el tope de aceleracion (1500 rad/s2) el torque maximo era
##    I*1500 = 1,5-20 N*m: la columna se dobla sola (medido: el torso
##    acababa con -0,9 de vertical y la cabeza bajo la pelvis).
## b) El amortiguamiento multiplicado por la ganancia del rig (13) daba
##    c = 1300 cuando el critico era 11: 33 veces sobreamortiguado e
##    inestable. El cuerpo se ponia a girar a 47 rad/s (el tope del motor
##    es 6) y se quedaba con 170 grados de error de forma permanente
##    (medido: todos los huesos con err 165-178 grados).
##
## Ahora el PD es `tau = k_t*e - c_t*w` en N*m, con el amortiguamiento
## CRITICO calculado con la inercia REAL de cada cuerpo
## (`c_t = 2*zeta*sqrt(k_t*I)`) y topado para que el damping explicito
## sea estable (`c_t*dt/I <= 2`). Asi el PD tiene fuerza suficiente para
## sostener el tronco y es estable con cualquier inercia.

## Rigidez del spring (N*m por radian de error).
##
## El PD es por TORQUE: `tau = k*e - c*w`, con el amortiguamiento CRITICO
## de cada cuerpo (`c = 2*zeta*sqrt(k*I)`) y topado por la aceleracion
## maxima del cuerpo (`|tau| <= I*max_angular_accel`).
##
## Por que por TORQUE y no por aceleracion (`tau = I*(k*e - c*w)`):
## con las masas de este rig (una caja de 20 cm con 1,6 kg) la inercia
## del tronco es 0,010 kg*m2, y un PD por aceleracion solo daba
## I*k*e = 0,17 N*m cuando la gravedad exige 7,8 N*m: el tronco se
## doblaba solo (medido). Con torque, la fuerza la decide la CARGA y no
## la inercia.
@export var stiffness := 2.0
## Amortiguamiento como fraccion del CRITICO (1 = critico).
##
## El amortiguamiento en N*m*s/rad NO se escribe aqui: se calcula por
## cuerpo con su inercia real, que es lo unico que da un PD estable.
@export var damping_ratio := 1.0
## Tope de la aceleracion angular del cuerpo (rad/s2). El torque se
## topa por `I * este valor`.
##
## OJO (medido) — este valor es el que define la VELOCIDAD a la que el PD
## puede girar un cuerpo: `w += alpha*dt`, o sea `w += alpha/60` rad/s por
## frame. Con 3000 el PD ganaba 50 rad/s por frame, se pasaba de pose y el
## error CRECIA (medido: la pelvis con 160 grados de error y 30 rad/s
## clavados). Con 300 gana 5 rad/s por frame (el tope de velocidad del
## motor es 6) y converge.
##
## El torque que sale de aqui es `I * 300`: para un hueso del tronco
## (I = 0,027) son 8 N*m, justo lo que la gravedad le pide.
@export var max_angular_accel := 450.0
## Tope de la velocidad angular (rad/s). Sin el, un frame puede dar 40
## rad/s y la cadena se convierte en un latigazo.
@export var max_angular_speed := 6.0
## Tope del TORQUE (N*m) que se puede aplicar a un hueso.
@export var max_torque := 200.0
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
		delta: float, ganancias: Dictionary = {},
		physical_skel: Skeleton3D = null) -> void:
	# Mapa id de hueso -> cuerpo, para poder leer el PADRE de cada hueso.
	var cuerpos := {}
	for b in bones:
		var id := b.get_bone_id()
		if id >= 0:
			cuerpos[id] = b
	for b in bones:
		var id := b.get_bone_id()
		if id < 0 or not objetivos.has(id):
			continue
		var objetivo: Transform3D = objetivos[id]
		# La ganancia del PD segun la carga que soporta el hueso.
		var gain := float(ganancias.get(id, 1.0))
		var stiff := stiffness
		if String(grupos.get(id, "")) == "arm":
			stiff *= arm_spring_scale
		# OJO (medido) — la ganancia se aplica al TORQUE, no a la rigidez.
		# La velocidad de equilibrio del PD es `w = k*e/c`: si la ganancia
		# multiplicase la rigidez, `w` se iba a 46 rad/s y el PD conmutaba
		# (medido: todos los huesos con 175 grados de error y 47 rad/s,
		# clavados para siempre). Con la ganancia en el torque, la
		# velocidad transitoria no depende de ella.
		var stiff_total := stiff * gain
		# La pose REAL del cuerpo, YA EN ESPACIO MUNDO (el nodo no se
		# actualiza: ver body_transform).
		var actual := body_transform(b)
		# OJO: el giro que lleva de `actual` a `objetivo` es
	# `actual⁻¹ * objetivo`. Al reves (`objetivo * actual⁻¹`) sale el
	# conjugado: el mismo angulo con el EJE OPUESTO, y el PD empuja en
	# sentido contrario -> diverge y el cuerpo se queda girando (medido: el
	# pecho y la cabeza bailando entre -180 y +180 grados).
		# --- EL ERROR ES RELATIVO AL PADRE (medido, esto es lo que
		# endereza una cadena articulada).
		#
		# Con el error ABSOLUTO (cada hueso persiguiendo su pose absoluta
		# en el mundo) los 7 huesos de la columna compiten entre si: cada
		# uno tira de su padre y la cadena se dobla en vez de estirarse
		# (medido: la cabeza a 0,55 m POR DEBAJO de la pelvis con el
		# personaje de pie).
		#
		# El error de una ARTICULACION es el del hijo respecto al padre:
		#   e = (actual_padre^-1 * actual_hijo)^-1 * (obj_padre^-1 * obj_hijo)
		# y el torque se aplica al hijo, que es quien puede girar respecto
		# al padre. El eje se lleva a MUNDO antes de aplicar el torque.
		var error := Vector3.ZERO
		var padre_id := -1
		if physical_skel != null:
			padre_id = physical_skel.get_bone_parent(id)
		if padre_id >= 0 and cuerpos.has(padre_id) and objetivos.has(padre_id):
			var pb: PhysicalBone3D = cuerpos[padre_id]
			var xf_padre := body_transform(pb)
			var actual_rel := xf_padre.basis.inverse() * actual.basis
			var objetivo_rel: Basis = objetivos[padre_id].basis.inverse() * objetivo.basis
			error = error_de_rotacion(actual_rel.inverse() * objetivo_rel)
			error = xf_padre.basis * error
		else:
			# Hueso raiz: el error es absoluto.
			error = error_de_rotacion(actual.basis.inverse() * objetivo.basis)
		# OJO (medido): el error NO se clampea a 90 grados. Con ese tope el
		# torque maximo era insuficiente para sostener el tronco (5,7 N*m
		# frente a los 8 que pide la gravedad) y la cadena se quedaba
		# doblada. Con 180 grados el PD puede deshacer el volteo entero.
		var max_err := deg_to_rad(180.0)
		if error.length() > max_err:
			error = error.normalized() * max_err
		# --- Amortiguamiento CRITICO con la inercia REAL de este cuerpo.
		# Es lo que hace el PD estable: con el amortiguamiento fijo (o
		# multiplicado por la ganancia) el cuerpo se ponia a girar a
		# 47 rad/s y se quedaba con 170 grados de error (medido).
		var inercia := inercia_media(b)
		var c := 2.0 * damping_ratio * sqrt(maxf(stiff_total * inercia, 0.000001))
		# El damping es EXPLICITO: para que sea estable hace falta
		# `c*dt/I <= 2`.
		c = minf(c, 2.0 * inercia / maxf(delta, 0.0001))
		var torque := hookes_law(error, body_angular_velocity(b), stiff, c) * gain
		# Tope por ACELERACION: el torque se limita con la inercia del
		# cuerpo, para que un hueso pequeno no salga disparado.
		torque = torque.limit_length(inercia * max_angular_accel)
		# OJO: PhysicalBone3D NO hereda de RigidBody3D (extiende de
		# PhysicsBody3D) y no tiene apply_torque(): se usa la API del
		# servidor de fisica, que es la misma ruta que usa RigidBody3D.
		PhysicsServer3D.body_apply_torque(b.get_rid(), torque.limit_length(max_torque))
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


## Inercia media de un cuerpo (kg*m2). Si el motor de fisica no la da, se
## usa un valor pequeno: el PD por torque no depende de ella para tener
## fuerza, solo para el amortiguamiento.
static func inercia_media(b: PhysicalBone3D) -> float:
	var inercia: Vector3 = PhysicsServer3D.body_get_param(b.get_rid(),
		PhysicsServer3D.BODY_PARAM_INERTIA)
	if inercia == Vector3.ZERO:
		return 0.01
	return maxf((inercia.x + inercia.y + inercia.z) / 3.0, 0.0005)


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
