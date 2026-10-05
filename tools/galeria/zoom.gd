extends Node3D
const LADO := 900
func _ready() -> void:
	var vp := SubViewport.new(); vp.size = Vector2i(LADO, LADO)
	vp.own_world_3d = true; vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	for r in [[Vector3(-38,-35,0), 2.2, Color(1,.95,.86)], [Vector3(-18,145,0), .8, Color(.7,.8,1)]]:
		var l := DirectionalLight3D.new(); l.rotation_degrees = r[0]
		l.light_energy = r[1]; l.light_color = r[2]; vp.add_child(l)
	var we := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(.07,.08,.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(.5,.56,.7); e.ambient_light_energy = 1.0
	we.environment = e; vp.add_child(we)
	var cam := Camera3D.new(); cam.fov = 34.0; vp.add_child(cam)
	var casos := [["res://assets/env/NIE-01/NIE-01_Costra.gltf", Vector3(0,0,0), 0.72, "N01", Vector3(0.4,0.75,-0.6)],
				  ["res://assets/env/NIE-03/NIE-03_Pustula.gltf", Vector3(0,0.4,0), 0.48, "N03", Vector3(0.5,0.25,-1)],
				  ["res://assets/env/NIE-05/NIE-05_Bulbo_de_esporas.gltf", Vector3(0,0.65,0), 0.75, "N05", Vector3(0.5,0.2,-1)]]
	for c in casos:
		var n: Node3D = (load(c[0]) as PackedScene).instantiate()
		vp.add_child(n)
		await RenderingServer.frame_post_draw
		var centro: Vector3 = c[1]
		var d: float = float(c[2]) / tan(deg_to_rad(cam.fov * .5)) * 1.1
		cam.position = centro + (c[4] as Vector3).normalized() * d
		cam.look_at(centro); cam.near = 0.01; cam.far = d * 5.0
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(
			ProjectSettings.globalize_path("user://capturas/") + str(c[3]) + ".png")
		print("zoom: ", c[3])
		n.queue_free(); await get_tree().process_frame
	get_tree().quit()
