class_name WaterBody
extends Node
## Componente universal de sumersión y empuje. Se engancha a CUALQUIER cuerpo
## fisico — CharacterBody3D (Iza), PhysicalBone3D (ragdoll), RigidBody3D
## (cajas, restos) — y funciona igual con cuerpos de distinta complexion. :v
##
## MULTI-CUERPO: un mismo componente puede flotar VARIOS cuerpos a la vez.
## El ragdoll es 10 PhysicalBone3D con 21 kg repartidos: si solo flotaba el
## Body (10 kg) recibia 140 N de empuje contra 206 N de peso de TODO el
## cuerpo => neto -3,15 m/s² y se hundia (medido, no supuesto). Ahora cada
## hueso muestrea y flota por su cuenta. :v
##
## Como generaliza sin saber quien es el cuerpo:
##  * MUESTREA por CAPAS con peso: en cada altura se mide la seccion REAL de
##    la forma (box/cylinder/sphere/capsule) y cada punto pesa
##    area_seccion * alto_capa / puntos — la fraccion de sumersion es un
##    estimador honesto del volumen sumergido (muestrear las esquinas del
##    AABB da puntos fuera de una capsula). :v
##  * RESUELVE cada punto contra el mundo de agua (WaterQuery), donde las
##    bolsas de aire restan. :v
##  * CONVIERTE a aceleracion solo con DENSIDADES: a =
##    fraccion * (rho_fluido / rho_cuerpo) * g. La masa se cancela. :v
##  * APUNTA a cada cuerpo: fuerzas por sonda (RigidBody3D, rueda con la
##    ola) o velocidad lineal (CharacterBody3D y PhysicalBone3D). :v
##
## Senales:
##   sumersio_cambiada(sumergido)  — entraste o saliste del agua
##   cabeza_cambiada(sumergida)    — la cabeza entro o salio: Oxygen cuelga
##                                    de aqui, y cualquier HUD tambien :v
##
## API publica: `fraccion` (0..1), `sumergido`, `cabeza_sumergida`,
## `profundidad`, `nivel`, `corriente`, `aceleracion_empuje()`,
## `fijar_cuerpo()`, `fijar_cuerpos_extra()`, `fijar_cabeza()`.

signal sumersio_cambiada(sumergido: bool)
signal cabeza_cambiada(sumergida: bool)

## Puntos por capa de muestreo: 1 centro + 4 de anillo. :v
const PUNTOS_POR_CAPA: int = 5

## Muestras de UN cuerpo: rejilla con pesos, rellenas cada tick. :v
class Muestra extends RefCounted:
	var cuerpo: PhysicsBody3D
	var puntos: PackedVector3Array = []
	var pesos: PackedFloat32Array = []
	var gps: PackedVector3Array = []
	var subs: PackedFloat32Array = []
	var peso_total: float = 0.0
	var fraccion: float = 0.0
	var aabb: AABB = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)


@export_group("Cuerpo")
## Cuerpo principal: el de la CABEZA, la profundidad y las senales. Vacio =
## el padre del componente. :v
@export var cuerpo: NodePath
## Capas verticales sobre la altura del cuerpo. 6 x 5 = 30 muestras por
## cuerpo, bien para una capsula de 1,5 m. :v
@export_range(2, 24, 1) var capas := 6
## Punto de respiracion en local, relativo al cuerpo PRINCIPAL. Vacio = 85%
## de la altura del AABB hacia arriba. NO cuenta para la fraccion. :v
@export var cabeza_local := Vector3.ZERO

@export_group("Fluido")
## Densidad media del cuerpo en kg/m3 (500 = madera clara, 700 = persona,
## 1040 = agua de mar, 2500 = roca). Por DEBAJO de la del fluido flota. :v
@export_range(50.0, 12000.0, 10.0) var densidad_cuerpo := 700.0
## Densidad de rescate si el punto no cae en ningun WaterVolume. :v
@export_range(50.0, 2000.0, 1.0) var densidad_agua := 1000.0
## Multiplica el empuje. >1 = boya, <1 = se hunde mas despacio. :v
@export_range(0.0, 3.0, 0.05) var factor_empuje := 1.0
## Gravedad en m/s2. <0 = la del proyecto (es la que usa tu script). :v
@export var gravedad := -1.0

@export_group("Arrastre")
## Arrastre lineal del fluido en 1/s. Aplica RELATIVO a la corriente. :v
@export_range(0.0, 30.0, 0.1) var arrastre := 4.0
## Arrastre angular (solo RigidBody3D) en 1/s. :v
@export_range(0.0, 30.0, 0.1) var arrastre_angular := 2.0
@export var aplica_empuje := true
@export var aplica_corriente := true
## Ancho de la rampa de transicion en la linea de flotacion, en metros. :v
@export_range(0.02, 1.0, 0.01) var gradiente_superficie := 0.25
## No aplicar empuje mientras el cuerpo esta APOYADO. Un CharacterBody3D no
## tiene reaccion normal: sin esto, el personaje de pie en el fondo (o en el
## muelle, con las olas a ras) flotaria hacia arriba y pareceria que salta.
## Para CharacterBody3D se lee solo de is_on_floor(); para PhysicalBone3D
## el host escribe `apoyado` (lo hace ragdoll_character con sus raycasts). :v
@export var suprimir_empuje_al_apoyar := true
## Estado de apoyo para cuerpos que no son CharacterBody3D. :v
var apoyado := false
## Supresion MANUAL del empuje, que escribe el host cada tick. Es lo que hace
## que Ctrl hunda de verdad: sin esto el empuje (hasta 14 m/s2 con rho 700)
## siempre gana al tirito de hundimiento y flotas aunque empujes hacia abajo.
## El ragdoll lo pone en true con `crouch`; cuando no, vuelves a flotar. :v
var empuje_suprimido := false

## Fraccion del VOLUMEN total bajo el agua, 0..1 (ponderada por seccion).
var fraccion: float = 0.0
var sumergido: bool = false
var cabeza_sumergida: bool = false
## Profundidad del ORIGEN del cuerpo PRINCIPAL bajo la superficie.
var profundidad: float = 0.0
## Y de mundo de la superficie sobre el origen del principal.
var nivel: float = 0.0
var corriente: Vector3 = Vector3.ZERO
## Volumen del agua que contiene el origen del principal, o null.
var volumen: WaterVolume = null

var _cuerpo: PhysicsBody3D
var _extras: Array[PhysicsBody3D] = []
var _muestras: Array[Muestra] = []
var _peso_total: float = 0.0
var _densidad_usada: float = 1000.0
var _cabeza_local := Vector3.ZERO
var _aabb_principal: AABB = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
var _sin_cuerpo_avisado := false


func _ready() -> void:
	if not cuerpo.is_empty():
		_cuerpo = get_node_or_null(cuerpo) as PhysicsBody3D
	if _cuerpo == null:
		_cuerpo = get_parent() as PhysicsBody3D
	if _cuerpo != null:
		_reconstruir()
	# Sin cuerpo NO se avisa aqui: los hijos _ready ANTES que el padre, y el
	# ragdoll resuelve su hueso Body en el _ready del padre y llama
	# fijar_cuerpo(). El aviso real sale en el primer tick. :v


## Fija el cuerpo PRINCIPAL (cabeza/profundidad/senales). Hace falta en el
## ragdoll: el hueso `Body` se reparenta al PhysicalBoneSimulator3D en
## _ready, asi que su ruta no existe al montar la escena. :v
func fijar_cuerpo(nuevo: PhysicsBody3D) -> void:
	_cuerpo = nuevo
	_reconstruir()


## Cuerpos EXTRA que flotan con este mismo componente. El ragdoll pasa aqui
## sus 10 huesos: sin ellos solo flota el Body y el resto cuelga y lo
## hunde (140 N de empuje contra 206 N de peso, medido). :v
func fijar_cuerpos_extra(lista: Array) -> void:
	_extras.clear()
	for n in lista:
		var b := n as PhysicsBody3D
		if b != null and b != _cuerpo and not _extras.has(b):
			_extras.append(b)
	_reconstruir()


## Mueve el punto de respiracion EN TIEMPO REAL. El ragdoll lo usa para seguir
## el hueso Head, que se mueve respecto al Body con cada pose. :v
func fijar_cabeza(local: Vector3) -> void:
	cabeza_local = local
	_cabeza_local = local


## Busca el WaterBody dentro de un arbol. Para scripts de jugador que no
## quieran depender del nombre del nodo. :v
static func buscar_en(raiz: Node) -> WaterBody:
	if raiz == null:
		return null
	if raiz is WaterBody:
		return raiz as WaterBody
	for c in raiz.get_children():
		var hit := buscar_en(c)
		if hit != null:
			return hit
	return null


## Vuelve a leer shapes y a generar las muestras de todos los cuerpos. :v
func _reconstruir() -> void:
	_muestras.clear()
	if _cuerpo != null:
		_muestras.append(_nueva_muestra(_cuerpo))
		_aabb_principal = _muestras[0].aabb
		_cabeza_local = cabeza_local if cabeza_local != Vector3.ZERO \
				else _aabb_principal.position + Vector3(0.0, _aabb_principal.size.y * 0.85, 0.0)
	for b in _extras:
		_muestras.append(_nueva_muestra(b))
	_peso_total = 0.0
	for m in _muestras:
		_peso_total += m.peso_total
		if _peso_total <= 0.0:
			push_warning("[water] %s: los cuerpos no aportaron muestras. :v" % name)


func recalcular_muestreo() -> void:
	_reconstruir()


## Construye la rejilla de UN cuerpo: capas sobre su AABB, puntos dentro de
## su seccion real, cada uno con su peso de volumen. :v
func _nueva_muestra(b: PhysicsBody3D) -> Muestra:
	var m := Muestra.new()
	m.cuerpo = b
	m.aabb = _aabb_de(b)
	var formas := _formas_de(b)
	for f in formas:
		var forma: Shape3D = f.forma
		var centro: Vector3 = f.centro
		var esc: Vector3 = f.esc
		var la := WaterShapeTest.aabb_de(forma)
		var y_min := centro.y + la.position.y * esc.y
		var y_max := centro.y + la.end.y * esc.y
		var alto := maxf(y_max - y_min, 1e-4)
		for i in capas:
			var y0 := y_min + alto * (float(i) / float(capas))
			var y1 := y_min + alto * (float(i + 1) / float(capas))
			var ym := (y0 + y1) * 0.5
			var y_local := (ym - centro.y) / maxf(esc.y, 1e-5)
			var sec := WaterShapeTest.seccion(forma, y_local)
			var area := sec.z * esc.x * esc.z
			if area <= 1e-5:
				continue
			var hx := maxf(sec.x * esc.x, 1e-3) * 0.6
			var hz := maxf(sec.y * esc.z, 1e-3) * 0.6
			var peso := area * (y1 - y0) / float(PUNTOS_POR_CAPA)
			m.puntos.append(Vector3(centro.x, ym, centro.z))
			m.pesos.append(peso)
			for a in 4:
				var ang := PI * 0.5 * float(a)
				m.puntos.append(Vector3(centro.x + cos(ang) * hx, ym,
						centro.z + sin(ang) * hz))
				m.pesos.append(peso)
	if m.puntos.is_empty():
		push_warning("[water] %s: cuerpo sin muestras; nada flotara. :v" % name)
		m.puntos.append(Vector3.ZERO)
		m.pesos.append(1.0)
	m.gps.resize(m.puntos.size())
	m.subs.resize(m.puntos.size())
	for w in m.pesos:
		m.peso_total += w
	return m


func _physics_process(delta: float) -> void:
	if _cuerpo == null or not is_instance_valid(_cuerpo):
		if not _sin_cuerpo_avisado:
			_sin_cuerpo_avisado = true
			push_warning("[water] WaterBody (%s) sin cuerpo fisico: nada que \
flotar. Pasa la ruta en `cuerpo` o llama fijar_cuerpo(). :v" % name)
		return
	_muestrear()
	_notificar_cambios()
	_aplicar(delta)


# ---------------------------------------------------------------------------
#  Muestreo
# ---------------------------------------------------------------------------

func _muestrear() -> void:
	var suma := 0.0
	var peso := 0.0
	var cor := Vector3.ZERO
	var vol_ref: WaterVolume = null

	for m in _muestras:
		if not is_instance_valid(m.cuerpo):
			continue
		var xf := m.cuerpo.global_transform
		var suma_c := 0.0
		for i in m.puntos.size():
			var gp := xf * m.puntos[i]
			m.gps[i] = gp
			var vol := WaterQuery.volumen_en(gp)
			if vol == null:
				m.subs[i] = 0.0
				continue
			var h := vol.nivel_agua_en(gp)
			# Rampa sobre `gradiente_superficie` metros alrededor de la
			# superficie: a h == gp.y vale 0.5 y nunca hay salto. :v
			var sub := clampf((h - gp.y) / gradiente_superficie + 0.5, 0.0, 1.0)
			m.subs[i] = sub
			if sub <= 0.0:
				continue
			var w := m.pesos[i] * sub
			suma += w
			peso += m.pesos[i]
			suma_c += w
			cor += vol.corriente * w
			if vol_ref == null:
				vol_ref = vol
		m.fraccion = clampf(suma_c / maxf(m.peso_total, 1e-6), 0.0, 1.0)

	fraccion = clampf(suma / maxf(_peso_total, 1e-6), 0.0, 1.0)
	corriente = cor / maxf(suma, 1e-6) if suma > 0.0 else Vector3.ZERO

	# El ORIGEN del principal decide nivel/profundidad/densidad. :v
	volumen = WaterQuery.volumen_en(_cuerpo.global_position)
	if volumen == null:
		volumen = vol_ref
	if volumen != null:
		_densidad_usada = volumen.densidad
		nivel = volumen.nivel_agua_en(_cuerpo.global_position)
		profundidad = maxf(nivel - _cuerpo.global_position.y, 0.0)
	else:
		_densidad_usada = densidad_agua
		nivel = 0.0
		profundidad = 0.0


func _notificar_cambios() -> void:
	var nuevo := fraccion > 0.02
	if nuevo != sumergido:
		sumergido = nuevo
		sumersio_cambiada.emit(nuevo)

	var cabeza := false
	var gp := _cuerpo.global_transform * _cabeza_local
	var vol := WaterQuery.volumen_en(gp)
	cabeza = vol != null and gp.y <= vol.nivel_agua_en(gp)
	if cabeza != cabeza_sumergida:
		cabeza_sumergida = cabeza
		cabeza_cambiada.emit(cabeza)


# ---------------------------------------------------------------------------
#  Aplicacion
# ---------------------------------------------------------------------------

## Aceleracion de empuje vertical sobre el cuerpo PRINCIPAL, en m/s2. :v
func aceleracion_empuje() -> float:
	if not aplica_empuje or empuje_suprimido or fraccion <= 0.0 or _cuerpo == null:
		return 0.0
	return _fraccion_de(_cuerpo) * (_densidad_usada / maxf(densidad_cuerpo, 1.0)) \
			* _gravedad() * factor_empuje


## Fraccion sumergida de un cuerpo concreto de este componente. :v
func _fraccion_de(b: PhysicsBody3D) -> float:
	for m in _muestras:
		if m.cuerpo == b:
			return m.fraccion
	return fraccion


## Impulso vertical para TODOS los cuerpos del componente, de golpe.
##
## Es lo que hace la salida del agua: si solo se lanza el hueso Body, los
## otros 9 huesos (11 kg) se quedan quietos y las articulaciones se comen el
## impulso en un par de ticks — medido: vy=8 aplicado y a los 0,5 s el cuerpo
## seguia en la superficie. Lanzando todos a la vez no hay pelea interna. :v
func impulso_vertical(v: float) -> void:
	for m in _muestras:
		if not is_instance_valid(m.cuerpo):
			continue
		if m.cuerpo is CharacterBody3D:
			var cb := m.cuerpo as CharacterBody3D
			cb.velocity.y = maxf(cb.velocity.y, v)
		elif m.cuerpo is PhysicalBone3D:
			var pb := m.cuerpo as PhysicalBone3D
			pb.linear_velocity.y = maxf(pb.linear_velocity.y, v)
		elif m.cuerpo is RigidBody3D:
			var rb := m.cuerpo as RigidBody3D
			rb.linear_velocity.y = maxf(rb.linear_velocity.y, v)


func _aplicar(delta: float) -> void:
	var g := _gravedad()
	var sin_empuje := (suprimir_empuje_al_apoyar and _esta_apoyado()) \
			or empuje_suprimido
	var ratio := _densidad_usada / maxf(densidad_cuerpo, 1.0)
	for m in _muestras:
		if not is_instance_valid(m.cuerpo):
			continue
		if m.cuerpo is RigidBody3D:
			# Los RigidBody3D SIEMPRE reciben empuje: una caja de madera
			# apoyada en el fondo tiene que flotar (es lo fisicamente
			# correcto, y la reaccion normal del suelo la aguanta sola). :v
			_aplicar_rigido(m, g, ratio)
		elif m.cuerpo is CharacterBody3D:
			# OJO: CharacterBody3D se llama `velocity`; solo RigidBody3D y
			# PhysicalBone3D tienen `linear_velocity`. :v
			var cb := m.cuerpo as CharacterBody3D
			cb.velocity = _velocidad_con_agua(cb.velocity, m, g, ratio, delta,
					sin_empuje)
		elif m.cuerpo is PhysicalBone3D:
			var pb := m.cuerpo as PhysicalBone3D
			pb.linear_velocity = _velocidad_con_agua(pb.linear_velocity, m, g,
					ratio, delta, sin_empuje)


## ¿Esta apoyado el cuerpo? CharacterBody3D lo sabe solo; los demas usan el
## flag `apoyado` que escribe su script host. :v
func _esta_apoyado() -> bool:
	if _cuerpo is CharacterBody3D:
		return (_cuerpo as CharacterBody3D).is_on_floor()
	return apoyado


## Camino de los cuerpos que NO reciben fuerzas de fuera. Solo se mueve la
## velocidad lineal, igual que ya hace ragdoll_character con SPEED. :v
func _velocidad_con_agua(v: Vector3, m: Muestra, g: float, ratio: float,
		delta: float, sin_empuje: bool) -> Vector3:
	if m.fraccion <= 0.0:
		return v
	if aplica_empuje and not sin_empuje:
		v.y += m.fraccion * ratio * g * factor_empuje * delta
	var k := clampf(arrastre * m.fraccion * delta, 0.0, 1.0)
	var objetivo := corriente if aplica_corriente else Vector3.ZERO
	return v.lerp(objetivo, k)


## Camino RigidBody3D: una fuerza POR MUESTRA, aplicada en el offset de la
## muestra, con peso proporcional al volumen que representa — asi una caja
## larga rueda con la ola en vez de subir entera y plana. :v
func _aplicar_rigido(m: Muestra, g: float, ratio: float) -> void:
	var rb := m.cuerpo as RigidBody3D
	var masa := rb.mass
	if masa <= 0.0:
		return
	var pos := rb.global_position
	# gravity_scale entra en la cuenta: un objeto agarrado (gravity_scale = 0)
	# no flota, lo sueltas y vuelve a la cuenta. :v
	var con_gravedad := rb.gravity_scale > 0.001
	var escala := ratio * g * factor_empuje * rb.gravity_scale * masa if con_gravedad else 0.0

	for i in m.puntos.size():
		var sub := m.subs[i]
		if sub <= 0.001 or escala <= 0.0:
			continue
		var peso := m.pesos[i] * sub / maxf(m.peso_total, 1e-6)
		rb.apply_force(Vector3.UP * (escala * peso), m.gps[i] - pos)

	if m.fraccion <= 0.001:
		return
	var objetivo := corriente if aplica_corriente else Vector3.ZERO
	var rel := rb.linear_velocity - objetivo
	rb.apply_force(-rel * (arrastre * m.fraccion * masa))
	var inercia := masa * maxf(m.aabb.size.length_squared(), 0.01) / 6.0
	rb.apply_torque(-rb.angular_velocity * (arrastre_angular * m.fraccion * inercia))


func _gravedad() -> float:
	if gravedad > 0.0:
		return gravedad
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


# ---------------------------------------------------------------------------
#  Geometria
# ---------------------------------------------------------------------------

## AABB de colision de un cuerpo en SU espacio local (por shape owners). :v
func _aabb_de(b: PhysicsBody3D) -> AABB:
	var aabb := AABB()
	var primero := true
	for oid in b.get_shape_owners():
		if b.is_shape_owner_disabled(oid):
			continue
		var oxf := b.shape_owner_get_transform(oid)
		for si in b.shape_owner_get_shape_count(oid):
			var sh := b.shape_owner_get_shape(oid, si)
			if sh == null:
				continue
			var la := WaterShapeTest.aabb_transformada(
					WaterShapeTest.aabb_de(sh), oxf)
			if primero:
				aabb = la
				primero = false
			else:
				aabb = WaterShapeTest.aabb_unir(aabb, la)
	if primero:
		push_warning("[water] %s: el cuerpo no tiene shapes; muestreo de 1 m³. :v" % name)
		aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	return aabb


## Shapes de un cuerpo normalizados a {forma, centro, esc} en su espacio,
## todos SIN ROTACION para que la seccion horizontal sea valida. :v
func _formas_de(b: PhysicsBody3D) -> Array:
	var out: Array = []
	for oid in b.get_shape_owners():
		if b.is_shape_owner_disabled(oid):
			continue
		var oxf := b.shape_owner_get_transform(oid)
		for si in b.shape_owner_get_shape_count(oid):
			var sh := b.shape_owner_get_shape(oid, si)
			if sh == null:
				continue
			var esc := Vector3(oxf.basis.x.length(), oxf.basis.y.length(),
					oxf.basis.z.length())
			# Rotacion, no escala: una escala (2,0,0) sigue alineada con el eje
			# y la seccion sigue siendo valida multiplicandola por `esc`. :v
			var dx := oxf.basis.x.normalized() if oxf.basis.x.length() > 1e-6 \
					else Vector3.RIGHT
			var dy := oxf.basis.y.normalized() if oxf.basis.y.length() > 1e-6 \
					else Vector3.UP
			var girado := not dx.is_equal_approx(Vector3.RIGHT) \
					or not dy.is_equal_approx(Vector3.UP)
			if girado:
				# Rotada: se muestrea su AABB (un BoxShape en el centro del
				# AABB transformado). Conservador y sin trigonometria. :v
				var la := WaterShapeTest.aabb_de(sh)
				var box := BoxShape3D.new()
				box.size = la.size
				out.append({"forma": box, "centro": oxf * la.get_center(),
						"esc": Vector3.ONE})
				continue
			out.append({"forma": sh, "centro": oxf.origin, "esc": esc})
	return out
