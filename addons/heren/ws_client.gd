@tool
extends Node

# Heren MCP v4 - WebSocket client.
# Connects to the FlojoMCP MCP server (ADR-003: plugin = WS CLIENT).
# Speaks MCP JSON-RPC: receives `tools/call` requests, replies with
# `tools/call` results. Auto-reconnect with exponential backoff.

signal connected
signal disconnected
signal tool_invoke_received(request_id: String, tool_name: String, args: Dictionary)
signal error_reported(message: String)

const HerenConstants := preload("constants.gd")

const DEFAULT_URL := "ws://127.0.0.1:%d" % HerenConstants.WS_PORT_DEFAULT
const RECONNECT_DELAY := 2.0
const MAX_RECONNECT_DELAY := 30.0
const PING_INTERVAL := 10.0
const POLL_INTERVAL := 0.1  # 10 Hz — suficiente para MCP, 6× menos carga que _process

var socket: WebSocketPeer = WebSocketPeer.new()
var server_url: String = DEFAULT_URL
var _is_connected := false
var _initialized := false
var _should_reconnect := true
var _current_reconnect_delay := RECONNECT_DELAY
var _reconnect_timer: Timer
var _ping_timer: Timer
var _poll_timer: Timer
var _discovery_timer: Timer
var _focused := true  # track editor focus para pausar poll
var _project_path: String = ""
var _last_known_port: int = 0  # último puerto leído del discovery file


func _ready() -> void:
	_project_path = ProjectSettings.globalize_path("res://")

	_reconnect_timer = Timer.new()
	_reconnect_timer.one_shot = true
	_reconnect_timer.timeout.connect(_on_reconnect_timer)
	add_child(_reconnect_timer)

	_ping_timer = Timer.new()
	_ping_timer.wait_time = PING_INTERVAL
	_ping_timer.timeout.connect(_send_ping)
	add_child(_ping_timer)

	# Poll por timer en vez de _process: 10 Hz vs 60 Hz = 6× menos overhead
	_poll_timer = Timer.new()
	_poll_timer.wait_time = POLL_INTERVAL
	_poll_timer.timeout.connect(_poll_socket)
	add_child(_poll_timer)
	_poll_timer.start()

	# Discovery: verificar `.heren/server_port.json` cada 5s para reconectar
	# al server correcto cuando OpenCode reinicia (fix 2026-09-03).
	_discovery_timer = Timer.new()
	_discovery_timer.wait_time = 5.0
	_discovery_timer.timeout.connect(_check_discovery)
	add_child(_discovery_timer)
	_discovery_timer.start()

	_initialized = true


## Pausa/reanuda el poll según foco del editor.
## Al minimizar, el socket no necesita polling — al maximizar se reanuda.
func _notification(what: int) -> void:
	if not _initialized:
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_focused = true
			if _poll_timer and not _poll_timer.is_stopped():
				return  # ya corriendo
			if _should_reconnect and socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
				_poll_timer.start()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_focused = false
			# No paramos el timer — solo evitamos trabajo pesado adicional.
			# El poll sigue a 10 Hz para mantener la conexión viva (ping/pong).


func _poll_socket() -> void:
	if not _initialized:
		return

	var state := socket.get_ready_state()

	if state == WebSocketPeer.STATE_CLOSED:
		if _is_connected:
			_handle_disconnect()
		return

	socket.poll()

	# Re-leer state tras poll (puede haber cambiado)
	state = socket.get_ready_state()
	match state:
		WebSocketPeer.STATE_OPEN:
			if not _is_connected:
				_handle_connect()
			while socket.get_available_packet_count() > 0:
				var packet := socket.get_packet()
				_handle_message(packet.get_string_from_utf8())
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			if _is_connected:
				_handle_disconnect()


func connect_to_server(url: String = "") -> void:
	server_url = _resolve_server_url(url)
	_should_reconnect = true
	_current_reconnect_delay = RECONNECT_DELAY
	_attempt_connection()


func _resolve_server_url(explicit_url: String) -> String:
	if explicit_url != "":
		return explicit_url
	# 1. Discovery file: `.heren/server_port.json` (fix 2026-09-03).
	var disc_port := _read_discovery_port()
	if disc_port > 0:
		_last_known_port = disc_port
		return "ws://127.0.0.1:%d" % disc_port
	# 2. HEREN_MCP_PORT environment variable.
	var env_port := OS.get_environment("HEREN_MCP_PORT")
	if env_port != "" and env_port.is_valid_int():
		var port := int(env_port)
		if port >= 1 and port <= 65535:
			_last_known_port = port
			return "ws://127.0.0.1:%d" % port
	return DEFAULT_URL


## Lee `.heren/server_port.json` y devuelve el puerto, o 0 si no existe.
func _read_discovery_port() -> int:
	var path := ProjectSettings.globalize_path("res://.heren/server_port.json")
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var json_text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed is Dictionary:
		var port: int = int(parsed.get("port", 0))
		return port
	return 0


## Verifica si el discovery file cambió de puerto → reconectar al nuevo.
func _check_discovery() -> void:
	if not _should_reconnect:
		return
	var new_port := _read_discovery_port()
	if new_port > 0 and new_port != _last_known_port:
		print("[HEREN] discovery: server port changed %d -> %d, reconnecting" % [_last_known_port, new_port])
		_last_known_port = new_port
		server_url = "ws://127.0.0.1:%d" % new_port
		# Forzar reconexión inmediata al nuevo puerto.
		if socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
			socket.close()
		_current_reconnect_delay = RECONNECT_DELAY
		_attempt_connection()


func disconnect_from_server() -> void:
	_should_reconnect = false
	if _reconnect_timer:
		_reconnect_timer.stop()
	if _ping_timer:
		_ping_timer.stop()
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.close()
	_is_connected = false


func _attempt_connection() -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close()
	var err := socket.connect_to_url(server_url)
	print("[HEREN] ws connect attempt -> url=%s err=%d" % [server_url, err])
	if err != OK:
		error_reported.emit("ws connect failed: %d" % err)
		_schedule_reconnect()


func _detect_role() -> String:
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


func _handle_connect() -> void:
	_is_connected = true
	_current_reconnect_delay = RECONNECT_DELAY
	if _ping_timer:
		_ping_timer.start()
	_send_message({
		"jsonrpc": "2.0",
		"method": "notifications/godot_ready",
		"params": {
			"project_path": _project_path,
			"plugin_version": _read_plugin_version(),
			"role": _detect_role(),
		},
	})
	connected.emit()


## Versión del plugin que corre en este editor (plugin.cfg → [plugin] version).
## El server la compara con la versión source para avisar al agente cuando el
## editor corre una versión antigua (session/reopen para recargar).
func _read_plugin_version() -> String:
	var cfg := ConfigFile.new()
	var err := cfg.load("res://addons/heren/plugin.cfg")
	if err != OK:
		return ""
	return str(cfg.get_value("plugin", "version", ""))


func _handle_disconnect() -> void:
	_is_connected = false
	if _ping_timer:
		_ping_timer.stop()
	disconnected.emit()
	if _should_reconnect:
		_schedule_reconnect()


func _schedule_reconnect() -> void:
	if _reconnect_timer == null:
		return
	_reconnect_timer.start(_current_reconnect_delay)
	_current_reconnect_delay = min(_current_reconnect_delay * 2.0, MAX_RECONNECT_DELAY)


func _on_reconnect_timer() -> void:
	_attempt_connection()


func _send_ping() -> void:
	_send_message({
		"jsonrpc": "2.0",
		"method": "notifications/ping",
		"params": {},
	})


## Send a push notification to the server (e.g. selection_changed).
## Used by the editor plugin for event push (§13.6) with rate-limit.
func send_notification(name: String, params: Dictionary = {}) -> void:
	if not _is_connected:
		return
	_send_message({
		"jsonrpc": "2.0",
		"method": "notifications/" + name,
		"params": params,
	})


func _handle_message(json_string: String) -> void:
	var message = JSON.parse_string(json_string)
	if message == null:
		error_reported.emit("failed to parse message")
		return
	if not message is Dictionary:
		return

	var method: String = message.get("method", "")
	match method:
		"tools/call":
			var request_id: String = str(message.get("id", ""))
			var params: Dictionary = message.get("params", {})
			var tool_name: String = str(params.get("name", ""))
			var args: Dictionary = params.get("arguments", {})
			tool_invoke_received.emit(request_id, tool_name, args)
		"ping":
			_send_message({"jsonrpc": "2.0", "id": message.get("id", null), "result": {}})
		"notifications/pong":
			pass
		_:
			pass


func send_tool_result(request_id: String, success: bool, result: Dictionary, error: String) -> void:
	var response: Dictionary = {"jsonrpc": "2.0", "id": request_id}
	if success:
		response["result"] = {"content": [{"type": "text", "text": JSON.stringify(result)}]}
	else:
		response["error"] = {"code": -32000, "message": error}
	_send_message(response)


func _send_message(message: Dictionary) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(message))


func is_connected_to_server() -> bool:
	return _is_connected
