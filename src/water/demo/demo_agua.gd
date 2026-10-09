extends Node3D
## HUD, ayuda y PRUEBA AUTOMATICA del demo de agua (`demo_agua.tscn`). :v
##
## El personaje de prueba es el RAGDOLL (`Character`), no Iza — decision del
## General. Cualquier nodo con un WaterBody debajo vale: el script no asume
## CharacterBody3D, mide por `altura_cuerpo()` y teletransporta por
## `teletransportar()` si el personaje lo ofrece. :v
##
## Controles del demo:
##   WASD/flechas  moverse
##   Espacio       saltar / nadar arriba (mantener)
##   Ctrl          agacharse / nadar abajo (mantener)
##   Shift         sprint (solo en tierra)
##   Escape        salir

@export_group("Enlazado")
## Personaje de prueba. Si esta vacio se busca el primer hijo con un
## WaterBody debajo. :v
@export var jugador: NodePath

## Secuencias de la prueba automatica (AGUA_TEST=1). :v
## 6 s de estabilizar: caida (0,75 s) + frenada en el agua (0,5 s) + subida a
## la superficie a ~1 m/s desde los -2,5 m de fondo de inercia. Medido. :v
const T_ESTABILIZAR := 6.0
const T_SUMERGIR := 3.0
const T_AIRE := 2.0
## Aguas profundas en agua ABIERTA (x=20: con x=0 el ragdoll caia justo sobre
## el techo de la instalacion y el contacto lo sujetaba — medido). :v
const POS_CAIMIENTO := Vector3(20.0, 3.0, -6.0)
const POS_HONDA := Vector3(20.0, -8.0, -6.0)
## Suelta por encima del agua para asentar flotando (fases de CONTROLES). :v
const POS_SUPERFICIE := Vector3(20.0, 0.8, -6.0)
## Dentro de la bolsa de aire de la instalacion.
const POS_SALA := Vector3(0.0, -12.2, -6.0)

var _agua: WaterBody
var _oxigeno: Oxygen
var _personaje: Node3D
var _barra: ProgressBar
var _aviso: Label
var _datos: Label
var _ultimo_aviso := ""
var _tick := 0
var _t_total := 0.0
var _captura_hecha := false

# --- prueba automatica (AGUA_TEST=1) ----------------------------------------
var _prueba := false
var _fase := 0
var _t_fase := 0.0
var _oxigeno_antes := 0.0
var _ahogado_ok := false
var _fallos: Array[String] = []
var _y_hundir := 0.0
var _y_min := 0.0
var _y_max := 0.0
var _nivel_salida := 0.0
var _ok := 0


func _ready() -> void:
	var pj := get_node_or_null(jugador)
	if pj == null:
		# El personaje es el UNICO que trae WaterBody Y Oxygen: los cuerpos
		# flotantes del demo solo llevan WaterBody, y por orden de hijos
		# "Objetos" apareceria antes que el personaje. :v
		for h in get_children():
			if WaterBody.buscar_en(h) != null and Oxygen.buscar_en(h) != null:
				pj = h
				break
	_personaje = pj as Node3D
	if _personaje != null:
		_agua = WaterBody.buscar_en(_personaje)
		_oxigeno = Oxygen.buscar_en(_personaje)
	_construir_hud()
	_conectar_senales()
	print("[demo_agua] agua=%s oxigeno=%s personaje=%s" % [
		_agua != null, _oxigeno != null, _personaje.name if _personaje else "-"])
	if _agua == null or _oxigeno == null:
		push_warning("[demo_agua] faltan componentes: el personaje necesita \
los nodos Agua y Oxigeno. :v")
	_prueba = OS.get_environment("AGUA_TEST") != ""
	if _prueba:
		print("[demo_agua] MODO PRUEBA: buoyancy + ahogo + bolsa de aire")
		_mover(POS_CAIMIENTO)
		if _oxigeno != null:
			_oxigeno.ahogado.connect(func() -> void: _ahogado_ok = true)
	# Capturas: AGUA_SHOT_HONDA=1 deja la camara dentro del agua (muestra la
	# distorsion); AGUA_SHOT_FLOTA=1 lo suelta en agua abierta para verlo
	# flotando a los 5 s. :v
	if not _prueba and OS.get_environment("AGUA_SHOT_HONDA") != "":
		_mover(POS_HONDA)
	elif not _prueba and OS.get_environment("AGUA_SHOT_FLOTA") != "":
		_mover(POS_CAIMIENTO)
	_diagnostico()


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()
	_tick += 1
	_t_total += delta
	if not _prueba and not _captura_hecha and _t_total > 5.0 \
			and OS.get_environment("AGUA_SHOT") != "":
		_capturar()
	if not _prueba and _tick % 60 == 0:
		_diagnostico()
	if _prueba:
		_correr_prueba(delta)
	_actualizar_hud()


## Barra de oxigeno y lectura de datos. Esto va DENTRO de _process: una vez
## se colo una funcion a mitad de _process y el HUD se quedo congelado. :v
func _actualizar_hud() -> void:
	if _barra != null and _oxigeno != null:
		_barra.value = _oxigeno.porcentaje() * 100.0
		var est := _barra.get_theme_stylebox("fill") as StyleBoxFlat
		if est != null:
			var t := _oxigeno.porcentaje()
			est.bg_color = Color(0.85, 0.15, 0.12).lerp(Color(0.15, 0.55, 0.85), t)
	if _datos == null or _agua == null:
		return
	var linea := "fraccion %.2f | profundidad %.1f m | %s | cabeza %s" % [
		_agua.fraccion, _agua.profundidad,
		"SUMERGIDO" if _agua.sumergido else "fuera",
		"bajo el agua" if _agua.cabeza_sumergida else "al aire"]
	if _oxigeno != null:
		linea += "\noxigeno %.0f/%.0f (%.0f%%) | %s" % [
			_oxigeno.restante, _oxigeno.maximo, _oxigeno.porcentaje() * 100.0,
			"AGOTADO" if _oxigeno.agotado else "ok"]
	_datos.text = linea


## Captura el viewport a los 5 s (los cuerpos ya asentados) y sale. :v
func _capturar() -> void:
	_captura_hecha = true
	var img := get_viewport().get_texture().get_image()
	var ruta := OS.get_environment("AGUA_SHOT_RUTA")
	if ruta.is_empty():
		ruta = "C:/Users/Admin/AppData/Local/Temp/opencode/agua_shot.png"
	var err := img.save_png(ruta)
	print("[demo_agua] captura %s -> %s" % [error_string(err), ruta])
	get_tree().quit(0 if err == OK else 1)


# ---------------------------------------------------------------------------
#  Prueba automatica (AGUA_TEST=1) — buoyancy, ahogo y zona seca :v
# ---------------------------------------------------------------------------

## Maquina de fases: espera, VERIFICA y pasa. Al final imprime el veredicto y
## sale con codigo 0 (todo OK) o 1 (hubo fallos). :v
func _correr_prueba(delta: float) -> void:
	if _personaje == null or _agua == null or _oxigeno == null:
		return
	_t_fase += delta
	if fmod(_t_fase, 0.5) < delta:
		print("[PRUEBA] fase=%d raiz=%.2f y=%.2f vy=%.2f fraccion=%.2f emp=%.2f suprimido=%s apoyado=%s cabeza=%s nivel=%.2f" % [
			_fase, _personaje.global_position.y, _y_personaje(), _vy_personaje(),
			_agua.fraccion, _agua.aceleracion_empuje(),
			str(_agua.empuje_suprimido), str(_agua.apoyado),
			str(_agua.cabeza_sumergida), _agua.nivel])
	match _fase:
		0:
			if _t_fase > 0.5:
				_pasar(1)
		1:
			if _t_fase < T_ESTABILIZAR:
				return
			_comprobar("flota con cuerpo sumergido", _agua.sumergido,
					"fraccion=%.2f" % _agua.fraccion)
			_comprobar("flota con la CABEZA fuera (no se ahoga)",
					not _agua.cabeza_sumergida,
					"fraccion=%.2f y=%.2f nivel=%.2f" % [
						_agua.fraccion, _y_personaje(), _agua.nivel])
			_comprobar("flota a la altura de la superficie",
					absf(_y_personaje() - _agua.nivel) < 1.2,
					"y=%.2f nivel=%.2f" % [_y_personaje(), _agua.nivel])
			_comprobar("flotar NO gasta oxigeno",
					_oxigeno.restante >= _oxigeno.maximo - 1.0,
					"oxigeno=%.1f" % _oxigeno.restante)
			_comprobar_objetos()
			# Apnea corta para que el ahogo entre en el tiempo de prueba. :v
			_oxigeno.maximo = 6.0
			_oxigeno.restante = 6.0
			_oxigeno.consumo = 6.0
			_oxigeno.gracia = 1.0
			_mover(POS_HONDA)
			_pasar(2)
		2:
			if _t_fase < T_SUMERGIR:
				return
			_comprobar("buceando: la cabeza esta bajo el agua",
					_agua.cabeza_sumergida, "fraccion=%.2f" % _agua.fraccion)
			_comprobar("buceando: gasta oxigeno",
					_oxigeno.restante < _oxigeno.maximo,
					"oxigeno=%.1f" % _oxigeno.restante)
			_comprobar("sin aire -> senal de AHOGO", _ahogado_ok,
					"el oxigeno llego a 0 y no se emitio ahogado()")
			_oxigeno.maximo = 60.0
			_mover(POS_SALA)
			_pasar(3)
		3:
			if _t_fase < T_AIRE:
				return
			_comprobar("sala seca: el agua NO entra (fraccion=0)",
					_agua.fraccion <= 0.001, "fraccion=%.3f" % _agua.fraccion)
			_comprobar("sala seca: la cabeza respira",
					not _agua.cabeza_sumergida, "")
			_comprobar("sala seca: recupera oxigeno",
					_oxigeno.restante > _oxigeno_antes + 1.0,
					"antes=%.1f ahora=%.1f" % [_oxigeno_antes, _oxigeno.restante])
			# ---- BLOQUE DE CONTROLES: hundirse con Ctrl, salir con Espacio :v
			_liberar_controles()
			_mover(POS_SUPERFICIE)
			_pasar(4)
		4:
			# Asentar flotando en agua abierta tras el teletransporte.
			if _t_fase < 4.0:
				return
			_comprobar("vuelve a flotar tras teletransportar", _agua.sumergido,
					"fraccion=%.2f" % _agua.fraccion)
			_comprobar("flota con la cabeza fuera ANTES de bucear",
					not _agua.cabeza_sumergida,
					"fraccion=%.2f y=%.2f nivel=%.2f" % [
						_agua.fraccion, _y_personaje(), _agua.nivel])
			_y_hundir = _y_personaje()
			_y_min = _y_hundir
			Input.action_press("crouch")
			print("[PRUEBA] Ctrl pulsado (hundirse)")
			_pasar(5)
		5:
			_y_min = minf(_y_min, _y_personaje())
			if _t_fase < 2.5:
				return
			Input.action_release("crouch")
			_comprobar("Ctrl (crouch) lo HUNDE de verdad",
					_y_min <= _y_hundir - 1.5,
					"inicio %.2f -> minimo %.2f (bajo %.2f m)" % [
						_y_hundir, _y_min, _y_hundir - _y_min])
			_liberar_controles()
			_mover(POS_SUPERFICIE)
			_pasar(6)
		6:
			if _t_fase < 4.0:
				return
			_comprobar("de vuelta en la superficie, cabeza fuera",
					_agua.sumergido and not _agua.cabeza_sumergida,
					"fraccion=%.2f y=%.2f nivel=%.2f" % [
						_agua.fraccion, _y_personaje(), _agua.nivel])
			_y_max = _y_personaje()
			_nivel_salida = _agua.nivel
			# Evento REAL (parse_input_event), no action_press: el impulso de
			# salida se captura en _input() y action_press no dispara eventos. :v
			_pulsar("jump", true)
			print("[PRUEBA] Espacio pulsado en superficie (salir del agua)")
			_pasar(7)
		7:
			_y_max = maxf(_y_max, _y_personaje())
			if _t_fase < 2.0:
				return
			_liberar_controles()
			_comprobar("Espacio en superficie lo SACA del agua",
					_y_max >= _nivel_salida + 0.4,
					"maximo %.2f vs nivel %.2f (subio %.2f m)" % [
						_y_max, _nivel_salida, _y_max - _nivel_salida])
			_finalizar()


## Los cuerpos rigidos validan el camino de FUERZAS (apply_force), que es el
## unico que depende del motor de fisica activo (Box3D vs DEFAULT). :v
func _comprobar_objetos() -> void:
	var sup := get_node_or_null("Mar/Superficie") as WaterSurface
	var caja := get_node_or_null("Objetos/CajaMadera") as RigidBody3D
	if sup != null and caja != null:
		var nivel := sup.altura_en(caja.global_position)
		_comprobar("la caja de madera flota EN la superficie",
				absf(caja.global_position.y - nivel) < 1.0,
				"y=%.2f nivel=%.2f" % [caja.global_position.y, nivel])
	var ancla := get_node_or_null("Objetos/Ancla") as RigidBody3D
	if ancla != null:
		_comprobar("el ancla se hunde hasta el lecho",
				ancla.global_position.y < -10.0,
				"y=%.2f (lecho en -12.66)" % ancla.global_position.y)


func _pasar(fase: int) -> void:
	_fase = fase
	_t_fase = 0.0
	_oxigeno_antes = _oxigeno.restante


## Suelta todas las teclas simuladas (para que ninguna fase arrastre estado). :v
func _liberar_controles() -> void:
	Input.action_release("crouch")
	Input.action_release("jump")
	_pulsar("jump", false)


## Pulsacion como TECLA REAL: los InputEventAction sinteticos no llegan a
## _input() de los nodos, y ahi es donde el ragdoll captura el impulso de
## salida del agua (medido: con action no se disparaba). :v
func _pulsar(accion: String, abajo: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SPACE if accion == "jump" else KEY_CTRL
	ev.pressed = abajo
	ev.echo = false
	Input.parse_input_event(ev)


## Teletransporte generico: el ragdoll mueve raiz + cuerpos fisicos; un
## CharacterBody3D mueve la raiz y corta la velocidad. :v
func _mover(pos: Vector3) -> void:
	if _personaje.has_method("teletransportar"):
		_personaje.teletransportar(pos)
	else:
		_personaje.global_position = pos
		if _personaje is CharacterBody3D:
			(_personaje as CharacterBody3D).velocity = Vector3.ZERO
	print("[PRUEBA] teletransporte a %s" % str(pos))


## Y del cuerpo REAL: en el ragdoll la raiz no se mueve, solo los huesos. :v
func _y_personaje() -> float:
	if _personaje.has_method("altura_cuerpo"):
		return _personaje.altura_cuerpo()
	return _personaje.global_position.y


func _vy_personaje() -> float:
	if _personaje.has_method("velocidad_cuerpo"):
		return _personaje.velocidad_cuerpo().y
	if _personaje is CharacterBody3D:
		return (_personaje as CharacterBody3D).velocity.y
	return 0.0


func _comprobar(nombre: String, ok: bool, detalle: String) -> void:
	_ok += 1
	if ok:
		print("[PRUEBA] OK   " + nombre)
	else:
		var linea := nombre + ("" if detalle.is_empty() else " -> " + detalle)
		_fallos.append(linea)
		print("[PRUEBA] FAIL " + linea)


func _finalizar() -> void:
	if _fallos.is_empty():
		print("[PRUEBA] RESULTADO: TODO OK (%d fases, %d comprobaciones)" % [
			_fase, _ok])
		get_tree().quit(0)
		return
	for f in _fallos:
		print("[PRUEBA] FALLO: " + f)
	print("[PRUEBA] RESULTADO: %d comprobacion(es) fallida(s) de %d" % [
		_fallos.size(), _ok + _fallos.size()])
	get_tree().quit(1)


# ---------------------------------------------------------------------------
#  HUD
# ---------------------------------------------------------------------------

func _construir_hud() -> void:
	var capa := CanvasLayer.new()
	capa.name = "HUD"
	# Capa 10: POR ENCIMA de DistorsionAgua (capa 1), para que el HUD se lea
	# nito mientras la pantalla se distorsiona. Regla del proyecto: todo HUD
	# va en capa >= 10. :v
	capa.layer = 10
	add_child(capa)

	_barra = ProgressBar.new()
	_barra.name = "Oxigeno"
	_barra.show_percentage = false
	_barra.anchor_left = 0.5
	_barra.anchor_right = 0.5
	_barra.anchor_top = 1.0
	_barra.anchor_bottom = 1.0
	_barra.offset_left = -180.0
	_barra.offset_right = 180.0
	_barra.offset_top = -84.0
	_barra.offset_bottom = -56.0
	_barra.value = 100.0
	var fondo := StyleBoxFlat.new()
	fondo.bg_color = Color(0.05, 0.07, 0.09, 0.85)
	fondo.set_corner_radius_all(4)
	_barra.add_theme_stylebox_override("background", fondo)
	var relleno := StyleBoxFlat.new()
	relleno.bg_color = Color(0.15, 0.55, 0.85)
	relleno.set_corner_radius_all(4)
	_barra.add_theme_stylebox_override("fill", relleno)
	capa.add_child(_barra)

	var rotulo := Label.new()
	rotulo.text = "OXIGENO"
	rotulo.anchor_left = 0.5
	rotulo.anchor_right = 0.5
	rotulo.anchor_top = 1.0
	rotulo.anchor_bottom = 1.0
	rotulo.offset_left = -180.0
	rotulo.offset_right = 180.0
	rotulo.offset_top = -110.0
	rotulo.offset_bottom = -86.0
	rotulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rotulo.add_theme_font_size_override("font_size", 14)
	capa.add_child(rotulo)

	var ayuda := Label.new()
	ayuda.text = "DEMO DE AGUA (ragdoll)\nWASD moverse · Espacio nadar arriba\nCtrl nadar abajo · Esc salir\nPruébame: cae al agua, flota, bucea hasta la sala\ny respira dentro de la burbuja de aire."
	ayuda.position = Vector2(16, 12)
	ayuda.add_theme_font_size_override("font_size", 15)
	ayuda.add_theme_color_override("font_color", Color(0.92, 0.95, 0.97))
	ayuda.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	ayuda.add_theme_constant_override("outline_size", 4)
	capa.add_child(ayuda)

	_datos = Label.new()
	_datos.anchor_top = 1.0
	_datos.anchor_bottom = 1.0
	_datos.offset_left = 16.0
	_datos.offset_right = 900.0
	_datos.offset_top = -48.0
	_datos.offset_bottom = -8.0
	_datos.add_theme_font_size_override("font_size", 14)
	_datos.add_theme_color_override("font_color", Color(0.8, 0.9, 0.85))
	_datos.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_datos.add_theme_constant_override("outline_size", 4)
	capa.add_child(_datos)

	_aviso = Label.new()
	_aviso.anchor_left = 0.0
	_aviso.anchor_right = 1.0
	_aviso.anchor_top = 0.5
	_aviso.anchor_bottom = 0.5
	_aviso.offset_top = -120.0
	_aviso.offset_bottom = -60.0
	_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aviso.add_theme_font_size_override("font_size", 34)
	_aviso.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	_aviso.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_aviso.add_theme_constant_override("outline_size", 8)
	capa.add_child(_aviso)


func _conectar_senales() -> void:
	if _oxigeno != null:
		_oxigeno.sumergio_cambiada.connect(
				func(s: bool) -> void: _mostrar("SUMERGIDO" if s else "A LA SUPERFICIE"))
		_oxigeno.sin_aire.connect(func() -> void: _mostrar("SIN AIRE"))
		_oxigeno.respirando_de_nuevo.connect(func() -> void: _mostrar("RESPIRANDO"))
		_oxigeno.ahogado.connect(func() -> void: _mostrar("AHOGADO"))
	if _agua != null:
		_agua.sumersio_cambiada.connect(
				func(s: bool) -> void: print("[demo_agua] sumersio = %s" % s))
		_agua.cabeza_cambiada.connect(
				func(s: bool) -> void: print("[demo_agua] cabeza sumergida = %s" % s))


func _mostrar(texto: String) -> void:
	_ultimo_aviso = texto
	if _aviso == null:
		return
	_aviso.text = texto
	var tw := _aviso.create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(_aviso, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func() -> void: _aviso.text = "")
	_aviso.modulate.a = 1.0


# ---------------------------------------------------------------------------
#  Diagnostico :v
# ---------------------------------------------------------------------------

## Volcado de metricas cada segundo. La regla del proyecto es MEDIR, no mirar:
## aqui se ve si los cuerpos flotan a la altura que promete la superficie, si
## el reloj del shader esta cableado y si el oxigeno baja solo bajo el agua. :v
func _diagnostico() -> void:
	var sup := get_node_or_null("Mar/Superficie") as WaterSurface
	var mat: ShaderMaterial = null
	var lejano := get_node_or_null("Mar/MarLejano") as MeshInstance3D
	if lejano != null and lejano.mesh != null:
		mat = lejano.mesh.surface_get_material(0) as ShaderMaterial
	var reloj := -1.0
	if mat != null:
		var v: Variant = mat.get_shader_parameter("wave_time")
		reloj = float(v) if v is float else -1.0
	print("[demo_agua] t=%d reloj_shader=%.2f" % [_tick, reloj])

	if sup != null:
		var partes: Array[String] = []
		for nombre in ["CajaMadera", "Ancla", "Boya"]:
			var rb := get_node_or_null("Objetos/" + nombre) as RigidBody3D
			if rb == null:
				continue
			var wb := WaterBody.buscar_en(rb)
			var nivel := sup.altura_en(rb.global_position)
			partes.append("%s y=%.2f nivel=%.2f fraccion=%.2f%s" % [
				nombre, rb.global_position.y, nivel,
				wb.fraccion if wb != null else -1.0,
				"" if wb == null else (" sumergido" if wb.sumergido else " fuera")])
		if not partes.is_empty():
			print("    " + " | ".join(partes))

	if _personaje != null and _agua != null:
		var forma := "CARA" if _oxigeno != null and _oxigeno.agotado else "ok"
		print("    %s y=%.2f fraccion=%.2f cabeza=%s oxigeno=%.0f %s apoyado=%s" % [
			_personaje.name, _y_personaje(), _agua.fraccion,
			str(_agua.cabeza_sumergida), _oxigeno.restante if _oxigeno else -1.0,
			forma, str(_agua.apoyado)])
