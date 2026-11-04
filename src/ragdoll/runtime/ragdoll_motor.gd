extends Node
class_name RagdollMotor
## El MOTOR del ragdoll: lleva cada cuerpo fisico a su pose objetivo.
##
## Es un componente puro: no sabe nada de animacion, camara ni IK. Solo
## recibe "para cada cuerpo, cual es su pose objetivo" y comanda la
## velocidad angular necesaria. Asi se puede reusar con cualquier rig y
## probar aislado.
##
## ---------------------------------------------------------------------------
## LEY DE CONTROL (2026-11-03) — SERVO DE VELOCIDAD CON OBJETIVO ABSOLUTO
## ---------------------------------------------------------------------------
##
## Para cada cuerpo, en cada tick de fisica:
##
##   actual   = pose del HUESO en MUNDO   (cuerpo del servidor * body_offset^-1)
##   objetivo = pose del HUESO en MUNDO de la ANIMACION
##   e        = eje*angulo de (objetivo * actual^-1)      [MUNDO]
##   alpha    = k*e - c*omega                             [rad/s2]
##   omega   += alpha*dt                                  [rad/s]
##
## Es la MISMA ley que el proyecto de referencia
## (`tools/active_ragdoll_reference`, el unico ragdoll que se ha visto
## andar de verdad) y la UNICA que aguanta con Box3D.
##
## POR QUE NO HAY PD POR TORQUE (medido, noopinado)
## ----------------------------------------------------
## Se probo un PD "serio": error RELATIVO al padre, torque aplicado como
## PAR (+tau al hijo, -tau al padre), dos inercias (propia y de subarbol)
## y un controlador de balance aparte (upright + centro de masas + muelle
## de altura). Medido: la pelvis se ponia a girar a 40 rad/s constantes
## desde el primer frame (el balance le devolvia el par de todos los hijos
## con un tope de aceleracion de 3000 rad/s2) y el personaje se volcaba.
## El PD por torque tambien tiene ERROR DE EQUILIBRIO: la gravedad gana y
## el tronco se queda inclinado 20-29 grados.
##
## El servo de velocidad no tiene error de equilibrio (el error manda la
## velocidad, no la fuerza) y cada hueso va a su pose ABSOLUTA: no hay
## cadena de errores acumulados ni pares que se cancelen.
##
## TRAMPA — el tope de velocidad angular
## ------------------------------------
## Con un tope de 6 rad/s el servo no puede mover un hueso grande en un
## frame: el personaje se queda "aguado" y los brazos y el pecho parecen
## NO seguir al ragdoll (sintoma medido). El tope tiene que ser de
## decenas de rad/s (40), no de 6.
##
## TRAMPA — comparar pose de HUESO con pose de CUERPO
## --------------------------------------------------
## El cuerpo NO esta en el origen del hueso: esta a MEDIA HUESO
## (`body_offset`). Comparar el objetivo (origen del hueso) con el cuerpo
## (media hueso) deja un error constante y el servo gira el hueso para
## taparlo: el personaje sale torcido. Por eso se deshace el
## `body_offset` antes de comparar.

## Rigidez del servo (rad/s2 por radian de error).
##
## La frecuencia natural es `w_n = sqrt(k)`: a 60 Hz hace falta
## `w_n*dt < 1` -> `k < 3600`. El valor 3000 es el de la referencia (la
## escena la sobreescribia a 3000 sobre 4000 del script).
@export var stiffness := 3000.0
## Amortiguamiento del servo (1/s): frena la velocidad angular.
## `zeta = c / (2*sqrt(k))` -> con 3000 y 80 sale 0.73 (algo por debajo de
## lo critico: el servo llega rapido y no oscila).
@export var damping := 80.0
## Tope de la velocidad angular (rad/s). Con 6 el servo no puede mover
## un hueso grande: el personaje se ve "aguado" (medido).
@export var max_angular_speed := 40.0
## Escala de rigidez y amortiguamiento de los brazos que NO estan
## agarrando (1 = igual que el resto). 0.25 = los brazos cuelgan.
@export var arm_spring_scale := 0.25
## Tope de la aceleracion angular (rad/s2) que se puede pedir en un
## tick. Es el equivalente al `limit_length(max_angular_force)` de la
## referencia (que ponia 9999, o sea, casi ninguno).
@export var max_angular_accel := 4000.0
## Ley por TORQUE: en vez de COMANDAR la velocidad angular (que pisa la
## que calculo el solver y hace que los joints ganen siempre), se aplica un
## PARQUE de fuerza: `tau = I*(k*e - c*w)`. El solver de joints reparte
## esas fuerzas de forma consistente y la cadena aguanta el peso.
@export var por_torque := false
## Amortiguamiento como fraccion del CRITICO (1 = critico).
@export var damping_ratio := 1.0
## Tope del torque (N*m) que se puede aplicar a un hueso.
@export var max_torque := 400.0
## Rigidez del servo POR TORQUE (N*m por radian de error).
##
## Es la UNICA rigidez que no depende de la inercia para el error de
## equilibrio: con un servo en ACELERACION el error es
## `e = tau_gravedad / (I * k)` y con la pelvis del Shiba (I = 0,11
## kg*m2 sosteniendo 30 kg de torso a 0,3 m = 88 N*m) salen 15
## GRADOS de error en la pelvis: el personaje se inclina y se hunde (medido).
## Con k en N*m/rad el error es `e = tau_gravedad / k` y no depende de la
## inercia.
@export var stiffness_torque := 900.0
## Limite de estabilidad por cuerpo: `k < 4*I/dt^2` (a 60 Hz).
## Se aplica solo a los cuerpos que se doblarian con una rigidez global.
@export var limite_estabilidad := true


## Lleva los cuerpos a sus poses objetivo.
##
## `objetivos` = { bone_id : Transform3D en espacio MUNDO } (la pose del
## HUESO, no la del cuerpo).
## `grupos` = { bone_id : "arm" | "leg" | "column" | "" }.
## `ganancias` = { bone_id : multiplicador } (opcional; se IGNORA: la ley
## es de aceleracion y multiplicar la rigidez cambiaria la frecuencia
## natural. Ver la nota de `pd_gain` en el documento normativo).
func drive(bones: Array[PhysicalBone3D], objetivos: Dictionary,
		grupos: Dictionary, delta: float, ganancias: Dictionary = {},
		physical_skel: Skeleton3D = null) -> void:
	# Mapa id de hueso -> cuerpo.
	var cuerpos := {}
	for b in bones:
		var id := b.get_bone_id()
		if id >= 0:
			cuerpos[id] = b
	# Se procesa de la RAIZ a las puntas: el hijo necesita la velocidad
	# angular que se le ha COMMANDADO al padre (ver abajo).
	var orden := _orden_por_profundidad(bones, physical_skel)
	# Velocidad angular COMANDADA por cuerpo (no la real): el hijo hereda
	# la de su padre.
	var omega_cmd := {}
	for b in orden:
		var id := b.get_bone_id()
		if id < 0 or not objetivos.has(id):
			continue
		var objetivo: Transform3D = objetivos[id]
		# La pose del HUESO en mundo: el cuerpo va a media hueso
		# (`body_offset`), asi que se deshace para comparar peras con peras.
		var boff: Transform3D = b.get("body_offset")
		var actual := body_transform(b) * boff.affine_inverse()
		var omega_real := body_angular_velocity(b)
		var k := stiffness
		var c := damping
		if String(grupos.get(id, "")) == "arm":
			k *= arm_spring_scale
			c *= arm_spring_scale
		var e := Vector3.ZERO
		var omega_rel := Vector3.ZERO
		var padre_id := -1
		if physical_skel != null:
			padre_id = physical_skel.get_bone_parent(id)
		var pb: PhysicalBone3D = null
		if padre_id >= 0:
			pb = cuerpos.get(padre_id)
		# --- ERROR ABSOLUTO: la orientacion del hueso en el MUNDO (la del
		# personaje entero). Es la ley de la referencia.
		#
		# OJO (medido): la variante por ARTICULACION (el error del hijo
		# respecto al padre) se midio y NO funciona: cada hueso manda una
		# velocidad angular INCOMPATIBLE con la de su padre, el solver de
		# joints tiene que elegir y gana el joint -> el servo no puede con
		# el peso (medido: la columna obedecia con 2-8 grados de error pero
		# las piernas se quedaban en 27-80 y el personaje en cuclillas).
		e = error_de_rotacion(objetivo.basis * actual.basis.inverse())
		# El amortiguamiento va contra la velocidad angular PROPIA del
		# cuerpo.
		omega_rel = omega_real
		var alpha := (k * e) - (c * omega_rel)
		alpha = alpha.limit_length(max_angular_accel)
		if por_torque:
			# PARQUE: la ley del servo en N*m por radian de error.
			#
			# El error de equilibrio es `e = tau_gravedad / k`: NO depende
			# de la inercia del cuerpo (con la ley en aceleracion,
			# `e = tau_gravedad / (I*k)`, y con la pelvis del Shiba salian
			# 15 GRADOS de error: el personaje se inclinaba y se hundia).
			#
			# El amortiguamiento es el CRITICO de cada cuerpo:
			# `c = 2*zeta*sqrt(k*I)`.
			var inercia := inercia_media(b)
			var kt := stiffness_torque
			if limite_estabilidad:
				# `w_n = sqrt(k/I)` y hace falta `w_n*dt < 2` ->
				# `k < 4*I/dt^2`. Un hueso con poca inercia (la pelvis)
				# se doblaria con una rigidez global: se le recorta.
				var tope := 0.8 * 4.0 * inercia / maxf(delta * delta, 0.000001)
				kt = minf(kt, tope)
			# El amortiguamiento critico `c = 2*zeta*sqrt(k*I)` NO SIEMPRE
			# es estable: hace falta `c*dt/I <= 2` y en un hueso pequeno
			# (el pie: I = 0,0024) el critico se pasa y el servo EXPLOTA
			# (medido: el pie a 180 rad/s). Se recorta al limite de
			# estabilidad.
			var ct := 2.0 * damping_ratio * sqrt(maxf(kt * inercia, 0.000001))
			var ct_max := 0.9 * 2.0 * inercia / maxf(delta, 0.000001)
			ct = minf(ct, ct_max)
			var torque := (kt * e) - (ct * omega_rel)
			torque = torque.limit_length(max_torque)
			PhysicsServer3D.body_apply_torque(b.get_rid(), torque)
			continue
		var omega_nueva := omega_real + alpha * delta
		omega_nueva = omega_nueva.limit_length(max_angular_speed)
		omega_cmd[id] = omega_nueva
		PhysicsServer3D.body_set_state(b.get_rid(),
			PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, omega_nueva)


## Los cuerpos ordenados de la RAIZ a las puntas (por profundidad en el
## esqueleto). El servo necesita ese orden: el hijo hereda la velocidad
## angular que se le ha comandado al padre.
static func _orden_por_profundidad(bones: Array[PhysicalBone3D],
		physical_skel: Skeleton3D) -> Array[PhysicalBone3D]:
	if physical_skel == null:
		return bones
	var prof := {}
	for b in bones:
		var id := b.get_bone_id()
		if id < 0:
			continue
		prof[id] = _profundidad(physical_skel, id, prof)
	var out: Array[PhysicalBone3D] = []
	out.append_array(bones)
	out.sort_custom(func(a: PhysicalBone3D, c: PhysicalBone3D) -> bool:
		var ia := a.get_bone_id()
		var ic := c.get_bone_id()
		return int(prof.get(ia, 0)) < int(prof.get(ic, 0)))
	return out


## Profundidad de un hueso en el esqueleto (0 = raiz).
static func _profundidad(physical_skel: Skeleton3D, id: int, memo: Dictionary) -> int:
	if memo.has(id):
		return int(memo[id])
	memo[id] = 0
	var padre := physical_skel.get_bone_parent(id)
	if padre < 0:
		return 0
	var p := _profundidad(physical_skel, padre, memo) + 1
	memo[id] = p
	return p


## Convierte una aceleracion angular (rad/s2, en espacio de MUNDO) en un
## torque (N*m) usando la inercia real del cuerpo.
##
## Godot aplica el torque como aceleracion = torque/inertia, y la inercia
## esta en el eje LOCAL del cuerpo: hay que pasar al espacio local, aplicar
## el producto componente a componente y volver al mundo.
static func torque_de(b: PhysicalBone3D, alpha: Vector3) -> Vector3:
	var inercia: Vector3 = PhysicsServer3D.body_get_param(b.get_rid(),
		PhysicsServer3D.BODY_PARAM_INERTIA)
	if inercia == Vector3.ZERO:
		return alpha * TORQUE_SIN_INERCIA
	var xf := body_transform(b)
	var a_local := xf.basis.inverse() * alpha
	var t_local := Vector3(a_local.x * inercia.x, a_local.y * inercia.y, a_local.z * inercia.z)
	return xf.basis * t_local


## Ley de Hooke con amortiguamiento: `k·x - c·v`.
static func hookes_law(desplazamiento: Vector3, velocidad: Vector3,
		rigidez: float, amortiguamiento: float) -> Vector3:
	return (rigidez * desplazamiento) - (amortiguamiento * velocidad)


## Vector de error de una rotacion (eje * angulo), en espacio de MUNDO.
##
## Es el vector de error correcto para un servo de orientacion: el
## quaternion da el EJE REAL de la rotacion (el euler reparte el angulo
## entre los tres ejes y el vector resultante no apunta en la direccion
## real: con euler los brazos se quedaban a 116 grados del clip).
static func error_de_rotacion(diferencia: Basis) -> Vector3:
	var q := diferencia.get_rotation_quaternion()
	# Camino corto: si el quaternion es negativo, su inverso es el mas corto.
	if q.w < 0.0:
		q = -q
	var ang := q.get_angle()
	if ang < 0.0001:
		return Vector3.ZERO
	return q.get_axis() * ang


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


## Constante de torque cuando el motor de fisica no da la inercia.
const TORQUE_SIN_INERCIA := 0.03


## Inercia media de un cuerpo (kg*m2). Si el motor de fisica no la da, se
## usa un valor pequeno. (La ley actual no la usa: es una aceleracion
## comandada, no un torque.)
static func inercia_media(b: PhysicalBone3D) -> float:
	var inercia: Vector3 = PhysicsServer3D.body_get_param(b.get_rid(),
		PhysicsServer3D.BODY_PARAM_INERTIA)
	if inercia == Vector3.ZERO:
		return 0.01
	return maxf((inercia.x + inercia.y + inercia.z) / 3.0, 0.0005)
