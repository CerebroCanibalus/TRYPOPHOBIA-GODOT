extends Node
## Captura la isla desde la escena jugable REAL y sale. Diagnostico del shader:
## no hay sistema de guardado en el proyecto, asi que lanzarlo no toca nada.
##
## La camara del jugador NO sirve para medir el verde: Iza aparece a ras de suelo
## con la linterna encendida y el blanco quemado se come media pantalla. Asi que
## se anade una camara de diagnostico en alto y se apaga la linterna. El
## cuantizador ya no hay que moverlo: vive en un CanvasLayer, que es de pantalla.

const ANCHO_EFECTIVO := 384.0
const RUTA := "/tmp/claude-1000/-home-vaknadesu/862512b2-f0f0-4005-a8ac-7d5ea6845461/scratchpad"
# la isla: CENTRO (108, 0) y RADIO_BASE 280 en Blender -> (x, z, -y) en Godot
const MIRA := Vector3(108.0, 20.0, 0.0)
const OJO := Vector3(108.0, 210.0, 330.0)

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await get_tree().process_frame
	await get_tree().process_frame

	var rect := get_node_or_null("Isla/PostProceso/Pixelado") as ColorRect
	if rect == null:
		push_error("[captura] no encuentro el cuantizador en la escena")
		get_tree().quit(1)
		return
	var mat := rect.material as ShaderMaterial
	var pal: Texture2D = mat.get_shader_parameter("PaletteTexture")

	var linterna := get_node_or_null("Isla/Iza/CameraPivot/Camera3D/Linterna") as Light3D
	if linterna: linterna.visible = false

	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.far = 2000.0
	add_child(cam)
	cam.global_position = OJO
	cam.look_at(MIRA, Vector3.UP)
	cam.current = true

	for n in get_node("Isla/Isla").find_children("*", "DirectionalLight3D", true, false):
		print("[captura] %s energia %.3f" % [n.name, n.light_energy])

	var ancho := float(get_viewport().get_visible_rect().size.x)
	# el gestor de ventanas puede recortar: PixelSize se ajusta al ancho REAL
	var ps: float = max(1.0, ancho / ANCHO_EFECTIVO)
	mat.set_shader_parameter("PixelSize", ps)
	print("[captura] ventana %d px · PixelSize %.2f · efectivo %d px · paleta %dx%d = %d colores"
		% [int(ancho), ps, int(ancho / ps), pal.get_width(), pal.get_height(),
		   pal.get_width() * pal.get_height()])

	# el MISMO fotograma cuatro veces: sin cuantizar, con las 36, con las 32 de
	# siempre y con las 36 matando el azul. Las tres ultimas son contrafactuales:
	# sin ellas no se puede afirmar que la rampa verde ni el apano del azul
	# cambien nada.
	var pal32: Texture2D = load("res://assets/sprites/palettes/tripofobia-32.png")
	for nombre in ["isla_sin_paleta", "isla_con_paleta", "isla_con_32", "isla_mata_azul"]:
		mat.set_shader_parameter("Quantize", nombre != "isla_sin_paleta")
		mat.set_shader_parameter("PaletteTexture", pal32 if nombre == "isla_con_32" else pal)
		mat.set_shader_parameter("RemoveBlue", nombre == "isla_mata_azul")
		for i in 4:
			await get_tree().process_frame
		await get_tree().create_timer(0.4).timeout
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [RUTA, nombre])
		print("[captura] %s %dx%d" % [nombre, img.get_width(), img.get_height()])
	# EL ANTES, reconstruido: Sol a 1775.8 (el lux crudo del glTF) y revelado
	# Lineal con ambiente a cero, que es exactamente como estaba la escena antes
	# de este arreglo — sin WorldEnvironment no hay tonemapper ni ambiente.
	var ent := get_node("Isla/Entorno") as WorldEnvironment
	ent.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	ent.environment.ambient_light_energy = 0.0
	for n in get_node("Isla/Isla").find_children("*", "DirectionalLight3D", true, false):
		n.light_energy *= 683.0
	mat.set_shader_parameter("Quantize", false)
	for i in 4:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png("%s/isla_quemada.png" % RUTA)
	print("[captura] isla_quemada (estado anterior reconstruido)")
	get_tree().quit()
