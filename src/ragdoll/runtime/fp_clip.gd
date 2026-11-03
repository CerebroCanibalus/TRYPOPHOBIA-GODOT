extends Node
class_name FpClip
## RECORTE DE PRIMERA PERSONA: en 1a persona la camara esta dentro de la
## cabeza, asi que sin esto se ve el interior del craneo.
##
## Se sustituye el material de cada superficie por uno equivalente con el
## shader de recorte, que descarta los fragmentos mas cercanos a la camara.
##
## TRAMPA: el `Skin` del GLB es un recurso COMPARTIDO entre las dos
## instancias del modelo (la fisica y la animada) y su ruta apunta al
## esqueleto de SU padre. Sin duplicarlo, la malla del "Physical" se
## deformaba con el esqueleto ANIMADO (que esta en otra pose) y salia
## hecha pedazos. El mesh tambien se duplica por lo mismo.

## Shader de recorte.
@export_file("*.gdshader") var shader_path := "res://src/ragdoll/shaders/fp_body_clip_tex.gdshader"
## Radio de recorte (metros) alrededor de la camara.
@export var radius := 0.20
## Si el recorte esta activo.
@export var active_clip := true

var _clip_materials := {}     ## material original -> material de recorte
var _entries: Array = []      ## [MeshInstance3D, Mesh, Array[Material]]


## Recoge las mallas del cuerpo (las que llevan el skin).
func collect_meshes(root: Node) -> void:
	_entries.clear()
	if root == null:
		return
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin == null:
			continue
		_entries.append([mi, mi.mesh, []] as Array)


## Prepara los materiales de recorte (duplica mesh y skin).
func setup() -> void:
	_clip_materials.clear()
	if _entries.is_empty():
		return
	var shader: Shader = load(shader_path)
	if shader == null:
		push_warning("[FpClip] shader de recorte no encontrado: %s" % shader_path)
		return
	for entry in _entries:
		var mi: MeshInstance3D = entry[0]
		var mesh: Mesh = entry[1]
		if mesh == null:
			continue
		if not mesh.resource_local_to_scene:
			var dup := mesh.duplicate() as Mesh
			if dup != null:
				mi.mesh = dup
				mesh = dup
		# El SKIN tambien hay que duplicarlo (ver la nota de arriba).
		if mi.skin != null:
			mi.skin = mi.skin.duplicate()
		var originals: Array[Material] = []
		for s in mesh.get_surface_count():
			var orig := mesh.surface_get_material(s)
			originals.append(orig)
			if orig == null:
				continue
			if not _clip_materials.has(orig):
				_clip_materials[orig] = _make_material(shader, orig)
		entry[2] = originals


## Activa o desactiva el recorte (1a / 3a persona).
func set_active(v: bool) -> void:
	active_clip = v
	apply_materials()


## Aplica (o restaura) los materiales de recorte.
func apply_materials() -> void:
	var r := radius if active_clip else 0.0
	for entry in _entries:
		var mi: MeshInstance3D = entry[0]
		var mesh: Mesh = entry[1]
		var originals: Array = entry[2]
		var ov := mi.material_override
		if ov is ShaderMaterial:
			(ov as ShaderMaterial).set_shader_parameter("clip_radius", r)
			continue
		for s in originals.size():
			var orig: Material = originals[s]
			var m: Material = orig
			if active_clip and orig != null and _clip_materials.has(orig):
				m = _clip_materials[orig]
			if s < mesh.get_surface_count():
				mesh.surface_set_material(s, m)
	for key in _clip_materials.keys():
		var mat: ShaderMaterial = _clip_materials[key]
		mat.set_shader_parameter("clip_radius", r)


## Material de recorte que reproduce el aspecto del StandardMaterial3D
## original (color, rugosidad, metalic, textura y vertex colors).
func _make_material(shader: Shader, orig: Material) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var sm := orig as StandardMaterial3D
	if sm == null:
		mat.set_shader_parameter("albedo_color", Color.WHITE)
		return mat
	mat.set_shader_parameter("albedo_color", sm.albedo_color)
	mat.set_shader_parameter("roughness", sm.roughness)
	mat.set_shader_parameter("metallic", sm.metallic)
	var tex := sm.albedo_texture
	mat.set_shader_parameter("use_albedo_texture", tex != null)
	if tex != null:
		mat.set_shader_parameter("albedo_texture", tex)
	mat.set_shader_parameter("use_vertex_color", _bool_prop(sm, "vertex_color_use_as_albedo"))
	mat.set_shader_parameter("alpha_enabled", sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
	mat.set_shader_parameter("alpha_scissor_enabled",
			sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
	mat.set_shader_parameter("alpha_scissor", sm.alpha_scissor_threshold)
	mat.set_shader_parameter("emission_enabled", sm.emission_enabled)
	mat.set_shader_parameter("emission_color", sm.emission)
	mat.set_shader_parameter("emission_energy", sm.emission_energy_multiplier)
	return mat


## Lee una propiedad bool de un Object sin petar si la version del motor no
## la tiene (los materiales del GLB cambian entre versiones).
func _bool_prop(obj: Object, prop: String) -> bool:
	for p in obj.get_property_list():
		if String(p.get("name", "")) == prop:
			return bool(obj.get(prop))
	return false
