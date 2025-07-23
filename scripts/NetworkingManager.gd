# NetworkingManager.gd
# Singleton para manejar todas las conexiones de red del juego
# Este script gestiona el descubrimiento de servidores, conexiones y multijugador

extends Node

# === SEÑALES PARA COMUNICACIÓN CON LA UI ===
signal server_list_updated(servers: Array)
signal connection_attempt_started(server_name: String)
signal connection_successful(server_info: Dictionary)  
signal connection_failed(error_message: String)
signal server_discovery_started()
signal server_discovery_completed()

# === CONFIGURACIÓN DE RED ===
const DEFAULT_PORT = 7777
const DISCOVERY_PORT = 7778
const MAX_PLAYERS = 8

# Variables de estado
var is_server: bool = false
var is_client: bool = false
var discovered_servers: Array = []
var current_server_info: Dictionary = {}

# Referencias de networking
var udp_server: UDPServer
var udp_client: PacketPeerUDP
var multiplayer_peer: MultiplayerPeer

func _ready():
	print("🌐 NetworkingManager inicializado")
	setup_networking()

# === CONFIGURACIÓN INICIAL ===
func setup_networking():
	print("⚙️ Configurando sistemas de red...")
	
	# Inicializar UDP para descubrimiento de servidores
	udp_server = UDPServer.new()
	udp_client = PacketPeerUDP.new()
	
	# Configurar callbacks de multijugador
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# === FUNCIONES DE SERVIDOR ===

# Iniciar servidor de juego
func start_server(server_name: String, max_players: int = MAX_PLAYERS) -> bool:
	print("🖥️ Iniciando servidor: ", server_name)
	
	# Crear peer para el servidor
	var peer = ENetMultiplayerPeer.new()
	var result = peer.create_server(DEFAULT_PORT, max_players)
	
	if result == OK:
		multiplayer.multiplayer_peer = peer
		is_server = true
		current_server_info = {
			"name": server_name,
			"port": DEFAULT_PORT,
			"max_players": max_players,
			"current_players": 1
		}
		
		# Iniciar broadcast para anunciar el servidor
		start_server_broadcast()
		
		print("✅ Servidor iniciado exitosamente en puerto ", DEFAULT_PORT)
		return true
	else:
		print("❌ Error al iniciar servidor: ", result)
		return false

# Anunciar servidor en la red local
func start_server_broadcast():
	print("📡 Iniciando broadcast del servidor...")
	
	# Escuchar peticiones de descubrimiento
	udp_server.listen(DISCOVERY_PORT)

# Procesar peticiones de descubrimiento
func _process_discovery_requests():
	udp_server.poll()
	
	if udp_server.is_connection_available():
		var peer = udp_server.take_connection()
		var packet = peer.get_packet()
		
		if packet.get_string_from_utf8() == "TRYPOPHOBIA_DISCOVERY":
			# Responder con información del servidor
			var response = JSON.stringify(current_server_info)
			peer.put_packet(response.to_utf8_buffer())

# === FUNCIONES DE CLIENTE ===

# Descubrir servidores en la red local
func discover_servers() -> void:
	print("🔍 Buscando servidores en la red local...")
	
	discovered_servers.clear()
	server_discovery_started.emit()
	
	# Enviar broadcast de descubrimiento
	udp_client.connect_to_host("255.255.255.255", DISCOVERY_PORT)
	udp_client.put_packet("TRYPOPHOBIA_DISCOVERY".to_utf8_buffer())
	
	# Esperar respuestas por 3 segundos
	await get_tree().create_timer(3.0).timeout
	
	# Procesar respuestas recibidas
	_process_discovery_responses()
	
	server_discovery_completed.emit()
	server_list_updated.emit(discovered_servers)

# Procesar respuestas de servidores
func _process_discovery_responses():
	while udp_client.get_available_packet_count() > 0:
		var packet = udp_client.get_packet()
		var response = packet.get_string_from_utf8()
		
		var json = JSON.new()
		var parse_result = json.parse(response)
		
		if parse_result == OK:
			var server_data = json.data
			discovered_servers.append(server_data)
			print("📍 Servidor encontrado: ", server_data.name)

# Conectar a un servidor específico
func connect_to_server(ip: String, port: int = DEFAULT_PORT) -> bool:
	print("🔌 Conectando a servidor ", ip, ":", port)
	
	connection_attempt_started.emit(ip + ":" + str(port))
	
	# Crear peer para cliente
	var peer = ENetMultiplayerPeer.new()
	var result = peer.create_client(ip, port)
	
	if result == OK:
		multiplayer.multiplayer_peer = peer
		is_client = true
		print("🔄 Intento de conexión iniciado...")
		return true
	else:
		print("❌ Error al crear cliente: ", result)
		connection_failed.emit("Error al inicializar conexión")
		return false

# === CALLBACKS DE MULTIJUGADOR ===

func _on_peer_connected(id: int):
	print("👥 Jugador conectado - ID: ", id)
	if is_server:
		current_server_info.current_players += 1

func _on_peer_disconnected(id: int):
	print("👤 Jugador desconectado - ID: ", id)
	if is_server:
		current_server_info.current_players -= 1

func _on_connection_failed():
	print("❌ Fallo en la conexión al servidor")
	connection_failed.emit("No se pudo conectar al servidor")
	is_client = false

func _on_connected_to_server():
	print("✅ Conectado al servidor exitosamente")
	connection_successful.emit(current_server_info)

func _on_server_disconnected():
	print("🔌 Desconectado del servidor")
	is_client = false

# === FUNCIONES DE UTILIDAD ===

# Obtener información del estado actual
func get_network_status() -> Dictionary:
	return {
		"is_server": is_server,
		"is_client": is_client,
		"player_count": multiplayer.get_peers().size() + 1 if is_server else 0,
		"server_info": current_server_info
	}

# Desconectar de red actual
func disconnect_from_network():
	print("🔌 Desconectando de la red...")
	
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	
	is_server = false
	is_client = false
	current_server_info.clear()
	
	# Cerrar UDP
	if udp_server.is_listening():
		udp_server.stop()
	udp_client.close()

# Limpiar recursos al salir
func _exit_tree():
	disconnect_from_network()

# === FUNCIONES DE DESARROLLO (SERVIDORES FICTICIOS) ===

# Generar servidores ficticios para pruebas
func get_sample_servers() -> Array:
	return [
		{
			"name": "🚀 Expedición Aurora - ACTIVA",
			"description": "7/8 tripulantes • Estación Minera Artemis",
			"ping": randf_range(20, 60),
			"players": 7,
			"max_players": 8,
			"status": "active",
			"ip": "192.168.1.100",
			"port": DEFAULT_PORT
		},
		{
			"name": "⚠️ Carabela En Peligro - CRÍTICO", 
			"description": "4/8 tripulantes • Sistema Kepler-442",
			"ping": randf_range(60, 120),
			"players": 4,
			"max_players": 8,
			"status": "critical",
			"ip": "192.168.1.101", 
			"port": DEFAULT_PORT
		},
		{
			"name": "🔴 Expedición Perdida - SIN RESPUESTA",
			"description": "1/8 tripulantes • Ubicación Desconocida", 
			"ping": 999,
			"players": 1,
			"max_players": 8,
			"status": "lost",
			"ip": "192.168.1.102",
			"port": DEFAULT_PORT
		},
		{
			"name": "🟢 Estación Segura - ESTABLE",
			"description": "6/8 tripulantes • Base Lunar Europa", 
			"ping": randf_range(10, 40),
			"players": 6,
			"max_players": 8,
			"status": "safe",
			"ip": "192.168.1.103",
			"port": DEFAULT_PORT
		}
	]

func _process(_delta):
	# Procesar peticiones de descubrimiento si somos servidor
	if is_server and udp_server.is_listening():
		_process_discovery_requests() 