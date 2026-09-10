@tool
extends Node

# Heren MCP v4 - Tool dispatcher.
# Routes `tools/call` tool names to registered handler nodes. Each handler
# exposes a `handle_<tool>(args: Dictionary) -> Dictionary` method.
#
# Fase 3 (2026-09-03): routing DECLARATIVO. La tabla `_routes.gd::ROUTES` es la
# fuente de verdad (tool/action → handler_method). Renames rompen tests,
# no producción. Si una tool/action NO está en la tabla, fallback al routing
# convencional (handle_<action>) para compatibilidad hacia atrás; herramientas
# nuevas DEBEN declararse en _routes.gd.

const HerenRoutes := preload("_routes.gd")

var _handlers: Dictionary = {}


func register_handler(prefix: String, handler: Node) -> void:
	_handlers[prefix] = handler


func execute(tool_name: String, args: Dictionary) -> Dictionary:
	var prefix: String
	var sub_action: String
	var slash_idx := tool_name.find("/")
	if slash_idx < 0:
		# Formato corto: "scene" (legacy — action viene en args.action).
		prefix = tool_name
		sub_action = ""
	else:
		prefix = tool_name.substr(0, slash_idx)
		sub_action = tool_name.substr(slash_idx + 1)
	var handler: Node = _handlers.get(prefix, null)
	if handler == null:
		return {"ok": false, "error": "no handler for prefix: " + prefix}

	# Resolver método en 3 niveles (con tabla declarativa primero):
	#   1. Tabla explícita: "{prefix}/{action}" → method (si está registrado).
	#   2. Convención legacy: handle_<action> (compat con planes existentes).
	#   3. Strip prefix: "scene/create" → handle_create (último fallback).
	var method_name := ""
	var action := sub_action if sub_action != "" else str(args.get("action", ""))
	if action != "":
		# Nivel 1: tabla declarativa.
		method_name = HerenRoutes.lookup(prefix, action)
		# Nivel 2: convención handle_<action>.
		if method_name == "" or not handler.has_method(method_name):
			method_name = "handle_" + action
	# Nivel 3: strip prefix (caso tool_name="scene/create", sub_action="create").
	if method_name == "" or not handler.has_method(method_name):
		if sub_action != "":
			method_name = "handle_" + sub_action
	if method_name == "" or not handler.has_method(method_name):
		return {"ok": false, "error": "tool method not found: " + prefix + "/" + action}

	var result = handler.call(method_name, args)
	if result is Dictionary:
		return result
	# Soporte handlers coroutine (contienen `await`):
	# completar la coroutine antes de devolver. GDScriptFunctionState no es un
	# tipo usable en `is` (Godot 4) → detectar por get_class(). Requiere que el
	# caller use `await`.
	if result != null and result.get_class() == "GDScriptFunctionState":
		result = await result
		if result is Dictionary:
			return result
	return {"ok": false, "error": "invalid tool result from: " + tool_name}
