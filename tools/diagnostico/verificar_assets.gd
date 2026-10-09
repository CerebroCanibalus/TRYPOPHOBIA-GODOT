# Comprueba DENTRO de Godot lo que el exportador solo puede prometer desde fuera.
#   godot --headless --script tools/verificar_assets.gd
@tool
extends SceneTree

const FILTRO_NEAREST := BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS

func _arbol(n: Node, prof := 0) -> Dictionary:
	var r := {"malla": 0, "col": 0, "luz": 0, "mats": [], "meta": {}}
	if n is MeshInstance3D:
		r.malla += 1
		var m: Mesh = (n as MeshInstance3D).mesh
		if m:
			for i in m.get_surface_count():
				var mat := m.surface_get_material(i)
				if mat is BaseMaterial3D:
					r.mats.append([mat.texture_filter, mat.albedo_texture != null])
	if n is CollisionShape3D: r.col += 1
	if n is Light3D: r.luz += 1
	# los extras de glTF llegan agrupados en UN meta llamado "extras", no sueltos
	if n.has_meta("extras"):
		var e = n.get_meta("extras")
		if e is Dictionary: r.meta.merge(e)
	for h in n.get_children():
		var s := _arbol(h, prof + 1)
		r.malla += s.malla; r.col += s.col; r.luz += s.luz
		r.mats.append_array(s.mats); r.meta.merge(s.meta)
	return r

func _init() -> void:
	var dir := "res://assets/env/"
	var ids := DirAccess.get_directories_at(dir)
	ids.sort()
	var tot := {"esc": 0, "col": 0, "luz": 0, "sin_col": [], "borroso": [], "sin_tex": []}
	for id in ids:
		for f in DirAccess.get_files_at(dir + id):
			if not f.ends_with(".gltf"): continue
			var ps := load(dir + id + "/" + f) as PackedScene
			if ps == null:
				print("  NO CARGA: ", f); continue
			var n := ps.instantiate()
			var r := _arbol(n)
			tot.esc += 1; tot.col += r.col; tot.luz += r.luz
			if r.col == 0: tot.sin_col.append(f)
			for m in r.mats:
				if m[0] != BaseMaterial3D.TEXTURE_FILTER_NEAREST and m[0] != FILTRO_NEAREST:
					tot.borroso.append(f + " (filtro " + str(m[0]) + ")")
				if not m[1]: tot.sin_tex.append(f)
			if r.meta.has("carrera_m") or r.meta.has("luz_w") or r.meta.has("alternar_espejo"):
				print("  metadatos vivos en ", f, ": ", r.meta)
			n.queue_free()
	print("\nESCENAS ", tot.esc, " · colisionadores ", tot.col, " · luces ", tot.luz)
	print("sin colision: ", tot.sin_col.size(), " ", tot.sin_col)
	print("con filtro borroso: ", tot.borroso.size(), " ", tot.borroso)
	print("materiales sin textura: ", tot.sin_tex.size())
	quit()
