@tool
extends RefCounted

# Heren MCP v4 - Constantes del plugin (Fase C5).
# Centraliza números de configuración/protocolo. Los valores de redondeo de
# coordenadas (100.0/1000.0 en coords.gd) NO van aquí: son precisión de salida.

## Puerto base del WS plugin server (el server Rust busca 9099+N libre y se lo
## pasa al plugin via HEREN_MCP_PORT al lanzar el editor). Debe coincidir con
## `crates/heren-server/src/constants.rs` -> WS_PORT_BASE.
const WS_PORT_DEFAULT := 9099

## Prefijo de recursos Godot (paths `res://...`).
const RES_PREFIX := "res://"

## Default URL del plugin (el server real puede usar otro puerto via env).
static func default_ws_url() -> String:
	return "ws://127.0.0.1:%d" % WS_PORT_DEFAULT
