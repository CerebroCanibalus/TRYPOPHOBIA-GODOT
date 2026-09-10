@tool
extends "res://addons/heren/handlers/heren_handler.gd"
# Heren MCP v4.5 - Debug handlers.
# Control del editor real (ADR-002) + depurador real (EditorDebuggerSession
# vía heren_debugger_plugin.gd, registrado con add_debugger_plugin()).
#
# Actions:
#   summary             -> snapshot completo: editor + plugin + game + errors + breakpoints + profiler + console
#   status              -> sesiones del depurador (active/breaked/debuggable),
#                          is_playing, breakpoints, profiler state
#   breakpoint          -> op=set|clear|list|clear_all (path, line, enabled)
#   control             -> op=pause|continue|step_over|step_into
#   stack               -> rastreo de pila cuando el juego está breaked
#   vars                -> variables del frame (coroutine: pide y espera)
#   profiler            -> op=start|stop|status|get|clear (CPU profiler)
#   run_scene           -> EditorInterface.play_main_scene / play_custom_scene
#   stop_scene          -> EditorInterface.stop_playing_scene
#   is_playing          -> EditorInterface.is_playing_scene
#   get_editor_errors   -> errores de runtime capturados del debugger (con stack)
#
# Limitación documentada (verificado contra source Godot 4.7, 2026-08-07):
#   - El stack/vars/errores del juego pausado NO son accesibles vía la API
#     pública de EditorDebuggerPlugin._capture (los mensajes sin ":" como
#     stack_dump/error los consume el ScriptEditorDebugger integrado primero;
#     sed.cpp _parse_message). Se resuelve conectando al signal `debug_data`
#     del ScriptEditorDebugger default (tab 0 del dock Debugger).
#   - La evaluación de expresiones (evaluate) devuelve evaluation_return al
#     integrado; no capturable → no expuesta.

var _dbg_plugin: EditorDebuggerPlugin


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func set_debugger_plugin(plugin: EditorDebuggerPlugin) -> void:
	_dbg_plugin = plugin
	if _dbg_plugin:
		_dbg_plugin.ensure_hooked()


func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_editor_interface()


# ---------------------------------------------------------------- handlers

func handle_summary(args: Dictionary) -> Dictionary:
	# Snapshot completo del estado de debug en una sola llamada.
	var result := {"ok": true}
	
	# --- Editor state ---
	var editor := {}
	var ei = _editor_interface()
	if ei:
		var current_scene = ei.get_edited_scene_root()
		if current_scene:
			editor["scene_open"] = current_scene.scene_file_path
			editor["scene_name"] = current_scene.name
		else:
			editor["scene_open"] = null
		
		# Nodos seleccionados en el editor
		var selected: Array = []
		var selection = ei.get_selection()
		if selection:
			for node in selection.get_selected_nodes():
				selected.append(node.name)
		editor["selected_nodes"] = selected
	else:
		editor = {"error": "no editor interface"}
	result["editor"] = editor
	
	# --- Plugin state ---
	result["plugin"] = {"connected": _editor_plugin != null}
	
	# --- Game state ---
	var game := {}
	if ei:
		game["is_playing"] = ei.is_playing_scene()
		game["is_paused"] = false  # Simplificado por ahora
	else:
		game["is_playing"] = false
		game["is_paused"] = false
	
	if _dbg_plugin:
		_dbg_plugin.ensure_hooked()
		game["is_breaked"] = _dbg_plugin.stack_breaked
		
		# Breakpoint hit info
		if _dbg_plugin.stack_breaked and _dbg_plugin.last_stack.size() > 0:
			var top_frame = _dbg_plugin.last_stack[0]
			game["breakpoint_hit"] = {
				"file": top_frame.get("file", ""),
				"line": top_frame.get("line", 0),
				"function": top_frame.get("function", ""),
			}
		else:
			game["breakpoint_hit"] = null
		
		game["fps"] = Engine.get_frames_per_second() if ei.is_playing_scene() else 0
		game["received_msgs"] = _dbg_plugin.received_msgs
	else:
		game["is_breaked"] = false
		game["breakpoint_hit"] = null
		game["fps"] = 0
	result["game"] = game
	
	# --- Errors ---
	var errors := {}
	if _dbg_plugin:
		_dbg_plugin.refresh_errors_tree()
		errors["runtime"] = _dbg_plugin.last_errors
		errors["output_errors"] = _dbg_plugin.last_output_errors
		errors["tree"] = _dbg_plugin.last_errors_tree
		errors["count"] = _dbg_plugin.last_errors.size() + _dbg_plugin.last_output_errors.size() + _dbg_plugin.last_errors_tree.size()
	else:
		errors = {"runtime": [], "output_errors": [], "tree": [], "count": 0}
	result["errors"] = errors
	
	# --- Breakpoints ---
	if _dbg_plugin:
		result["breakpoints"] = _dbg_plugin.list_breakpoints()
	else:
		result["breakpoints"] = []
	
	# --- Profiler ---
	var profiler := {}
	if _dbg_plugin:
		profiler["running"] = _dbg_plugin.profiler_running
		profiler["frames_collected"] = _dbg_plugin.profiler_frames.size()
	else:
		profiler["running"] = false
		profiler["frames_collected"] = 0
	result["profiler"] = profiler
	
	# --- Console output ---
	var console := {}
	if _dbg_plugin:
		console["last_lines"] = _dbg_plugin.last_output
		console["count"] = _dbg_plugin.last_output.size()
	else:
		console = {"last_lines": [], "count": 0}
	result["console"] = console
	
	return result


# ---------------------------------------------------------------- handlers


func handle_breakpoint(args: Dictionary) -> Dictionary:
	if _dbg_plugin == null:
		return {"ok": false, "error": "debugger plugin not registered"}
	var op := str(args.get("op", "set"))
	match op:
		"set":
			var path := str(args.get("path", ""))
			var line := int(args.get("line", -1))
			if path == "" or line < 0:
				return {"ok": false, "error": "path and line required"}
			var enabled: bool = bool(args.get("enabled", true))
			return _dbg_plugin.set_breakpoint(path, line, enabled)
		"clear":
			var path := str(args.get("path", ""))
			var line := int(args.get("line", -1))
			if path == "" or line < 0:
				return {"ok": false, "error": "path and line required"}
			return _dbg_plugin.set_breakpoint(path, line, false)
		"list":
			return {"ok": true, "breakpoints": _dbg_plugin.list_breakpoints()}
		"clear_all":
			return _dbg_plugin.clear_all_breakpoints()
		_:
			return {"ok": false, "error": "unknown op: " + op}


func handle_control(args: Dictionary) -> Dictionary:
	if _dbg_plugin == null:
		return {"ok": false, "error": "debugger plugin not registered"}
	var op := str(args.get("op", ""))
	if op == "":
		return {"ok": false, "error": "op required (pause|continue|step_over|step_into)"}
	return _dbg_plugin.send_control(op)


func handle_stack(args: Dictionary) -> Dictionary:
	if _dbg_plugin == null:
		return {"ok": false, "error": "debugger plugin not registered"}
	_dbg_plugin.ensure_hooked()
	if not _dbg_plugin.stack_breaked:
		return {"ok": false, "error": "not breaked — run the scene, pause or hit a breakpoint first"}
	if not _dbg_plugin.has_stack:
		return {"ok": false, "error": "no stack dump captured"}
	return {"ok": true, "frames": _dbg_plugin.last_stack}


func handle_vars(args: Dictionary) -> Dictionary:
	# Coroutine: pide las variables del frame al juego y espera la respuesta.
	if _dbg_plugin == null:
		return {"ok": false, "error": "debugger plugin not registered"}
	if not _dbg_plugin.stack_breaked:
		return {"ok": false, "error": "not breaked — pause or hit a breakpoint first"}
	var frame := int(args.get("frame", 0))
	# D3: esperar señal real con timeout 2s en lugar de sleep fijo 0.3s.
	# El plugin expone last_vars (Array) y vars_pending (bool); NO has_frame_vars.
	_dbg_plugin.request_frame_vars(frame)
	var waited := 0
	var max_wait := 20  # 2s a 100ms pasos
	while _dbg_plugin.vars_pending and waited < max_wait:
		await get_tree().create_timer(0.1).timeout
		waited += 1
	if _dbg_plugin.last_vars.is_empty():
		return {"ok": true, "frame": frame, "vars": [], "note": "vars timeout — waiting for debugger signal"}
	return {"ok": true, "frame": frame, "vars": _dbg_plugin.last_vars}


func handle_profiler(args: Dictionary) -> Dictionary:
	if _dbg_plugin == null:
		return {"ok": false, "error": "debugger plugin not registered"}
	var op := str(args.get("op", "status"))
	match op:
		"start":
			var max_funcs := int(args.get("max_functions", 128))
			var include_native: bool = bool(args.get("include_native", true))
			return _dbg_plugin.profiler_start(max_funcs, include_native)
		"stop":
			return _dbg_plugin.profiler_stop()
		"status":
			return {
				"ok": true,
				"profiler_running": _dbg_plugin.profiler_running,
				"frames_collected": _dbg_plugin.profiler_frames.size(),
			}
		"get":
			var limit := int(args.get("limit", 0))
			var frames: Array = _dbg_plugin.profiler_frames
			if limit > 0 and frames.size() > limit:
				frames = frames.slice(frames.size() - limit)
			return {"ok": true, "profiler_running": _dbg_plugin.profiler_running, "frames": frames}
		"clear":
			_dbg_plugin.profiler_frames.clear()
			return {"ok": true, "frames_collected": 0}
		_:
			return {"ok": false, "error": "unknown op: " + op}


func handle_run_scene(args: Dictionary) -> Dictionary:
	# op: play (default) | stop. Reemplaza run_scene + stop_scene.
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "no editor interface"}

	var op := str(args.get("op", "play"))
	if op == "stop":
		if not ei.is_playing_scene():
			return {"ok": true, "was_playing": false}
		ei.stop_playing_scene()
		return {"ok": true, "was_playing": true}

	# --- op=play (comportamiento original) ---
	# P0.4: limpiar buffer debug ANTES de play.
	if _dbg_plugin:
		_dbg_plugin.last_output.clear()
		_dbg_plugin.last_output_errors.clear()

	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path != "":
		if not ResourceLoader.exists(scene_path):
			return {"ok": false, "error": "scene_not_found: " + scene_path}
		ei.play_custom_scene(scene_path)
		await get_tree().process_frame
		var playing := ei.is_playing_scene()
		if not playing:
			return {
				"ok": false,
				"error": "play_failed: scene didn't start (1 frame after play_custom_scene)",
				"requested": scene_path,
				"hint": "revisa debug/output filter=error",
			}
		# 🚨 CRASH CHECK (2026-09-04): la escena puede arrancar y crashear
		# en _ready (error de runtime). Esperar 2 frames más y verificar.
		await get_tree().process_frame
		await get_tree().process_frame
		var diagnostic := _check_crash()
		if diagnostic.has("crash"):
			return diagnostic["crash"]
		var resp := {"ok": true, "running": scene_path, "custom": true, "verified": true}
		if diagnostic.has("runtime_errors"):
			resp["runtime_errors"] = diagnostic["runtime_errors"]
			resp["error_count"] = diagnostic["error_count"]
		return resp

	ei.play_main_scene()
	await get_tree().process_frame
	var playing_main := ei.is_playing_scene()
	if not playing_main:
		return {
			"ok": false,
			"error": "play_failed: main_scene didn't start",
			"hint": "revisa application/run/main_scene en project.godot",
		}
	await get_tree().process_frame
	await get_tree().process_frame
	var diagnostic_main := _check_crash()
	if diagnostic_main.has("crash"):
		return diagnostic_main["crash"]
	var resp_main := {"ok": true, "running": "main_scene", "custom": false, "verified": true}
	if diagnostic_main.has("runtime_errors"):
		resp_main["runtime_errors"] = diagnostic_main["runtime_errors"]
		resp_main["error_count"] = diagnostic_main["error_count"]
	return resp_main


func _check_crash() -> Dictionary:
	# Verifica errores durante el arranque de la escena.
	# Devuelve {} si no hay nada, o:
	#   {"crash": {ok:false, ...}} — el juego crasheó (breaked + error estructurado)
	#   {"runtime_errors": [...], "error_count": N} — errores de runtime (sin break)
	if _dbg_plugin == null:
		return {}
	var result := {}
	# Crash: el debugger está breaked con error estructurado (protocolo "error")
	if _dbg_plugin.stack_breaked and not _dbg_plugin.last_errors.is_empty():
		var top: Dictionary = _dbg_plugin.last_errors[0]
		result["crash"] = {
			"ok": false,
			"error": "scene_crashed_on_start",
			"file": top.get("file", ""),
			"line": top.get("line", 0),
			"function": top.get("function", ""),
			"message": str(top.get("error", "")) + ": " + str(top.get("descr", "")),
			"stack": top.get("stack", []),
			"hint": "usa debug/output filter=error para ver el error completo",
		}
	# Runtime errors: errores de output level==2 (C++ ERR_FAIL_COND, scripts, etc.)
	# que no causaron break pero SÍ aparecen en el log.
	if not _dbg_plugin.last_output_errors.is_empty():
		var count: int = _dbg_plugin.last_output_errors.size()
		var preview: Array = _dbg_plugin.last_output_errors.slice(0, 10)
		result["runtime_errors"] = preview
		result["error_count"] = count
	return result


func handle_output(args: Dictionary) -> Dictionary:
	# Output del juego + errores del editor. Reemplaza output + get_editor_errors.
	# filter: all (todo) | error (runtime + editor errors). Default: error.
	if _dbg_plugin == null:
		return {"ok": false, "error": "debugger plugin not registered"}
	_dbg_plugin.ensure_hooked()
	var filter := str(args.get("filter", "error"))
	var limit := int(args.get("limit", 100))
	var lines: Array = []
	if filter == "all":
		lines = _dbg_plugin.last_output.duplicate()
	else:
		lines = _dbg_plugin.last_output_errors.duplicate()
	# filter=error: añadir errores del panel Output del editor (parse errors,
	# script errors). Busca el RichTextLabel del dock Output y parsea líneas.
	# Godot 3: "E hh:mm:ss:mmm ..." | Godot 4: " ERROR: ..." (con icono+bold)
	if filter == "error":
		var root := _editor_interface().get_base_control()
		if root:
			var rtl := _find_output_rich_text_label(root)
			if rtl:
				var raw_text: String = rtl.get_parsed_text()
				for line in raw_text.split("\n"):
					var stripped := line.strip_edges()
					if stripped.begins_with("ERROR:") or stripped.begins_with("WARNING:") or line.begins_with("E "):
						lines.append({"text": stripped, "level": 2})
		# Añadir errores del tab Errors del Debugger (Tree widget) — fuente
		# robusta: Godot puebla ese Tree siempre, sin depender del hook timing.
		_dbg_plugin.refresh_errors_tree()
		for err in _dbg_plugin.last_errors_tree:
			var text := "%s %s" % [err.get("time", ""), err.get("title", "")]
			if err.get("file", "") != "":
				text += " @ %s:%s" % [err.get("file", ""), err.get("line", 0)]
			if err.get("error", "") != "":
				text += " | %s" % err.get("error", "")
			for frame in err.get("stack", []):
				text += "\n    " + str(frame)
			lines.append({"text": text, "level": 2})
	if lines.size() > limit:
		lines = lines.slice(lines.size() - limit)
	return {
		"ok": true,
		"filter": filter,
		"lines": lines,
		"count": lines.size(),
		"hook_ok": _dbg_plugin._hooked,
	}


# ---------------------------------------------------- helpers internos

func _find_output_rich_text_label(root: Node) -> RichTextLabel:
	# Busca el RichTextLabel del panel Output del editor.
	# En Godot 4.x el dock "Output" contiene un RichTextLabel hijo.
	# Estrategia: encontrar nodo "Output" → RichTextLabel hijo.
	var output_node := root.find_child("Output", true, false)
	if output_node:
		var rtl := output_node.find_child("RichTextLabel", true, false)
		if rtl is RichTextLabel:
			return rtl
	# Fallback: buscar RichTextLabels que contengan "Error" o "error" en su texto
	for child in root.get_children():
		if child is RichTextLabel and child.visible:
			var txt: String = child.get_parsed_text()
			if txt.contains("error") or txt.contains("Error"):
				return child
	return null
