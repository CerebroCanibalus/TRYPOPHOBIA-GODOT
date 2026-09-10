@tool
extends "res://addons/heren/handlers/heren_handler.gd"

## Heren MCP v4 — filesystem (W4b §0.12, 2026-09-09).
##
## Tool única que cubre el gap del EditorFileSystem: scan() completo con espera
## al resultado (resuelve el bug EFS en frío de E2E Omega), status recursivo,
## import_errors del EFS, exists batch, y reimport puntual.
##
## Diseño: 5 acciones detrás de 1 tool (regla §6: "1 tool N acciones").
## Patrón: forward() — no forward_mutating (EFS no marca escenas dirty).

const MOD := "HerenFSHandler"


func _efs() -> EditorFileSystem:
	var ei := _editor_interface()
	if ei == null:
		return null
	return ei.get_resource_filesystem()


## filesystem/scan — fuerza un rescan del EFS y espera a is_scanning()=false.
## Args: timeout_seconds (default 30). Devuelve {ok, scanned, duration_s, timed_out}.
func handle_scan(args: Dictionary) -> Dictionary:
	var efs := _efs()
	if efs == null:
		return _err("editor_required: EditorFileSystem no disponible (headless?)")
	efs.scan()
	var timeout: float = float(args.get("timeout_seconds", 30.0))
	return await _wait_scan(efs, timeout)


## filesystem/status — snapshot rápido: scanning + file_count recursivo.
## (Godot 4.5/4.7 no expone get_scan_progress() en EditorFileSystem — usamos
## is_scanning() como señal booleana suficiente.)
func handle_status(_args: Dictionary) -> Dictionary:
	var efs := _efs()
	if efs == null:
		return _err("editor_required: EditorFileSystem no disponible")
	var root := efs.get_filesystem()
	var count := 0
	if root != null:
		count = _count_files_recursive(root)
	return {
		"ok": true,
		"is_scanning": efs.is_scanning(),
		"file_count": count,
	}


## filesystem/import_errors — walk recursivo del EFS, lista archivos con errores.
## Args: max_items (default 100). Devuelve {ok, count, items[], truncated}.
func handle_import_errors(args: Dictionary) -> Dictionary:
	var efs := _efs()
	if efs == null:
		return _err("editor_required: EditorFileSystem no disponible")
	var max_items: int = int(args.get("max_items", 100))
	var root := efs.get_filesystem()
	var items: Array = []
	if root != null:
		_walk_import_errors(root, "", items, max_items)
	return {
		"ok": true,
		"count": items.size(),
		"items": items,
		"truncated": items.size() >= max_items,
	}


## filesystem/exists — batch existence check (FileAccess.file_exists para todo:
## ResourceLoader.exists ignora archivos sin .import, ej. plugin.cfg, .tres
## sueltos sin import). Args: paths: Array[String].
func handle_exists(args: Dictionary) -> Dictionary:
	var raw = args.get("paths", [])
	if not (raw is Array):
		return _err("paths must be Array[String]")
	var paths: Array = raw
	var results: Array = []
	for p in paths:
		var s := str(p)
		if s.is_empty():
			results.append({"path": "", "exists": false, "kind": "missing", "error": "empty_path"})
			continue
		var res_path := s
		if not (s.begins_with("res://") or s.begins_with("user://")):
			res_path = "res://" + s
		var exists := FileAccess.file_exists(res_path)
		var kind := "missing"
		if exists:
			# Distinguir resource vs raw text.
			if res_path.ends_with(".tscn") or res_path.ends_with(".scn"):
				kind = "packed_scene"
			elif res_path.ends_with(".gd"):
				kind = "script"
			elif res_path.ends_with(".tres"):
				kind = "resource"
			else:
				kind = "file"
		results.append({"path": s, "exists": exists, "kind": kind})
	return {"ok": true, "results": results, "count": results.size()}


## filesystem/import — reimporta un path puntual vía efs.update_file() y espera.
## Args: path (res://...), timeout_seconds (default 30).
func handle_import(args: Dictionary) -> Dictionary:
	var efs := _efs()
	if efs == null:
		return _err("editor_required: EditorFileSystem no disponible")
	var path := str(args.get("path", ""))
	if path.is_empty():
		return _err("path required (res://... o user://...)")
	if not (path.begins_with("res://") or path.begins_with("user://")):
		path = "res://" + path
	if not FileAccess.file_exists(path):
		return _err("file_not_on_disk: %s" % path)
	efs.update_file(path)
	var timeout: float = float(args.get("timeout_seconds", 30.0))
	var r := await _wait_scan(efs, timeout)
	r["path"] = path
	return r


# --------------------- helpers internos ---------------------

## Espera polling con frame awaits hasta is_scanning()=false o timeout.
func _wait_scan(efs: EditorFileSystem, timeout: float) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	while efs.is_scanning():
		await Engine.get_main_loop().process_frame
		var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
		if elapsed > timeout:
			return {
				"ok": true,
				"scanned": true,
				"duration_s": elapsed,
				"timed_out": true,
			}
	return {
		"ok": true,
		"scanned": true,
		"duration_s": (Time.get_ticks_msec() - t0) / 1000.0,
		"timed_out": false,
	}


## Cuenta archivos recursivamente. EFS.get_file_count() solo el nivel raíz.
func _count_files_recursive(dir) -> int:
	if dir == null:
		return 0
	var n := int(dir.get_file_count())
	var sd := int(dir.get_subdir_count())
	for i in sd:
		n += _count_files_recursive(dir.get_subdir(i))
	return n


## Walk recursivo de import_errors. Corta en max_items para evitar respuestas
## gigantes en proyectos con miles de archivos rotos.
func _walk_import_errors(dir, prefix: String, items: Array, max_items: int) -> void:
	if dir == null or items.size() >= max_items:
		return
	var sd := int(dir.get_subdir_count())
	for i in sd:
		if items.size() >= max_items:
			return
		var sub = dir.get_subdir(i)
		_walk_import_errors(sub, prefix + "/" + str(sub.get_name()), items, max_items)
	var fc := int(dir.get_file_count())
	for i in fc:
		if items.size() >= max_items:
			return
		var info_raw = dir.get_file(i)
		if not (info_raw is Dictionary):
			continue
		var info: Dictionary = info_raw
		var errs_v = info.get("import_errors", [])
		var errs: Array = []
		if errs_v is PackedStringArray:
			errs = Array(errs_v)
		elif errs_v is Array:
			errs = errs_v
		if errs.size() > 0:
			items.append({
				"path": prefix + "/" + str(info.get("file", "?")),
				"type": str(info.get("type", "")),
				"import_path": str(info.get("import_path", "")),
				"errors": errs,
			})
