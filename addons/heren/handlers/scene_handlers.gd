@tool
extends "res://addons/heren/handlers/heren_handler.gd"
# Heren MCP v4 - Scene handlers (Fase 1).
# Handles: health, project_info, get_edited_scene_root, get_open_scenes,
# create, save, open. All mutations go through the UndoRedo wrapper
# (EditorUndoRedoManager) so Ctrl+Z undoes them (ADR-002 advantage).
#
# ADR 2026-08-04 (escenas robustas): el guardado NUNCA pasa por el sistema de
# pestañas. create registra el árbol en HerenSceneRegistry (memoria, por path);
# save hace pack() directo del root registrado → ResourceSaver → disco.
# Así la escena "fantasma" (creada por MCP sin pestaña del editor) persiste.

const HerenSceneRegistryScript := preload("../scene_registry.gd")
const HerenCoordsScript := preload("coords.gd")

var _undo_redo: Node


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin
	_undo_redo = plugin.get_undo_redo_wrapper()
	print("[HEREN] scene_handlers set_editor_plugin: ", _editor_plugin)


func handle_health(_args: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"status": "healthy",
		"editor_version": Engine.get_version_info().get("string", ""),
	}


func handle_project_info(_args: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"project_path": ProjectSettings.globalize_path("res://"),
		"project_name": ProjectSettings.get_setting("application/config/name", ""),
	}


func handle_get_edited_scene_root(_args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "editor interface unavailable"}
	var root := ei.get_edited_scene_root()
	if root == null:
		return {"ok": true, "has_scene": false}
	return {
		"ok": true,
		"has_scene": true,
		"scene_path": root.scene_file_path,
		"root_name": root.name,
		# Coords del root (Node3D / Node2D) — el agente las necesita para
		# verificar el state tras open/load/save. Fuente unificada coords.gd.
		"coords": HerenCoordsScript.coords_of_node(root, "", 2) if "scene_file_path" in root else {},
	}


func handle_get_open_scenes(_args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "editor interface unavailable"}
	var scenes := ei.get_open_scenes()
	# Añadir escenas del registry que NO están en pestañas (creadas por MCP):
	# así el agente ve TODO lo que existe, no solo pestañas del editor.
	for scene_path in HerenSceneRegistryScript.all().keys():
		if scene_path not in scenes:
			scenes.append(scene_path)
	return {"ok": true, "open_scenes": scenes}


func handle_create(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "editor interface unavailable"}

	var root_type: String = str(args.get("root_type", "Node2D"))
	var root_name: String = str(args.get("root_name", "NewNode"))
	var scene_path: String = _normalize_scene_path(str(args.get("scene_path", "")))

	# Instantiate the root node.
	var new_node: Node = ClassDB.instantiate(root_type)
	if new_node == null:
		return {"ok": false, "error": "unknown root_type: " + root_type}
	new_node.name = root_name

	# Instancia opcional (2026-08-24): la escena nueva contiene otra escena
	# como instancia (ExtResource al guardar). `instance_scene` = path
	# explícito; `instance_current:true` = instanciar la pestaña activa.
	# ensure_owner_recursive ya maneja instancias: el root de la instancia
	# recibe owner, sus internos se serializan vía el .tscn referenciado.
	var inst_path := str(args.get("instance_scene", ""))
	if bool(args.get("instance_current", false)) and inst_path == "":
		var cur := ei.get_edited_scene_root()
		if cur != null and cur.scene_file_path != "":
			inst_path = cur.scene_file_path
	if inst_path != "":
		inst_path = _normalize_scene_path(inst_path)
		# E6 (2026-08-24): self-check ANTES del exists-check — si la escena
		# destino aún no está en disco, "not_found" confundía; el problema
		# real es la auto-referencia.
		if scene_path != "" and inst_path == scene_path:
			new_node.free()
			return {"ok": false, "error": "cannot_instance_scene_into_itself: " + inst_path}
		if not ResourceLoader.exists(inst_path):
			new_node.free()
			return {"ok": false, "error": "instance_scene_not_found: " + inst_path}
		var packed_src: PackedScene = load(inst_path)
		if packed_src == null:
			new_node.free()
			return {"ok": false, "error": "instance_load_failed: " + inst_path}
		var inst: Node = packed_src.instantiate()
		if inst == null:
			new_node.free()
			return {"ok": false, "error": "instance_instantiate_failed: " + inst_path}
		inst.name = "Instance"
		new_node.add_child(inst)

	# scene_path explícito → SIEMPRE crear archivo nuevo (independiente de la
	# pestaña activa). El path es el destino del archivo, no la escena activa.
	if scene_path != "":
		if ResourceLoader.exists(scene_path):
			new_node.free()
			return {"ok": false, "error": "scene_exists: " + scene_path}
		return _create_scene_file(ei, new_node, scene_path, root_type, root_name)

	# Sin scene_path: si hay escena abierta, inyectar el nodo (v3 behavior).
	var scene_root := ei.get_edited_scene_root()
	if scene_root != null:
		_undo_redo.begin_action("Heren Create Node: %s" % root_name)
		_undo_redo.add_do_method(scene_root, &"add_child", [new_node])
		_undo_redo.add_do_property(new_node, &"owner", scene_root)
		_undo_redo.add_undo_method(scene_root, &"remove_child", [new_node])
		_undo_redo.commit_action()
		return {
			"ok": true,
			"node_name": root_name,
			"node_type": root_type,
			"parent_path": ".",
		}

	# No scene open: create a brand-new scene file and open it in the editor.
	var packed := PackedScene.new()
	HerenCoordsScript.ensure_owner_recursive(new_node)
	packed.pack(new_node)
	scene_path = "res://%s.tscn" % root_name
	if ResourceLoader.exists(scene_path):
		new_node.free()
		return {"ok": false, "error": "scene_exists: " + scene_path}
	return _create_scene_file(ei, new_node, scene_path, root_type, root_name)


func _create_scene_file(ei: EditorInterface, new_node: Node, scene_path: String,
		root_type: String, root_name: String) -> Dictionary:
	# Asegurar directorio padre (misma carencia que shader/resource).
	_ensure_parent_dir(scene_path)
	var packed := PackedScene.new()
	HerenCoordsScript.ensure_owner_recursive(new_node)
	packed.pack(new_node)
	# 🚨 SIN FLAG_BUNDLE_RESOURCES: esa flag INCORPORA los recursos externos
	# (scripts .gd con resource_path) dentro del .tscn como sub_resource —
	# el bug "save embebe scripts". Los recursos inline sin path se guardan
	# vía resource_local_to_scene (ensure_resource_local_recursive).
	var err := ResourceSaver.save(packed, scene_path)
	if err != OK:
		new_node.free()
		return {"ok": false, "error": "save_failed: " + error_string(err)}

	var efs: EditorFileSystem = ei.get_resource_filesystem()
	if efs:
		efs.update_file(scene_path)

	# Registrar en memoria SIEMPRE (fuente de verdad del flujo MCP). Prioridad:
	# pestaña real del editor (si abre) → árbol en memoria vivo (fallback).
	var opened := ei.get_edited_scene_root()
	var got_tab := opened != null and opened.scene_file_path == scene_path
	if not got_tab:
		ei.open_scene_from_path(scene_path)
		opened = ei.get_edited_scene_root()
		got_tab = opened != null and opened.scene_file_path == scene_path
	if got_tab:
		new_node.free()
		HerenSceneRegistryScript.register(scene_path, opened)
	else:
		# open_scene_from_path falló (silencioso): mantener nuestro árbol VIVO
		# en el registry para que node/save operen contra él igualmente.
		new_node.scene_file_path = scene_path
		HerenSceneRegistryScript.register(scene_path, new_node)

	return {
		"ok": true,
		"created": scene_path,
		"root_name": root_name,
		"root_type": root_type,
		"registered": true,
	}


## Save SIEMPRE por pack directo del root objetivo → ResourceSaver. NUNCA
## ei.save_scene() (guarda la pestaña activa, no la escena pedida).
func handle_save(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "editor interface unavailable"}

	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path == "":
		scene_path = str(args.get("output_path", ""))
	var root: Node = null
	# Rediseño 2026-08-15: true si sync_from_disk recargó desde disco y
	# re-aplicó ops (en ese caso, los replay_skipped SÍ son reales).
	var synced_root_had_sync := false

	# 1) scene_path explícito → MISMA prioridad que resolve_root:
	#    PESTAÑA REAL primero (lo que el usuario ve y edita — incluidas las
	#    mutaciones de set_prop), luego registry, luego disco.
	#    🚨 Si diéramos prioridad al registry, handle_save guardaría la copia
	#    stale (ej: script embebido) en vez de la pestaña real con ext_resource.
	if scene_path != "":
		# Rediseño 2026-08-15: SYNC ANTES de guardar. Si el disco cambió
		# (hand-edit del usuario), recargamos desde disco y re-aplicamos las
		# ops pendientes del agente (replay) — NUNCA machacamos el disco con
		# una copia stale. sync_from_disk devuelve el root fresco si hubo sync.
		var synced := HerenSceneRegistryScript.sync_from_disk(ei, scene_path)
		if synced != null:
			root = synced
			synced_root_had_sync = true
		else:
			var active := ei.get_edited_scene_root()
			if active != null and active.scene_file_path == scene_path:
				root = active
			else:
				root = HerenSceneRegistryScript.get_root(scene_path)
				if root == null and ResourceLoader.exists(scene_path):
					ei.open_scene_from_path(scene_path)
					root = ei.get_edited_scene_root()

	# 2) Sin scene_path → COMMIT INTELIGENTE:
	#    a) Escena dirty más reciente del registry (editada por MCP)
	#    b) Pestaña activa (fallback)
	if root == null:
		# a) Buscar escena dirty en registry (la más reciente).
		var dirty_path := HerenSceneRegistryScript.most_recent_dirty()
		if dirty_path != "":
			var synced := HerenSceneRegistryScript.sync_from_disk(ei, dirty_path)
			if synced != null:
				root = synced
				synced_root_had_sync = true
				scene_path = dirty_path
			else:
				root = HerenSceneRegistryScript.get_root(dirty_path)
				if root != null:
					scene_path = dirty_path
	#    b) Fallback: pestaña activa.
	if root == null:
		root = ei.get_edited_scene_root()
		if root != null:
			scene_path = root.scene_file_path

	if root == null:
		return {"ok": false, "error": "no scene to save"}
	if scene_path == "":
		return {"ok": false, "error": "scene has no scene_file_path; pass scene_path"}

	# 3) Pack directo + owners garantizados + disco.
	#    🚨 SIN FLAG_BUNDLE_RESOURCES: esa flag INCORPORA los recursos externos
	#    (scripts .gd con resource_path) dentro del .tscn como sub_resource —
	#    el bug "save embebe scripts". Los recursos inline SIN path se guardan
	#    vía resource_local_to_scene (ensure_resource_local_recursive).
	_ensure_parent_dir(scene_path)
	HerenCoordsScript.ensure_owner_recursive(root)
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, scene_path)
	if err != OK:
		return {"ok": false, "error": "save_failed: " + error_string(err)}

	var efs: EditorFileSystem = ei.get_resource_filesystem()
	if efs:
		efs.update_file(scene_path)
	# BUG 2 fix: actualizar mtime registrado después de guardar.
	HerenSceneRegistryScript.update_mtime(scene_path)
	# Rediseño 2026-08-15: tras guardar exitoso, limpiar ops pendientes.
	# SOLO reportamos replay_skipped si hubo sync real con el disco y alguna
	# op no se pudo re-aplicar. Si NO hubo divergencia (sync devolvió null),
	# el árbol guardado ya incluye las ops → limpiar silenciosamente.
	# 🚨 FIX 2026-08-15: sin esta guarda, un save normal reportaba
	# `replay_skipped` falso (la op sí estaba en el árbol guardado).
	var skipped: Array = []
	if synced_root_had_sync:
		skipped = HerenSceneRegistryScript.get_pending_ops(scene_path)
	HerenSceneRegistryScript.clear_ops(scene_path)
	var result := {"ok": true, "saved": true, "saved_to": scene_path}
	if skipped.size() > 0:
		result["replay_skipped"] = skipped
		result["note"] = "algunas ops del agente no se re-aplicaron tras sync con disco — re-hacerlas manualmente"
	# Coords estructurados del root tras save — confirma al agente que el
	# state guardado coincide con lo que vio (position/rotation/scale).
	if root != null:
		result["coords"] = HerenCoordsScript.coords_of_node(root, "", 2)
		result["child_count"] = root.get_child_count()
	return result


func handle_open(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "editor interface unavailable"}
	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path == "":
		return {"ok": false, "error": "scene_path required"}
	if not ResourceLoader.exists(scene_path):
		return {"ok": false, "error": "scene_not_found: " + scene_path}
	# P0.1 (2026-09-03): open_scene_from_path es DEFERRED en Godot 4
	# (issue #13816). Si retornamos ok:true en el mismo frame, el agente ve
	# la pestaña anterior. Esperamos 2 frames para garantizar que la pestaña
	# activa SÍ es la nueva, y verificamos scene_file_path antes de confirmar.
	ei.open_scene_from_path(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame
	var opened := ei.get_edited_scene_root()
	if opened == null or opened.scene_file_path != scene_path:
		return {
			"ok": false,
			"error": "open_failed: editor kept previous scene as active (path=" + scene_path + ")",
			"current_active": (opened.scene_file_path if opened != null else ""),
		}
	HerenSceneRegistryScript.register(scene_path, opened)
	# Fase 1: open adquiere lock automáticamente (agent_id="default" si no viene).
	var agent_id: String = str(args.get("agent_id", "default"))
	var mode: String = str(args.get("mode", "isolated"))
	var lock_result := HerenSceneRegistryScript.acquire_lock(scene_path, agent_id, mode)
	if not lock_result.get("ok", false):
		return {
			"ok": false,
			"error": "scene_locked_by_other_agent",
			"existing_agent_id": lock_result.get("existing_agent_id", ""),
			"existing_pid": lock_result.get("existing_pid", 0),
			"existing_since": lock_result.get("existing_since", ""),
		}
	return {
		"ok": true,
		"opened": scene_path,
		"root_name": opened.name,
		"root_type": opened.get_class(),
		# Coords estructurados del root — el agente las usa para verificar
		# el state tras open (en lugar de un get_info extra).
		"coords": HerenCoordsScript.coords_of_node(opened, "", 2),
		"lock_id": lock_result.get("lock_id", ""),
		"mode": lock_result.get("mode", "isolated"),
	}


## BUG 4 fix: unload cierra la escena del registry y del editor.
func handle_unload(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "editor interface unavailable"}
	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path == "":
		return {"ok": false, "error": "scene_path required"}
	# Quitar del registry.
	HerenSceneRegistryScript.unregister(scene_path)
	HerenSceneRegistryScript.release_lock(scene_path)
	# Cerrar la pestaña del editor si está abierta. Godot 4 NO expone API
	# pública para cerrar pestañas — el workaround es recargar la escena
	# vacía del usuario, pero eso es invasivo. En lugar de mentir con
	# ok:true ciego, reportamos honestamente: registry limpio, pestaña
	# sigue abierta (el usuario debe cerrarla manualmente o scene/open en
	# otra escena).
	var open_scenes := ei.get_open_scenes()
	var tab_still_open := scene_path in open_scenes
	return {
		"ok": true,
		"unloaded": scene_path,
		"registry_cleared": true,
		"tab_still_open": tab_still_open,
		"hint": "tab_still_open=true → Godot 4 no permite cerrar pestañas por API; ciérrala manualmente o abre otra escena" if tab_still_open else "",
	}


# ============================================================
# Fase 1: handlers de planning (state vive en HerenSceneRegistry)
# ============================================================

## scene/plan — escribe el ScenePlan JSON al registry del plugin.
## El agent_id del lock debe coincidir (o no haber lock).
func handle_plan(args: Dictionary) -> Dictionary:
	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path == "":
		return {"ok": false, "error": "scene_path required"}
	# Verificar lock (si lo hay) — agent_id debe coincidir.
	var lock := HerenSceneRegistryScript.get_lock(scene_path)
	if not lock.is_empty():
		var caller_agent: String = str(args.get("agent_id", "default"))
		if lock.get("agent_id", "default") != caller_agent:
			return {"ok": false, "error": "scene_locked_by_other_agent",
				"existing_agent_id": lock.get("agent_id", "")}
	var plan: Dictionary = args.get("plan", {})
	if typeof(plan) != TYPE_DICTIONARY or plan.is_empty():
		return {"ok": false, "error": "plan must be a non-empty Dictionary"}
	return HerenSceneRegistryScript.write_plan(scene_path, plan)


## scene/get_plan — devuelve el ScenePlan JSON. Usado por el server para
## ejecutar el coder/validator pure-logic.
func handle_get_plan(args: Dictionary) -> Dictionary:
	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path == "":
		return {"ok": false, "error": "scene_path required"}
	var plan: Dictionary = HerenSceneRegistryScript.get_plan(scene_path)
	return {"ok": true, "plan": plan, "has_plan": not plan.is_empty()}


## scene/set_qa_report — guarda el QAReport de la última validación.
func handle_set_qa_report(args: Dictionary) -> Dictionary:
	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path == "":
		return {"ok": false, "error": "scene_path required"}
	var report: Dictionary = args.get("qa_report", {})
	HerenSceneRegistryScript.write_qa_report(scene_path, report)
	return {"ok": true}


## scene/get_qa_report — devuelve el último QAReport.
func handle_get_qa_report(args: Dictionary) -> Dictionary:
	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path == "":
		return {"ok": false, "error": "scene_path required"}
	var qa: Dictionary = HerenSceneRegistryScript.get_qa_report(scene_path)
	return {"ok": true, "qa_report": qa}


## scene/status — devuelve el status completo de una escena (Fase 1: fuente plugin).
func handle_status(args: Dictionary) -> Dictionary:
	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path == "":
		# Sin scene_path → listar todas las escenas con plan registrado.
		return {"ok": true, "scenes": HerenSceneRegistryScript.list_scenes()}
	if scene_path == "":
		return {"ok": false, "error": "scene_path required"}
	return {"ok": true, "status": HerenSceneRegistryScript.status_of(scene_path)}


## scene/list — alias para status sin scene_path. Mantiene compat con la API vieja.
func handle_list(args: Dictionary) -> Dictionary:
	return {"ok": true, "scenes": HerenSceneRegistryScript.list_scenes()}


## scene/commit — guarda la escena al disco y libera el lock.
## Fase 1: el commit es responsabilidad del plugin (atomic save + lock release).
func handle_commit(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "editor interface unavailable"}
	var scene_path: String = str(args.get("scene_path", ""))
	if scene_path == "":
		return {"ok": false, "error": "scene_path required"}
	# Si no debe guardar (save=false) Y hay cambios dirty, error accionable.
	var save: bool = bool(args.get("save", true))
	var dirty := HerenSceneRegistryScript.is_dirty(scene_path)
	if not save and dirty:
		return {
			"ok": false,
			"error": "scene_has_uncommitted_changes",
			"hint": "pasa save=true para persistir, o scene(action='open') de nuevo para descartar",
		}
	if save:
		# Guardar la escena activa si coincide, o buscar la pestaña.
		var root := HerenSceneRegistryScript.resolve_root(ei, scene_path)
		if root == null:
			return {"ok": false, "error": "scene_not_resolvable: " + scene_path}
		var packed := PackedScene.new()
		var err := packed.pack(root)
		if err != OK:
			return {"ok": false, "error": "pack_failed: " + str(err)}
		var save_err := ResourceSaver.save(packed, scene_path, ResourceSaver.FLAG_COMPRESS)
		if save_err != OK:
			return {"ok": false, "error": "save_failed: " + str(save_err)}
		HerenSceneRegistryScript.update_mtime(scene_path)
	# Liberar lock.
	var released := HerenSceneRegistryScript.release_lock(scene_path)
	# Limpiar state de planning (plan + qa) tras commit exitoso.
	HerenSceneRegistryScript.write_plan(scene_path, {})
	HerenSceneRegistryScript.write_qa_report(scene_path, {})
	return {
		"ok": true,
		"saved": save,
		"scene_path": scene_path,
		"lock_released": released,
	}


func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		print("[HEREN] _editor_plugin is NULL in handler")
		return null
	var ei: EditorInterface = _editor_plugin.get_editor_interface()
	if ei == null:
		print("[HEREN] get_editor_interface() returned NULL")
	return ei


func _ensure_parent_dir(path: String) -> void:
	var dir_path := path.get_base_dir()
	if dir_path != "" and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))


## Normaliza un scene_path a la forma canónica de Godot (res://, forward
## slashes, sin trailing). El server ya normaliza; esta es defensa en el
## plugin para que la key del SceneRegistry SIEMPRE coincida con el
## scene_file_path de la pestaña (fix 2026-08-06: paths crudos del agente
## rompían el match → escena fantasma divergente).
func _normalize_scene_path(path: String) -> String:
	var s := path.strip_edges()
	if s == "":
		return ""
	s = s.replace("\\", "/")
	while s.ends_with("/"):
		s = s.substr(0, s.length() - 1)
	if s.begins_with("res:/") and not s.begins_with("res://"):
		return "res://" + s.substr(5)
	if not s.begins_with("res://"):
		return "res://" + s
	return s
