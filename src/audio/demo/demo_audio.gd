extends Node3D
## Demo + test automático del sistema AmbienteAudio :v
##
## Uso (headless):
##   $env:AUDIO_TEST="1"; Godot --headless --path <proj> --quit-after 200000 \
##       "res://src/audio/demo/demo_audio.tscn"
## Sin AUDIO_TEST queda en modo demo (suena y espera, sin asserts) :v
##
## Fases: buses → activación → zonas múltiples (crossfade) → salida :v
## → duck → intensidad=0 (sin bucle) → multi-instancia → limpieza.

const OXIDO := "res://audio/music/ambience/submarino/oxido.ogg"
const MAR_ROJO := "res://audio/music/traveling/el mar rojo.ogg"

var _ok := 0
var _fallos: Array[String] = []
var _activados: Array[String] = []
var _apagados: Array[String] = []

var _oyente: Marker3D
var _mapa: AmbienteAudio
var _tormenta: AmbienteAudio
var _s1: SoundScape
var _s2: SoundScape


func check(cond: bool, texto: String) -> void:
	if cond:
		_ok += 1
		print("  OK  ", texto)
	else:
		_fallos.append(texto)
		print("  FALLO  ", texto)


func _ready() -> void:
	_montar()
	if OS.get_environment("AUDIO_TEST") != "1":
		print("Modo demo: suena sin asserts. Pulsa F3 en debug para el overlay.")
		return
	await _test()
	print("")
	if _fallos.is_empty():
		print("RESULTADO: TODO OK (%d comprobaciones)" % _ok)
		get_tree().quit(0)
	else:
		for f in _fallos:
			print("FALLO: ", f)
		print("RESULTADO: %d FALLOS, %d OK" % [_fallos.size(), _ok])
		get_tree().quit(1)


func _hacer_scape(nom: String, path: String, vol: float, fade: float) -> SoundScape:
	var capa := SoundCapa.new()
	capa.nombre = nom + "_capa"
	capa.streams = [load(path)]
	capa.volumen_base = vol
	capa.fade_in = fade
	capa.fade_out = fade
	var s := SoundScape.new()
	s.nombre = nom
	s.capas = [capa]
	return s


func _hacer_zona(nom: String, centro: Vector3, scape: SoundScape) -> SoundZona:
	var z := SoundZona.new()
	z.nombre = nom
	z.soundscape = scape
	z.forma = SoundZona.Forma.ESFERA
	z.centro = centro
	z.radio = 8.0
	z.caida = 4.0
	return z


func _montar() -> void:
	_oyente = Marker3D.new()
	_oyente.name = "Oyente"
	_oyente.position = Vector3.ZERO
	add_child(_oyente)

	_s1 = _hacer_scape("submarino", OXIDO, -6.0, 0.1)
	_s2 = _hacer_scape("corriente", MAR_ROJO, -6.0, 0.1)

	_mapa = AmbienteAudio.new()
	_mapa.name = "Mapa"
	_mapa.grupo = "ambiente"
	_mapa.oyente = NodePath("../Oyente")
	# Zona1 centrada en 0; Zona2 en 16 → en x=10 la z1 pesa 0.5 y la z2 1.0 :v
	_mapa.zonas = [_hacer_zona("interno", Vector3.ZERO, _s1),
		_hacer_zona("corriente", Vector3(16, 0, 0), _s2)]
	_mapa.scape_activado.connect(func(n): _activados.append(n))
	_mapa.scape_apagado.connect(func(n): _apagados.append(n))
	add_child(_mapa)


func _peso(scape: SoundScape) -> float:
	for act in _mapa._activos:
		if act.scape == scape:
			return act.peso
	return -1.0


func _vol(scape: SoundScape) -> float:
	for act in _mapa._activos:
		if act.scape == scape and act.pistas.size() > 0:
			return act.pistas[0].vol_actual
	return -1.0


func _test() -> void:
	# ── FASE 1: buses (grupo + propios, cadena de envío) ──
	var i_grupo := AudioServer.get_bus_index("ambiente")
	var i_mapa := AudioServer.get_bus_index("Mapa")
	check(i_grupo != -1, "bus-grupo «ambiente» creado")
	check(i_mapa != -1, "bus propio «Mapa» creado (nombre = nodo)")
	check(AudioServer.get_bus_send(i_grupo) == &"Master", "ambiente envía a Master")
	check(AudioServer.get_bus_send(i_mapa) == &"ambiente", "Mapa envía a ambiente")

	# ── FASE 2: activación + fade in dentro de la zona ──
	await get_tree().create_timer(0.3).timeout
	check(_mapa._activos.size() == 1, "1 soundscape activo (solo zona interna)")
	check(_activados == ["submarino"], "señal scape_activado «submarino»")
	check(_vol(_s1) > 0.4, "fade in completado (vol=%.2f, obj≈0.50)" % _vol(_s1))
	if _mapa._activos.size() == 1:
		var pa = _mapa._activos[0].pistas[0]
		check(pa.player.is_playing(), "player reproduciendo")

	# ── FASE 3: zona solapada → DOS soundscapes a la vez (crossfade) ──
	_oyente.position = Vector3(10, 0, 0)
	await get_tree().create_timer(0.3).timeout
	check(_mapa._activos.size() == 2, "2 soundscapes vivos a la vez")
	check(absf(_peso(_s1) - 0.5) < 0.15, "peso zona1 ≈ 0.5 (=%.2f)" % _peso(_s1))
	check(absf(_peso(_s2) - 1.0) < 0.05, "peso zona2 ≈ 1.0 (=%.2f)" % _peso(_s2))

	# ── FASE 4: fuera de todo → fade out + release + señales ──
	_oyente.position = Vector3(100, 0, 0)
	await get_tree().create_timer(0.8).timeout
	check(_mapa._activos.size() == 0, "handles liberados fuera de zonas")
	check(_apagados.has("submarino") and _apagados.has("corriente"),
		"señales scape_apagado emitidas para ambos")

	# ── FASE 5: duck manual por bus (A2) ──
	_oyente.position = Vector3.ZERO
	await get_tree().create_timer(0.3).timeout
	check(_mapa._activos.size() == 1, "reactivado al volver a la zona")
	var n_activ := _activados.size()
	_mapa.atenuar(-12.0, 0.1)
	await get_tree().create_timer(0.4).timeout
	check(absf(_mapa.duck_db() + 12.0) < 1.5, "duck_db ≈ -12 (=%.1f)" % _mapa.duck_db())
	var i_mapa2 := AudioServer.get_bus_index("Mapa")
	check(absf(AudioServer.get_bus_volume_db(i_mapa2) + 12.0) < 1.5,
		"bus «Mapa» bajó a ≈ -12 dB (=%.1f)" % AudioServer.get_bus_volume_db(i_mapa2))
	_mapa.restaurar(0.1)
	await get_tree().create_timer(0.4).timeout
	check(absf(_mapa.duck_db()) < 1.5, "duck restaurado a ≈ 0 (=%.1f)" % _mapa.duck_db())

	# ── FASE 6: intensidad=0 → silencio SIN bucle activar/liberar ──
	_mapa.set_intensidad(0.0)
	await get_tree().create_timer(0.6).timeout
	check(_mapa._activos.size() == 1, "intensidad 0: handle MANTIENE (sin bucle)")
	check(_activados.size() == n_activ, "intensidad 0: sin re-activaciones")
	check(_vol(_s1) < 0.01, "intensidad 0: vol a silencio (=%.4f)" % _vol(_s1))
	_mapa.set_intensidad(1.0)
	await get_tree().create_timer(0.4).timeout
	check(_vol(_s1) > 0.4, "intensidad 1: vuelve a sonar (vol=%.2f)" % _vol(_s1))

	# ── FASE 7: multi-instancia — tormenta APILADA sobre el mapa ──
	var s3 := _hacer_scape("granizo", OXIDO, -10.0, 0.05)
	_tormenta = AmbienteAudio.new()
	_tormenta.name = "Tormenta"
	_tormenta.grupo = "clima"
	_tormenta.oyente = NodePath("../Oyente")
	_tormenta.zonas = [_hacer_zona("granizo_zona", Vector3.ZERO, s3)]
	add_child(_tormenta)
	await get_tree().create_timer(0.3).timeout
	check(AudioServer.get_bus_index("clima") != -1, "bus-grupo «clima» creado")
	check(AudioServer.get_bus_index("Tormenta") != -1, "bus propio «Tormenta» creado")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("Tormenta")) == &"clima",
		"Tormenta envía a clima")
	check(_mapa._activos.size() == 1 and _tormenta._activos.size() == 1,
		"ambas instancias suenan APILADAS (mapa + tormenta)")

	# ── FASE 8: refcount al destruir — clima muere, ambiente sobrevive ──
	_tormenta.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(AudioServer.get_bus_index("clima") == -1, "bus-grupo «clima» destruido")
	check(AudioServer.get_bus_index("Tormenta") == -1, "bus «Tormenta» destruido")
	check(AudioServer.get_bus_index("ambiente") != -1, "bus «ambiente» sigue vivo (mapa)")

	_mapa.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(AudioServer.get_bus_index("ambiente") == -1, "bus «ambiente» destruido")
	var nombres: Array[String] = []
	for i in AudioServer.bus_count:
		nombres.append(AudioServer.get_bus_name(i))
	check(AudioServer.get_bus_count() == 1,
		"solo queda Master (=%d: %s)" % [AudioServer.bus_count, ",".join(nombres)])
