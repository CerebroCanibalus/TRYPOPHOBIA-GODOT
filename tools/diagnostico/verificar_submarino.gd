@tool
extends SceneTree
## Comprueba el SM-13 DENTRO de Godot, que es lo unico que vale: el exportador
## solo puede prometerlo desde fuera.
func _init():
	var esc := load("res://assets/env/Submarino/SM-13_Sumergible.gltf") as PackedScene
	assert(esc != null, "no carga el glTF")
	var n := esc.instantiate()
	var luces: Array = n.find_children("*", "Light3D", true, false)
	var cuerpos: Array = n.find_children("*", "StaticBody3D", true, false)
	var mallas: Array = n.find_children("*", "MeshInstance3D", true, false)
	print("[verif] luces: %d" % luces.size())
	for l in luces:
		print("   %-18s %s  energia %.3f" % [l.name, l.get_class(), l.light_energy])
		assert(l is OmniLight3D, "viaja una luz que no es lampara: %s" % l.get_class())
		assert(abs(l.light_energy - 26.0) < 0.01, "la luz no volvio a vatios: %f" % l.light_energy)
	print("[verif] cuerpos de colision: %d" % cuerpos.size())
	assert(cuerpos.size() > 0, "sin colision: el submarino se atraviesa y no hay interior")
	var tris := 0
	for m in mallas:
		if m.mesh: tris += m.mesh.get_faces().size() / 3
		for i in (m.mesh.get_surface_count() if m.mesh else 0):
			var mat := m.mesh.surface_get_material(i) as BaseMaterial3D
			var t: Texture2D = mat.albedo_texture if mat else null
			if t:
				var im := t.get_image()
				print("   atlas %-16s %dx%d  formato %d  mipmaps %s"
					% [t.resource_path.get_file(), im.get_width(), im.get_height(),
					   im.get_format(), im.has_mipmaps()])
				assert(im.get_format() == Image.FORMAT_RGBA8 or im.get_format() == Image.FORMAT_RGB8,
					"el atlas viene comprimido: la paleta de 6 colores esta rota")
				assert(not im.has_mipmaps(), "el atlas trae mipmaps")
	print("[verif] triangulos: %d" % tris)
	print("[verif] OK")
	quit()
