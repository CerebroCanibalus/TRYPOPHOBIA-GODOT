class_name WaterSurface
extends Node3D
## Réplica en CPU de la solución de olas de `ocean_stylized.gdshader`. :v
##
## Es el corazon de la buoyancy: para que un cuerpo CAVALGUE la ola que se ve,
## la altura fisica y la del pixel tienen que salir de la MISMA cuenta y del
## MISMO reloj. Tres decisiones, todas por un bug medido:
##
## 1. RELLOJ COMPARTIDO. `wave_time` es un uniform del shader que empuja este
##    nodo (Time.get_ticks_msec/1000). Sin el, el shader usaria TIME, que NO
##    es legible desde GDScript y que ademas rueda cada 3600 s: la fase
##    fisica se desfasaria de la visual y los cuerpos flotarian a distinta
##    altura que la ola que se ve. :v
## 2. MISMOS PARAMETROS. Longitudes/amplitudes/velocidades se leen del
##    material, y la direccion de viento de los shader globals — exactamente
##    los valores que recibe el shader. Si alguien mueve `swell_height` en el
##    material, la fisica se entera sola. :v
## 3. SIN LOD. El shader atenua las olas lejos de la camara (`wave_lod_near`
##    = 150 m). La fisica usa amplitud COMPLETA: el jugador no flota a 150 m,
##    y cerca de la camara el LOD ya vale 1. :v
##
## API publica:
##   altura_en(p)          -> Y de mundo de la superficie en p.xz
##   altura_en_xz(x, z)    -> lo mismo sin construir un Vector3
##   velocidad_vertical(p) -> d(altura)/dt en m/s, para que el cuerpo siga
##                            la subida de la ola en vez de perseguirla :v
##   relativa_en(p)        -> altura sobre el plano base (marea + olas)

@export_group("Enlazado")
## Material del shader. Vacio = se busca el primero de la escena que use
## ocean_stylized (o el que este en la malla `malla`). :v
@export var material: ShaderMaterial
## Malla del agua. Su Y de mundo es la base del nivel. Vacio = se busca la
## malla hermana con ocean_stylized, y si no hay, manda global_position. :v
@export var malla: NodePath
## Nodo Ocean (dueno de marea y viento). Vacio = se busca en la escena; si no
## hay, la marea sale del material (`tide_level`) horneada. :v
@export var ocean: NodePath
## Escribe `wave_time` en el material. Desactivalo SOLO si otro nodo ya manda
## el reloj (dos escritores del mismo uniform = una pelea silenciosa). :v
@export var empujar_reloj := true

@export_group("Ajuste")
## Amplitud de las olas para la FISICA. 1 = identico al shader. Bajalo solo
## si el oleaje mareea a los personajes; no arregla desfases. :v
@export_range(0.0, 2.0, 0.01) var escala_olas := 1.0
## false = superficie plana (aisla un bug de muestreo del resto del sistema).
@export var olas_activas := true

var _mat: ShaderMaterial
var _malla_node: MeshInstance3D
var _ocean_node: Ocean
var _tiene_reloj := false
var _reloj_no_avisa := false

# --- estado cacheado, recalculado en _process ---------------------------------
var _t := 0.0                 # reloj del oleaje (segundos, el mismo del shader)
var _marea := 0.0
var _vel_marea := 0.0
var _marea_prev := 0.0
var _calm := 1.0
var _wd := Vector2(0.0, 1.0)  # direccion del viento normalizada (XZ del mundo)
var _d1 := Vector2(1.0, 0.0)
var _d2 := Vector2(0.0, -1.0)
var _wi := 0.0
# cada ola: (longitud, amplitud, velocidad, chop) — igual que el shader
var _w0 := Vector4(34.0, 0.70, 2.2, 0.60)
var _w1 := Vector4(12.0, 0.22, 3.0, 0.40)
var _w2 := Vector4(4.5, 0.06, 3.8, 0.0)
var _spread := 0.7
var _ripple_center := Vector3.ZERO
var _ripple_time := 0.0
var _ripple_strength := 0.0


func _ready() -> void:
	add_to_group("water_surface")
	_resolver_nodos()
	_leer_parametros()
	_t = Time.get_ticks_msec() * 0.001
	_actualizar_viento()
	_empujar_reloj()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# Reloj monotónico del motor, NO un acumulador propio: es el mismo numero
	# que se empuja al shader y que (casi) es TIME, asi que el corte de
	# arranque entre "shader con TIME" y "shader con wave_time" es nulo. :v
	_t = Time.get_ticks_msec() * 0.001
	_actualizar_viento()
	_actualizar_marea(delta)
	_leer_ripple()
	_empujar_reloj()


# ---------------------------------------------------------------------------
#  API publica
# ---------------------------------------------------------------------------

## Y de mundo de la superficie del agua en el punto `p`. :v
func altura_en(p: Vector3) -> float:
	return altura_en_xz(p.x, p.z)


func altura_en_xz(x: float, z: float) -> float:
	return _base_y() + _marea + _olas_altura(x, z)


## Altura sobre el plano base (marea + olas), para HUD/debug. :v
func relativa_en(p: Vector3) -> float:
	return _marea + _olas_altura(p.x, p.z)


## Velocidad vertical de la superficie en m/s. Diferencia finita de la marea
## (asi vale lo que sea que este mandando Ocean, ciclo o red) + derivada
## analitica de las olas. :v
func velocidad_vertical(p: Vector3) -> float:
	if not olas_activas:
		return _vel_marea
	var v := 0.0
	v += _v_ola(Vector2(p.x, p.z), _wd, _w0)
	v += _v_ola(Vector2(p.x, p.z), _d1, _w1)
	v += _v_ola(Vector2(p.x, p.z), _d2, _w2)
	return v * escala_olas + _vel_marea


## Reloj del oleaje, por si otro sistema quiere replicar la misma fase (por
## ejemplo un sistema de particulas de espuma). :v
func tiempo_olas() -> float:
	return _t


# ---------------------------------------------------------------------------
#  Oleaje — replica literal de solve_waves()/add_wave() del shader :v
# ---------------------------------------------------------------------------

func _olas_altura(x: float, z: float) -> float:
	if not olas_activas:
		return 0.0
	var p := Vector2(x, z)
	var h := 0.0
	h += _h_ola(p, _wd, _w0)
	h += _h_ola(p, _d1, _w1)
	h += _h_ola(p, _d2, _w2)
	h += _anillo_sonido(x, z)
	return h * escala_olas


func _h_ola(p: Vector2, dir: Vector2, w: Vector4) -> float:
	var k := TAU / maxf(w.x, 0.01)
	var omega := k * w.z
	var amp := w.y * _calm
	return amp * sin(p.dot(dir) * k + _t * omega)


## d/dt de _h_ola: la ola sube y baja, y un cuerpo que solo recibe una fuerza
## media se hunde respecto a la cresta. :v
func _v_ola(p: Vector2, dir: Vector2, w: Vector4) -> float:
	var k := TAU / maxf(w.x, 0.01)
	var omega := k * w.z
	var amp := w.y * _calm
	return amp * omega * cos(p.dot(dir) * k + _t * omega)


## Radar de sonido: el mismo anillo que pinta el shader, inyectado en la misma
## solucion de olas. Emitelo con Ocean.emit_noise(). :v
func _anillo_sonido(x: float, z: float) -> float:
	if _ripple_strength <= 0.001:
		return 0.0
	var rp := Vector2(x, z) - Vector2(_ripple_center.x, _ripple_center.z)
	var rr := rp.length()
	var radius := _ripple_time * 7.0
	var ring := sin((rr - radius) * 1.6) * exp(-rr * 0.10) * exp(-_ripple_time * 0.55)
	return ring * _ripple_strength * 0.16


# ---------------------------------------------------------------------------
#  Sincronizacion con shader, globals y Ocean :v
# ---------------------------------------------------------------------------

func _actualizar_viento() -> void:
	# El viento sale de Ocean, NO de RenderingServer.global_shader_parameter_get():
	# esa funcion esta reservada al editor y en runtime emite ERROR por frame
	# ("This function should never be used outside the editor"). Sin Ocean, se
	# usan los mismos defaults que trae project.godot: intensidad 0 y direccion
	# (0,0,0) -> el shader aplica su guarda anti-NaN y queda (0,1). :v
	var dir := Vector3(0.0, 0.0, 1.0)
	var inten := 0.0
	if _ocean_node != null and is_instance_valid(_ocean_node):
		inten = _ocean_node.wind_intensity_actual()
		dir = _ocean_node.wind_direction_actual()
	_wi = clampf(inten, 0.0, 1.0)

	# Guarda anti-NaN identica a la del shader: (0,0,0) -> (0,1). :v
	var n := dir.normalized() if dir.length() > 1e-4 else Vector3(0.0, 0.0, 1.0)
	var l := Vector2(n.x, n.z).length()
	_wd = Vector2(n.x, n.z) / l if l > 1e-4 else Vector2(0.0, 1.0)

	var wperp := Vector2(-_wd.y, _wd.x)
	var spread := _spread * (0.35 + 0.65 * _wi)
	var a1 := spread * 0.9
	var a2 := -spread * 1.4
	_d1 = (_wd * cos(a1) + wperp * sin(a1)).normalized()
	_d2 = (_wd * cos(a2) + wperp * sin(a2)).normalized()
	_calm = 1.0 - _wi * 0.55


func _actualizar_marea(delta: float) -> void:
	var nueva := 0.0
	if _ocean_node != null and is_instance_valid(_ocean_node):
		nueva = _ocean_node.current_tide_level()
	elif _mat != null:
		nueva = _pf(_mat, "tide_level", 0.0)
	if delta > 0.0:
		_vel_marea = (nueva - _marea) / delta
	_marea_prev = _marea
	_marea = nueva


func _leer_ripple() -> void:
	if _mat == null:
		return
	var c: Variant = _mat.get_shader_parameter("ripple_center")
	if c is Vector3:
		_ripple_center = c as Vector3
	_ripple_time = _pf(_mat, "ripple_time", 0.0)
	_ripple_strength = _pf(_mat, "ripple_strength", 0.0)


## Lee del material las mismas constants que usa el shader. Los defaults aqui
## SON los del shader: si el .tres no trae la clave, la fisica y la vista
## coinciden igual. :v
func _leer_parametros() -> void:
	if _mat == null:
		return
	_w0 = Vector4(_pf(_mat, "swell_length", 34.0), _pf(_mat, "swell_height", 0.70),
			_pf(_mat, "swell_speed", 2.2), _pf(_mat, "swell_chop", 0.60))
	_w1 = Vector4(_pf(_mat, "ripple_length", 12.0), _pf(_mat, "ripple_height", 0.22),
			_pf(_mat, "ripple_speed", 3.0), _pf(_mat, "ripple_chop", 0.40))
	_w2 = Vector4(_pf(_mat, "chop_length", 4.5), _pf(_mat, "chop_height", 0.06),
			_pf(_mat, "chop_speed", 3.8), _pf(_mat, "chop_chop", 0.0))
	_spread = _pf(_mat, "wave_spread", 0.7)


func _empujar_reloj() -> void:
	if not empujar_reloj or _mat == null:
		return
	if not _tiene_reloj:
		if not _reloj_no_avisa:
			_reloj_no_avisa = true
			push_warning("[water] el shader no declara `wave_time`: la fisica CPU \
no compartira reloj con la vista (aniade el uniform y pasalo por aqui). :v")
		return
	_mat.set_shader_parameter("wave_time", _t)


func _resolver_nodos() -> void:
	if not malla.is_empty():
		_malla_node = get_node_or_null(malla) as MeshInstance3D
	if _malla_node == null:
		_malla_node = _buscar_malla(get_parent())

	# Orden: material explicito -> material de la malla -> el de la escena.
	if material != null:
		_mat = material
	elif _malla_node != null:
		_mat = _material_de(_malla_node)
	if _mat == null:
		_mat = _buscar_material(get_parent())
	if _mat == null:
		push_warning("[water] WaterSurface sin material: la altura quedara plana. :v")

	if not ocean.is_empty():
		_ocean_node = get_node_or_null(ocean) as Ocean
	if _ocean_node == null:
		_ocean_node = _buscar_ocean(get_tree().current_scene)

	if _mat != null and _mat.shader != null:
		for p in _mat.shader.get_shader_uniform_list():
			if String(p.name) == "wave_time":
				_tiene_reloj = true
				break


func _base_y() -> float:
	if _malla_node != null and is_instance_valid(_malla_node):
		return _malla_node.global_transform.origin.y
	return global_position.y


func _buscar_material(desde: Node) -> ShaderMaterial:
	var mi := _buscar_malla(desde)
	return _material_de(mi) if mi != null else null


## Material de una malla: primero el override, despues el de la superficie. :v
func _material_de(mi: MeshInstance3D) -> ShaderMaterial:
	if mi.material_override is ShaderMaterial:
		return mi.material_override as ShaderMaterial
	if mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m is ShaderMaterial:
				return m as ShaderMaterial
	return null


## Malla hermana cuyo material usa ocean_stylized — el mismo criterio que
## Ocean._find_ocean_material(), para que los dos nodos hablen del mismo mar. :v
func _buscar_malla(desde: Node) -> MeshInstance3D:
	if desde == null:
		return null
	for n in desde.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null:
			continue
		var mats: Array[Material] = []
		if mi.material_override != null:
			mats.append(mi.material_override)
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				if m != null:
					mats.append(m)
		for m in mats:
			var sm := m as ShaderMaterial
			if sm != null and sm.shader != null and sm.shader.resource_path != "" \
					and "ocean_stylized" in sm.shader.resource_path:
				return mi
	return null


func _buscar_ocean(desde: Node) -> Ocean:
	if desde == null:
		return null
	if desde is Ocean:
		return desde as Ocean
	for c in desde.get_children():
		var hit := _buscar_ocean(c)
		if hit != null:
			return hit
	return null


func _pf(mat: ShaderMaterial, nombre: String, dflt: float) -> float:
	var v: Variant = mat.get_shader_parameter(nombre)
	return dflt if v == null else float(v)
