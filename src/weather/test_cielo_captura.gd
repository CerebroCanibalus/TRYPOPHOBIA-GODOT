extends SceneTree
## LABORATORIO DE CIELO: mira al horizonte y guarda PNGs del cielo.
##
## Existe porque en la petrolera la camara mira a la plataforma y la niebla
## roja se come el cielo entero: no hay forma de juzgar si el fundido al
## horizonte sigue cortando en seco. Aqui la camara apunta deliberadamente
## RASANTE, a unos 8 grados sobre el horizonte, que es justo donde antes
## estaba el escalon.
##
## Se corre SIN --headless (hace falta render real):
##   Godot --path <proj> --script res://src/weather/test_cielo_captura.gd
##
## Salida: `CIELO_RUTA` (si no, junto a Temp) con cielo_normal.png y
## cielo_rayo.png (:v

const PITCH_GRADOS := 35.0


func _initialize() -> void:
	call_deferred("_arrancar")


func _arrancar() -> void:
	var destino: String = OS.get_environment("CIELO_RUTA")
	if destino.is_empty():
		destino = OS.get_environment("TEMP") + "/cielo"
	DirAccess.make_dir_recursive_absolute(destino)

	# ---- Entorno ---------------------------------------------------------
	var ent := Environment.new()
	ent.background_mode = Environment.BG_SKY
	ent.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ent.ambient_light_color = Color(0.42, 0.055, 0.058)
	ent.ambient_light_energy = 1.1
	ent.volumetric_fog_enabled = true
	ent.volumetric_fog_emission_energy = 1.05

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = ent
	# NO se anade aqui: tiene que ser HIJO de Atmosfera, no hermano.
	# `_resolver_entorno` busca por ruta RELATIVA, y si no lo encuentra crea
	# una Environment vacia que ignora la de abajo — el cielo se queda en los
	# defaults y la niebla ni se entera. Es la misma trampa que el test de
	# rayos; ver el warning en `atmosfera.gd` (:v

	# ---- Luz del mapa (Atmosfera la LEE para pintar el sol) ---------------
	var sol := DirectionalLight3D.new()
	sol.name = "Sol"
	# Mira hacia el horizonte y algo abajo, para que el disco del sol quede
	# visible cerca del borde superior.
	sol.rotation_degrees = Vector3(-72.0, 35.0, 0.0)
	root.add_child(sol)

	# ---- Camara rasante ---------------------------------------------------
	var cam := Camera3D.new()
	cam.name = "Camara"
	cam.fov = 75.0
	# OJO CON EL SIGNO: en un Camera3D la rotacion positiva de X es MIRAR
	# ARRIBA. Con `-PITCH_GRADOS` la camara apuntaba 35 grados HACIA ABAJO y
	# las capturas salian del mar y la niebla roja, no del cielo — dos
	# capturas enteras para descubrir un signo.
	cam.rotation_degrees = Vector3(PITCH_GRADOS, 200.0, 0.0)
	root.add_child(cam)
	# OJO con `current_scene`: `_raiz_busqueda()` de Atmosfera parte de ahi
	# para encontrar la luz del mapa, y si el current_scene fuera esta camara
	# (un hermano, no un padre) `Sol` no se encontraria y el disco del sol se
	# pintaria con el respaldo del preset.

	# ---- Atmosfera con el preset de la petrolera --------------------------
	var atm := Atmosfera.new()
	atm.name = "Atmosfera"
	atm.add_child(we)
	root.add_child(atm)
	atm.preset = load("res://resources/clima/petrolera.tres") as AtmosferaPreset
	if atm.preset == null:
		print("FALLO: no carga el preset de la petrolera")
		quit(1)
		return
	print("preset cargado: capas=%d peso=%.2f intensidad=%.2f" % [
			atm.preset.nubes_capas, atm.preset.nubes_peso, atm.preset.nubes_intensidad])

	# Dejo la tormenta APAGADA para la captura normal, y la enciendo despues.
	#
	# La NIEBLA VOLUENTICADA tambien: la de la petrolera es tan densa (y tan
	# roja) que a cualquier elevacion razonable el cielo entero queda tapado
	# por niebla. Mirando rasante a 8 grados la captura salia enteramente roja
	# y no se veia NI UNA nube. Es un laboratorio, no el mapa: se apaga lo que
	# estorba a lo que se quiere medir (:v
	var estaba: bool = atm.preset.rayos_activos
	atm.preset.rayos_activos = false
	atm.preset.niebla_vol_activa = false
	atm.preset.niebla_activa = false
	atm._aplicar()

	for i in 12:
		await process_frame
	_capturar(destino + "/cielo_normal.png")

	# ---- Ahora con tormenta ------------------------------------------------
	atm.preset.rayos_activos = true
	atm.preset.rayos_frecuencia_media = 1.5
	atm.preset.rayos_variacion = 0.0
	atm.preset.rayos_semilla = 7
	atm.preset.rayos_distancia_min = 500.0
	atm.preset.rayos_distancia_max = 1500.0
	atm._aplicar()

	# Espero hasta que haya un Relampago con la cinta visible. Lo miro a mano
	# porque el temporizador reparte los destellos por su cuenta.
	var rel := atm.get_node_or_null("Relampago") as Relampago
	if rel == null:
		print("FALLO: no se creo el Relampago")
		quit(1)
		return
	rel.set_process(false)
	rel.forzar_rayo(900.0)
	for _i in 3:
		rel._process(0.016)
	print("intensidad cielo=%.2f ambiente=%.2f niebla=%.2f rayo_visible=%s" % [
			float(atm._mat.get_shader_parameter("rayos_intensidad")),
			ent.ambient_light_energy, ent.volumetric_fog_emission_energy,
			str(rel.get_node("Rayo").visible)])

	for i in 4:
		await process_frame
	_capturar(destino + "/cielo_rayo.png")

	atm.preset.rayos_activos = estaba
	print("GUARDADO en " + destino)
	quit(0)


func _capturar(ruta: String) -> void:
	var tex := root.get_viewport().get_texture()
	if tex == null:
		print("FALLO: no hay textura de viewport en " + ruta)
		return
	var img := tex.get_image()
	var err := img.save_png(ruta)
	print("  %s -> %s (%s)" % [ruta, "OK" if err == OK else "ERR", error_string(err)])
