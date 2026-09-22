extends Node3D
## Captura la escena y sale. Solo para verificar el shader sin abrir el editor.

const ANCHO_EFECTIVO := 384.0   # la resolucion a la que se dibuja el juego

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await get_tree().process_frame
	await get_tree().process_frame

	# PixelSize se ajusta al ancho REAL de la ventana, no al que yo quiera:
	# el gestor de ventanas puede recortarla y entonces el pixelado saldria a
	# otra escala y la prueba no valdria.
	var ancho := float(get_viewport().get_visible_rect().size.x)
	var quad := $Camara/PostProceso as MeshInstance3D
	var mat := quad.get_surface_override_material(0) as ShaderMaterial
	# sin redondear a entero: el shader admite float, y redondear a 2 daba
	# 477 px efectivos en vez de 384, o sea otra escala de pixel
	var ps: float = max(1.0, ancho / ANCHO_EFECTIVO)
	mat.set_shader_parameter("PixelSize", ps)
	print("[captura] ventana %d px · PixelSize %.2f · efectivo %d px de ancho"
		% [int(ancho), ps, int(ancho / ps)])

	for i in 3:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("/tmp/claude-1000/-home-vaknadesu/862512b2-f0f0-4005-a8ac-7d5ea6845461/scratchpad/orn01_godot.png")
	print("[captura] guardada ", img.get_width(), "x", img.get_height())
	get_tree().quit()
