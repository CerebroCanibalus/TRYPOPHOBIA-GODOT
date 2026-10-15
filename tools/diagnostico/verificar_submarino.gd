@tool
extends SceneTree
## Comprueba el SM-13 DENTRO de Godot, que es lo unico que vale: el exportador
## solo puede prometerlo desde fuera.
func _init():
	var esc := load("res://assets/env/Submarino/SM-13_Sumergible.tscn") as PackedScene
	assert(esc != null, "no carga la pieza")
	var n := esc.instantiate()
	var luces: Array = n.find_children("*", "Light3D", true, false)
	var cuerpos: Array = n.find_children("*", "StaticBody3D", true, false)
	var formas: Array = n.find_children("*", "CollisionShape3D", true, false)
	var mallas: Array = n.find_children("*", "MeshInstance3D", true, false)
	print("[verif] %d malla(s) · %d cuerpo(s) de colision · %d forma(s) · %d luces"
		% [mallas.size(), cuerpos.size(), formas.size(), luces.size()])
	assert(mallas.size() == 1, "deberia ser UNA pieza: hay %d mallas" % mallas.size())
	assert(cuerpos.size() == 1, "deberia ser UN cuerpo: hay %d" % cuerpos.size())
	for f in formas:
		var c := f.shape as ConcavePolygonShape3D
		assert(c != null, "la colision no es trimalla: un casco convexo tapa el interior")
		assert(c.backface_collision, "la trimalla choca por una cara: se cae por el suelo")
	# SE COMPRUEBAN LAS UNIDADES, NO EL NUMERO. Aqui habia escrito 26.0 a mano, que
	# es un valor que vive en montar_sumergible.py; al reajustar las lamparas a 32
	# el assert fallo y el proceso se quedo COLGADO, sin decir por que. Un
	# comprobador que fija una constante de otro fichero se rompe solo cada vez que
	# se afina algo. Lo que de verdad hay que vigilar es que el glTF no entre en
	# unidades fotometricas: 32 W frente a los 1.740 cd que manda el exportador.
	for l in luces:
		assert(l is OmniLight3D, "viaja una luz que no es lampara")
		assert(l.light_energy > 0.5 and l.light_energy < 200.0,
			"la luz no esta en vatios (%f): el glTF la manda en candelas" % l.light_energy)
		print("   %-16s %.1f W" % [l.name, l.light_energy])
	var tris := 0
	for m in mallas:
		if m.mesh: tris += m.mesh.get_faces().size() / 3
		for i in (m.mesh.get_surface_count() if m.mesh else 0):
			var mat := m.mesh.surface_get_material(i) as BaseMaterial3D
			if mat and mat.albedo_texture:
				var im := mat.albedo_texture.get_image()
				assert(im.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_RGB8],
					"atlas comprimido: la paleta de 6 colores esta rota")
				assert(not im.has_mipmaps(), "el atlas trae mipmaps")
	var caja: AABB = mallas[0].mesh.get_aabb()
	print("[verif] %d tris · caja %.2f x %.2f x %.2f m" % [tris, caja.size.x, caja.size.y, caja.size.z])
	print("[verif] OK")
	quit()
