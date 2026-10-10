extends SceneTree
## Prueba del sistema de RAYOS, sin escenas ni render.
##
## Se corre con:
##   Godot --headless --path <proj> --script res://src/weather/test_relampago.gd
##
## Monta un Atmosfera con su Environment a mano, fuerza destellos y mide la
## envoltura. NO mira si se ve bonito — para eso esta el General — sino si la
## logica hace lo que dice que hace: que la luz SUBE de golpe, que BAJA suave,
## que vuelve al valor base, que el rayo existe y que el trueno se senala con
## su retardo (:v

var _fallos := 0
var _total := 0
var _terminado := false


func check(cond: bool, texto: String) -> void:
	_total += 1
	if cond:
		print("  OK   " + texto)
	else:
		_fallos += 1
		print("  MAL  " + texto)


func _initialize() -> void:
	# Los nodos se crean en el PRIMER FRAME y no en `_initialize`: un player
	# o un add_child dentro de `_initialize` se queja de que aun no esta en el
	# arbol. Gotcha ya medida en el sistema de audio (:v
	call_deferred("_arrancar")
	# CUCHILLO DE SEGURIDAD. GDScript no tiene `try/catch`: si algo revienta
	# dentro de `_arrancar`, la ejecucion se corta ahi y `_fin()` — que es el
	# unico que llama a `quit()` — no llega a ejecutarse, con lo que la prueba
	# se queda COLGADA para siempre esperando salir. Me acabo de tropezar con
	# esto: un indice fuera de bounds en la fase 5 y diez minutos de timeout.
	# Con un timer de fondo, falle lo que falle el proceso termina (:v
	create_timer(60.0).timeout.connect(_fin_por_seguridad)


## Salida de emergencia: si llegamos aqui es que algo reviento antes de tiempo.
func _fin_por_seguridad() -> void:
	if _terminado:
		return
	print("")
	print("RESULTADO: TIMEOUT — _arrancar() no llego a completar (%d comprobaciones hechas, %d fallos)" % [
			_total, _fallos])
	quit(1)


func _arrancar() -> void:
	print("=== PRUEBA DE RAYOS ===")

	var ent := Environment.new()
	ent.ambient_light_energy = 1.1
	ent.ambient_light_color = Color(0.42, 0.055, 0.058)
	ent.volumetric_fog_enabled = true
	ent.volumetric_fog_emission_energy = 1.05

	var we := WorldEnvironment.new()
	# OBLIGATORIO ponerle nombre: sin el, Godot lo bautiza como
	# `@WorldEnvironment@2` al entrar en el arbol, `get_node_or_null(
	# NodePath("WorldEnvironment"))` no lo encuentra, y `_resolver_entorno`
	# crea OTRO con una Environment vacia — que es exactamente el fallo que
	# me dio la primera vez y que parecia un bug del sistema. En
	# `atmosfera.tscn` el hijo SI se llama `WorldEnvironment` (:v
	we.name = "WorldEnvironment"
	we.environment = ent

	var atm := Atmosfera.new()
	atm.add_child(we)

	var pres := AtmosferaPreset.new()
	pres.rayos_activos = true
	pres.rayos_semilla = 12345
	pres.rayos_frecuencia_media = 5.0
	pres.rayos_variacion = 0.0
	pres.nubes_altura = 800.0
	atm.preset = pres

	root.add_child(atm)

	# ------------------------------------------------------------------ 1
	print("\n-- 1. montaje --")
	var rel := atm.get_node_or_null("Relampago") as Relampago
	check(rel != null, "Relampago creado en runtime")
	if rel == null:
		return _fin()
	check(rel.has_node("LuzImpacto"), "hijo LuzImpacto")
	check(rel.has_node("LuzNube"), "hijo LuzNube")
	check(rel.has_node("Rayo"), "hijo Rayo (cinta)")
	check(rel.has_node("FlashPantalla"), "hijo FlashPantalla")
	check(rel.get_node("LuzImpacto") is OmniLight3D, "LuzImpacto es OmniLight3D")
	check(rel.get_node("LuzImpacto").shadow_enabled == false, "sombras APAGADAS por defecto")

	# Dejo el proceso en manos del test: si lo mueve el motor, el numero de
	# frames reales depende de la maquina y las medidas no valen para nada.
	rel.set_process(false)

	# ------------------------------------------------------------------ 2
	print("\n-- 2. senales --")
	var cont := {"producido": 0, "dist": -1.0, "truenos": 0, "t_dist": -1.0}
	rel.relampago_producido.connect(func(pos: Vector3, d: float) -> void:
		cont["producido"] = int(cont["producido"]) + 1
		cont["dist"] = d)
	rel.trueno_escuchado.connect(func(d: float, e: float) -> void:
		cont["truenos"] = int(cont["truenos"]) + 1
		cont["t_dist"] = d)

	rel.forzar_rayo(1000.0)
	check(int(cont["producido"]) == 1, "relampago_producido emitido UNA vez")
	check(is_equal_approx(float(cont["dist"]), 1000.0), "la distancia notificada es la pedida")

	# ------------------------------------------------------------------ 3
	print("\n-- 3. envoltura: sube de golpe, baja suave --")
	var mat := atm._mat as ShaderMaterial
	check(mat != null, "atmosfera tiene el material del cielo")

	# ¿El Relampago manda sobre el MISMO Environment de la escena? Si apuntara
	# a otro, la tormenta iluminaria un entorno huerfano y el jugador no
	# veria nada. Salio porque un WorldEnvironment SIN NOMBRE se bautiza
	# como `@WorldEnvironment@2` y ya no lo encuentra `get_node_or_null`.
	check(rel._entorno == ent, "Relampago apunta al MISMO Environment de la escena")
	check(rel._ambiente_base > 0.0, "capturo el ambiente base antes de tocar nada (%.3f)" % rel._ambiente_base)

	var base_amb: float = ent.ambient_light_energy
	var base_nie: float = ent.volumetric_fog_emission_energy
	var paso := 0.016
	var pico_amb := 0.0
	var pico_nie := 0.0
	var pico_cielo := 0.0
	var idx_pico := -1
	var historial: Array[float] = []

	for i in 400:
		rel._process(paso)
		var e: float = ent.ambient_light_energy
		var n: float = ent.volumetric_fog_emission_energy
		var c: float = float(mat.get_shader_parameter("rayos_intensidad"))
		historial.append(e)
		if e > pico_amb:
			pico_amb = e
			idx_pico = i
		pico_nie = maxf(pico_nie, n)
		pico_cielo = maxf(pico_cielo, c)

	check(pico_amb > base_amb * 1.5, "el ambiente SUBE de verdad (%.2f > %.2f)" % [pico_amb, base_amb])
	check(pico_amb <= base_amb * pres.rayos_ambiente_pico + 0.001,
			"no se pasa del pico configurado (%.2f <= %.2f)" % [pico_amb, base_amb * pres.rayos_ambiente_pico])
	check(pico_nie > base_nie * 1.5, "la niebla volumetrica se ENCIENTE (%.2f)" % pico_nie)
	check(pico_cielo > 0.0, "el halo dentro de la nube recibe intensidad (%.2f)" % pico_cielo)

	# La ASIMETRIA es el corazon del encargo: SUBE de golpe y BAJA suave.
	#
	# OJO con lo que se mide. `rayos_restrikes` hace que la envoltura tenga
	# VARIOS bultos, asi que el maximo GLOBAL no es el ataque inicial sino la
	# suma de los repiques — medir "frames hasta el pico" estaba midiendo el
	# repique, no la subida, y salia un falso fallo. Lo que hay que medir es
	# cuando se alcanza la MITAD por PRIMERA vez (eso si es la subida) y
	# cuanto tarda en volver a bajar de ahi.
	var umbral_mitad: float = base_amb + (pico_amb - base_amb) * 0.5
	var idx_subida := -1
	var idx_caida := -1
	for i in historial.size():
		if idx_subida < 0 and historial[i] >= umbral_mitad:
			idx_subida = i
		if idx_subida >= 0 and i > idx_pico and historial[i] <= umbral_mitad:
			idx_caida = i
			break
	check(idx_subida >= 0, "la luz alcanza la mitad del pico")
	check(idx_subida * paso <= 0.08, "la SUBIDA es de golpe: %.3f s hasta la mitad" % (idx_subida * paso))
	check(idx_pico * paso <= 0.3, "el pico entero no tarda mas de 0.3 s (%.3f s)" % (idx_pico * paso))
	check(idx_caida > idx_pico, "la luz baja hasta la mitad por debajo del pico")
	check((idx_caida - idx_pico) > (idx_pico - idx_subida) * 2.0,
			"la CAIDA dura MAS que la SUBIDA: %d frames de caida vs %d de subida" % [
			idx_caida - idx_pico, idx_pico - idx_subida])

	# ------------------------------------------------------------------ 4
	print("\n-- 4. vuelve al valor base --")
	check(is_equal_approx(ent.ambient_light_energy, base_amb),
			"ambiente_restaurado a %.3f (llega %.3f)" % [base_amb, ent.ambient_light_energy])
	# `is_equal_approx(a, b)` global es de FLOATS; para Color va el metodo.
	check(ent.ambient_light_color.is_equal_approx(Color(0.42, 0.055, 0.058)),
			"color del ambiente_restaurado")
	check(is_equal_approx(ent.volumetric_fog_emission_energy, base_nie),
			"niebla_restaurada a %.3f (llega %.3f)" % [base_nie, ent.volumetric_fog_emission_energy])
	check(is_equal_approx(float(mat.get_shader_parameter("rayos_intensidad")), 0.0),
			"halo del cielo apagado al terminar")
	check(not rel.get_node("Rayo").visible, "la cinta se oculta al terminar")

	# ------------------------------------------------------------------ 5
	print("\n-- 5. la cinta del rayo --")
	# EL GOLPE SE FUERZA, no se sortea. `rayos_prob_nube_sola` decide si hay
	# golpe, y con el default 0.3 un destello SIN golpe no dibuja cinta — que
	# es correcto, pero deja la prueba a merced del estado del RNG. Me acabo de
	# tropezar: al cambiar el temporizador a distribucion exponencial se
	# consumieron numeros distintos, salio un solo-nube y la prueba fallo sin
	# que hubiera ningun bug (:v
	pres.rayos_prob_nube_sola = 0.0
	rel.forzar_rayo(800.0)
	var malla := rel.get_node("Rayo").mesh as ImmediateMesh
	var n_sup := malla.get_surface_count()
	check(n_sup > 0, "un rayo que golpea genera superficie (%d)" % n_sup)
	# SIN acceso ciego al indice 0: si no hay superficie, `surface_get_arrays`
	# revienta el worker, `_arrancar` se aborta y `_fin()` NUNCA llega a
	# llamar a `quit()` — o sea que la prueba se COLGABA en vez de fallar.
	# Un test que se cuelga es peor que uno que falla (:v
	if n_sup > 0:
		var verts := malla.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as Array
		check(verts.size() >= 6, "al menos una cinta completa, 6 vertices (%d)" % verts.size())
	else:
		check(false, "no se puede leer vertices sin superficie previa")

	pres.rayos_prob_nube_sola = 1.0
	rel.forzar_rayo(800.0)
	check(malla.get_surface_count() == 0, "un destello SOLO de nube no dibuja cinta")
	pres.rayos_prob_nube_sola = 0.0

	# ------------------------------------------------------------------ 6
	print("\n-- 6. el trueno llega tarde --")
	# VACIO la cola ANTES: los destellos de las fases 2 y 5 siguen con su
	# retardo pendiente, y sin limpiarlos el test contaba el trueno de un rayo
	# anterior como si fuera este. Asi me salio la primera vez.
	rel._truenos.clear()
	rel._apagar()
	cont["truenos"] = 0
	cont["t_dist"] = -1.0

	# 3000 m / 343 m/s = 8.75 s. No hace falta esperarlos a 16 ms: mido con
	# paso grande para que el test dure lo justo.
	rel.forzar_rayo(3000.0)
	var llego := false
	var t := 0.0
	while t < 12.0 and not llego:
		rel._process(0.25)
		t += 0.25
		llego = int(cont["truenos"]) > 0
	check(llego, "trueno_escuchado se emite")
	check(is_equal_approx(float(cont["t_dist"]), 3000.0), "el trueno notifica su distancia")
	var retardo_esperado: float = 3000.0 / Relampago.VELOCIDAD_SONIDO
	check(t >= retardo_esperado - 0.3, "no llega ANTES de lo que tarda el sonido (%.2f s >= %.2f)" % [
			t, retardo_esperado])

	_fin()


func _fin() -> void:
	if _terminado:
		return
	_terminado = true
	print("")
	if _fallos == 0:
		print("RESULTADO: TODO OK (%d comprobaciones)" % _total)
	else:
		print("RESULTADO: %d FALLOS de %d comprobaciones" % [_fallos, _total])
	quit(1 if _fallos > 0 else 0)
