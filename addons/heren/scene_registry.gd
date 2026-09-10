class_name HerenSceneRegistry
extends RefCounted
## Heren MCP v4 - SceneRegistry.
##
## Registro de escenas en MEMORIA por scene_path (ADR 2026-08-04).
## Fuente de verdad para el flujo create → add → save, independiente del
## sistema de pestañas del editor (que falla silenciosamente: open_scene_from_path
## no siempre abre pestaña → la escena quedaba "fantasma" y save no la persistía).
##
## PRINCIPIO (rediseño 2026-08-15): el DISCO es la fuente de verdad. La memoria
## es solo un overlay de trabajo del agente. Antes de CADA operación sobre una
## escena que existe en disco, el plugin sincroniza: si el disco cambió (mtime),
## recarga desde disco y re-aplica las ops pendientes del agente (replay).
## El agente NUNCA ve el conflicto — se resuelve silenciosamente.
##
## Resolución de escena (resolve_root), en orden:
##   0. SYNC: si el disco cambió → reload/replay ANTES de operar
##   1. Pestaña REAL del editor que coincide (lo que el usuario ve)
##   2. Registry (escena creada/editada por MCP en memoria, sin pestaña)
##   3. Archivo en disco → open_scene_from_path
##   4. null (error claro, nunca escena equivocada)
##
## Fase 1 (2026-09-03): SINGLE SOURCE OF TRUTH. El plugin-registry ahora también
## guarda state de PLANNING (plan, qa_report, lock, mode, dirty). El server NO
## mantiene estado paralelo — todo consulta/accede vía forward a este registry.
## Persistencia en `.heren/scenes/<scene>.json` para sobrevivir reinicios del editor.


static var _scenes: Dictionary = {}  # scene_path → Node (root)
static var _mtimes: Dictionary = {}  # scene_path → int (mtime al registrar)
static var _pending_ops: Dictionary = {}  # scene_path → Array[Dictionary] (ops del agente re-aplicables)
static var _dirty: Dictionary = {}  # scene_path → bool (hay mutaciones pendientes)

# Cache de mtime para evitar FileAccess.open en cada llamada.
# TTL 1s: suficiente para detectar cambios reales del disco sin overhead.
const MTIME_CACHE_TTL := 1.0
static var _mtime_cache: Dictionary = {}  # abs_path → {mtime: int, time: float}

# ============================================================
# Fase 1: state de planning (plan JSON, qa_report, lock, mode)
# ============================================================
static var _plans: Dictionary = {}        # scene_path → Dictionary (ScenePlan JSON)
static var _qa_reports: Dictionary = {}   # scene_path → Dictionary (QAReport JSON)
static var _locks: Dictionary = {}        # scene_path → {agent_id, mode, pid, since, progress, lock_id}
static var _modes: Dictionary = {}        # scene_path → SceneMode (isolated/attached/modify)
static var _plan_dirty: Dictionary = {}   # scene_path → bool (override explícito dirty de plan)


# Persistencia: .heren/scenes/<scene>.json con state de planning.
# Solo se persiste state, no el árbol (eso vive en _scenes mientras hay editor).
const _SCENES_DIR := ".heren/scenes"


static func _scenes_state_path(scene_path: String) -> String:
	var p := _norm(scene_path)
	var safe := p.replace("res://", "").replace("/", "_").replace(":", "_")
	return _SCENES_DIR + "/" + safe + ".json"


## Persiste state de planning a disco (llamar tras write_plan, acquire_lock, etc).
static func _persist_state(scene_path: String) -> void:
	var p := _norm(scene_path)
	if p == "":
		return
	var path := _scenes_state_path(p)
	var dir := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var state := {
		"scene_path": p,
		"plan": _plans.get(p, null),
		"qa_report": _qa_reports.get(p, null),
		"lock": _locks.get(p, null),
		"mode": _modes.get(p, ""),
		"dirty": _plan_dirty.get(p, false),
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(state))
	f.close()


## Carga state de planning desde disco (lazy, primera vez que se accede).
static func _load_state_if_needed(scene_path: String) -> void:
	var p := _norm(scene_path)
	if p == "":
		return
	var path := _scenes_state_path(p)
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var s := parsed as Dictionary
	if s.has("plan") and s["plan"] != null:
		_plans[p] = s["plan"]
	if s.has("qa_report") and s["qa_report"] != null:
		_qa_reports[p] = s["qa_report"]
	if s.has("lock") and s["lock"] != null:
		_locks[p] = s["lock"]
	if s.has("mode") and s["mode"] != "":
		_modes[p] = s["mode"]
	if s.has("dirty"):
		_plan_dirty[p] = s["dirty"]


## Normaliza la key a la forma canónica (res://, forward slashes, sin
## trailing) para que coincida SIEMPRE con scene_file_path de las pestañas.
static func _norm(path: String) -> String:
	var s := path.strip_edges()
	if s == "":
		return ""
	s = s.replace("\\", "/")
	while s.ends_with("/"):
		s = s.substr(0, s.length() - 1)
	if not s.begins_with("res://"):
		return "res://" + s
	return s


## Obtiene el mtime de un archivo en disco (0 si no existe).
## Usa cache con TTL 1s para evitar FileAccess.open en cada llamada.
static func _get_file_mtime(path: String) -> int:
	if not ResourceLoader.exists(path):
		return 0
	var abs_path := ProjectSettings.globalize_path(path)
	var now := Time.get_ticks_msec() / 1000.0
	# Cache hit: mtime consultado hace < TTL
	var cached: Variant = _mtime_cache.get(abs_path, null)
	if cached is Dictionary:
		var age: float = now - (cached as Dictionary).get("time", 0.0)
		if age < MTIME_CACHE_TTL:
			return (cached as Dictionary).get("mtime", 0)
	# Cache miss: leer del disco
	var file := FileAccess.open(abs_path, FileAccess.READ)
	if file == null:
		return 0
	var mtime := file.get_modified_time(abs_path)
	file.close()
	_mtime_cache[abs_path] = {"mtime": mtime, "time": now}
	return mtime


## Verifica si el archivo en disco cambió desde que se registró la escena.
static func _is_stale(path: String) -> bool:
	var p := _norm(path)
	if not _mtimes.has(p):
		return false  # No tenemos mtime registrado, asumir fresco
	var disk_mtime := _get_file_mtime(p)
	if disk_mtime == 0:
		return false  # Archivo no existe en disco, no puede estar stale
	return disk_mtime > _mtimes[p]


static func register(path: String, root: Node) -> void:
	var p := _norm(path)
	if p == "" or root == null:
		return
	_scenes[p] = root
	# Guardar mtime actual del archivo en disco (0 si no existe aún).
	_mtimes[p] = _get_file_mtime(p)


static func unregister(path: String) -> void:
	var p := _norm(path)
	_scenes.erase(p)
	_mtimes.erase(p)


static func get_root(path: String) -> Node:
	var p := _norm(path)
	# BUG 2 fix: verificar si el archivo en disco cambió (mtime).
	if _is_stale(p):
		# Invalidar cache — el usuario editó el .tscn manualmente.
		_scenes.erase(p)
		_mtimes.erase(p)
		return null
	var root: Variant = _scenes.get(p, null)
	# 🚨 ORDEN CRÍTICO: is_instance_valid() PRIMERO (seguro con freed), luego
	# `is Node`. Si root es una instancia previamente liberada, `root is Node`
	# CRASHEA con "Left operand of 'is' is a previously freed instance".
	if is_instance_valid(root) and root is Node:
		return root
	# Referencia colgante (pestaña cerrada → nodo liberado): limpiar.
	_scenes.erase(p)
	_mtimes.erase(p)
	return null


static func has(path: String) -> bool:
	return get_root(path) != null


static func all() -> Dictionary:
	var out := {}
	for path in _scenes.keys():
		var root := get_root(path)
		if root != null:
			out[path] = root
	return out


static func clear() -> void:
	_scenes.clear()
	_mtimes.clear()
	_pending_ops.clear()
	_dirty.clear()
	_mtime_cache.clear()


## Actualiza el mtime registrado para una escena (llamar después de save).
static func update_mtime(path: String) -> void:
	var p := _norm(path)
	if p == "":
		return
	_mtimes[p] = _get_file_mtime(p)


## ============================================================
## Ops pendientes del agente (replay) — rediseño 2026-08-15
## ============================================================

## Registra una operación del agente para poder re-aplicarla sobre un árbol
## fresco del disco (si el disco cambió entre la op y el save).
static func record_op(path: String, op: Dictionary) -> void:
	var p := _norm(path)
	if p == "":
		return
	if not _pending_ops.has(p):
		_pending_ops[p] = []
	(_pending_ops[p] as Array).append(op)
	_dirty[p] = true


## Limpia las ops pendientes de una escena (tras save exitoso).
static func clear_ops(path: String) -> void:
	var p := _norm(path)
	_pending_ops.erase(p)
	_dirty.erase(p)


## Devuelve las ops pendientes de una escena (copia).
static func get_pending_ops(path: String) -> Array:
	var p := _norm(path)
	return (_pending_ops.get(p, []) as Array).duplicate()


static func has_pending_ops(path: String) -> bool:
	var p := _norm(path)
	return _pending_ops.has(p) and (_pending_ops[p] as Array).size() > 0


## Devuelve la escena dirty más reciente (por mtime), o "" si no hay ninguna.
## Útil para commit inteligente: si el agente no pasa scene_path, usar la
## última escena que fue editada por el MCP.
static func most_recent_dirty() -> String:
	var best_path := ""
	var best_mtime := -1
	for path in _dirty.keys():
		if not _dirty[path]:
			continue
		var mtime := _get_file_mtime(path)
		if mtime > best_mtime:
			best_mtime = mtime
			best_path = path
	return best_path


## Re-aplica UNA op sobre un root fresco. Devuelve true si se re-aplicó.
## Fail-safe: si la op no puede re-aplicarse (nodo no existe, prop cambió),
## devuelve false y el caller la conserva en _pending_ops para reportar.
static func _replay_op(root: Node, op: Dictionary) -> bool:
	var kind: String = str(op.get("kind", ""))
	var node_path: String = str(op.get("node_path", ""))
	var node: Node = null
	if node_path == "" or node_path == ".":
		node = root
	else:
		node = root.get_node_or_null(NodePath(node_path))
	if node == null:
		return false
	match kind:
		"set_prop":
			var property: String = str(op.get("property", ""))
			if property == "":
				return false
			# 🚨 property puede no existir aún si el script no se aplicó al
			# recargar. Esperamos 1 frame para que Godot aplique el script y
			# sus exports. Si sigue sin existir, es una prop real inexistente.
			if property not in node:
				return false
			node.set(property, op.get("value"))
			return true
		"set_owner":
			node.owner = root
			return true
		_:
			return false  # Op desconocida: no re-aplicable, conservar


## ============================================================
## Sincronización disco ↔ memoria (rediseño 2026-08-15)
## ============================================================

## Detecta si el disco cambió desde el último registro y resuelve la
## divergencia SILENCIOSAMENTE:
##   - Sin ops pendientes: recarga desde disco (el árbol en memoria se
##     refresca; el agente opera sobre la versión fresca)
##   - Con ops pendientes: recarga desde disco + re-aplica las ops (replay)
## Devuelve el root FRESCO si hubo sync, null si no hubo divergencia o falló.
## El caller usa el root devuelto en lugar de resolver de nuevo.
static func sync_from_disk(ei: EditorInterface, scene_path: String) -> Node:
	var p := _norm(scene_path)
	if ei == null or p == "":
		return null
	# Caso 4 (matriz): archivo borrado del disco → limpiar, NO recrear.
	if not ResourceLoader.exists(p):
		unregister(p)
		_pending_ops.erase(p)
		_dirty.erase(p)
		return null
	var disk_mtime := _get_file_mtime(p)
	var registered := _mtimes.get(p, -1)
	if registered == -1:
		return null  # Nunca registrada: resolve_root la carga fresca
	if disk_mtime <= registered:
		return null  # Sin divergencia: no tocar nada
	# 🚨 DIVERGENCIA: el disco es más nuevo que nuestra copia.
	var ops: Array = get_pending_ops(p)
	var has_ops: bool = ops.size() > 0
	# Recargar la escena desde disco. Si está activa en la pestaña, forzar
	# reload_scene_from_path (que pierde memoria — por eso re-aplicamos ops).
	# 🚨 API REAL Godot 4: reload_scene_from_path(path) — NO reload_scene_from_disk()
	# (ese es de Godot 3). Además, reload_scene_from_path SOLO funciona una vez
	# por frame con la escena activa (issue #13816) — si falla, usar open.
	var active := ei.get_edited_scene_root()
	var reloaded := false
	if active != null and active.scene_file_path == p:
		if ei.has_method("reload_scene_from_path"):
			ei.reload_scene_from_path(p)
			active = ei.get_edited_scene_root()
			reloaded = active != null and active.scene_file_path == p
	if not reloaded:
		ei.open_scene_from_path(p)
		active = ei.get_edited_scene_root()
	if active == null or active.scene_file_path != p:
		# No se pudo recargar: limpiar y dejar que resolve_root intente de nuevo.
		unregister(p)
		return null
	# Re-aplicar ops pendientes sobre el árbol fresco (replay).
	var skipped: Array = []
	if has_ops:
		for op in ops:
			if not _replay_op(active, op):
				skipped.append(op)
	# Registrar con el mtime NUEVO del disco (ya no hay divergencia).
	register(p, active)
	if skipped.size() > 0:
		# Conservar las no re-aplicadas (el agente las verá en el próximo
		# save como `replay_skipped`) y marcar dirty.
		_pending_ops[p] = skipped
		_dirty[p] = true
	else:
		_pending_ops.erase(p)
		_dirty.erase(p)
	return active


## Resuelve la escena objetivo de una operación.
## Prioridad (rediseño 2026-08-15):
##   0. SYNC: si el disco cambió → reload/replay ANTES de operar
##   1. Pestaña REAL del editor que coincide (lo que el usuario ve)
##   2. Registry (escena creada/editada por MCP en memoria, sin pestaña)
##   3. Archivo en disco → open_scene_from_path
##   4. null (error claro, nunca escena equivocada)
static func resolve_root(ei: EditorInterface, scene_path: String) -> Node:
	if ei == null:
		return null
	if scene_path == "":
		return ei.get_edited_scene_root()
	var path := _norm(scene_path)
	# 0) SYNC: si el disco cambió, recargar/replay ANTES de operar.
	#    Esto evita que el agente opere sobre un árbol stale (matriz #1,#9).
	var synced := sync_from_disk(ei, path)
	if synced != null:
		return synced
	# 1) Pestaña real: si el usuario abrió la escena, es la fuente de verdad.
	var active := ei.get_edited_scene_root()
	if active != null and active.scene_file_path == path:
		register(path, active)
		return active
	# 2) Registry (fantasma en memoria — escena creada por MCP sin pestaña).
	var registered := get_root(path)
	if registered != null:
		return registered
	# 3) Disco: abrir y registrar la pestaña.
	if ResourceLoader.exists(path):
		ei.open_scene_from_path(path)
		var opened := ei.get_edited_scene_root()
		if opened != null and opened.scene_file_path == path:
			register(path, opened)
			return opened
	return null


# ============================================================
# Fase 1: API de state de planning (plan, qa, lock, mode)
# ============================================================

## Escribe el ScenePlan JSON de una escena. Valida que sea un dict mínimo.
## Persiste a disco y marca la escena como plan_owner.
static func write_plan(scene_path: String, plan: Dictionary) -> Dictionary:
	var p := _norm(scene_path)
	if p == "":
		return {"ok": false, "error": "scene_path required"}
	if typeof(plan) != TYPE_DICTIONARY:
		return {"ok": false, "error": "plan must be a Dictionary"}
	_load_state_if_needed(p)
	_plans[p] = plan
	_plan_dirty[p] = true
	_persist_state(p)
	return {"ok": true}


## Devuelve el ScenePlan JSON de una escena, o {} si no tiene.
static func get_plan(scene_path: String) -> Dictionary:
	var p := _norm(scene_path)
	_load_state_if_needed(p)
	return _plans.get(p, {})


## Devuelve true si la escena tiene un plan registrado.
static func has_plan(scene_path: String) -> bool:
	var p := _norm(scene_path)
	_load_state_if_needed(p)
	return _plans.has(p)


## Escribe el QA report de una escena (resultado del último validate).
static func write_qa_report(scene_path: String, report: Dictionary) -> void:
	var p := _norm(scene_path)
	_load_state_if_needed(p)
	_qa_reports[p] = report
	_persist_state(p)


## Devuelve el QA report de una escena, o {} si no tiene.
static func get_qa_report(scene_path: String) -> Dictionary:
	var p := _norm(scene_path)
	_load_state_if_needed(p)
	return _qa_reports.get(p, {})


## Adquiere un lock para la escena. agent_id="" → usa "default".
## Si ya hay lock de otro agent → retorna error con existing_agent_id.
static func acquire_lock(scene_path: String, agent_id: String, mode: String) -> Dictionary:
	var p := _norm(scene_path)
	if p == "":
		return {"ok": false, "error": "scene_path required"}
	_load_state_if_needed(p)
	var aid := agent_id if agent_id != "" else "default"
	var md := mode if mode != "" else "isolated"
	if _locks.has(p):
		var existing: Dictionary = _locks[p]
		if existing.get("agent_id", "") != aid:
			return {
				"ok": false,
				"error": "scene_locked_by_agent",
				"existing_agent_id": existing.get("agent_id", ""),
				"existing_pid": existing.get("pid", 0),
				"existing_since": existing.get("since", ""),
			}
		# Mismo agent re-opening: OK, retorna el mismo lock_id.
		return {"ok": true, "lock_id": existing.get("lock_id", ""), "mode": md}
	# Crear nuevo lock.
	var lock_id := "lock_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 10000)
	_locks[p] = {
		"agent_id": aid,
		"mode": md,
		"pid": OS.get_process_id(),
		"since": Time.get_datetime_string_from_system(true),
		"progress": "Opening scene",
		"lock_id": lock_id,
	}
	_modes[p] = md
	_persist_state(p)
	return {"ok": true, "lock_id": lock_id, "mode": md}


## Libera el lock de una escena. Retorna true si había lock.
static func release_lock(scene_path: String) -> bool:
	var p := _norm(scene_path)
	_load_state_if_needed(p)
	var removed := _locks.erase(p)
	if removed:
		_persist_state(p)
	return removed


## Devuelve info del lock actual o {} si no hay.
static func get_lock(scene_path: String) -> Dictionary:
	var p := _norm(scene_path)
	_load_state_if_needed(p)
	return _locks.get(p, {})


## Marca la escena dirty (override explícito; el orchestrator setea esto).
static func set_dirty(scene_path: String, value: bool) -> void:
	var p := _norm(scene_path)
	_load_state_if_needed(p)
	_plan_dirty[p] = value
	_persist_state(p)


## Devuelve el estado de dirty de una escena (considera _plan_dirty Y _dirty legacy).
static func is_dirty(scene_path: String) -> bool:
	var p := _norm(scene_path)
	_load_state_if_needed(p)
	if _plan_dirty.get(p, false):
		return true
	return _dirty.get(p, false)


## Devuelve el status completo de una escena (lo que retorna `scene/status`).
static func status_of(scene_path: String) -> Dictionary:
	var p := _norm(scene_path)
	_load_state_if_needed(p)
	var qa := _qa_reports.get(p, {})
	return {
		"lock_id": _locks.get(p, {}).get("lock_id", ""),
		"scene_path": p,
		"mode": _modes.get(p, _locks.get(p, {}).get("mode", "isolated")),
		"dirty": is_dirty(p),
		"has_plan": _plans.has(p),
		"qa_status": qa.get("error_type", "none") if not qa.is_empty() else null,
		"lock_info": _locks.get(p, null),
	}


## Lista el status de todas las escenas con plan registrado.
static func list_scenes() -> Array:
	var out := []
	for path in _plans.keys():
		out.append(status_of(path))
	return out


## Limpia TODO el state de planning (mantiene _scenes intacto).
## Usado al cerrar el editor o reiniciar el plugin.
static func clear_planning_state() -> void:
	_plans.clear()
	_qa_reports.clear()
	_locks.clear()
	_modes.clear()
	_plan_dirty.clear()
