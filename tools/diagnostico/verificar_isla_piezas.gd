@tool
extends SceneTree
## Comprueba DENTRO de Godot las piezas sueltas de la Isla. El exportador solo
## puede prometerlas desde fuera.
const PIEZAS := {
	"res://assets/env/Isla_terreno/Isla_terreno.gltf": 9,
	"res://assets/env/Broto_recercado/Broto_recercado.gltf": 1,
}
func _init():
	var mal := 0
	for ruta in PIEZAS:
		var esc := load(ruta) as PackedScene
		if esc == null:
			print("[verif] NO CARGA %s" % ruta); mal += 1; continue
		var n := esc.instantiate()
		var cuerpos: Array = n.find_children("*", "StaticBody3D", true, false)
		var mallas: Array = n.find_children("*", "MeshInstance3D", true, false)
		var tris := 0
		var atlas := 0
		for m in mallas:
			if m.mesh == null: continue
			tris += m.mesh.get_faces().size() / 3
			for i in m.mesh.get_surface_count():
				var mat := m.mesh.surface_get_material(i) as BaseMaterial3D
				if mat == null or mat.albedo_texture == null: continue
				atlas += 1
				var im := mat.albedo_texture.get_image()
				if im.get_format() != Image.FORMAT_RGBA8 and im.get_format() != Image.FORMAT_RGB8:
					print("   ATLAS COMPRIMIDO en %s (formato %d)" % [ruta, im.get_format()]); mal += 1
				if im.has_mipmaps():
					print("   mipmaps en %s" % ruta); mal += 1
		print("[verif] %-34s %7d tris · %d colision · %d superficies con atlas"
			% [ruta.get_file(), tris, cuerpos.size(), atlas])
		if cuerpos.is_empty():
			print("   SIN COLISION: se atraviesa"); mal += 1
	print("[verif] %s" % ("OK" if mal == 0 else "%d problemas" % mal))
	quit()
