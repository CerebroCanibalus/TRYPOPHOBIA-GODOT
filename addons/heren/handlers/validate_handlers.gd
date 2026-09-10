@tool
extends "res://addons/heren/handlers/heren_handler.gd"
# Heren MCP v4 - Validation handlers (Fase 2).
# Verifica integridad de escenas, scripts, nodos y recursos (ADR-002):
# el editor vivo ya tiene la escena en RAM; scripts y recursos se cargan
# con ResourceLoader (Godot falla si están corruptos).
#
# Actions (heredadas de v3 validate_tool.py, adaptadas a editor vivo):
#   scene    -> ResourceLoader.load PackedScene + verificar instanciable
#   script   -> ResourceLoader.load GDScript + verificar clase
#   node     -> resolver en escena viva + validar prop/script opcional
#   resource -> ResourceLoader.load + verificar es Resource

const HerenCoordsScript := preload("coords.gd")



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
	# Contexto de escena explícito: si se pide scene_path y no es la activa,
	# activarla. Así el contexto NO cambia impredeciblemente con la pestaña.
	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path != "":
		var active := ei.get_edited_scene_root()
		if active == null or active.scene_file_path != scene_path:
			if not ResourceLoader.exists(scene_path):
				return null
			ei.open_scene_from_path(scene_path)
	return ei.get_edited_scene_root()


func _resolve_node(root: Node, node_path: Variant) -> Node:
	if root == null or node_path == null:
		return null
	var normalized := HerenCoordsScript.normalize_node_path(node_path, root)
	if normalized == ".":
		return root
	if normalized == "":
		return null
	return root.get_node_or_null(NodePath(normalized))


# ---------------------------------------------------------------- handlers

func handle_scene(args: Dictionary) -> Dictionary:
	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path == "":
		return {"ok": false, "error": "scene_path required"}
	if not ResourceLoader.exists(scene_path):
		return {"ok": false, "error": "not_found: " + scene_path}

	var packed: Resource = load(scene_path)
	if packed == null or not packed is PackedScene:
		return {"ok": false, "error": "invalid_scene: " + scene_path}

	var instance: Node = (packed as PackedScene).instantiate()
	var valid: bool = instance != null
	if instance != null:
		instance.free()

	return {"ok": true, "valid": valid, "scene_path": scene_path, "root": packed.get_state().get_node_name(0)}


func handle_script(args: Dictionary) -> Dictionary:
	var script_path: String = str(args.get("script_path", ""))
	# W4-c: el shape unificado vive en el static `script_diagnostics` del
	# heren_handler base (DRY con resource/create_script/edit_script).
	# Wrappeamos el resultado en {ok: bool} para el contrato JSON-RPC.
	var d := script_diagnostics(script_path)
	if not d.get("valid", false):
		# d ya trae reload_err + parse_hints inline; el fix-loop baja
		# de 3 calls (validate→debug/output→fix) a 2.
		var r: Dictionary = {"ok": false, "valid": false}
		r.merge(d)
		# Si el diagnóstico vino sin parse_hints (p.ej. file vacío), deja
		# pista explícita de adónde mirar el mensaje crudo del parser.
		if not d.has("parse_hints") and d.has("reload_err"):
			r["hint"] = "sin parse_hints — el parser no expuso línea; abre debug/output filter=error para el mensaje exacto"
		return r
	return {
		"ok": true,
		"valid": true,
		"script_path": d.get("script_path", script_path),
		"can_instance": d.get("can_instance", false),
		"warnings": d.get("warnings", []),
	}


# Validación BULK con el compilador del editor: recorre *.gd bajo dir_path
# y reutiliza script_diagnostics (load + analyze + reload). Cada script roto
# adjunta parse_hints, así el fix-loop es de 1 llamada vs 3.
# NOTA: salta res://addons/heren/ (auto-reload del plugin vivo en ejecución
# es riesgoso); los handlers del plugin se validan con el grafo headless
# (session/diagnose) + run_tests.gd.
func handle_scripts(args: Dictionary) -> Dictionary:
	var dir_path: String = str(args.get("dir", "res://"))
	var broken: Array = []
	var with_warnings: Array = []
	var checked: int = _check_scripts_dir(dir_path, broken, with_warnings)
	return {
		"ok": broken.is_empty(),
		"dir": dir_path,
		"checked": checked,
		"broken_count": broken.size(),
		"broken": broken,
		"warnings_count": with_warnings.size(),
		"warnings": with_warnings,
		"hint": "los parse_hints de cada entry apuntan al problema; corrige con resource/edit_script o resource/update_script" if not broken.is_empty() else "",
	}


func _check_scripts_dir(dir_path: String, broken: Array, with_warnings: Array) -> int:
	if dir_path.begins_with("res://addons/heren"):
		return 0
	var da := DirAccess.open(dir_path)
	if da == null:
		return 0
	var count := 0
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if da.current_is_dir():
			if not f.begins_with("."):
				count += _check_scripts_dir(dir_path.path_join(f), broken, with_warnings)
		elif f.ends_with(".gd"):
			count += 1
			var path := dir_path.path_join(f)
			# script_diagnostics es estático y puro: load + analyze + reload.
			# No tocamos el GDScript cacheado de antes; el helper refresca source.
			var d: Dictionary = script_diagnostics(path)
			if not d.get("valid", false):
				var entry: Dictionary = {
					"path": path,
					"reload_err": d.get("reload_err", -1),
					"error": d.get("error", ""),
					"parse_hints": d.get("parse_hints", []),
				}
				broken.append(entry)
			elif d.get("warnings", []).size() > 0:
				with_warnings.append({
					"path": path,
					"warnings": d.get("warnings", []),
				})
		f = da.get_next()
	return count


func handle_node(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var node_path: Variant = args.get("node_path", "")
	if node_path == "":
		return {"ok": false, "error": "node_path required"}
	var node: Node = _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}

	var issues: Array = []
	var script: Script = node.get_script() as Script
	if script != null and not script.can_instantiate():
		issues.append("script_cannot_instantiate")

	return {
		"ok": true,
		"valid": issues.is_empty(),
		"node_path": node.get_name(),
		"type": node.get_class(),
		"issues": issues,
		"has_script": script != null,
	}


func handle_resource(args: Dictionary) -> Dictionary:
	var resource_path: String = str(args.get("resource_path", ""))
	if resource_path == "":
		return {"ok": false, "error": "resource_path required"}
	if not ResourceLoader.exists(resource_path):
		return {"ok": false, "error": "not_found: " + resource_path}

	var res: Resource = load(resource_path)
	if res == null:
		return {"ok": false, "error": "invalid_resource: " + resource_path}

	return {"ok": true, "valid": true, "resource_path": resource_path, "resource_class": res.get_class()}
