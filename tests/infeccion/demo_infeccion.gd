extends Node3D
## Demo de la FASE 2 — la plasta sobre superficies + test automatico. (:v
##
## Construye TODO en runtime (suelo, pared, pilares, camara, luz, cielo,
## viento y las dos zonas), asi que la escena es solo raiz + este script y no
## hay artefactos guardados que se pudieran desincronizar. (:v
##
##   INFECT_TEST=1  -> 8 comprobaciones y exit 1 si algo falla.
##   INFECT_SHOT=1  -> guarda captura a los ~5 s (NO en --headless).
##   Los dos a la vez: primero test, despues captura, despues sale. (:v
##
## Correr (PowerShell):
##   test:
##     $env:INFECT_TEST="1"; & "D:\Mis Juegos\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:\Mis Juegos\Tripofobia\Repositorio" --quit-after 1800 "res://tests/infeccion/demo_infeccion.tscn"
##   captura (render real):
##     $env:INFECT_SHOT="1"; & "D:\Mis Juegos\Godot\Godot_v4.7.1-stable_win64_console.exe" --path "D:\Mis Juegos\Tripofobia\Repositorio" --quit-after 1800 "res://tests/infeccion/demo_infeccion.tscn"
##
## Sin ninguna variable, queda como demo estatica para mirarla a mano. :v

## Parches por zona (las comprobaciones comparan contra estos). :v
const PARCHES_SUELO := 12
const PARCHES_PARED := 8

## Segundos hasta la captura medida desde que acaba la siembra. :v
const T_SHOT := 5.0
## Ruta por defecto de la captura (con INFECT_SHOT_RUTA se cambia). :v
const RUTA_SHOT := "res://tests/infeccion/infeccion_shot.png"

var _test := false
var _shot := false
var _fase := 0
var _t := 0.0
var _fallos := 0

var _atm: Atmosfera
var _zona_suelo: InfeccionZona
var _zona_pared: InfeccionZona


func _ready() -> void:
	_test = OS.get_environment("INFECT_TEST") != ""
	_shot = OS.get_environment("INFECT_SHOT") != ""
	_construir_mundo()
	_construir_camara_y_luz()


func _process(delta: float) -> void:
	_t += delta
	match _fase:
		0:
			if _zona_suelo.siembra_terminada() and _zona_pared.siembra_terminada() and _t > 0.3:
				if _test:
					_comprobar_todo()
				_fase = 1
				_t = 0.0
				if _test and not _shot:
					_finalizar()
		1:
			if _shot and _t >= T_SHOT:
				_capturar()
				if not _test:
					get_tree().quit(0)
				_fase = 2
				_t = 0.0
		2:
			if _t >= 0.5:
				_finalizar()
		# 3 = demo estatica: ya no pasa nada, la escena se queda corriendo.


# ---------------------------------------------------------------------------
#  Construccion del escenario
# ---------------------------------------------------------------------------
func _construir_mundo() -> void:
	# Suelo 24x24 con colision: los parches se conforman por RAYCAST, sin
	# colision no hay superficie que encontrar (los meshes visuales puros
	# no sirven — medido en el sistema del agua). :v
	_crear_caja(Vector3(24.0, 1.0, 24.0), Vector3(0.0, -0.5, 0.0), Color(0.3, 0.29, 0.31))
	# Pared interior en x = 7 (cara util con normal -X, mirando a la sala). :v
	_crear_caja(Vector3(0.5, 6.0, 24.0), Vector3(7.25, 3.0, 0.0), Color(0.34, 0.31, 0.27))
	# Dos pilares FUERA de la zona del suelo (radio 5 + alcance del parche):
	# estan para la captura y para ver sombras, no entran en las medidas. :v
	_crear_caja(Vector3(1.2, 4.0, 1.2), Vector3(-1.5, 2.0, 7.0), Color(0.32, 0.3, 0.33))
	_crear_caja(Vector3(1.2, 4.0, 1.2), Vector3(3.0, 2.0, 7.0), Color(0.32, 0.3, 0.33))

	# Viento de verdad (D-I2): la demo NO tiene Ocean, asi que Atmosfera es
	# la unica que empuja los globals que el shader de plasta lee. :v
	_atm = (load("res://src/weather/atmosfera.tscn") as PackedScene).instantiate() as Atmosfera
	_atm.viento_intensidad = 0.9
	add_child(_atm)

	_zona_suelo = InfeccionZona.new()
	_zona_suelo.cantidad_parches = PARCHES_SUELO
	_zona_suelo.radio_zona = 5.0
	_zona_suelo.semilla = 12345
	add_child(_zona_suelo)

	# Pared: la zona se pone DETRAS del muro (x = 8) con su "abajo" local
	# mirando hacia -X... NO: hacia +X. Regla del rayo: viaja HACIA la
	# direccion de siembra y el PRIMER golpe es la cara que nos mira. Para
	# que ese golpe sea la cara interior (x = 7, normal -X) el rayo tiene
	# que venir de la sala viajando +X, o sea dir = +X = abajo local, o sea
	# local UP = -X. Radio 2.5 en y [0.5, 5.5]: dentro del muro (y 0..6). :v
	_zona_pared = InfeccionZona.new()
	_zona_pared.cantidad_parches = PARCHES_PARED
	_zona_pared.radio_zona = 2.5
	_zona_pared.semilla = 777
	_zona_pared.global_transform = Transform3D(
			Basis(Quaternion(Vector3.UP, Vector3.LEFT)), Vector3(8.0, 3.0, 0.0))
	add_child(_zona_pared)


func _crear_caja(tamano: Vector3, centro: Vector3, color: Color) -> void:
	var cuerpo := StaticBody3D.new()
	cuerpo.position = centro
	var forma := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = tamano
	forma.shape = shape
	cuerpo.add_child(forma)
	var malla := MeshInstance3D.new()
	var caja := BoxMesh.new()
	caja.size = tamano
	malla.mesh = caja
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	malla.material_override = mat
	cuerpo.add_child(malla)
	add_child(cuerpo)


func _construir_camara_y_luz() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.78, 0.82)
	env.ambient_light_energy = 0.8
	we.environment = env
	add_child(we)

	# Sol de tarde: X inclina hacia abajo, Y = -35 para que le de de CHEPA
	# a la pared interior (con +35 la cara de la sala quedaba a sombra y la
	# captura salia la mitad negra — pensado antes de disparar, no a ojo). :v
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sol.light_energy = 1.15
	sol.shadow_enabled = true
	add_child(sol)

	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(-7.0, 4.5, -7.0)
	cam.look_at(Vector3(2.5, 1.0, 0.5))


# ---------------------------------------------------------------------------
#  Test automatico (INFECT_TEST=1) — 8 comprobaciones
# ---------------------------------------------------------------------------
func _comprobar_todo() -> void:
	var suelo := _zona_suelo.parches()
	var pared := _zona_pared.parches()

	# ---- DIAGNOSTICO DEL NEGRO: que VE Godot dentro del material ---------
	var mat := _zona_suelo.material_zona()
	if mat != null:
		print("[DIAG] shader=", mat.shader.resource_path if mat.shader else "null")
		print("[DIAG] color_base=", mat.get_shader_parameter("color_base"))
		print("[DIAG] color_rojo=", mat.get_shader_parameter("color_rojo"))
		print("[DIAG] textura_huecos=", mat.get_shader_parameter("textura_huecos"))
		var nombres := PackedStringArray()
		if mat.shader != null:
			for p in mat.shader.get_shader_uniform_list():
				nombres.append(String(p.name))
		print("[DIAG] uniforms=", nombres)
		if not suelo.is_empty():
			print("[DIAG] override==zona? ", suelo[0].material_override == mat)

	_comprobar(
			"zona suelo siembra todos (%d)" % PARCHES_SUELO,
			suelo.size() == PARCHES_SUELO,
			"hay %d (descartados=%d)" % [suelo.size(), _zona_suelo.descartados]
	)
	_comprobar(
			"zona pared siembra todos (%d)" % PARCHES_PARED,
			pared.size() == PARCHES_PARED,
			"hay %d (descartados=%d)" % [pared.size(), _zona_pared.descartados]
	)
	_comprobar(
			"ningun rayo central en el vacio",
			_zona_suelo.descartados == 0 and _zona_pared.descartados == 0,
			"descartados suelo=%d pared=%d" % [_zona_suelo.descartados, _zona_pared.descartados]
	)

	# --- mallas y material -------------------------------------------------
	var malla_ok := true
	var mat_ok := true
	var rid_esperado := _zona_suelo.material_zona().get_rid() if _zona_suelo.material_zona() else RID()
	for p in suelo:
		if p.mesh == null or p.mesh.get_surface_count() == 0:
			malla_ok = false
		if p.material_override == null or p.material_override.get_rid() != rid_esperado:
			mat_ok = false
	for p in pared:
		if p.mesh == null or p.mesh.get_surface_count() == 0:
			malla_ok = false
	_comprobar("todos los parches con malla valida", malla_ok, "algun parche sin superficie")
	_comprobar(
			"material compartido dentro de la zona",
			mat_ok,
			"algun parche no cuelga del material de su zona"
	)

	# --- conformacion del suelo -------------------------------------------
	# Todos los vertices deben estar a OFFSET sobre el plano del NODO (el
	# suelo es plano y los pilares estan fuera de la zona). :v
	var desv_max := 0.0
	for p in suelo:
		var arr := p.mesh.surface_get_arrays(0)
		var verts := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var base := p.global_position.y + Parche.OFFSET
		for v in verts:
			var y := p.to_global(v).y
			desv_max = maxf(desv_max, absf(y - base))
	_comprobar(
			"suelo conformado (desviacion max < 0.06 m)",
			desv_max < 0.06,
			"desviacion=%.4f m" % desv_max
	)

	# --- orientacion de la pared ------------------------------------------
	# La normal local (0,1,0) del parche tiene que salir a -X en el mundo:
	# si el rayo hubiera pegado en la cara equivocada, saldria +X. :v
	var alinear := -1.0
	if not pared.is_empty():
		var arrp := pared[0].mesh.surface_get_arrays(0)
		var n0 := (arrp[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0]
		alinear = (pared[0].global_transform.basis * n0).dot(Vector3.LEFT)
	_comprobar(
			"parche de pared orientado a la sala (-X)",
			alinear > 0.9,
			"dot(normal, -X)=%.3f" % alinear
	)

	# --- viento (D-I2) -----------------------------------------------------
	_comprobar(
			"Atmosfera empuja viento a la demo",
			_atm != null and _atm.wind_intensity_actual() > 0.1,
			"wind=%.3f" % (_atm.wind_intensity_actual() if _atm else -1.0)
	)


func _comprobar(nombre: String, ok: bool, detalle: String) -> void:
	if ok:
		print("[PRUEBA] OK   " + nombre)
	else:
		_fallos += 1
		print("[PRUEBA] FALLA " + nombre + " — " + detalle)


func _finalizar() -> void:
	if _fase != 3:
		if _fallos == 0:
			print("[PRUEBA] RESULTADO: TODO OK (8 comprobaciones)")
		else:
			print("[PRUEBA] RESULTADO: FALLA — %d comprobacion(es)" % _fallos)
		get_tree().quit(1 if _fallos > 0 else 0)
	_fase = 3


func _capturar() -> void:
	var ruta := OS.get_environment("INFECT_SHOT_RUTA")
	if ruta == "":
		ruta = RUTA_SHOT
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(ruta)
	print("[PRUEBA] captura -> %s (%s)" % [ruta, error_string(err)])
