@tool
extends SceneTree
## Comprueba, DENTRO del motor, las piezas de la Isla que viven en la carpeta del
## nivel. Lo que importa no es si salio un mensaje al importar: es si el arreglo
## llego a la pieza. `backface_collision` encendido solo puede haberlo puesto
## `src/import/arreglos_al_importar.gd`, asi que sirve de testigo.
func _init():
	var dir := DirAccess.open("res://maps/misiones/isla_c2")
	var rutas: Array = []
	for f in dir.get_files():
		if f.ends_with(".gltf"): rutas.append("res://maps/misiones/isla_c2/" + f)
	rutas.sort()
	var ok := 0; var rotos := []; var sin_script := []; var comprimidos := []
	var con_col := 0; var tris := 0
	for r in rutas:
		var esc := load(r) as PackedScene
		if esc == null: rotos.append(r.get_file()); continue
		var n := esc.instantiate()
		var formas: Array = n.find_children("*", "CollisionShape3D", true, false)
		for f in formas:
			var c := f.shape as ConcavePolygonShape3D
			if c != null:
				con_col += 1
				if not c.backface_collision: sin_script.append(r.get_file())
		for m in n.find_children("*", "MeshInstance3D", true, false):
			if m.mesh == null: continue
			tris += m.mesh.get_faces().size() / 3
			for i in m.mesh.get_surface_count():
				var mat := m.mesh.surface_get_material(i) as BaseMaterial3D
				if mat and mat.albedo_texture:
					var im := mat.albedo_texture.get_image()
					if im.get_format() != Image.FORMAT_RGBA8 and im.get_format() != Image.FORMAT_RGB8:
						comprimidos.append(r.get_file())
		ok += 1
	print("[nivel] %d/%d glTF cargan · %d tris · %d formas de colision trimalla"
		% [ok, rutas.size(), tris, con_col])
	print("[nivel] sin el arreglo de importacion: %d  %s"
		% [sin_script.size(), ", ".join(sin_script.slice(0, 4))])
	print("[nivel] atlas comprimidos: %d · rotos: %d %s"
		% [comprimidos.size(), rotos.size(), ", ".join(rotos.slice(0, 3))])
	quit()
