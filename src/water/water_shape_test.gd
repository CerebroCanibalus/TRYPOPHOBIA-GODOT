class_name WaterShapeTest
extends RefCounted
## Test de un punto contra la forma de un CollisionShape3D, en espacio LOCAL
## del shape. :v
##
## El agua NO usa PhysicsDirectSpaceState.intersect_point(): el test analitico
## de Box/Cylinder/Sphere no cuesta una query al physics server y da el mismo
## resultado. Como cada punto se consulta 60 veces por segundo y por cuerpo,
## eso se nota. :v
##
## Dos modos:
##   abierto = false  la forma cerrada es el volumen entero (AirVolume).
##   abierto = true   la forma solo da XZ + FONDO; la tapa de arriba no cuenta
##                    porque la pone WaterSurface, que se mueve con las olas y
##                    con la marea. Si el tope lo decidiera la caja, el nivel
##                    quedaria clavado al autor y la marea no serviria. :v


## ¿El punto (local al shape) esta dentro de la forma?
static func contiene(cs: CollisionShape3D, punto_local: Vector3, abierto: bool) -> bool:
	if cs == null or cs.shape == null or cs.disabled:
		return false
	var p := punto_local
	var s := cs.shape

	if s is BoxShape3D:
		var half := (s as BoxShape3D).size * 0.5
		if absf(p.x) > half.x or absf(p.z) > half.z:
			return false
		if p.y < -half.y:
			return false
		return abierto or p.y <= half.y

	if s is CylinderShape3D:
		var cyl := s as CylinderShape3D
		var r := cyl.radius
		if p.x * p.x + p.z * p.z > r * r:
			return false
		var hh := cyl.height * 0.5
		if p.y < -hh:
			return false
		return abierto or p.y <= hh

	if s is SphereShape3D:
		# Esfera cerrada siempre: no tiene "suelo" separable del techo. :v
		return p.length_squared() <= (s as SphereShape3D).radius ** 2

	if s is CapsuleShape3D:
		var cap := s as CapsuleShape3D
		var hh := maxf(cap.height * 0.5 - cap.radius, 0.0)
		var q := Vector3(p.x, clampf(p.y, -hh, hh), p.z)
		return p.distance_squared_to(q) <= cap.radius ** 2

	# Fallback conservador: el AABB de la forma. Cubre ConvexPolygon y
	# cualquier forma nueva sin romper el volumen. :v
	var laabb := aabb_de(s)
	if abierto:
		if p.y < laabb.position.y:
			return false
		return p.x >= laabb.position.x and p.x <= laabb.end.x \
				and p.z >= laabb.position.z and p.z <= laabb.end.z
	return laabb.has_point(p)


## AABB de `aabb` llevado a otra base. `AABB.transformed()` no existe en
## Godot 4.7: hay que envolver los 8 vertices y unirlos a mano. :v
static func aabb_transformada(aabb: AABB, xf: Transform3D) -> AABB:
	var out := AABB(xf * aabb.get_endpoint(0), Vector3.ZERO)
	for i in range(1, 8):
		out = aabb_unir(out, AABB(xf * aabb.get_endpoint(i), Vector3.ZERO))
	return out


## Union de dos AABB (min/max por eje). Funcion propia para no depender de
## `merge`/`enclose`, que cambiaron de nombre entre 3.x y 4.x. :v
static func aabb_unir(a: AABB, b: AABB) -> AABB:
	var pos := Vector3(minf(a.position.x, b.position.x), minf(a.position.y, b.position.y),
			minf(a.position.z, b.position.z))
	var fin := Vector3(maxf(a.end.x, b.end.x), maxf(a.end.y, b.end.y),
			maxf(a.end.z, b.end.z))
	return AABB(pos, fin - pos)


## AABB en el espacio LOCAL de la forma.
##
## Shape3D NO tiene get_aabb() en Godot 4.7 (solo get_debug_mesh), y usar
## `var x := sh.get_aabb()` ni siquiera compila: la llamada resuelve a Variant
## y el tipado estatico aborta con "Cannot infer the type". De ahi este
## helper analitico por tipo, con la malla de debug como red de seguridad. :v
static func aabb_de(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var s := (shape as BoxShape3D).size
		return AABB(-s * 0.5, s)
	if shape is CylinderShape3D:
		var c := shape as CylinderShape3D
		var r := c.radius
		return AABB(Vector3(-r, -c.height * 0.5, -r), Vector3(r * 2.0, c.height, r * 2.0))
	if shape is SphereShape3D:
		var r2 := (shape as SphereShape3D).radius
		var d := r2 * 2.0
		return AABB(Vector3(-r2, -r2, -r2), Vector3(d, d, d))
	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		var rr := cap.radius
		return AABB(Vector3(-rr, -cap.height * 0.5, -rr),
				Vector3(rr * 2.0, cap.height, rr * 2.0))
	# Cualquier otra forma: su malla de debug (el editor ya la calcula para
	# dibujar el gizmo, no es codigo nuevo de riesgo). :v
	var m := shape.get_debug_mesh()
	if m != null:
		return m.get_aabb()
	return AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)


## ¿Tiene esta forma tapa utilitaria (Box/Cylinder), la unica que soporta
## modo abierto? Se avisa UNA VEZ al montar el nivel, no en cada punto. :v
static func soporta_abierto(cs: CollisionShape3D) -> bool:
	if cs == null or cs.shape == null:
		return false
	return cs.shape is BoxShape3D or cs.shape is CylinderShape3D


## Seccion horizontal de la forma en la altura `y` (espacio local del shape).
## Devuelve (semiancho X, semiancho Z, AREA de la seccion). :v
##
## Es lo que hace que la buoyancy no mienta en formas redondeadas: muestrear
## las esquinas de una capsula da puntos que estan FUERA de la capsula, la
## fraccion de sumersion sale inflada y el cuerpo se hunde mas de lo que
## debe — con el jugador flotando con la cabeza bajo el agua. Con la seccion
## real se pondera cada capa por su area y la fraccion es un estimador
## honesto del volumen sumergido. :v
static func seccion(shape: Shape3D, y: float) -> Vector3:
	if shape is BoxShape3D:
		var s := (shape as BoxShape3D).size
		if absf(y) > s.y * 0.5:
			return Vector3.ZERO
		return Vector3(s.x * 0.5, s.z * 0.5, s.x * s.z)

	if shape is CylinderShape3D:
		var c := shape as CylinderShape3D
		if absf(y) > c.height * 0.5:
			return Vector3.ZERO
		return Vector3(c.radius, c.radius, PI * c.radius * c.radius)

	if shape is SphereShape3D:
		var r := (shape as SphereShape3D).radius
		var d := r * r - y * y
		if d <= 0.0:
			return Vector3.ZERO
		var rr := sqrt(d)
		return Vector3(rr, rr, PI * d)

	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		var a := maxf(cap.height * 0.5 - cap.radius, 0.0)
		var rr := cap.radius
		if absf(y) > a:
			var dy := absf(y) - a
			var d := cap.radius * cap.radius - dy * dy
			if d <= 0.0:
				return Vector3.ZERO
			rr = sqrt(d)
		return Vector3(rr, rr, PI * rr * rr)

	# Fallback: el AABB de la forma. Cubre ConvexPolygon y formas nuevas. :v
	var la := aabb_de(shape)
	if y < la.position.y or y > la.end.y:
		return Vector3.ZERO
	return Vector3(la.size.x * 0.5, la.size.z * 0.5, la.size.x * la.size.z)
