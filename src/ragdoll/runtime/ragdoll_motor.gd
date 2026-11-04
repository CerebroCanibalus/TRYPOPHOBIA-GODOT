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
## LEY UNICA (2026-11-04): SERVO EN CADENA, ERROR RELATIVO AL PADRE
## ---------------------------------------------------------------------------
##
## Es UNA sola ley. La diferencia con un servo absoluto es el MARCO del error:
## el hijo se sirve contra la pose que le impone su padre fisico, no contra
## una orientacion absoluta de mundo.
##
##   RAIZ (pelvis):
##     actual   = pose del HUESO en MUNDO   (servidor * body_offset^-1)
##     objetivo = pose del HUESO en MUNDO de la ANIMACION
##     e        = eje*angulo de (objetivo * actual^-1)      [QUATERNION]
##     alpha    = k*e - c*omega
##     omega    = omega + alpha*dt
##
##   HIJO (padre fisico P):
##     rel_objetivo = objetivo_P^-1 * objetivo_hijo
##     rel_actual   = actual_P^-1   * actual_hijo
##     e            = eje*angulo de (rel_objetivo * rel_actual^-1)
##     omega_rel    = actual_P^-1 * (omega_hijo - omega_P)
##     alpha_rel    = k*e - c*omega_rel
##     omega_hijo   = omega_P + actual_P.basis * (omega_rel + alpha_rel*dt)
##
## El padre MANDA: el hijo no puede apartarse de la pose que el padre le
## impone, asi que el joint y el servo dejan de pelear.
##
## POR QUE NO ABSOLUTO (medido 2026-11-04): con el servo absoluto el
## `spine.003` se iba a 41 grados y el `hand.R` a 90: la mano NO tiene track
## en el clip y, al perseguir una orientacion de mundo, se queda atada
## mientras el antebrazo se mueve. El hijo tiene que seguir al padre.
##
## El error va en QUATERNION siempre (eje real), nunca en euler: el euler
## reparte el angulo entre los tres ejes y con errores cercanos a 180 grados
## salta de golpe.
##
## El "padre fisico" es el ancestro mas cercano que tenga cuerpo: es el mismo
## que usa Godot para crear el joint
## (`PhysicalBoneSimulator3D::_get_physical_bone_parent` sube por la
## jerarquia), asi que el servo y la fisica comparten jerarquia.
##
## TRAMPA ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â el tope de velocidad angular: con 6 rad/s el servo no puede mover
## un hueso grande en un frame y el personaje se ve "aguado". El tope es de
## decenas (40).
##
## TRAMPA ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â comparar pose de HUESO con pose de CUERPO: el cuerpo puede no
## estar en el origen del hueso (`body_offset`). Se deshace antes de comparar.

## Rigidez del servo (rad/s2 por radian de error).
##
## La frecuencia natural es `w_n = sqrt(k)`: a 60 Hz hace falta
## `w_n*dt < 1` -> `k < 3600`. 4000 es el valor MEDIDO que aguanta con el
## rig de 15 cuerpos (la referencia usaba 3000 con 10 cuerpos).
@export var stiffness := 4000.0
## Amortiguamiento del servo (1/s): frena la velocidad angular.
## `zeta = c / (2*sqrt(k))` -> con 4000 y 80 sale 0,63.
@export var damping := 80.0
## Tope de la velocidad angular (rad/s). Con 6 el servo no puede mover un
## hueso grande: el personaje se ve "aguado" (medido).
@export var max_angular_speed := 40.0
## Escala de rigidez y amortiguamiento de los brazos (1 = igual que el resto).
@export var arm_spring_scale := 1.0
## Escala de rigidez de la COLUMNA (1 = igual que el resto).
##
## MEDIDO (2026-11-04): subirla EMPEORA. Con 1.5 el pecho pasa de 24 a 41
## grados y el cuerpo entero se descoloca (omega 3.75 rad/s, muslo 15.5
## grados). La razon es la del tope de estabilidad: `w_n*dt = sqrt(k)*dt` y con
## k=4000 ya esta en 1.05 (el limite). k=2500/c=100 tambien empeora (pecho 53
## grados y `up_col` cae a 0.25). El rango util de `stiffness` es este.
##
## El error del pecho NO se arregla con ganancia: es un REPARTO. Con el cono
## del pecho a 12 grados el pecho baja a 13 grados pero el hombro sube a 32;
## con 30 el pecho se va a 44 y el hombro queda en 5. El compromiso medido es
## el cono 20/15 (pecho 24, hombro 8.7) y es el que lleva la escena.
@export var column_spring_scale := 1.0
## Tope de la aceleracion angular (rad/s2) que se puede pedir en un tick.
## MEDIDO (2026-11-04): con 4000 el pecho se quedaba a 37 grados cuando el
## brazo estira (la reaccion del agarre). Con 20000 vuelve a 16.
@export var max_angular_accel := 20000.0


## Lleva los cuerpos a sus poses objetivo.
##
## `objetivos` = { bone_id : Transform3D en espacio MUNDO } (la pose del
## HUESO, no la del cuerpo).
## `grupos` = { bone_id : "arm" | "leg" | "column" | "" }.
## `physical_skel` = el esqueleto, para saber quien es el padre con cuerpo.
func drive(bones: Array[PhysicalBone3D], objetivos: Dictionary,
		grupos: Dictionary, delta: float,
		physical_skel: Skeleton3D = null) -> void:
	var cuerpos := {}
	for b in bones:
		var id := b.get_bone_id()
		if id >= 0:
			cuerpos[id] = b
	# El padre FISICO de cada hueso: el ancestro mas cercano con cuerpo.
	# Es el mismo que usa Godot para el joint.
	var padres := {}
	for b in bones:
		var id := b.get_bone_id()
		if id >= 0:
			padres[id] = _padre_con_cuerpo(physical_skel, id, cuerpos)
	# De la RAIZ a las puntas: el padre se resuelve antes que el hijo.
	var orden := _orden_por_profundidad(bones, physical_skel)
	var actuals := {}   ## id -> pose del hueso en MUNDO (la de este tick)
	var omegas := {}    ## id -> velocidad angular COMANDADA (MUNDO)
	for b in orden:
		var id := b.get_bone_id()
		if id < 0 or not objetivos.has(id):
			continue
		var objetivo: Transform3D = objetivos[id]
		# El cuerpo puede estar a media hueso: se deshace `body_offset`.
		var boff: Transform3D = b.get("body_offset")
		var actual := body_transform(b) * boff.affine_inverse()
		actuals[id] = actual
		var omega_real := body_angular_velocity(b)
		var k := stiffness
		var c := damping
		var grupo := String(grupos.get(id, ""))
		if grupo == "arm":
			k *= arm_spring_scale
			c *= arm_spring_scale
		elif grupo == "column":
			k *= column_spring_scale
			# Amortiguamiento critico: c ~ sqrt(k).
			c *= sqrt(column_spring_scale)
		var pid: int = int(padres.get(id, -1))
		var omega_nueva := Vector3.ZERO
		if pid >= 0 and actuals.has(pid) and omegas.has(pid):
			# --- HIJO: error RELATIVO al padre (la cadena) ---------------
			var obj_padre: Transform3D = objetivos[pid]
			var act_padre: Transform3D = actuals[pid]
			var omega_padre: Vector3 = omegas[pid]
			var rel_objetivo := obj_padre.basis.inverse() * objetivo.basis
			var rel_actual := act_padre.basis.inverse() * actual.basis
			var e := error_de_rotacion(rel_objetivo * rel_actual.inverse())
			var omega_rel := act_padre.basis.inverse() * (omega_real - omega_padre)
			var alpha := (k * e) - (c * omega_rel)
			alpha = alpha.limit_length(max_angular_accel)
			var omega_rel_nueva := (omega_rel + alpha * delta).limit_length(max_angular_speed)
			# El padre MANDA: el hijo gira con el padre mas su correccion.
			omega_nueva = omega_padre + act_padre.basis * omega_rel_nueva
		else:
			# --- RAIZ de la cadena: error ABSOLUTO -----------------------
			var e := error_de_rotacion(objetivo.basis * actual.basis.inverse())
			var alpha := (k * e) - (c * omega_real)
			alpha = alpha.limit_length(max_angular_accel)
			omega_nueva = (omega_real + alpha * delta).limit_length(max_angular_speed)
		omegas[id] = omega_nueva
		PhysicsServer3D.body_set_state(b.get_rid(),
			PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, omega_nueva)


## El ancestro mas cercano que TIENE CUERPO (el padre del joint).
##
## Es la misma regla que usa Godot 4.7 al crear los joints
## (`PhysicalBoneSimulator3D::_get_physical_bone_parent`): sube por la
## jerarquia del esqueleto hasta encontrar un hueso con cuerpo. Por eso los
## huesos "puente" (pelvis.L, shoulder.L, foot.L) no rompen la cadena.
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


## Los cuerpos ordenados de la RAIZ a las puntas (por profundidad).
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
## OJO: la ley ya NO usa torque (comanda velocidad angular). Se conserva
## porque `BalanceController` (componente inactivo) la referencia.
static func torque_de(b: PhysicalBone3D, alpha: Vector3) -> Vector3:
	var inercia: Vector3 = PhysicsServer3D.body_get_param(b.get_rid(),
		PhysicsServer3D.BODY_PARAM_INERTIA)
	if inercia == Vector3.ZERO:
		return alpha * TORQUE_SIN_INERCIA
	var xf := body_transform(b)
	var a_local := xf.basis.inverse() * alpha
	var t_local := Vector3(a_local.x * inercia.x, a_local.y * inercia.y, a_local.z * inercia.z)
	return xf.basis * t_local


## Ley de Hooke con amortiguamiento: `kÃƒâ€šÃ‚Â·x - cÃƒâ€šÃ‚Â·v`.
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
