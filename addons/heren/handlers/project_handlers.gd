@tool
extends "res://addons/heren/handlers/heren_handler.gd"
# Heren MCP v4 - Project handlers (Fase 2).
# Configuración del proyecto vía ProjectSettings + InputMap (ADR-002):
# el editor vivo aplica y persiste los cambios en project.godot.
#
# Actions (heredadas de v3 project_tool.py, adaptadas a editor vivo):
#   setting      -> get/set ProjectSettings (persiste con ProjectSettings.save)
#   autoload     -> add (script_path) / list / remove_autoload
#   input_map    -> add/remove/list/set_event (InputEvent desde JSON)
#   shader_global-> RenderingServer.global_shader_parameter (runtime)
#
# NO portado de v3: create (crear proyecto desde 0), setup_daemon (obsoleto —
# v4 es EditorPlugin, no daemon; el plugin viaja con el proyecto).

const HerenCoordsScript := preload("coords.gd")



func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_editor_interface()


## Accepts a Dictionary directly, or a JSON string.
func _args_dict(args: Dictionary, key: String) -> Dictionary:
	var raw: Variant = args.get(key, {})
	if raw is Dictionary:
		return raw
	if raw is String:
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
	return {}


func _serialize_setting(value: Variant) -> Variant:
	if value is Array:
		var out: Array = []
		for item in value:
			out.append(_serialize_setting(item))
		return out
	if value is Dictionary:
		var out := {}
		for k in value.keys():
			out[k] = _serialize_setting(value[k])
		return out
	return HerenCoordsScript.serialize_value(value, true)


# ---------------------------------------------------------------- handlers

func handle_setting(args: Dictionary) -> Dictionary:
	var setting_name: String = str(args.get("setting_name", ""))
	var op: String = str(args.get("op", "get"))

	# ---- SET / GET (backward-compatible) ------------------------------
	if op == "set" or (op == "get" and args.has("value") and args.get("value") != null):
		if setting_name == "":
			return {"ok": false, "error": "setting_name required"}
		var raw: Variant = args.get("value")
		# IMPORTANT: path strings (res://...) stay as PLAIN strings.
		# deserialize_value() would load() them into a Resource, and
		# ProjectSettings.save() serializes a Resource as
		# Resource("uid://X", "res://...") using a synthetic uid that may
		# NOT exist in uid_cache (files created by MCP have no .uid yet) ->
		# Godot rejects the whole project.godot and the project won't open.
		var value: Variant = raw
		if raw is String:
			var str_value := raw as String
			if not str_value.begins_with("res://") and not str_value.begins_with("user://"):
				value = HerenCoordsScript.deserialize_value(raw)
		else:
			value = HerenCoordsScript.deserialize_value(raw)
		ProjectSettings.set_setting(setting_name, value)
		var err := ProjectSettings.save()
		if err != OK:
			return {"ok": false, "error": "save_failed: " + error_string(err)}
		var applied: bool = _apply_runtime_setting(setting_name, value)
		return {
			"ok": true,
			"setting": setting_name,
			"value": _serialize_setting(ProjectSettings.get_setting(setting_name)),
			"op": "set",
			"restart_required": _setting_requires_restart(setting_name) and not applied,
			"applied_runtime": applied,
		}

	if op == "get" or op == "set":
		if not ProjectSettings.has_setting(setting_name):
			return {"ok": false, "error": "setting_not_found: " + setting_name}
		return {
			"ok": true,
			"setting": setting_name,
			"value": _serialize_setting(ProjectSettings.get_setting(setting_name)),
			"op": "get",
			"type": _variant_type_name(ProjectSettings.get_setting(setting_name)),
			# P0.6 (2026-09-03): GET NO requiere restart (solo SET).
			# Antes siempre decía true para application/run/, etc.
			"restart_required": false,
		}

	# ---- LIST ---------------------------------------------------------
	if op == "list":
		var prefix: String = str(args.get("prefix", ""))
		var out: Array = []
		for prop in ProjectSettings.get_property_list():
			var prop_name: String = str(prop.name)
			if prop_name == "":
				continue
			if prefix != "" and not prop_name.begins_with(prefix):
				continue
			var val: Variant = ProjectSettings.get_setting(prop_name)
			out.append({
				"setting": prop_name,
				"value": _serialize_setting(val),
				"type": _variant_type_name(val),
				"restart_required": _setting_requires_restart(prop_name),
			})
		return {"ok": true, "settings": out, "count": out.size()}

	# ---- DELETE -------------------------------------------------------
	if op == "delete":
		if setting_name == "":
			return {"ok": false, "error": "setting_name required"}
		if not ProjectSettings.has_setting(setting_name):
			return {"ok": false, "error": "setting_not_found: " + setting_name}
		ProjectSettings.set_setting(setting_name, null)
		var err := ProjectSettings.save()
		if err != OK:
			return {"ok": false, "error": "save_failed: " + error_string(err)}
		return {"ok": true, "setting": setting_name, "op": "deleted"}

	# ---- SET_MULTI ----------------------------------------------------
	if op == "set_multi":
		var values: Dictionary = args.get("values", {})
		if values.is_empty():
			return {"ok": false, "error": "values required (dict setting->value)"}
		var results: Array = []
		for k in values.keys():
			var key: String = str(k)
			var raw2: Variant = values[k]
			var v: Variant = raw2
			if raw2 is String:
				var s2 := raw2 as String
				if not s2.begins_with("res://") and not s2.begins_with("user://"):
					v = HerenCoordsScript.deserialize_value(raw2)
			else:
				v = HerenCoordsScript.deserialize_value(raw2)
			ProjectSettings.set_setting(key, v)
			var applied2: bool = _apply_runtime_setting(key, v)
			results.append({
				"setting": key,
				"value": _serialize_setting(ProjectSettings.get_setting(key)),
				"restart_required": _setting_requires_restart(key) and not applied2,
				"applied_runtime": applied2,
			})
		var err := ProjectSettings.save()
		if err != OK:
			return {"ok": false, "error": "save_failed: " + error_string(err)}
		return {"ok": true, "results": results, "count": results.size(), "op": "set_multi"}

	return {"ok": false, "error": "unknown_op: " + op}


## Settings que SOLO se leen al arrancar (docs Godot: "many project settings
## are only read once at startup"). No hay API pública de restart_if_changed,
## así que se detectan por prefijos conocidos.
func _setting_requires_restart(setting_name: String) -> bool:
	var prefixes: Array[String] = [
		"display/",
		"rendering/",
		"audio/driver",
		"application/config/",
		"application/boot/",
		"application/run/",
		"input/",
		"physics/",
		"layer_names/",
		"network/",
	]
	for p in prefixes:
		if setting_name.begins_with(p):
			return true
	return false


## Aplica en runtime los settings que tienen equivalente vivo (evita recarga).
func _apply_runtime_setting(setting_name: String, value: Variant) -> bool:
	match setting_name:
		"display/window/size/viewport_width":
			DisplayServer.window_set_size(Vector2i(int(value), DisplayServer.window_get_size().y))
			return true
		"display/window/size/viewport_height":
			DisplayServer.window_set_size(Vector2i(DisplayServer.window_get_size().x, int(value)))
			return true
		"application/run/max_fps":
			Engine.max_fps = int(value)
			return true
	return false


func _variant_type_name(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL: return "nil"
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "String"
		TYPE_VECTOR2: return "Vector2"
		TYPE_VECTOR3: return "Vector3"
		TYPE_COLOR: return "Color"
		TYPE_ARRAY: return "Array"
		TYPE_DICTIONARY: return "Dictionary"
		TYPE_OBJECT: return "Object"
		_:
			return type_string(typeof(value))


func handle_autoload(args: Dictionary) -> Dictionary:
	var autoload_name: String = str(args.get("autoload_name", ""))
	var script_path: String = str(args.get("script_path", ""))

	# No name -> list all autoloads (via property_list; get_autoload_list
	# is unreliable through the parser in some 4.x builds).
	if autoload_name == "":
		var out: Array = []
		for prop in ProjectSettings.get_property_list():
			var prop_name: StringName = prop.name
			if not str(prop_name).begins_with("autoload/"):
				continue
			var value: Variant = ProjectSettings.get_setting(prop_name)
			if value == null or str(value) == "":
				continue
			out.append({
				"name": str(prop_name).trim_prefix("autoload/"),
				"path": str(value),
			})
		return {"ok": true, "autoloads": out, "count": out.size()}

	if script_path == "":
		return {"ok": false, "error": "script_path required"}

	ProjectSettings.set_setting("autoload/" + autoload_name, "*" + script_path)
	var err := ProjectSettings.save()
	if err != OK:
		return {"ok": false, "error": "save_failed: " + error_string(err)}
	return {"ok": true, "autoload": autoload_name, "path": script_path}


func handle_remove_autoload(args: Dictionary) -> Dictionary:
	var autoload_name: String = str(args.get("autoload_name", ""))
	if autoload_name == "":
		return {"ok": false, "error": "autoload_name required"}

	ProjectSettings.set_setting("autoload/" + autoload_name, null)
	var err := ProjectSettings.save()
	if err != OK:
		return {"ok": false, "error": "save_failed: " + error_string(err)}
	return {"ok": true, "removed": autoload_name}


func handle_input_map(args: Dictionary) -> Dictionary:
	var action_type: String = str(args.get("type", "list"))
	var action_name: String = str(args.get("action_name", ""))

	match action_type:
		"add":
			if action_name == "":
				return {"ok": false, "error": "action_name required"}
			if InputMap.has_action(action_name):
				return {"ok": true, "action": action_name, "op": "exists"}
			var deadzone: float = float(args.get("deadzone", 0.5))
			InputMap.add_action(action_name, deadzone)
			_persist_input_action(action_name)
			return {"ok": true, "action": action_name, "op": "added", "deadzone": deadzone}

		"remove":
			if action_name == "":
				return {"ok": false, "error": "action_name required"}
			if not InputMap.has_action(action_name):
				return {"ok": false, "error": "action_not_found: " + action_name}
			InputMap.erase_action(action_name)
			_persist_input_action(action_name)
			return {"ok": true, "action": action_name, "op": "removed"}

		"list":
			# P0.5 (2026-09-03): antes leía InputMap.get_actions() (runtime del
			# editor → solo acciones builtin spatial_editor). Ahora leemos
			# ProjectSettings.get_property_list() filtrado por "input/" → TODAS
			# las acciones del proyecto desde disco (move_forward, grab_left,
			# etc.) sin importar si el editor las cargó en InputMap.
			var include_ui: bool = bool(args.get("include_ui", false))
			var prefix: String = str(args.get("prefix", ""))
			var out: Array = []
			for prop in ProjectSettings.get_property_list():
				var pname: String = str(prop.name)
				if not pname.begins_with("input/"):
					continue
				var inp_action: String = pname.substr("input/".length())
				if inp_action == "":
					continue
				if not include_ui and inp_action.begins_with("ui_"):
					continue
				if prefix != "" and not inp_action.begins_with(prefix):
					continue
				out.append(_describe_input_action(inp_action))
			return {"ok": true, "actions": out, "count": out.size()}

		"get":
			if action_name == "":
				return {"ok": false, "error": "action_name required"}
			if not InputMap.has_action(action_name):
				return {"ok": false, "error": "action_not_found: " + action_name}
			return {"ok": true, "action": _describe_input_action(action_name)}

		"add_event":
			if action_name == "":
				return {"ok": false, "error": "action_name required"}
			var event_data := _args_dict(args, "event")
			var ev: Variant = _create_input_event(event_data)
			if not ev is InputEvent:
				return {"ok": false, "error": "unsupported_input_event: " + str(event_data.get("type", ""))}
			if not InputMap.has_action(action_name):
				InputMap.add_action(action_name)
			InputMap.action_add_event(action_name, ev)
			_persist_input_action(action_name)
			return {
				"ok": true,
				"action": action_name,
				"event": (ev as InputEvent).as_text(),
				"event_count": InputMap.action_get_events(action_name).size(),
			}

		"set_events":
			if action_name == "":
				return {"ok": false, "error": "action_name required"}
			var events_raw: Array = args.get("events", [])
			if events_raw.is_empty():
				return {"ok": false, "error": "events required (array)"}
			if not InputMap.has_action(action_name):
				InputMap.add_action(action_name)
			InputMap.action_erase_events(action_name)
			var added: Array = []
			for ed in events_raw:
				var ev: Variant = _create_input_event(ed if ed is Dictionary else {})
				if ev is InputEvent:
					InputMap.action_add_event(action_name, ev)
					added.append((ev as InputEvent).as_text())
			_persist_input_action(action_name)
			return {"ok": true, "action": action_name, "events": added, "event_count": added.size()}

		"remove_event":
			if action_name == "":
				return {"ok": false, "error": "action_name required"}
			if not InputMap.has_action(action_name):
				return {"ok": false, "error": "action_not_found: " + action_name}
			var ev_idx: int = int(args.get("index", -1))
			var events: Array[InputEvent] = InputMap.action_get_events(action_name)
			if ev_idx < 0 or ev_idx >= events.size():
				return {"ok": false, "error": "index_out_of_range: " + str(ev_idx) + " (count " + str(events.size()) + ")"}
			InputMap.action_erase_event(action_name, events[ev_idx])
			_persist_input_action(action_name)
			return {"ok": true, "action": action_name, "removed_index": ev_idx, "event_count": InputMap.action_get_events(action_name).size()}

		"set_deadzone":
			if action_name == "":
				return {"ok": false, "error": "action_name required"}
			if not InputMap.has_action(action_name):
				return {"ok": false, "error": "action_not_found: " + action_name}
			var dz: float = float(args.get("deadzone", 0.5))
			InputMap.action_set_deadzone(action_name, dz)
			_persist_input_action(action_name)
			return {"ok": true, "action": action_name, "deadzone": dz}

		# Backward-compat: set_event reemplaza TODOS los eventos con uno solo.
		"set_event":
			if action_name == "":
				return {"ok": false, "error": "action_name required"}
			var event_data := _args_dict(args, "event")
			var ev: Variant = _create_input_event(event_data)
			if not ev is InputEvent:
				return {"ok": false, "error": "unsupported_input_event: " + str(event_data.get("type", ""))}
			if not InputMap.has_action(action_name):
				InputMap.add_action(action_name)
			InputMap.action_erase_events(action_name)
			InputMap.action_add_event(action_name, ev)
			_persist_input_action(action_name)
			return {"ok": true, "action": action_name, "event": (ev as InputEvent).as_text()}

	return {"ok": false, "error": "unknown_type: " + action_type}


## Persistencia REAL: escribe el setting input/<action> en ProjectSettings con
## el formato que Godot espera en project.godot:
##   [input] action={"deadzone":0.5,"events":[Object(InputEventKey,...)]}
## Sin esto, InputMap.add_action() solo vive en memoria y se pierde al recargar.
func _persist_input_action(action_name: String) -> void:
	if not InputMap.has_action(action_name):
		ProjectSettings.set_setting("input/" + action_name, null)
		ProjectSettings.save()
		return
	var events: Array[InputEvent] = InputMap.action_get_events(action_name)
	ProjectSettings.set_setting("input/" + action_name, {
		"deadzone": InputMap.action_get_deadzone(action_name),
		"events": events,
	})
	ProjectSettings.save()


func _describe_input_action(action_name: String) -> Dictionary:
	var events: Array[InputEvent] = InputMap.action_get_events(action_name)
	var event_list: Array = []
	for ev in events:
		event_list.append(_describe_input_event(ev))
	return {
		"name": action_name,
		"deadzone": InputMap.action_get_deadzone(action_name),
		"event_count": events.size(),
		"events": event_list,
	}


func _describe_input_event(ev: InputEvent) -> Dictionary:
	var out := {"type": ev.get_class(), "as_text": ev.as_text()}
	if ev is InputEventKey:
		var k := ev as InputEventKey
		out["keycode"] = k.keycode
		out["physical_keycode"] = k.physical_keycode
		out["modifiers"] = {
			"ctrl": k.ctrl_pressed,
			"shift": k.shift_pressed,
			"alt": k.alt_pressed,
			"meta": k.meta_pressed,
		}
	elif ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		out["button_index"] = mb.button_index
		out["modifiers"] = {
			"ctrl": mb.ctrl_pressed,
			"shift": mb.shift_pressed,
			"alt": mb.alt_pressed,
			"meta": mb.meta_pressed,
		}
	elif ev is InputEventJoypadButton:
		var jb := ev as InputEventJoypadButton
		out["button_index"] = jb.button_index
		out["device"] = jb.device
	elif ev is InputEventJoypadMotion:
		var jm := ev as InputEventJoypadMotion
		out["axis"] = jm.axis
		out["axis_value"] = jm.axis_value
		out["device"] = jm.device
	return out


func handle_shader_global(args: Dictionary) -> Dictionary:
	var global_name: String = str(args.get("global_name", ""))
	if global_name == "":
		return {"ok": false, "error": "global_name required"}

	var value: Variant = HerenCoordsScript.deserialize_value(args.get("value", 0.0))
	# Runtime only (RenderingServer); does not persist to project.godot.
	if RenderingServer.global_shader_parameter_get(global_name) == null:
		RenderingServer.global_shader_parameter_add(global_name, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, value)
	else:
		RenderingServer.global_shader_parameter_set(global_name, value)

	return {"ok": true, "global": global_name, "value": HerenCoordsScript.serialize_value(value), "runtime_only": true}


func _create_input_event(data: Dictionary) -> Variant:
	var type_name: String = str(data.get("type", "InputEventKey"))
	match type_name:
		"InputEventKey":
			var ev := InputEventKey.new()
			# keycode puede venir como int (KEY_W) o nombre ("W", "KEY_W", "space").
			var keycode_raw: Variant = data.get("keycode", 0)
			if keycode_raw is String:
				ev.keycode = _keycode_from_name(str(keycode_raw))
			else:
				ev.keycode = int(keycode_raw)
			var phys_raw: Variant = data.get("physical_keycode", 0)
			if phys_raw is String:
				ev.physical_keycode = _keycode_from_name(str(phys_raw))
			else:
				ev.physical_keycode = int(phys_raw)
			ev.ctrl_pressed = bool(data.get("ctrl", false))
			ev.shift_pressed = bool(data.get("shift", false))
			ev.alt_pressed = bool(data.get("alt", false))
			ev.meta_pressed = bool(data.get("meta", false))
			return ev
		"InputEventMouseButton":
			var ev := InputEventMouseButton.new()
			ev.button_index = int(data.get("button_index", MOUSE_BUTTON_LEFT))
			ev.ctrl_pressed = bool(data.get("ctrl", false))
			ev.shift_pressed = bool(data.get("shift", false))
			ev.alt_pressed = bool(data.get("alt", false))
			return ev
		"InputEventMouseMotion":
			var ev := InputEventMouseMotion.new()
			ev.ctrl_pressed = bool(data.get("ctrl", false))
			ev.shift_pressed = bool(data.get("shift", false))
			ev.alt_pressed = bool(data.get("alt", false))
			return ev
		"InputEventJoypadButton":
			var ev := InputEventJoypadButton.new()
			ev.button_index = int(data.get("button_index", 0))
			ev.device = int(data.get("device", -1))
			return ev
		"InputEventJoypadMotion":
			var ev := InputEventJoypadMotion.new()
			ev.axis = int(data.get("axis", 0))
			ev.axis_value = float(data.get("axis_value", 1.0))
			ev.device = int(data.get("device", -1))
			return ev
	return null


## Convierte "KEY_W"/"W"/"space" -> Key enum (KEY_W, KEY_SPACE).
## Key::from_string no es estático en GDScript; se usa OS.find_keycode_from_string
## (acepta "W", "Space", "KEY_W" con trim) + fallback al char.
func _keycode_from_name(name: String) -> int:
	var n := name.trim_prefix("KEY_").trim_prefix("key_")
	var code := OS.find_keycode_from_string(n)
	if code != 0:
		return code
	if n.length() == 1:
		return n.unicode_at(0)
	return 0
