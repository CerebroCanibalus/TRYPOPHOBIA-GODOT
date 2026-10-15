@tool
extends SceneTree
## ¿Estan TODAS las piezas de la Isla cargables desde Godot? Se carga cada una y
## se mira lo que de verdad rompe: que instancie, que traiga malla, que traiga
## colision y que su atlas NO venga comprimido a VRAM.
func _init():
	var f := FileAccess.open("/tmp/claude-1000/-home-vaknadesu/862512b2-f0f0-4005-a8ac-7d5ea6845461/scratchpad/rutas.json", FileAccess.READ)
	var rutas: Array = JSON.parse_string(f.get_as_text())
	var ok := 0; var sin_col := []; var comprimidos := []; var rotos := []
	var tris := 0
	for r in rutas:
		var esc := load(r) as PackedScene
		if esc == null: rotos.append(r); continue
		var n := esc.instantiate()
		var mallas: Array = n.find_children("*", "MeshInstance3D", true, false)
		var cuerpos: Array = n.find_children("*", "StaticBody3D", true, false)
		if mallas.is_empty(): rotos.append(r + " (sin malla)"); continue
		if cuerpos.is_empty(): sin_col.append(r.get_file())
		for m in mallas:
			if m.mesh == null: continue
			tris += m.mesh.get_faces().size() / 3
			for i in m.mesh.get_surface_count():
				var mat := m.mesh.surface_get_material(i) as BaseMaterial3D
				if mat == null or mat.albedo_texture == null: continue
				var im := mat.albedo_texture.get_image()
				if im.get_format() != Image.FORMAT_RGBA8 and im.get_format() != Image.FORMAT_RGB8:
					comprimidos.append(r.get_file())
		ok += 1
	print("[isla] %d/%d glTF cargan e instancian · %d tris sumados" % [ok, rutas.size(), tris])
	print("[isla] sin colision: %d  %s" % [sin_col.size(), ", ".join(sin_col.slice(0, 8))])
	print("[isla] atlas comprimidos: %d" % comprimidos.size())
	print("[isla] rotos: %d  %s" % [rotos.size(), ", ".join(rotos.slice(0, 5))])
	quit()
