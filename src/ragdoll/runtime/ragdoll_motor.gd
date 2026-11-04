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
## LEY DE CONTROL: SERVO JERARQUICO (2026-11-04)
## ---------------------------------------------------------------------------
##
## NUESTRO rig es una cadena articulada (la columna son 7 huesos, los brazos
## 2, las piernas 2). Servir cada hueso a una ORIENTACION ABSOLUTA uno por
## uno hace que cada uno pelee con su vecino: los jointsendeduran la
## posicion rigida del padre mientras el servo del hijo quiere llevarla a
## una orientacion absoluta distinta.
##
## MEDIDO (2026-11-04): con el servo absoluto, la pelvis giraba a 344
## grados por segundo de forma continua (un trompo), el personaje no ganaba
## terreno (0,5 m/s con un objetivo de 1,7) y la marcha no se leia.
##
## La ley correcta para una cadena es la JERARQUICA:
##
##   RAIZ de la cadena (la pelvis):
##     actual   = pose del HUESO en MUNDO
##     objetivo = pose del HUESO en MUNDO de la ANIMACION
##     e        = eje*angulo de (objetivo * actual^-1)      [MUNDO]
##     alpha    = k*e - c*omega                              [rad/s2]
##     omega    = omega + alpha*dt                           [rad/s]
##
##   HIJO (con padre fisico P):
##     rel_objetivo = objetivo_P^-1 * objetivo_hijo          [marco del padre]
##     rel_actual   = actual_P^-1   * actual_hijo            [marco del padre]
##     e            = eje*angulo de (rel_objetivo * rel_actual^-1)
##     omega_rel    = actual_P^-1 * (omega_hijo - omega_P)
##     alpha_rel    = k*e - c*omega_rel
##     omega_hijo   = omega_P + actual_P.basis * (omega_rel + alpha_rel*dt)
##
## El padre MANDA: el hijo no puedeapartarse de la pose que el padre le
## impone, asi que la cadena se comporta como un cuerpo articulado de
## verdad y el joint y el servo dejan de pelear.
##
## El "padre fisico" es el ancestro mas cercano que tenga cuerpo: es el
## mismo que usa Godot para crear el joint
## (`PhysicalBoneSimulator3D::_get_physical_bone_parent` sube por la
## jerarquia), asi que el servo y la fisica comparten la misma jerarquia.
##
## ---------------------------------------------------------------------------
## POR QUE NO HAY PD POR TORQUE (medido, no opinado)
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
## El servo no tiene error de equilibrio (el error manda la velocidad, no
## la fuerza) y cada hueso va a su pose: no hay cadena de errores
## acumulados ni pares que se cancelen.
##
## TRAMPA — el tope de velocidad angular
## ------------------------------------
## Con un tope de 6 rad/s el servo no puede mover un hueso grande en un
## frame: el personaje se queda "aguado" y los brazos y el pecho parecen
## NO seguir el ragdoll (sintoma medido). El tope tiene que ser de
## decenas de rad/s, no de 6.
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
@export var stiffness := 4000.0
## Amortiguamiento del servo (1/s): frena la velocidad angular.
## `zeta = c / (2*sqrt(k))` -> con 3000 y 80 sale 0,73 (algo por debajo de
## lo critico: el servo llega rapido y no oscila).
@export var damping := 80.0
## Tope de la velocidad angular (rad/s). Con 6 el servo no puede mover
## un hueso grande: el personaje se ve "aguado" (medido).
@export var max_angular_speed := 9999.0
## Escala de rigidez y amortiguamiento de los brazos que NO estan
## agarrando (1 = igual que el resto).
##
## MEDIDO (2026-11-04): con 0,25 los brazos se CAEN por la gravedad (el
## servo no los sujeta) y, con el personaje ya bien erguido, se veia con
## los brazos caidos. Ahora valen 1 (se sujetan en la pose del clip) y el
## IK los estira cuando se pulsa el clic.
@export var arm_spring_scale := 1.0
## Tope de la aceleracion angular (rad/s2) que se puede pedir en un
## tick. Es el equivalente al `limit_length(max_angular_force)` de la
## referencia (que ponia 9999, o sea, casi ninguno).
@export var max_angular_accel := 99999.0


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
	# El padre FISICO de cada hueso: el ancestro mas cercano con cuerpo.
	# Es el mismo que usa Godot para el joint, asi que el servo y la
	# articulacion comparten jerarquia (y no se pelean).
	var padres := {}
	for b in bones:
		var id := b.get_bone_id()
		if id >= 0:
			padres[id] = _padre_con_cuerpo(physical_skel, id, cuerpos)
	# Se procesa de la RAIZ a las puntas: el padre se resuelve antes que
	# el hijo (el servo del hijo necesita la velocidad que se le ha
	# comandado al padre).
	var orden := _orden_por_profundidad(bones, physical_skel)
	var actuals := {}   ## id -> pose del hueso en MUNDO (la de este tick)
	var omegas := {}    ## id -> velocidad angular COMANDADA (MUNDO)
	for b in orden:
		var id := b.get_bone_id()
		if id < 0 or not objetivos.has(id):
			continue
		var objetivo: Transform3D = objetivos[id]
		# La pose del HUESO en mundo: el cuerpo va a media hueso
		# (`body_offset`), asi que se deshace para comparar peras con peras.
		var boff: Transform3D = b.get("body_offset")
		var actual := body_transform(b) * boff.affine_inverse()
		actuals[id] = actual
		var omega_real := body_angular_velocity(b)
		var k := stiffness
		var c := damping
		if String(grupos.get(id, "")) == "arm":
			k *= arm_spring_scale
			c *= arm_spring_scale
		var pid: int = int(padres.get(id, -1))
		var omega_nueva := Vector3.ZERO
		if pid >= 0 and actuals.has(pid) and omegas.has(pid):
			# --- HIJO: error RELATIVO al padre (la cadena) ---------------
			var obj_padre: Transform3D = objetivos[pid]
			var act_padre: Transform3D = actuals[pid]
			var omega_padre: Vector3 = omegas[pid]
			# Las poses RELATIVAS al padre (en el marco del padre).
			var rel_objetivo := obj_padre.basis.inverse() * objetivo.basis
			var rel_actual := act_padre.basis.inverse() * actual.basis
			# OJO (medido 2026-11-04): aqui el error es el QUATERNION
			# (eje*angulo), NO el euler. El euler de una diferencia que se
			# acerca a 180 grados salta de golpe (la discontinuidad del
			# euler) y el servo EXPLOTA: medido, el personaje salio
			# disparado a 8,7 m de altura a 9,8 m/s.
			#
			# El euler solo se usa en la RAIZ de la cadena (la ley de la
			# referencia, ver mas abajo).
			#
			# Y el error es RELATIVO al padre: la diferencia se calcula con
			# las poses relativas (en el marco del padre).
			var e := error_de_rotacion(rel_objetivo * rel_actual.inverse())
			# La velocidad angular RELATIVA (en el marco del padre).
			var omega_rel := act_padre.basis.inverse() * (omega_real - omega_padre)
			var alpha := (k * e) - (c * omega_rel)
			alpha = alpha.limit_length(max_angular_accel)
			var omega_rel_nueva := omega_rel + alpha * delta
			omega_rel_nueva = omega_rel_nueva.limit_length(max_angular_speed)
			# El padre MANDA: el hijo gira con el padre mas su correccion.
			omega_nueva = omega_padre + act_padre.basis * omega_rel_nueva
		else:
			# --- RAIZ de la cadena: error ABSOLUTO (la ley de la
			#     referencia, que es la que hace que el personaje se tenga
			#     de pie) -----------------------------------------------
			#
			# OJO (medido): el error es el EULER de la diferencia, como en
			# la REFERENCIA:
			#   `rotation_difference = target.basis * current.basis.inverse()`
			#   `torque = hookes_law(rotation_difference.get_euler(), omega, k, c)`
			# Con el quaternion el error es mas CORTO (apunta en la
			# direccion real) pero tambien mas FUERTE: el pie, que esta en
			# el suelo, no puede plantarse (el servo lo obliga a girar a la
			# velocidad del clip) y la pierna barre a 1,4 m/s mientras el
			# cuerpo no avanza. Con el euler el vector del error se reparte
			# en los tres ejes y el servo cede mas: el pie se planta y el
			# cuerpo pasa por encima.
			# OJO (medido 2026-11-04): el error es el EULER de la
			# diferencia, como en la REFERENCIA (vease la nota de la
			# rama del hijo): el quaternion es mas fuerte y el pie no se
			# planta.
			var e := (objetivo.basis * actual.basis.inverse()).get_euler()
			var alpha := (k * e) - (c * omega_real)
			alpha = alpha.limit_length(max_angular_accel)
			omega_nueva = omega_real + alpha * delta
			omega_nueva = omega_nueva.limit_length(max_angular_speed)
		omegas[id] = omega_nueva
		PhysicsServer3D.body_set_state(b.get_rid(),
			PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, omega_nueva)


## El ancestro mas cercano que TIENE CUERPO (el padre del joint).
##
## Es la misma regla que usa Godot 4.7 al crear los joints
## (`PhysicalBoneSimulator3D::_get_physical_bone_parent`): sube por la
## jerarquia del esqueleto hasta encontrar un hueso con cuerpo. Por eso los
## huesos "puente" (pelvis.L, shoulder.L, foot.L) no rompen la cadena: el
## muslo se articula con la pelvis, el brazo con el pecho y el pie con la
## espinilla.
static func _padre_con_cuerpo(physical_skel: Skeleton3D, id: int,
		cuerpos: Dictionary) -> int:
	if physical_skel == null:
		return -1
	var padre := physical_skel.get_bone_parent(id)
	while padre >= 0:
		if cuerpos.has(padre):
			return padre
		padre = physical_skel.get_bone_parent(padre)
	return -1


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
## usa un valor pequeno.
static func inercia_media(b: PhysicalBone3D) -> float:
	var inercia: Vector3 = PhysicsServer3D.body_get_param(b.get_rid(),
		PhysicsServer3D.BODY_PARAM_INERTIA)
	if inercia == Vector3.ZERO:
		return 0.01
	return maxf((inercia.x + inercia.y + inercia.z) / 3.0, 0.0005)
