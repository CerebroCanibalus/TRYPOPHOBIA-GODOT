@tool
extends "res://addons/heren/handlers/heren_handler.gd"
# Heren MCP v4 - Shader handlers (Fase 2).
# Shaders .gdshader y ShaderMaterial sobre la escena viva (ADR-002).
#
# Actions (heredadas de v3 shader_tool.py + daemon shader_ops, adaptadas):
#   create   -> escribir .gdshader (dedup de shader_type, heredado de v3)
#   edit     -> append/reemplazar código
#   validate -> ResourceLoader.load + verificar es Shader
#   material -> crear ShaderMaterial en nodo (CanvasItem material,
#               GeometryInstance3D override/overlay, MeshInstance3D surface)
#   uniform  -> set_shader_parameter en el material del nodo

const HerenCoordsScript := preload("coords.gd")
const HerenSceneRegistryScript := preload("../scene_registry.gd")



func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_editor_interface()


func _scene_root(args: Dictionary = {}) -> Node:
	var ei := _editor_interface()
	if ei == null:
		return null
	# Registry (escena creada por MCP en memoria) → pestaña → disco.
	return HerenSceneRegistryScript.resolve_root(ei, str(args.get("scene_path", "")))


func _resolve_node(root: Node, node_path: Variant) -> Node:
	if root == null or node_path == null:
		return null
	var normalized := HerenCoordsScript.normalize_node_path(node_path, root)
	if normalized == ".":
		return root
	if normalized == "":
		return null
	return root.get_node_or_null(NodePath(normalized))


func _node_path_relative(node: Node, root: Node) -> String:
	if node == root:
		return "."
	var path := node.get_path()
	var root_path := root.get_path()
	var path_str := str(path)
	if path_str.begins_with(str(root_path) + "/"):
		return path_str.substr(str(root_path).length() + 1)
	return path_str


func _args_dict(args: Dictionary, key: String) -> Dictionary:
	var raw: Variant = args.get(key, {})
	if raw is Dictionary:
		return raw
	if raw is String:
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
	return {}


func _ensure_gdshader_ext(shader_path: String) -> String:
	if shader_path.ends_with(".gdshader"):
		return shader_path
	return shader_path + ".gdshader"


func _ensure_parent_dir(path: String) -> void:
	var dir_path := path.get_base_dir()
	if dir_path != "" and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))


# ---------------------------------------------------------------- handlers

func handle_create(args: Dictionary) -> Dictionary:
	var shader_path: String = _ensure_gdshader_ext(str(args.get("shader_path", "")))
	var shader_type: String = str(args.get("shader_type", "canvas_item"))
	var code: String = str(args.get("code", ""))
	if shader_path == "" or shader_path == ".gdshader":
		return {"ok": false, "error": "shader_path required"}
	if FileAccess.file_exists(shader_path):
		return {"ok": false, "error": "shader_exists: " + shader_path}

	# v3 fix heredado: no duplicar shader_type si el usuario ya lo incluyó.
	# Template: si el agente no da código, generar boilerplate según tipo
	# (el agente escribe la lógica, no la estructura).
	var full_code := code
	if not code.strip_edges().begins_with("shader_type"):
		full_code = "shader_type " + shader_type + ";\n\n" + _shader_template_body(shader_type, code)

	_ensure_parent_dir(shader_path)
	var file := FileAccess.open(shader_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "write_failed: " + shader_path}
	file.store_string(full_code)
	file = null

	var efs: EditorFileSystem = _editor_interface().get_resource_filesystem()
	if efs:
		efs.update_file(shader_path)

	return {"ok": true, "shader_path": shader_path, "shader_type": shader_type}


## Template body: retorna el cuerpo base según tipo cuando el agente no da
## código. Si code viene, solo retorna ese código (el "shader_type X;" ya se
## añadió arriba).
func _shader_template_body(shader_type: String, code: String) -> String:
	if code.strip_edges() != "":
		return code
	match shader_type.strip_edges():
		"spatial", "world":
			return """uniform vec3 color : source_color = vec3(1.0, 1.0, 1.0);

void fragment() {
	ALBEDO = color;
}"""
		_:
			return """uniform float intensity : hint_range(0.0, 10.0, 0.1) = 1.0;

void fragment() {
	// Lógica del shader aquí
	COLOR = vec4(1.0);
}"""


func handle_edit(args: Dictionary) -> Dictionary:
	var shader_path: String = _ensure_gdshader_ext(str(args.get("shader_path", "")))
	var code: String = str(args.get("code", ""))
	var append: bool = bool(args.get("append", false))
	if shader_path == "" or shader_path == ".gdshader":
		return {"ok": false, "error": "shader_path required"}
	if not FileAccess.file_exists(shader_path):
		return {"ok": false, "error": "shader_not_found: " + shader_path}

	var existing := ""
	if append:
		var rf := FileAccess.open(shader_path, FileAccess.READ)
		if rf:
			existing = rf.get_as_text()
			rf = null

	var file := FileAccess.open(shader_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "write_failed: " + shader_path}
	file.store_string(existing + code)
	file = null

	var efs: EditorFileSystem = _editor_interface().get_resource_filesystem()
	if efs:
		efs.update_file(shader_path)

	return {"ok": true, "shader_path": shader_path, "append": append}


func handle_validate(args: Dictionary) -> Dictionary:
	var shader_path: String = _ensure_gdshader_ext(str(args.get("shader_path", "")))
	if shader_path == "" or shader_path == ".gdshader":
		return {"ok": false, "error": "shader_path required"}
	if not FileAccess.file_exists(shader_path):
		return {"ok": false, "error": "shader_not_found: " + shader_path}

	var shader: Resource = load(shader_path)
	if shader == null or not shader is Shader:
		return {"ok": false, "error": "invalid_shader: " + shader_path}
	var sh := shader as Shader

	# Validación REAL (fix 2026-08-06): Godot 4.7 NO tiene Shader.get_errors()
	# (verificado en runtime: has_method("get_errors") == false) → antes este
	# handler crasheaba con SCRIPT ERROR → "Unknown error" en la tool.
	# Señales reales que SÍ podemos leer:
	#   - parseo estructural (shader_type, función principal, llaves)
	#   - get_shader_uniform_list(): si el código declara uniforms pero el
	#     compilador no registró ninguno → error de compilación.
	var code := ""
	var f := FileAccess.open(shader_path, FileAccess.READ)
	if f != null:
		code = f.get_as_text()
		f = null
	var issues: Array = _shader_structural_issues(sh, code)
	var uniforms := sh.get_shader_uniform_list()
	if uniforms.is_empty() and _shader_declares_uniforms(code):
		issues.append("uniforms declared but none compiled — shader compilation error")
	if issues.is_empty():
		return {"ok": true, "valid": true, "shader_path": shader_path, "error_count": 0}
	return {
		"ok": false,
		"valid": false,
		"shader_path": shader_path,
		"error_count": issues.size(),
		"errors": issues,
	}


func handle_get(args: Dictionary) -> Dictionary:
	var shader_path: String = _ensure_gdshader_ext(str(args.get("shader_path", "")))
	if shader_path == "" or shader_path == ".gdshader":
		return {"ok": false, "error": "shader_path required"}
	if not FileAccess.file_exists(shader_path):
		return {"ok": false, "error": "shader_not_found: " + shader_path}

	var file := FileAccess.open(shader_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot_open: " + shader_path}
	var content := file.get_as_text()
	file = null

	# Uniforms: mejor vía load() (lista real del compilador); fallback parseo.
	var shader_type := _parse_shader_type(content)
	var uniforms: Array = []
	var shader: Resource = load(shader_path)
	if shader is Shader:
		uniforms = _shader_uniforms_to_json(shader as Shader)
	return {
		"ok": true,
		"shader_path": shader_path,
		"shader_type": shader_type,
		"content": content,
		"uniforms": uniforms,
		"uniform_count": uniforms.size(),
	}


func handle_inspect(args: Dictionary) -> Dictionary:
	var shader_path: String = _ensure_gdshader_ext(str(args.get("shader_path", "")))
	# Inspección por nodo: {node_path} → material del nodo → su shader.
	if shader_path == "" or shader_path == ".gdshader":
		var node_path: Variant = args.get("node_path", "")
		if node_path == "":
			return {"ok": false, "error": "shader_path or node_path required"}
		var root := _scene_root(args)
		if root == null:
			return {"ok": false, "error": "no scene open in editor"}
		var node: Node = _resolve_node(root, node_path)
		if node == null:
			return {"ok": false, "error": "node_not_found: " + str(node_path)}
		var material := _find_shader_material(node)
		if material == null or material.shader == null:
			return {"ok": false, "error": "no shader on node", "node_path": str(node_path)}
		shader_path = material.shader.resource_path
		if shader_path == "":
			return {"ok": false, "error": "shader has no resource_path (builtin/visual)", "node_path": str(node_path)}

	if not FileAccess.file_exists(shader_path):
		return {"ok": false, "error": "shader_not_found: " + shader_path}

	var shader: Resource = load(shader_path)
	if shader == null or not shader is Shader:
		return {"ok": false, "error": "invalid_shader: " + shader_path}
	var sh := shader as Shader
	var uniforms := _shader_uniforms_to_json(sh)
	var issues: Array = _shader_structural_issues(sh, sh.get_code())
	return {
		"ok": true,
		"shader_path": shader_path,
		"shader_type": _mode_to_str(sh.get_mode()),
		"uniforms": uniforms,
		"uniform_count": uniforms.size(),
		"errors": issues,
		"valid": issues.is_empty(),
	}


## One-shot: crea shader (si code) + material + asigna al nodo + uniforms en UNA
## llamada. Devuelve también la lista de uniforms disponibles para iterar.
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


func handle_material(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var node_path: Variant = args.get("node_path", "")
	if node_path == "":
		return {"ok": false, "error": "node_path required"}
	var node: Node = _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}

	var shader_path: String = str(args.get("shader_path", ""))
	var material_name: String = str(args.get("material_name", ""))

	var material := ShaderMaterial.new()
	# Fix H2: a ShaderMaterial is a Resource, so it has `resource_name`, NOT
	# `name`. Assigning `material.name` threw a runtime error (→ "Unknown error").
	if material_name != "":
		material.resource_name = material_name
	if shader_path != "" and ResourceLoader.exists(shader_path):
		material.shader = load(shader_path)

	var uniforms := _args_dict(args, "uniforms")
	for uniform_name in uniforms.keys():
		material.set_shader_parameter(uniform_name, HerenCoordsScript.deserialize_value(uniforms[uniform_name]))

	# B9 fix heredado de v3: asignar a TODOS los tipos de nodos.
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
		"has_shader": shader_path != "",
		"material_assigned": true,
	}


func handle_uniform(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var node_path: Variant = args.get("node_path", "")
	var uniform_name: String = str(args.get("uniform_name", ""))
	if node_path == "" or uniform_name == "":
		return {"ok": false, "error": "node_path and uniform_name required"}
	var node: Node = _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}

	var material: ShaderMaterial = _find_shader_material(node)
	if material == null:
		return {"ok": false, "error": "no_shader_material", "message": "no ShaderMaterial found on node"}

	# FAIL-FAST (2026-09-03): set_shader_parameter SILENCIOSAMENTE descarta
	# el valor si el shader no declara ese uniform. Verificar leyendo de
	# vuelta Y listando los uniforms reales del shader para hint diagnóstico.
	var value: Variant = HerenCoordsScript.deserialize_value(args.get("value"))
	material.set_shader_parameter(uniform_name, value)
	var readback: Variant = material.get_shader_parameter(uniform_name)
	var shader := material.shader
	var declared: Array = []
	if shader != null:
		for u in shader.get_shader_uniform_list():
			declared.append(u.get("name", ""))
	if not _shader_value_match(readback, value):
		return {
			"ok": false,
			"error": "uniform_not_set: el shader no acepta '%s'" % uniform_name,
			"hint": "uniforms declarados en el shader: %s" % str(declared),
		}
	return {
		"ok": true,
		"uniform": uniform_name,
		"node_path": _node_path_relative(node, root),
		"verified": true,
	}


## Comparador laxo para set/get_shader_parameter (tolera float→int, etc).
func _shader_value_match(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		# Tolerar float↔int si numéricamente iguales.
		if (a is float or a is int) and (b is float or b is int):
			return float(a) == float(b)
		return false
	if a is Vector2 and b is Vector2:
		return a.is_equal_approx(b)
	if a is Vector3 and b is Vector3:
		return a.is_equal_approx(b)
	if a is Color and b is Color:
		return a.is_equal_approx(b)
	return a == b


## Busca el primer ShaderMaterial en el nodo (material / override / overlay /
## superficie). Compartido por uniform, inspect y apply.
func _find_shader_material(node: Node) -> ShaderMaterial:
	if "material" in node and node.material is ShaderMaterial:
		return node.material
	if "material_override" in node and node.material_override is ShaderMaterial:
		return node.material_override
	if "material_overlay" in node and node.material_overlay is ShaderMaterial:
		return node.material_overlay
	if node is MeshInstance3D:
		for i in range((node as MeshInstance3D).get_surface_override_material_count()):
			var surf_mat = (node as MeshInstance3D).get_surface_override_material(i)
			if surf_mat is ShaderMaterial:
				return surf_mat
	return null


## Cascada de asignación de material a nodo (B9): cubre CanvasItem,
## GeometryInstance3D (override/overlay) y MeshInstance3D (superficie).
func _assign_material(node: Node, material: ShaderMaterial) -> bool:
	if node.has_method("set_material"):
		node.set_material(material)
		return true
	elif "material" in node:
		node.material = material
		return true
	if node is MeshInstance3D:
		node.set_surface_override_material(0, material)
		return true
	if node.has_method("set_material_override"):
		node.set_material_override(material)
		return true
	elif "material_override" in node:
		node.material_override = material
		return true
	if node.has_method("set_material_overlay"):
		node.set_material_overlay(material)
		return true
	elif "material_overlay" in node:
		node.material_overlay = material
		return true
	return false


## Convierte get_shader_uniform_list() a JSON serializable con nombres
## legibles. Cada dict: {name, type, default, hint, range}.
func _shader_uniforms_to_json(shader: Shader) -> Array:
	var out: Array = []
	for u in shader.get_shader_uniform_list():
		var d: Dictionary = {}
		for key in ["name", "type", "default_value", "hint", "hint_range", "group", "subgroup"]:
			if key in u:
				d[key] = u[key]
		var entry := {
			"name": str(d.get("name", "")),
			"type": _uniform_type_str(int(d.get("type", 0))),
			"hint": _hint_str(int(d.get("hint", 0))),
		}
		if d.has("default_value"):
			entry["default"] = d["default_value"]
		if d.has("hint_range") and d["hint_range"] is Vector3:
			var r: Vector3 = d["hint_range"]
			entry["range"] = {"min": r.x, "max": r.y, "step": r.z}
		out.append(entry)
	return out


## RenderingDevice.DataType → string legible.
func _uniform_type_str(t: int) -> String:
	var names := {
		1: "bool", 2: "bvec2", 3: "bvec3", 4: "bvec4",
		5: "int", 6: "ivec2", 7: "ivec3", 8: "ivec4",
		9: "uint", 10: "uvec2", 11: "uvec3", 12: "uvec4",
		13: "float", 14: "vec2", 15: "vec3", 16: "vec4",
		17: "mat2", 18: "mat3", 19: "mat4",
		20: "sampler2D", 21: "samplerCube", 22: "samplerExternal", 23: "sampler3D",
	}
	return str(names.get(t, "type_%d" % t))


## RenderingDevice.ShaderUniformHint → string legible.
func _hint_str(h: int) -> String:
	var names := {
		1: "range", 2: "default_white", 3: "default_black", 4: "albedo",
		5: "normal", 6: "anisotropy", 7: "screen_texture", 8: "depth_texture",
		9: "normal_roughness_texture", 10: "default_black_albedo",
		11: "default_normal", 12: "default_anisotropy", 13: "default_gray",
		15: "max", 16: "compare", 17: "instance_id", 18: "default_transparent",
	}
	return str(names.get(h, "none"))


func _mode_to_str(mode: int) -> String:
	var names := {0: "spatial", 1: "canvas_item", 2: "particles", 3: "sky", 4: "fog", 5: "texture_blit"}
	return str(names.get(mode, "mode_%d" % mode))


func _parse_shader_type(content: String) -> String:
	var m := RegEx.create_from_string("shader_type\\s+([a-z_0-9]+)")
	var res := m.search(content)
	if res:
		return res.get_string(1)
	return "unknown"


## Issues estructurales detectables sin Shader.get_errors() (inexistente en
## Godot 4.7): shader_type presente, función principal según el modo, y llaves
## balanceadas. La compilación real la hace Godot al usar el shader; esto da
## señales tempranas SIN crashear.
func _shader_structural_issues(sh: Shader, code: String) -> Array:
	var issues: Array = []
	if _parse_shader_type(code) == "unknown":
		issues.append("missing or invalid shader_type")
	var mode := sh.get_mode()
	var required: String
	match mode:
		2: required = "start()"
		3: required = "sky()"
		_:
			required = "fragment()"
	if not code.contains(required):
		issues.append("missing main function: " + required)
	# Llaves balanceadas (heurística simple de parseo).
	var open := 0
	for ch in code:
		if ch == "{":
			open += 1
		elif ch == "}":
			open -= 1
			if open < 0:
				issues.append("unbalanced braces: extra }")
				break
	if open > 0:
		issues.append("unbalanced braces: missing }")
	return issues


## ¿El código declara uniforms? (señal indirecta de compilación fallida:
## si declara uniforms pero get_shader_uniform_list() sale vacío → error).
func _shader_declares_uniforms(code: String) -> bool:
	return code.contains("uniform")
