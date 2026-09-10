@tool
extends RefCounted

# Heren MCP v4 - Shape estándar de error (Fase C6).
# Todos los handlers devuelven `{"ok": bool, ...}`. Para errores, el shape
# canónico es:
#   {"ok": false, "error": "mensaje"}
# Este helper centraliza la construcción para que ningún handler invente
# claves distintas. Los handlers existentes aún usan dicts literales; los
# nuevos deben usar HerenError.err(msg) / ok(payload).


## Error canónico: `{"ok": false, "error": msg}`.
static func err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


## Éxito con payload: `{"ok": true, ...payload}`.
static func ok(payload: Dictionary = {}) -> Dictionary:
	payload["ok"] = true
	return payload


## Helper para la clase base: devuelve un error con detalle opcional.
static func err_with(msg: String, details: Dictionary = {}) -> Dictionary:
	var out := err(msg)
	if not details.is_empty():
		out["details"] = details
	return out
