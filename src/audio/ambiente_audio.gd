@tool
class_name AmbienteAudio
extends Node3D
## NODO ÚNICO de audio ambiental configurable por mapa (Fases A+B) :v
##
## Arrastra src/audio/ambiente_audio.tscn a la escena, rellena `zonas` en el
## inspector y ya suena. Encapsulado: todo su estado (buses, reproductores,
## gizmos, overlay) vive DENTRO de este nodo — se pueden instanciar varios
## en la misma escena sin pisarse (grupos de bus distintos = apilables :v
## aditivamente; mismo grupo = bus compartido).
##
## Modelo de mezcla:
##  - Cada SoundZona aporta un peso 0..1 según distancia del oyente :v
##    (math puro, sin Area3D). Varias zonas conviven: los soundscapes se
##    crossfadean solos porque sus pesos se mueven en direcciones opuestas.
##  - Peso por soundscape = MAX entre zonas que lo comparten (no se duplica).
##  - Por pista: objetivo = volumen_base × peso × intensidad × duck :v
##    con fade exponencial 1-exp(-delta/tau), tau = fade/3 (estable a :v
##    cualquier FPS — mismo criterio que underwater_fx.gd).
##
## API pública:
##  - atenuar(db, segundos) / restaurar(segundos) → ducking manual (A2) :v
##  - set_intensidad(v) → escala todas las capas (tormentas/gameplay) :v
##  - señal scape_activado/apagado(nombre) → para HUD/gameplay :v
##  - F3 (solo builds de debug) → overlay de diagnóstico :v

## Un soundscape empezó a sonar en esta instancia :v
signal scape_activado(nombre: String)
## Un soundscape dejó de sonar por completo en esta instancia :v
signal scape_apagado(nombre: String)

## Refcount de instancias vivas por bus-grupo (static: compartido entre :v
## todas las instancias de la clase, sobrevive a cambios de escena)
static var _refcount_grupos: Dictionary = {}

const REFRECO_GIZMOS := 0.25
const REFRECO_OVERLAY := 0.1
const VOL_CERO := 0.0005
const DB_PISO := -80.0

## Zonas del mapa; cada una aporta su SoundScape con su peso :v
@export var zonas: Array[SoundZona] = []
## Bus agrupador. Instancias con el MISMO grupo comparten bus (volumen :v
## maestro conjunto); grupos distintos se apilan sin cortarse.
@export var grupo: String = "ambiente"
## Volumen maestro de ESTA instancia (dB), encima va el duck :v
@export var volumen_db: float = 0.0
## Escala global de todas las capas 0..1 (para tormentas u oscuridad) :v
@export var intensidad: float = 1.0
## Nivel ENTERO actual, 0..2. Es el selector de intensidad de lluvia/viento:
## 0 = Suave, 1 = Moderada, 2 = Fuerte. No es un volumen — manda SOBRE QUE
## CAPAS suenan, mirando `SoundCapa.nivel_min/nivel_max`. El volumen fino sigue
## siendo `intensidad` y `SoundCapa.volumen_base` (:v
@export_range(0, 2, 1) var nivel: int = 2
## Soundscapes que suenan SIEMPRE a peso pleno, sin necesitar zona :v
##
## El sistema de zonas asume que lo que suena esta en un SITIO del mapa, y la
## lluvia y el viento no: se oyen en todas partes. Con `zonas` vacias un
## soundscape no se activaria jamas, porque los pesos salen solo de las zonas.
@export var globales: Array[SoundScape] = []
## Nodo oyente explícito (vacío = Camera3D activa del viewport) :v
@export var oyente: NodePath = NodePath()

@export_group("Gizmos")
## Ver las zonas como wireframe en el editor (math con visualización, A1) :v
@export var mostrar_gizmos: bool = true:
	set(v):
		mostrar_gizmos = v
		_aplicar_visibilidad_gizmos()
## También dibujar los gizmos al jugar (para tuning in-game) :v
@export var gizmos_en_juego: bool = false
@export var color_forma: Color = Color(0.2, 0.9, 1.0, 0.85)
@export var color_caida: Color = Color(0.2, 0.5, 0.7, 0.4)


## Pista reproduciéndose (1 capa = 1 player mientras el scape vive) :v
class PistaActiva:
	var capa: SoundCapa
	var player: AudioStreamPlayer
	var vol_actual: float = 0.0


## Soundscape sonando con sus pistas y su peso actual :v
class ScapeActivo:
	var scape: SoundScape
	var peso: float = 0.0
	var pistas: Array[PistaActiva] = []


var _activos: Array[ScapeActivo] = []
var _pool: Array[AudioStreamPlayer] = []
var _bus_propio: String = ""
var _duck_db: float = 0.0
var _duck_objetivo_db: float = 0.0
var _duck_tau: float = 0.1
var _malla: MeshInstance3D
var _firma_gizmos: String = ""
var _t_gizmos: float = REFRECO_GIZMOS
var _overlay: CanvasLayer
var _label: Label
var _t_overlay: float = 0.0


func _enter_tree() -> void:
	# _enter_tree (no _ready) para que un reparenting en runtime :v
	# vuelva a recrear los buses que _exit_tree liberó
	if Engine.is_editor_hint():
		return
	_crear_buses()


func _ready() -> void:
	_crear_gizmos()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	for act in _activos:
		for p in act.pistas:
			p.player.stop()
			# Soltar el stream: si no, el playback OGG queda retenido :v
			# al salir y Godot reporta "Leaked instance: AudioStreamOgg..."
			p.player.stream = null
	_activos.clear()
	_pool.clear()
	_liberar_buses()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_t_gizmos += delta
		if _t_gizmos >= REFRECO_GIZMOS:
			_t_gizmos = 0.0
			_refrescar_gizmos()
		return
	_mezclar(delta)
	if mostrar_gizmos and gizmos_en_juego:
		_t_gizmos += delta
		if _t_gizmos >= REFRECO_GIZMOS:
			_t_gizmos = 0.0
			_refrescar_gizmos()
	if _label != null:
		_t_overlay += delta
		if _t_overlay >= REFRECO_OVERLAY:
			_t_overlay = 0.0
			_actualizar_overlay()


func _unhandled_input(event: InputEvent) -> void:
	# Overlay de debug solo en builds de debug y nunca en el editor :v
	if Engine.is_editor_hint() or not OS.is_debug_build():
		return
	var tecla := event as InputEventKey
	if tecla != null and tecla.pressed and not tecla.echo and tecla.keycode == KEY_F3:
		_alternar_overlay()
		get_viewport().set_input_as_handled()


# ────────────────────────────── BUSES ──────────────────────────────

func _crear_buses() -> void:
	var grupo_real := grupo.strip_edges()
	if grupo_real == "" or grupo_real == "Master":
		grupo_real = ""
	# Bus agrupador compartido (refcount) :v
	if grupo_real != "":
		if AudioServer.get_bus_index(grupo_real) == -1:
			AudioServer.add_bus(AudioServer.bus_count)
			var gi := AudioServer.bus_count - 1
			AudioServer.set_bus_name(gi, grupo_real)
			AudioServer.set_bus_send(gi, &"Master")
		_refcount_grupos[grupo_real] = int(_refcount_grupos.get(grupo_real, 0)) + 1
	# Bus propio único de ESTA instancia :v
	var base := String(name)
	if base == "":
		base = "ambiente"
	var nombre := base
	var n := 1
	while AudioServer.get_bus_index(nombre) != -1:
		n += 1
		nombre = "%s_%d" % [base, n]
	_bus_propio = nombre
	AudioServer.add_bus(AudioServer.bus_count)
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, nombre)
	AudioServer.set_bus_send(idx, StringName(grupo_real if grupo_real != "" else "Master"))
	AudioServer.set_bus_volume_db(idx, volumen_db)


func _liberar_buses() -> void:
	if _bus_propio != "":
		var idx := AudioServer.get_bus_index(_bus_propio)
		if idx != -1:
			AudioServer.remove_bus(idx)
		_bus_propio = ""
	var grupo_real := grupo.strip_edges()
	if grupo_real != "" and grupo_real != "Master":
		var c := int(_refcount_grupos.get(grupo_real, 0)) - 1
		if c <= 0:
			# OJO: si el grupo llega a 0 instancias, su bus también se va :v
			_refcount_grupos.erase(grupo_real)
			var gi := AudioServer.get_bus_index(grupo_real)
			if gi != -1:
				AudioServer.remove_bus(gi)
		else:
			_refcount_grupos[grupo_real] = c


# ──────────────────────────── MEZCLA ────────────────────────────

func _mezclar(delta: float) -> void:
	var oy := _obtener_oyente()
	var local := Vector3.ZERO
	var hay_oyente := oy != null
	if hay_oyente:
		local = to_local(oy.global_position)
	# Peso por soundscape = MAX entre zonas que lo usan (sin duplicar) :v
	var pesos: Dictionary = {}
	for z in zonas:
		if z == null or z.soundscape == null:
			continue
		var p := z.peso_en(local) if hay_oyente else 0.0
		if p > float(pesos.get(z.soundscape, 0.0)):
			pesos[z.soundscape] = p
	# Y los GLOBALES, a peso pleno: lluvia y viento se oyen en todo el mapa y
	# no en una region. Sin esto solo se activarian scapes con zona (:v
	for g in globales:
		if g != null:
			pesos[g] = 1.0
	# Activar soundscapes con peso > 0 que aún no suenan :v
	for scape in pesos:
		if float(pesos[scape]) > 0.0 and _buscar(scape as SoundScape) == null:
			_activar(scape as SoundScape)
	# Actualizar / liberar :v
	for i in range(_activos.size() - 1, -1, -1):
		var act := _activos[i]
		act.peso = float(pesos.get(act.scape, 0.0))
		# Si el scape tiene peso se MANTIENE aunque suene a 0 (intensidad 0 :v
		# = silencio, no bucle activar/liberar). Se libera solo cuando el
		# peso cae a 0 Y el fade_out ya diluyó el resto :v
		var vivo := act.peso > 0.0
		for pa in act.pistas:
			# El duck NO va aquí: se aplica una sola vez en el bus :v
			var obj := db_to_linear(pa.capa.volumen_base) * act.peso \
				* clampf(intensidad, 0.0, 4.0)
			# SISTEMA DE NIVELES: si la capa no pertenece al nivel actual, el
			# objetivo es 0 y `_mover_volumen` la diluye con SU fade_out. Por
			# eso subir de "suave" a "fuerte" se oye como capas que se VAN
			# ANADIENDO y no como un salto de volumen (:v
			if not pa.capa.suena_en(nivel):
				obj = 0.0
			_mover_volumen(pa, obj, delta)
			if pa.vol_actual > VOL_CERO:
				vivo = true
		if not vivo:
			_liberar(i)
	# Duck animado (exponencial, estable a cualquier FPS) :v
	_duck_db = _aprox(_duck_db, _duck_objetivo_db, _duck_tau, delta)
	_aplicar_volumen_bus()


func _obtener_oyente() -> Node3D:
	if oyente != NodePath():
		var n := get_node_or_null(oyente)
		if n is Node3D:
			return n as Node3D
	return get_viewport().get_camera_3d()


func _mover_volumen(pa: PistaActiva, objetivo: float, delta: float) -> void:
	var fade := pa.capa.fade_in if objetivo > pa.vol_actual else pa.capa.fade_out
	if fade <= 0.001:
		pa.vol_actual = objetivo
	else:
		pa.vol_actual = _aprox(pa.vol_actual, objetivo, fade / 3.0, delta)
	pa.player.volume_db = maxf(linear_to_db(maxf(pa.vol_actual, 0.0001)), DB_PISO)


func _aprox(actual: float, objetivo: float, tau: float, delta: float) -> float:
	return actual + (objetivo - actual) * (1.0 - exp(-delta / maxf(tau, 0.001)))


func _buscar(scape: SoundScape) -> ScapeActivo:
	for act in _activos:
		if act.scape == scape:
			return act
	return null


func _activar(scape: SoundScape) -> void:
	if scape.capas.is_empty():
		push_warning("AmbienteAudio '%s': scape '%s' sin capas :v" % [name, scape.nombre])
		return
	var act := ScapeActivo.new()
	act.scape = scape
	for capa in scape.capas:
		if capa == null:
			continue
		var stream := capa.construir_stream()
		if stream == null:
			push_warning("AmbienteAudio '%s': capa '%s' sin streams :v" % [name, capa.nombre])
			continue
		var pa := PistaActiva.new()
		pa.capa = capa
		pa.player = _obtener_player(capa.nombre)
		pa.player.stream = stream
		pa.player.volume_db = DB_PISO
		pa.player.play()
		act.pistas.append(pa)
	if act.pistas.is_empty():
		return
	_activos.append(act)
	scape_activado.emit(_nombre_scape(scape))


func _liberar(i: int) -> void:
	var act := _activos[i]
	for pa in act.pistas:
		pa.player.stop()
		pa.player.stream = null
		_pool.append(pa.player)
	_activos.remove_at(i)
	scape_apagado.emit(_nombre_scape(act.scape))


func _nombre_scape(scape: SoundScape) -> String:
	return scape.nombre if scape.nombre != "" else scape.resource_path.get_file()


func _obtener_player(nom_capa: String) -> AudioStreamPlayer:
	var p: AudioStreamPlayer
	if _pool.is_empty():
		p = AudioStreamPlayer.new()
		add_child(p)
		p.name = "Pista_%s" % nom_capa
		# Loop MANUAL: finished→play (ver nota en SoundCapa.construir_stream) :v
		p.finished.connect(_replay_si_termino.bind(p))
	else:
		p = _pool.pop_back()
	p.bus = StringName(_bus_propio)
	p.stream = null
	return p


## Replay manual del loop. Sin loop=true en el ogg (bug de leak medido). :v
## finished NO se emite al hacer stop(), así que un player liberado :v
## nunca se reactiva; el guard de stream lo cubre igual.
func _replay_si_termino(p: AudioStreamPlayer) -> void:
	if is_inside_tree() and p.stream != null:
		p.play()


func _aplicar_volumen_bus() -> void:
	if _bus_propio == "":
		return
	var idx := AudioServer.get_bus_index(_bus_propio)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, volumen_db + _duck_db)


# ──────────────────────── API PÚBLICA ────────────────────────

## Ducking manual (A2): baja ESTA instancia `db` (negativo) en `segundos` :v
func atenuar(db: float, segundos: float = 0.3) -> void:
	_duck_objetivo_db = db
	_duck_tau = maxf(segundos, 0.01) / 3.0


## Vuelve del ducking a 0 dB con fade :v
func restaurar(segundos: float = 0.6) -> void:
	_duck_objetivo_db = 0.0
	_duck_tau = maxf(segundos, 0.01) / 3.0


## Escala todas las capas 0..1 (subir la tormenta, apagar lejos...) :v
func set_intensidad(v: float) -> void:
	intensidad = clampf(v, 0.0, 4.0)


## Cambia el nivel de intensidad (0 Suave / 1 Moderada / 2 Fuerte) :v
##
## No toca volumenes: solo cambia QUE CAPAS cumplen `suena_en()`, y de ahi
## sale sola la suma de fades de cada capa. Se puede llamar en caliente desde
## gameplay — la lluvia se apila o se desmonta sin cortarse (:v
func set_nivel(n: int) -> void:
	nivel = clampi(n, 0, 2)


## Duck actual en dB (para tests/overlay) :v
func duck_db() -> float:
	return _duck_db


# ─────────────────────────── GIZMOS ───────────────────────────
# Wireframe de las zonas en el editor: círculos (esfera) o aristas (caja) :v
# + un segundo contorno en color de CAÍDA. Se regenera solo si cambia la
# "firma" de las zonas (throttle 0.25 s — patrón de atmosfera.gd) :v

func _crear_gizmos() -> void:
	if _malla != null:
		return
	_malla = MeshInstance3D.new()
	_malla.name = "GizmosZonas"
	_malla.mesh = ImmediateMesh.new()
	_malla.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	_malla.material_override = m
	# Sin owner → NUNCA se serializa dentro del .tscn :v
	add_child(_malla, false, Node.INTERNAL_MODE_BACK)
	_aplicar_visibilidad_gizmos()


func _aplicar_visibilidad_gizmos() -> void:
	if _malla == null:
		return
	_malla.visible = mostrar_gizmos and (Engine.is_editor_hint() or gizmos_en_juego)


func _firma_zonas() -> String:
	var f := ""
	for z in zonas:
		if z == null:
			f += "null;"
			continue
		f += "%s|%s|%s|%s|%.2f|%s;" % [
			z.nombre, str(z.forma), str(z.centro), str(z.tamano), z.caida,
			str(z.soundscape) if z.soundscape != null else "-"]
	return f


func _refrescar_gizmos() -> void:
	if _malla == null or not mostrar_gizmos:
		return
	var firma := _firma_zonas()
	if firma == _firma_gizmos:
		return
	_firma_gizmos = firma
	var im := _malla.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for z in zonas:
		if z == null:
			continue
		match z.forma:
			SoundZona.Forma.ESFERA:
				_circulo(im, z.centro, z.radio, color_forma, 0)
				_circulo(im, z.centro, z.radio, color_forma, 1)
				_circulo(im, z.centro, z.radio, color_forma, 2)
				if z.caida > 0.0:
					_circulo(im, z.centro, z.radio + z.caida, color_caida, 1)
			SoundZona.Forma.CAJA:
				_caja(im, z.centro, z.tamano, color_forma)
				if z.caida > 0.0:
					_caja(im, z.centro, z.tamano + Vector3.ONE * z.caida, color_caida)
	im.surface_end()


func _circulo(im: ImmediateMesh, c: Vector3, r: float, col: Color, plano: int) -> void:
	const SEG := 32
	var prev := _pto_circulo(c, r, 0.0, plano)
	for i in range(1, SEG + 1):
		var ang := TAU * float(i) / float(SEG)
		var p := _pto_circulo(c, r, ang, plano)
		im.surface_set_color(col)
		im.surface_add_vertex(prev)
		im.surface_set_color(col)
		im.surface_add_vertex(p)
		prev = p


func _pto_circulo(c: Vector3, r: float, ang: float, plano: int) -> Vector3:
	match plano:
		0:  # vertical XY :v
			return c + Vector3(cos(ang) * r, sin(ang) * r, 0.0)
		1:  # horizontal XZ :v
			return c + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		_:  # vertical YZ :v
			return c + Vector3(0.0, cos(ang) * r, sin(ang) * r)


func _caja(im: ImmediateMesh, c: Vector3, h: Vector3, col: Color) -> void:
	var esq: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				esq.append(c + Vector3(sx * h.x, sy * h.y, sz * h.z))
	# 12 aristas del cubo (índices de esq) :v
	var aristas := [
		[0, 1], [2, 3], [0, 2], [1, 3],
		[4, 5], [6, 7], [4, 6], [5, 7],
		[0, 4], [1, 5], [2, 6], [3, 7]]
	for a in aristas:
		im.surface_set_color(col)
		im.surface_add_vertex(esq[a[0]])
		im.surface_set_color(col)
		im.surface_add_vertex(esq[a[1]])


# ────────────────────────── OVERLAY F3 ──────────────────────────

func _alternar_overlay() -> void:
	if _overlay == null:
		_overlay = CanvasLayer.new()
		_overlay.layer = 100
		_label = Label.new()
		_label.position = Vector2(12, 12)
		_label.add_theme_font_size_override("font_size", 14)
		_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
		_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_label.add_theme_constant_override("outline_size", 4)
		_overlay.add_child(_label)
		add_child(_overlay, false, Node.INTERNAL_MODE_BACK)
	_overlay.visible = not _overlay.visible
	if _overlay.visible:
		_actualizar_overlay()


func _actualizar_overlay() -> void:
	var l: Array[String] = []
	l.append("AmbienteAudio «%s» grupo=%s bus=%s duck=%.1f dB intens=%.2f" % [
		name, grupo, _bus_propio, _duck_db, intensidad])
	var oy := _obtener_oyente()
	l.append("oyente: %s | zonas: %d | scapes activos: %d" % [
		oy.name if oy != null else "NINGUNO", zonas.size(), _activos.size()])
	for act in _activos:
		l.append("  scape «%s» peso=%.2f" % [_nombre_scape(act.scape), act.peso])
		for pa in act.pistas:
			l.append("    %s: vol=%.3f (obj aprox) %s" % [
				pa.capa.nombre, pa.vol_actual,
				"▶" if pa.player.is_playing() else "■"])
	_label.text = "\n".join(l)
