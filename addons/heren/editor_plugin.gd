@tool
extends EditorPlugin

# Heren MCP v4 - EditorPlugin core.
# Lifecycle: creates the WS client + dispatcher, wires signals, exposes the
# editor interface to handlers. The plugin is the WS CLIENT (ADR-003); the
# FlojoMCP server connects back to Godot operations.

const WsClientScript := preload("ws_client.gd")
const DispatcherScript := preload("dispatcher.gd")
const UndoRedoWrapperScript := preload("undo_redo_wrapper.gd")
const SceneHandlersScript := preload("handlers/scene_handlers.gd")
const NodeHandlersScript := preload("handlers/node_handlers.gd")
const ResourceHandlersScript := preload("handlers/resource_handlers.gd")
const ProjectHandlersScript := preload("handlers/project_handlers.gd")
const SignalHandlersScript := preload("handlers/signal_handlers.gd")
const ValidateHandlersScript := preload("handlers/validate_handlers.gd")
const DebugHandlersScript := preload("handlers/debug_handlers.gd")
const HerenDebuggerPluginScript := preload("heren_debugger_plugin.gd")
const ShaderHandlersScript := preload("handlers/shader_handlers.gd")
const AnimationHandlersScript := preload("handlers/animation_handlers.gd")
const SkeletonHandlersScript := preload("handlers/skeleton_handlers.gd")
const TileMapHandlersScript := preload("handlers/tilemap_handlers.gd")
const VisualHandlersScript := preload("handlers/visual_handlers.gd")
const UiHandlersScript := preload("handlers/ui_handlers.gd")

var _ws_client: Node
var _dispatcher: Node
var _undo_redo: Node
var _scene_handlers: Node
var _node_handlers: Node
var _resource_handlers: Node
var _project_handlers: Node
var _signal_handlers: Node
var _validate_handlers: Node
var _debug_handlers: Node
var _dbg_plugin: EditorDebuggerPlugin
var _shader_handlers: Node
var _animation_handlers: Node
var _skeleton_handlers: Node
var _tilemap_handlers: Node
var _visual_handlers: Node
var _ui_handlers: Node

var _status_label: Label


func _enter_tree() -> void:
	# Undo/redo wrapper first - handlers depend on it.
	_undo_redo = UndoRedoWrapperScript.new()
	_undo_redo.name = "HerenUndoRedo"
	_undo_redo.set_editor_plugin(self)
	add_child(_undo_redo)

	# Scene handlers (register with dispatcher).
	_scene_handlers = SceneHandlersScript.new()
	_scene_handlers.name = "HerenSceneHandlers"
	_scene_handlers.set_editor_plugin(self)
	add_child(_scene_handlers)

	# Node handlers (register with dispatcher).
	_node_handlers = NodeHandlersScript.new()
	_node_handlers.name = "HerenNodeHandlers"
	_node_handlers.set_editor_plugin(self)
	add_child(_node_handlers)

	# Resource handlers (register with dispatcher).
	_resource_handlers = ResourceHandlersScript.new()
	_resource_handlers.name = "HerenResourceHandlers"
	_resource_handlers.set_editor_plugin(self)
	add_child(_resource_handlers)

	# Project handlers.
	_project_handlers = ProjectHandlersScript.new()
	_project_handlers.name = "HerenProjectHandlers"
	_project_handlers.set_editor_plugin(self)
	add_child(_project_handlers)

	# Signal handlers.
	_signal_handlers = SignalHandlersScript.new()
	_signal_handlers.name = "HerenSignalHandlers"
	_signal_handlers.set_editor_plugin(self)
	add_child(_signal_handlers)

	# Validate handlers.
	_validate_handlers = ValidateHandlersScript.new()
	_validate_handlers.name = "HerenValidateHandlers"
	_validate_handlers.set_editor_plugin(self)
	add_child(_validate_handlers)

	# Debug handlers.
	_debug_handlers = DebugHandlersScript.new()
	_debug_handlers.name = "HerenDebugHandlers"
	_debug_handlers.set_editor_plugin(self)
	add_child(_debug_handlers)

	# Plugin del depurador (EditorDebuggerPlugin v4.5): expone sesiones del
	# depurador (breakpoints, control, profiler) y captura stack/vars/errores
	# via el signal `debug_data` del ScriptEditorDebugger default (tab 0).
	_dbg_plugin = HerenDebuggerPluginScript.new()
	_dbg_plugin.setup(self)
	_debug_handlers.set_debugger_plugin(_dbg_plugin)
	add_debugger_plugin(_dbg_plugin)
	# 🚨 Hookear TEMPRANO (2026-09-04): si el hook se establece cuando el
	# agente llama debug (después del crash), los errores ya pasaron y
	# last_errors queda vacío. ensure_hooked() con retries 10×1s maneja
	# el caso de que el dock aún no esté montado.
	_dbg_plugin.ensure_hooked()

	# Shader handlers.
	_shader_handlers = ShaderHandlersScript.new()
	_shader_handlers.name = "HerenShaderHandlers"
	_shader_handlers.set_editor_plugin(self)
	add_child(_shader_handlers)

	# Animation + skeleton handlers (skeleton separado en Fase C2, hereda de animation).
	_animation_handlers = AnimationHandlersScript.new()
	_animation_handlers.name = "HerenAnimationHandlers"
	_animation_handlers.set_editor_plugin(self)
	add_child(_animation_handlers)

	_skeleton_handlers = SkeletonHandlersScript.new()
	_skeleton_handlers.name = "HerenSkeletonHandlers"
	_skeleton_handlers.set_editor_plugin(self)
	add_child(_skeleton_handlers)

	# TileMap handlers.
	_tilemap_handlers = TileMapHandlersScript.new()
	_tilemap_handlers.name = "HerenTileMapHandlers"
	_tilemap_handlers.set_editor_plugin(self)
	add_child(_tilemap_handlers)

	# Visual handlers (Fase 3 - visión).
	_visual_handlers = VisualHandlersScript.new()
	_visual_handlers.name = "HerenVisualHandlers"
	_visual_handlers.set_editor_plugin(self)
	add_child(_visual_handlers)

	# UI handlers (Fase UI-2 - tool ui + templates transversales).
	_ui_handlers = UiHandlersScript.new()
	_ui_handlers.name = "HerenUiHandlers"
	_ui_handlers.set_editor_plugin(self)
	add_child(_ui_handlers)

	# Dispatcher routes tool_invoke -> handler.
	_dispatcher = DispatcherScript.new()
	_dispatcher.name = "HerenDispatcher"
	add_child(_dispatcher)
	_dispatcher.register_handler("scene", _scene_handlers)
	_dispatcher.register_handler("node", _node_handlers)
	_dispatcher.register_handler("resource", _resource_handlers)
	_dispatcher.register_handler("project", _project_handlers)
	_dispatcher.register_handler("signal", _signal_handlers)
	_dispatcher.register_handler("validate", _validate_handlers)
	_dispatcher.register_handler("debug", _debug_handlers)
	_dispatcher.register_handler("shader", _shader_handlers)
	_dispatcher.register_handler("animation", _animation_handlers)
	_dispatcher.register_handler("skeleton", _skeleton_handlers)
	_dispatcher.register_handler("tilemap", _tilemap_handlers)
	_dispatcher.register_handler("visual", _visual_handlers)
	_dispatcher.register_handler("ui", _ui_handlers)

	# WS client connects to the FlojoMCP server.
	_ws_client = WsClientScript.new()
	_ws_client.name = "HerenWsClient"
	add_child(_ws_client)
	_ws_client.connected.connect(_on_connected)
	_ws_client.disconnected.connect(_on_disconnected)
	_ws_client.tool_invoke_received.connect(_on_tool_invoke)
	_ws_client.error_reported.connect(_on_error)

	_setup_status_indicator()
	_ws_client.connect_to_server()
	print("[HEREN] plugin entered tree, ws client connecting...")


func _exit_tree() -> void:
	if _ws_client:
		if _ws_client.connected.is_connected(_on_connected):
			_ws_client.connected.disconnect(_on_connected)
		if _ws_client.disconnected.is_connected(_on_disconnected):
			_ws_client.disconnected.disconnect(_on_disconnected)
		if _ws_client.tool_invoke_received.is_connected(_on_tool_invoke):
			_ws_client.tool_invoke_received.disconnect(_on_tool_invoke)
		if _ws_client.error_reported.is_connected(_on_error):
			_ws_client.error_reported.disconnect(_on_error)
		_ws_client.disconnect_from_server()
		_ws_client.queue_free()
		_ws_client = null

	if _dispatcher:
		_dispatcher.queue_free()
		_dispatcher = null
	if _visual_handlers:
		_visual_handlers.queue_free()
		_visual_handlers = null
	if _ui_handlers:
		_ui_handlers.queue_free()
		_ui_handlers = null
	if _tilemap_handlers:
		_tilemap_handlers.queue_free()
		_tilemap_handlers = null
	if _animation_handlers:
		_animation_handlers.queue_free()
		_animation_handlers = null
	if _skeleton_handlers:
		_skeleton_handlers.queue_free()
		_skeleton_handlers = null
	if _shader_handlers:
		_shader_handlers.queue_free()
		_shader_handlers = null
	if _debug_handlers:
		_debug_handlers.queue_free()
		_debug_handlers = null
	if _dbg_plugin:
		remove_debugger_plugin(_dbg_plugin)
		_dbg_plugin = null
	if _validate_handlers:
		_validate_handlers.queue_free()
		_validate_handlers = null
	if _signal_handlers:
		_signal_handlers.queue_free()
		_signal_handlers = null
	if _project_handlers:
		_project_handlers.queue_free()
		_project_handlers = null
	if _resource_handlers:
		_resource_handlers.queue_free()
		_resource_handlers = null
	if _node_handlers:
		_node_handlers.queue_free()
		_node_handlers = null
	if _scene_handlers:
		_scene_handlers.queue_free()
		_scene_handlers = null
	if _undo_redo:
		_undo_redo.queue_free()
		_undo_redo = null
	if _status_label:
		remove_control_from_container(CONTAINER_TOOLBAR, _status_label)
		_status_label.queue_free()
		_status_label = null


func get_editor_interface_wrapper() -> EditorInterface:
	return get_editor_interface()


func get_undo_redo_wrapper() -> Node:
	return _undo_redo


# ---------------------------------------------------------------- event push
# §13.6: selection_changed notifica al agente qué nodo seleccionó el usuario
# (rate-limited: máx 1 por segundo). NO envía imagen, solo el path (barato).

var _last_selection_sent: float = -1.0
const SELECTION_RATE_LIMIT := 1.0  # seconds


func _edit(object: Object) -> void:
	# Called when the user changes selection in the editor.
	if _ws_client == null or not _ws_client.is_connected_to_server():
		return
	var now := Time.get_ticks_msec() * 0.001
	if now - _last_selection_sent < SELECTION_RATE_LIMIT:
		return
	_last_selection_sent = now
	var path := ""
	var type_name := ""
	if object is Node:
		path = object.get_path()
		type_name = object.get_class()
	elif object is Resource:
		path = (object as Resource).resource_path
		type_name = object.get_class()
	_ws_client.send_notification("selection_changed", {
		"node_path": path,
		"type": type_name,
	})


func _get_role() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--heren-agent="):
			var id := a.substr("--heren-agent=".length())
			if id.is_empty():
				id = "default"
			return "agent:" + id
		elif a == "--heren-agent":
			return "agent:default"
	return "user"


func _setup_status_indicator() -> void:
	_status_label = Label.new()
	var role := _get_role()
	if role != "user":
		_status_label.text = "Heren: Connecting (%s)..." % role
	else:
		_status_label.text = "Heren: Connecting..."
	_status_label.add_theme_color_override("font_color", Color.YELLOW)
	_status_label.add_theme_font_size_override("font_size", 12)
	add_control_to_container(CONTAINER_TOOLBAR, _status_label)


func _on_connected() -> void:
	if _status_label:
		var role := _get_role()
		if role != "user":
			_status_label.text = "Heren: Connected (%s)" % role
		else:
			_status_label.text = "Heren: Connected"
		_status_label.add_theme_color_override("font_color", Color.GREEN)


func _on_disconnected() -> void:
	if _status_label:
		_status_label.text = "Heren: Disconnected"
		_status_label.add_theme_color_override("font_color", Color.RED)


func _on_error(message: String) -> void:
	if _status_label:
		_status_label.text = "Heren: Error"
		_status_label.add_theme_color_override("font_color", Color.ORANGE)
		_status_label.tooltip_text = message


func _on_tool_invoke(request_id: String, tool_name: String, args: Dictionary) -> void:
	if _dispatcher == null or _ws_client == null:
		return
	var result: Dictionary = await _dispatcher.execute(tool_name, args)
	var success: bool = result.get("ok", false)
	if success:
		var payload: Dictionary = result.duplicate(true)
		payload.erase("ok")
		_ws_client.send_tool_result(request_id, true, payload, "")
	else:
		_ws_client.send_tool_result(request_id, false, {}, str(result.get("error", "Unknown error")))
