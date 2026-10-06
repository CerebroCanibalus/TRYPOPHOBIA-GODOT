# Galeria de los assets exportados desde la biblia.
#   godot --path . tools/galeria/galeria.tscn
#
# UNA CAPTURA POR PIEZA, cada una con su encuadre. El primer intento ponia toda
# una familia en fila y sacaba una foto: la compuerta de 6x8 m se comia el
# encuadre y la palanca de pared, que mide un metro, salia de tres pixeles. Una
# fila de assets de tamanos tan distintos no se puede fotografiar junta — o ves
# los grandes o ves los pequenos.
extends Node3D

# SE RENDERIZA A UN SubViewport DE TAMANO FIJO, no a la ventana. Con --resolution
# 1920x1080 las capturas salian a 955x1043: Hyprland tesela la ventana y Godot
# obedece al gestor, asi que el tamano de la imagen lo acababa decidiendo el
# escritorio. Un SubViewport no lo toca nadie.
const LADO := 512
const SALIDA := "user://capturas/"

var camara: Camera3D
var mundo: SubViewport
var piezas: Array = []


func _bbox(n: Node, aabb: AABB, primero: bool) -> Array:
	if n is MeshInstance3D and n.mesh:
		var a: AABB = (n as MeshInstance3D).global_transform * n.mesh.get_aabb()
		aabb = a if primero else aabb.merge(a)
		primero = false
	for h in n.get_children():
		var r := _bbox(h, aabb, primero)
		aabb = r[0]; primero = r[1]
	return [aabb, primero]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SALIDA))

	mundo = SubViewport.new()
	mundo.size = Vector2i(LADO, LADO)
	mundo.own_world_3d = true
	mundo.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(mundo)

	# DOS LUCES Y AMBIENTE GENEROSO. Con una sola direccional, la cara opuesta de
	# cada pieza cae a negro puro y la mitad del modelado no se ve — que es justo
	# lo contrario de para lo que sirve una galeria.
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-38, -35, 0)
	sol.light_energy = 2.0
	sol.light_color = Color(1.0, 0.95, 0.86)
	mundo.add_child(sol)
	var relleno := DirectionalLight3D.new()
	relleno.rotation_degrees = Vector3(-18, 145, 0)
	relleno.light_energy = 0.7
	relleno.light_color = Color(0.72, 0.80, 1.0)
	mundo.add_child(relleno)

	var ent := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.075, 0.085, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.46, 0.52, 0.66)
	e.ambient_light_energy = 0.9
	ent.environment = e
	mundo.add_child(ent)

	camara = Camera3D.new()
	camara.fov = 38.0
	mundo.add_child(camara)

	var raiz := "res://assets/env/"
	var ids := DirAccess.get_directories_at(raiz)
	ids.sort()
	for id in ids:
		var fs := DirAccess.get_files_at(raiz + id)
		fs.sort()
		for f in fs:
			if not f.ends_with(".gltf"):
				continue
			var ps := load(raiz + id + "/" + f) as PackedScene
			if ps:
				piezas.append([f.get_basename(), ps])
	_capturar.call_deferred()


func _capturar() -> void:
	for par in piezas:
		var n: Node3D = par[1].instantiate()
		mundo.add_child(n)
		await RenderingServer.frame_post_draw
		var a: AABB = _bbox(n, AABB(), true)[0]
		var centro := a.position + a.size * 0.5
		var radio: float = maxf(a.size.length() * 0.5, 0.15)
		var d: float = radio / tan(deg_to_rad(camara.fov * 0.5)) * 1.18
		# POR DELANTE. Al exportar a glTF, Blender pasa de Z-arriba a Y-arriba y
		# su +Y se convierte en -Z. Con la camara en +Z yo estaba fotografiando
		# la ESPALDA de todo: la pilastra salia lisa —sin acanaladuras y sin las
		# hojas del capitel— y parecia que la geometria no estaba. Estaba; la
		# estaba mirando por el lado que se pega al muro.
		var dir := Vector3(0.72, 0.42, -1.0).normalized()
		camara.position = centro + dir * d
		camara.look_at(centro)
		camara.near = maxf(d * 0.01, 0.01)
		camara.far = d * 4.0
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := mundo.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(SALIDA) + par[0] + ".png")
		print("captura: ", par[0], "  ", a.size.snappedf(0.01))
		n.queue_free()
		await get_tree().process_frame
	print("TOTAL ", piezas.size())
	get_tree().quit()
