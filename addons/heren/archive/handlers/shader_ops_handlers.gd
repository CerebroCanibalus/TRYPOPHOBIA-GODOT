@tool
extends "res://addons/heren/handlers/shader_handlers.gd"

# Heren MCP v4 - ARCHIVADO 2026-09-09 (§0.12 W4 cleanup).
# shader/apply + shader/material + shader/uniform. Reemplazados por
# scene_script workers — la lógica de crear ShaderMaterial, asignarlo al
# nodo y aplicar uniforms es ~10 líneas de GDScript directo.
#
# Hereda de shader_handlers.gd (que sigue activo) para reutilizar helpers
# (_scene_root, _resolve_node, _assign_material, _ensure_gdshader_ext, etc.).
# Para restaurar, ver addons/heren/archive/handlers/README.md.

## One-shot: crea shader (si code) + material + asigna al nodo + uniforms en UNA
## llamada. Útil cuando el agente quiere "pintar este nodo con este shader"
## sin tener que orquestar 3 tool calls.
func handle_apply(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var node_path: Variant = args.get("node_path", "")
	if node_path == "":
		return {"ok": false, "error": "node_path required"}
	var node: Node = _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}

	# 1) Shader: o path existente, o crear desde code/template.
	var shader_path: String = str(args.get("shader_path", ""))
	var shader: Shader = null
	if shader_path != "":
		shader_path = _ensure_gdshader_ext(shader_path)
		if ResourceLoader.exists(shader_path):
			shader = load(shader_path) as Shader
		elif str(args.get("code", "")) != "" or true:
			# crear: shader_path + code (con template si code vacío)
			var code: String = str(args.get("code", ""))
			var st: String = str(args.get("shader_type", "canvas_item"))
			_ensure_parent_dir(shader_path)
			var full_code := code
			if not code.strip_edges().begins_with("shader_type"):
				full_code = "shader_type " + st + ";\n\n" + _shader_template_body(st, code)
			var f := FileAccess.open(shader_path, FileAccess.WRITE)
			if f == null:
				return {"ok": false, "error": "write_failed: " + shader_path}
			f.store_string(full_code)
			f = null
			var efs: EditorFileSystem = _editor_interface().get_resource_filesystem()
			if efs:
				efs.update_file(shader_path)
			shader = load(shader_path) as Shader
	if shader == null:
		return {"ok": false, "error": "shader_load_failed", "shader_path": shader_path}

	# 2) Material + asignación al nodo (misma cascada que handle_material).
	var material := ShaderMaterial.new()
	var material_name: String = str(args.get("material_name", ""))
	if material_name != "":
		material.resource_name = material_name
	material.shader = shader

	var uniforms := _args_dict(args, "uniforms")
	for uniform_name in uniforms.keys():
		material.set_shader_parameter(uniform_name, HerenCoordsScript.deserialize_value(uniforms[uniform_name]))

	var assigned := _assign_material(node, material)
	if not assigned:
		material.free()
		return {
			"ok": false,
			"error": "material_assignment_failed",
			"node_type": node.get_class(),
		}

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"shader_path": shader_path,
		"applied_uniforms": uniforms.keys(),
		"available_uniforms": _shader_uniforms_to_json(shader),
	}


## Crea ShaderMaterial desde un .gdshader y lo asigna al nodo. Si el nodo ya
## tenía material, lo reemplaza (undoable si la operación original lo fue).
## Args: node_path (str, requerido), shader_path (str, requerido),
## material_name (str, opcional), uniforms (dict, opcional).
func handle_material(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var node_path: Variant = args.get("node_path", "")
	var shader_path: String = str(args.get("shader_path", ""))
	if node_path == "" or shader_path == "":
		return {"ok": false, "error": "node_path and shader_path required"}
	shader_path = _ensure_gdshader_ext(shader_path)
	if not ResourceLoader.exists(shader_path):
		return {"ok": false, "error": "shader_not_found: " + shader_path}

	var node: Node = _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}

	var shader: Shader = load(shader_path) as Shader
	if shader == null:
		return {"ok": false, "error": "shader_load_failed: " + shader_path}

	var material := ShaderMaterial.new()
	var material_name: String = str(args.get("material_name", ""))
	if material_name != "":
		material.resource_name = material_name
	material.shader = shader

	var uniforms := _args_dict(args, "uniforms")
	for uniform_name in uniforms.keys():
		material.set_shader_parameter(uniform_name, HerenCoordsScript.deserialize_value(uniforms[uniform_name]))

	var assigned := _assign_material(node, material)
	if not assigned:
		material.free()
		return {
			"ok": false,
			"error": "material_assignment_failed",
			"node_type": node.get_class(),
		}

	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"shader_path": shader_path,
		"material_name": material_name,
		"applied_uniforms": uniforms.keys(),
		"available_uniforms": _shader_uniforms_to_json(shader),
	}


## Modifica uniforms del ShaderMaterial del nodo. Si el nodo no tiene shader
## material, falla (usar handle_material primero para asignarlo).
## Args: node_path (str, requerido), uniforms (dict name→value, requerido).
func handle_uniform(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var node_path: Variant = args.get("node_path", "")
	var uniforms := _args_dict(args, "uniforms")
	if node_path == "" or uniforms.is_empty():
		return {"ok": false, "error": "node_path and uniforms required"}
	var node: Node = _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}
	var material := _find_shader_material(node)
	if material == null or material.shader == null:
		return {"ok": false, "error": "no shader on node", "node_path": str(node_path)}
	var shader_path: String = material.shader.resource_path
	for uniform_name in uniforms.keys():
		material.set_shader_parameter(uniform_name, HerenCoordsScript.deserialize_value(uniforms[uniform_name]))
	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"shader_path": shader_path,
		"applied_uniforms": uniforms.keys(),
		"available_uniforms": _shader_uniforms_to_json(material.shader),
	}
