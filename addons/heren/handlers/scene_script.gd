@tool
extends "res://addons/heren/handlers/heren_handler.gd"
# Heren MCP v4 — scene_script (W4, Plan Worker-First §0.12).
#
# El agente escribe un WORKER GDScript (@tool, extends RefCounted, func run(ctx))
# y nosotros lo ejecutamos contra la escena real con red de seguridad transaccional:
#
#   1. PARSE-CHECK previo (GDScript.reload → err 43 = fail-fast con diagnósticos)
#   2. Resolución de root (misma prioridad que todo: pestaña → registry → disco)
#   3. SNAPSHOT del .tscn a .heren/backup/ (W0)
#   4. Ejecución: worker.run(ctx)
#   5. Save SOLO si ctx.mark_modified() (worker que aborta a mitad → disco intacto)
#   6. POST-validación (validate/scene) — si falla → RESTAURAR snapshot
#   7. Receipt: ok + script_path + logs + outputs + changes + coords + validation
#
# Contrato del worker (fail-fast si no se cumple):
#   @tool
#   extends RefCounted
#   func run(ctx) -> void:
#
# ctx API:
#   get_scene_root() -> Node            get_scene_path() -> String
#   is_read_only() -> bool              set_scene_root(root)  (solo escenas nuevas, 1 vez)
#   own(node) -> bool                   (SOLO nodos raw; internals de PackedScene = RECHAZADO)
#   instance_scene(parent, path, name)  template(name, params, parent)
#   get_node_or_null(path)              find_nodes_by_name(name)
#   ensure_unique_child_name(p, n)      remove_node(path)  clear_children(node)
#   coords(node, tier) -> Dictionary    (sistema de coords §0.11 DENTRO del worker)
#   log(msg)  error(msg)  mark_modified()  output(key, value)
#   snapshot_subtree(path, tier)        (adjunta al receipt el árbol de un subpath)
#
# Modo inspect: instancia el PackedScene DETACHED (read-only), helpers de
# mutación rechazados, instancia liberada al terminar. NUNCA guarda.
#
# Límite documentado (convención, no sandbox): el GDScript arbitrario puede
# tocar filesystem/editor/OS — mismo modelo de confianza que Fennara. Los
# runtime errors de GDScript abortan run() silenciosamente (visibles en
# debug/output filter=error); el save transaccional es la red de seguridad.

const HerenCoordsScript := preload("coords.gd")
const HerenSceneRegistryScript := preload("../scene_registry.gd")
const HerenTemplateRegistry := preload("../template_registry.gd")
const ValidateHandlersScript := preload("validate_handlers.gd")

const WORKERS_DIR := "res://.heren/tmp/workers/"
const LIBRARY_DIR := "res://.heren/scripts/"
const MAX_LOGS := 100
const MAX_OUTPUTS := 32


# ============================================================
# WorkerCtx — el objeto ctx que recibe el worker
# ============================================================

class WorkerCtx extends RefCounted:
	var _handler: Node = null  # scene_script.gd (para save/coords/template)
	var _root: Node = null
	var _scene_path: String = ""
	var _read_only: bool = false
	var _modified: bool = false
	var _failed: bool = false
	var _error: String = ""
	var _logs: Array = []
	var _outputs: Dictionary = {}
	var _changes: Dictionary = {"added": [], "removed": [], "instanced": [], "templates": []}
	var _touched: Array = []  # Nodes tocados (para coords del receipt)
	var _snapshots: Array = []  # [{path, tier}] via ctx.snapshot_subtree(path, tier)
	var _root_set: bool = false

	func setup(handler: Node, root: Node, scene_path: String, read_only: bool) -> void:
		_handler = handler
		_root = root
		_scene_path = scene_path
		_read_only = read_only

	func get_scene_root() -> Node:
		return _root

	func get_scene_path() -> String:
		return _scene_path

	func is_read_only() -> bool:
		return _read_only

	## SOLO escenas nuevas (root null en disco): registra el root creado por
	## el worker. Una sola vez.
	func set_scene_root(root: Node) -> bool:
		if _read_only:
			_fail("set_scene_root rechazado en modo inspect (read-only)")
			return false
		if _root != null:
			_fail("set_scene_root: la escena ya tiene root — solo para escenas nuevas")
			return false
		if root == null or not (root is Node):
			_fail("set_scene_root: root requerido")
			return false
		_root = root
		_root_set = true
		_touched.append(root)
		return true

	## Ownership helper: SOLO nodos raw creados con .new(). RECHAZA nodos que
	## son (o están dentro de) instancias PackedScene — aplanarían la instancia.
	func own(node: Node) -> bool:
		if _read_only:
			_fail("own rechazado en modo inspect (read-only)")
			return false
		if node == null or not is_instance_valid(node):
			_fail("own: node inválido")
			return false
		if node == _root:
			return true  # el root no tiene owner
		# Walk-up: si entre node y _root hay un nodo con scene_file_path,
		# node es (o está dentro de) una instancia PackedScene → RECHAZADO.
		var n: Node = node
		while n != null and n != _root:
			if n.scene_file_path != "":
				_fail("own RECHAZADO: '%s' está dentro de la instancia PackedScene '%s' — usa ctx.instance_scene() para instanciar subescenas" % [n.name, n.scene_file_path])
				return false
			n = n.get_parent()
		if n != _root:
			_fail("own: node no está bajo el root de la escena")
			return false
		node.owner = _root
		_track("added", _relpath(node))
		if _touched.find(node) < 0:
			_touched.append(node)
		return true

	## Instancia una subescena de la forma CORRECTA: owner solo en el root de
	## la instancia (preserva el interior de la subescena en el .tscn guardado).
	func instance_scene(parent: Node, scene_path: String, desired_name: String) -> Node:
		if _read_only:
			_fail("instance_scene rechazado en modo inspect (read-only)")
			return null
		if parent == null or not is_instance_valid(parent):
			_fail("instance_scene: parent requerido")
			return null
		if not ResourceLoader.exists(scene_path):
			_fail("instance_scene: no existe " + scene_path)
			return null
		var packed: PackedScene = load(scene_path)
		if packed == null:
			_fail("instance_scene: no se pudo cargar " + scene_path)
			return null
		var inst: Node = packed.instantiate()
		if inst == null:
			_fail("instance_scene: instantiate falló para " + scene_path)
			return null
		inst.name = ensure_unique_child_name(parent, desired_name)
		parent.add_child(inst)
		inst.owner = _root  # SOLO el root de la instancia
		_track("instanced", _relpath(inst))
		if _touched.find(inst) < 0:
			_touched.append(inst)
		return inst

	## ★ Innovación Heren: templates transversales (health_bar, crosshair...)
	## disponibles DENTRO del worker. Semántica de instance_scene (owner solo
	## en el root del template). parent null → agrega al root de la escena.
	func template(template_name: String, params: Dictionary, parent: Node = null) -> Node:
		if _read_only:
			_fail("template rechazado en modo inspect (read-only)")
			return null
		var target: Node = parent if parent != null else _root
		if target == null:
			_fail("template: parent requerido (la escena aún no tiene root)")
			return null
		var inst: Node = _handler._instantiate_template(template_name, params)
		if inst == null:
			_fail("template: no existe o falló '" + template_name + "' (ver scene_script/list o ui/templates)")
			return null
		inst.name = ensure_unique_child_name(target, template_name)
		target.add_child(inst)
		inst.owner = _root
		_track("templates", _relpath(inst))
		if _touched.find(inst) < 0:
			_touched.append(inst)
		return inst

	func get_node_or_null(node_path: String) -> Node:
		if _root == null:
			return null
		return _root.get_node_or_null(NodePath(node_path))

	func find_nodes_by_name(node_name: String) -> Array:
		var out: Array = []
		if _root == null:
			return out
		_find_by_name(_root, node_name, out)
		return out

	func ensure_unique_child_name(parent: Node, desired_name: String) -> String:
		if parent == null or not is_instance_valid(parent):
			return desired_name
		var name := desired_name
		var idx := 1
		while parent.has_node(NodePath(name)):
			idx += 1
			name = "%s%d" % [desired_name, idx]
		return name

	func remove_node(node_path: String) -> bool:
		if _read_only:
			_fail("remove_node rechazado en modo inspect (read-only)")
			return false
		var node: Node = get_node_or_null(node_path)
		if node == null:
			_fail("remove_node: no existe " + node_path)
			return false
		if node == _root:
			_fail("remove_node: no se puede remover el root")
			return false
		var parent: Node = node.get_parent()
		parent.remove_child(node)
		node.queue_free()
		_track("removed", str(node_path))
		return true

	func clear_children(node: Node) -> bool:
		if _read_only:
			_fail("clear_children rechazado en modo inspect (read-only)")
			return false
		if node == null or not is_instance_valid(node):
			_fail("clear_children: node inválido")
			return false
		var children: Array = node.get_children()
		for child in children:
			if child is Node:
				node.remove_child(child)
				child.queue_free()
				_track("removed", _relpath(child))
		return true

	## ★ Innovación Heren: el sistema de coords (§0.11) consultable DENTRO
	## del worker. Pure 2D/3D + tiers garantizados por ADR-005.
	func coords(node: Node, tier: int = 1) -> Dictionary:
		if node == null:
			return {}
		return _handler._node_coords(node, _relpath(node), tier)

	func log(message: String) -> void:
		if _logs.size() < MAX_LOGS:
			_logs.append(str(message))

	func error(message: String) -> void:
		_failed = true
		_error = str(message)

	func mark_modified() -> void:
		if _read_only:
			_fail("mark_modified rechazado en modo inspect (read-only)")
			return
		_modified = true

	func output(key: String, value: Variant) -> void:
		if _outputs.size() < MAX_OUTPUTS:
			_outputs[key] = value

	## Adjunta al receipt un snapshot completo de un subárbol (tier configurable).
	## Útil para que el worker reporte "así quedó el personaje" sin que el agente
	## tenga que re-inspectar la escena entera. Coste acotado al subárbol.
	## Sin efecto en modo inspect.
	func snapshot_subtree(path: String, sub_tier: int = 1) -> bool:
		if _read_only:
			_fail("snapshot_subtree rechazado en modo inspect (read-only)")
			return false
		var n: Node = get_node_or_null(path)
		if n == null:
			_fail("snapshot_subtree: path no existe '" + path + "'")
			return false
		var rel: String = _relpath(n)
		_snapshots.append({"path": rel, "tier": sub_tier})
		return true

	# ------------------------------------------------------------ internals

	func _fail(msg: String) -> void:
		_failed = true
		if _error == "":
			_error = msg

	func _track(kind: String, detail: String) -> void:
		var arr: Array = _changes.get(kind, [])
		if arr.size() < 64:
			arr.append(detail)
			_changes[kind] = arr

	## Relpath manual (get_path() requiere SceneTree — NUNCA en detached).
## Convención unificada:
##   root → "."
##   hijo → "./X/Y/Z" (prefijo "./" para distinguir de paths absolutos)
##   fuera del root (huérfano) → nombre plano
## Mismo formato que _inspect_walk para que el agente vea paths consistentes
## entre changes.added[] y inspect.tree.
	func _relpath(node: Node) -> String:
		if node == _root:
			return "."
		var parts: Array = []
		var n: Node = node
		while n != null and n != _root:
			parts.push_front(str(n.name))
			n = n.get_parent()
		if n != _root:
			return str(node.name)  # fuera del root: nombre plano
		return "./" + "/".join(parts)

	func _find_by_name(node: Node, target: String, out: Array) -> void:
		if str(node.name) == target:
			out.append(node)
		for child in node.get_children():
			if child is Node:
				_find_by_name(child, target, out)


# ============================================================
# Handlers
# ============================================================

## scene_script/run — ejecuta el worker contra la escena.
func handle_run(args: Dictionary) -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "editor interface unavailable"}

	var code := str(args.get("code", ""))
	var script_path := str(args.get("script_path", ""))
	if code == "" and script_path == "":
		return {"ok": false, "error": "code o script_path requerido"}

	var mode := str(args.get("mode", "edit"))
	if mode != "edit" and mode != "inspect":
		return {"ok": false, "error": "mode debe ser edit|inspect"}
	var read_only := mode == "inspect"
	var do_save: bool = bool(args.get("save", true)) and not read_only
	var tier: int = int(args.get("tier", 2))

	# 1) Resolver fuente del worker (code → temp path; script_path → tal cual).
	var worker_path := script_path
	if code != "":
		worker_path = WORKERS_DIR + "worker_%d_%d.gd" % [Time.get_ticks_msec(), randi() % 10000]
		ensure_dir(worker_path)
		var f := FileAccess.open(worker_path, FileAccess.WRITE)
		if f == null:
			return {"ok": false, "error": "cannot_write_worker: " + worker_path}
		f.store_string(code)
		f = null
	else:
		if not FileAccess.file_exists(worker_path):
			return {"ok": false, "error": "not_found: " + worker_path + " — usa code para crear el worker, luego itera con script_path"}

	# 2) PARSE-CHECK previo (fail-fast — la escena ni se carga).
	# 🚨 Contrato de errores (W4): el fallo del WORKER no es fallo de la tool.
	# Se devuelve ok:true + ran:false + diagnósticos + script_path (el payload
	# sobrevive el transporte — el workflow de retry lo necesita). ok:false
	# queda reservado para fallos de infraestructura (sin editor, etc.).
	var gd_res: Resource = load(worker_path)
	if gd_res == null or not gd_res is Script:
		return {"ok": true, "ran": false, "error": "invalid_worker_script: " + worker_path, "script_path": worker_path}
	var gd: Script = gd_res as Script
	# 🚨 Cache de recursos: si el worker ya se cargó antes (retry tras parche),
	# load() devuelve el GDScript CACHED con el source VIEJO → reload()
	# recompilaría el código roto de siempre. Refrescar source desde disco.
	var fresh_src := FileAccess.get_file_as_string(worker_path)
	if fresh_src != "":
		gd.source_code = fresh_src
	var reload_err: int = gd.reload()
	if reload_err != OK:
		return {
			"ok": true,
			"ran": false,
			"error": "worker_has_errors reload_err=%d — parcha el MISMO script_path (resource/edit_script) y re-run; no reenvíes todo el code" % reload_err,
			"script_path": worker_path,
			"valid": false,
			"reload_err": reload_err,
		}
	if gd.get_instance_base_type() != "RefCounted":
		return {
			"ok": true,
			"ran": false,
			"error": "worker_contract: el worker debe ser 'extends RefCounted' (base actual: %s)" % gd.get_instance_base_type(),
			"script_path": worker_path,
		}

	# 3) Resolver root de la escena.
	var scene_path := str(args.get("scene_path", ""))
	var root: Node = null
	var scene_exists := false
	if read_only:
		if scene_path == "":
			return {"ok": false, "error": "scene_path requerido en modo inspect"}
		if not ResourceLoader.exists(scene_path):
			return {"ok": false, "error": "not_found: " + scene_path}
		var packed: PackedScene = load(scene_path)
		if packed == null:
			return {"ok": false, "error": "invalid_scene: " + scene_path}
		root = packed.instantiate()
		if root == null:
			return {"ok": false, "error": "instantiate_failed: " + scene_path}
		scene_exists = true
	else:
		if scene_path == "":
			root = ei.get_edited_scene_root()
			scene_path = root.scene_file_path if root != null else ""
			scene_exists = root != null and scene_path != ""
		elif ResourceLoader.exists(scene_path):
			root = HerenSceneRegistryScript.resolve_root(ei, scene_path)
			scene_exists = true
		# scene_path en disco inexistente → root null = flujo escena nueva.

	# 4) SNAPSHOT (W0) — solo si el archivo existe en disco.
	var snapshot := ""
	if not read_only and scene_exists and scene_path != "":
		snapshot = snapshot_file(scene_path)

	# 5) Ejecutar worker.run(ctx).
	var ctx := WorkerCtx.new()
	ctx.setup(self, root, scene_path, read_only)
	var worker: RefCounted = gd.new()
	if not worker.has_method("run"):
		if read_only and root != null:
			root.free()
		return {
			"ok": true,
			"ran": false,
			"error": "worker_contract: el worker debe definir func run(ctx) -> void",
			"script_path": worker_path,
		}
	# 🚨 Un runtime error DENTRO de run() aborta el callee silenciosamente
	# (el caller continúa). El save transaccional (mark_modified requerido)
	# es la red: si abortó antes de marcar, no se guarda nada.
	# call() en vez de .run() directo: dispatch dinámico sin warnings.
	worker.call("run", ctx)

	var receipt := {
		"ok": true,
		"ran": true,
		"script_path": worker_path,
		"mode": mode,
		"modified": ctx._modified,
		"logs": ctx._logs,
		"outputs": ctx._outputs,
		"changes": ctx._changes,
	}

	# 6) Resultado del worker: error explícito (ctx.error) → ran:false.
	if ctx._failed:
		receipt["ran"] = false
		receipt["error"] = ctx._error
		if read_only and root != null:
			root.free()
		return receipt

	# 7) Modo inspect: liberar instancia detached, NUNCA guardar.
	if read_only:
		if root != null:
			root.free()
		receipt["scene_saved"] = false
		receipt["coords"] = _receipt_coords(ctx, tier)
		return receipt

	# 8) Save transaccional: SOLO si el worker marcó modified.
	var scene_saved := false
	if ctx._modified and do_save:
		if root == null:
			receipt["ran"] = false
			receipt["error"] = "worker marcó modified pero no hay root — usa ctx.set_scene_root(root) para escenas nuevas"
			return receipt
		var save_result := _save_scene(root, scene_path)
		if not save_result.get("ok", false):
			# Rollback: restaurar snapshot (la escena original intacta).
			var restored := restore_snapshot(ei, snapshot, scene_path)
			receipt["ran"] = false
			receipt["error"] = str(save_result.get("error", "save_failed"))
			receipt["scene_saved"] = false
			receipt["snapshot_restored"] = restored
			return receipt
		scene_saved = true

		# 9) POST-validación — si falla, restaurar snapshot.
		var vres := _post_validate(scene_path)
		if not vres.get("ok", false) or not vres.get("valid", false):
			var restored := restore_snapshot(ei, snapshot, scene_path)
			receipt["ran"] = false
			receipt["error"] = "post_validation_failed: " + str(vres.get("error", "invalid scene"))
			receipt["scene_saved"] = false
			receipt["snapshot_restored"] = restored
			receipt["validation"] = vres
			return receipt
		receipt["validation"] = {"ok": true, "valid": true}

	receipt["scene_saved"] = scene_saved
	receipt["snapshot"] = snapshot
	receipt["coords"] = _receipt_coords(ctx, tier)
	if root != null:
		receipt["scene_node_count"] = _count_nodes(root)
	return receipt


## scene_script/list — workers guardados en res://.heren/scripts/ (memoria
## del proyecto: workers reutilizables que el agente persiste).
func handle_list(args: Dictionary) -> Dictionary:
	var out: Array = []
	_walk_gd(LIBRARY_DIR, out)
	return {"ok": true, "directory": LIBRARY_DIR, "count": out.size(), "workers": out}


## scene_script/inspect — W4b (§0.12) inspección READ-ONLY de la escena SIN
## ejecutar un worker. Devuelve árbol recursivo (tier 1 por defecto) con
## huesos, animaciones, materiales, luces y audio agregados para que el agente
## sepa QUÉ hay antes de escribir un worker. PackedScene instanciadas son
## opacas por defecto (sin expandir) — opt-in vía expand_scene (Array de
## paths a expandir, ej ["res://character.tscn"]).
##
## Costo típico: 50-200 tok por nodo en tier 1; tier 3 añade dynamic state
## (skeleton bones completos, animation tracks, light/audio params).
##
## Diferencia con mode="inspect" de handle_run: NO ejecuta código arbitrario;
## es una vista estática, instantánea y pura.
func handle_inspect(args: Dictionary) -> Dictionary:
	var scene_path := str(args.get("scene_path", ""))
	if scene_path == "":
		var ei0 := _editor_interface()
		var edited := ei0.get_edited_scene_root() if ei0 != null else null
		if edited != null and edited.scene_file_path != "":
			scene_path = edited.scene_file_path
	if scene_path == "":
		return {"ok": false, "error": "scene_path requerido (o escena abierta con scene_file_path)"}
	if not ResourceLoader.exists(scene_path):
		return {"ok": false, "error": "not_found: " + scene_path}
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return {"ok": false, "error": "invalid_scene: " + scene_path}
	var root: Node = packed.instantiate()
	if root == null:
		return {"ok": false, "error": "instantiate_failed: " + scene_path}

	var depth: int = int(args.get("depth", -1))  # -1 = ilimitado
	var tier: int = int(args.get("tier", 1))
	var expand_scenes: Array = args.get("expand_scene", [])
	var expand_set: Dictionary = {}
	for p in expand_scenes:
		expand_set[str(p)] = true

	# Tree recursivo (PackedScene como opacas salvo en expand_set).
	# El root NUNCA es opaco (el usuario pidió esa escena; sí entra a sus hijos).
	var tree: Array = []
	var opaques: Array = []
	tree.append(_inspect_walk(root, ".", tier, depth, 0, expand_set, opaques, true))

	# Agregados (cruzados, no por nodo — para que el agente los vea sin expandir).
	var aggr := _inspect_aggregates(root, tier)

	# Liberar instancia detached.
	root.free()

	# Top-level: scene_node_count = aggregates.node_count (el motor vive en
	# _inspect_aggregates; este campo es solo una alias para conveniencia).
	return {
		"ok": true,
		"scene_path": scene_path,
		"mode": "inspect",
		"tier": tier,
		"depth": depth,
		"expand_scene": expand_scenes,
		"opaque_packed_scenes": opaques,
		"root": tree[0],
		"aggregates": aggr,
		"scene_node_count": int(aggr.get("node_count", 0)),
	}


## Walk recursivo de un nodo: coord + children. depth<0 = ilimitado.
## Marca PackedScene como opacas salvo si su source está en expand_set.
## El ROOT (is_root=true) NUNCA es opaco: el usuario pidió esa escena y quiere
## ver sus hijos (los PackedScene que contiene son los que sí pueden ser opacos).
static func _inspect_walk(node: Node, relpath: String, tier: int, depth: int, cur_depth: int, expand_set: Dictionary, opaques: Array, is_root: bool = false) -> Dictionary:
	if node == null:
		return {"kind": "None"}
	var out: Dictionary = HerenCoordsScript.coords_of_node(node, relpath, tier)
	# El nombre del nodo va inline para que el agente lo lea sin mirar parent_path.
	out["name"] = str(node.name)
	# PackedScene como opaca (no expandir) salvo opt-in. El root se exenta.
	if not is_root and node.scene_file_path != "" and not expand_set.has(node.scene_file_path):
		var child_count := node.get_child_count()
		out["kind"] = "PackedScene"
		out["source"] = node.scene_file_path
		out["child_count"] = child_count
		out["expanded"] = false
		opaques.append(relpath)
		return out
	if depth >= 0 and cur_depth >= depth:
		out["children_truncated"] = true
		return out
	var children: Array = []
	var idx := 0
	for child in node.get_children():
		if child is Node:
			var child_relpath: String = relpath + "/" + str(child.name) if relpath != "." else "./" + str(child.name)
			children.append(_inspect_walk(child, child_relpath, tier, depth, cur_depth + 1, expand_set, opaques, false))
			idx += 1
	if children.size() > 0:
		out["children"] = children
	return out


## Agregados cruzados: skeleton bones, animation tracks, materials, lights,
## audio, cameras. Para que el agente vea QUÉ tiene la escena sin expandir.
static func _inspect_aggregates(root: Node, tier: int) -> Dictionary:
	var node_count := _count_nodes(root)
	var skeletons_3d: Array = []
	var skeletons_2d: Array = []
	var animations: Array = []
	var animation_trees: Array = []
	var materials: Array = []
	var lights: Array = []
	var audios: Array = []
	var cameras: Array = []
	var tiled_maps: Array = []
	_collect_into(root, ".", 0, -1, skeletons_3d, skeletons_2d, animations, animation_trees, materials, lights, audios, cameras, tiled_maps)
	return {
		"node_count": node_count,
		"skeletons_3d": skeletons_3d,
		"skeletons_2d": skeletons_2d,
		"animations": animations,
		"animation_trees": animation_trees,
		"materials": materials,
		"lights": lights,
		"audios": audios,
		"cameras": cameras,
		"tilemaps": tiled_maps,
	}


## Walk no recursivo en agg (lo hace _collect_into).
static func _collect_into(node: Node, relpath: String, depth: int, max_depth: int, sk3: Array, sk2: Array, anims: Array, trees: Array, mats: Array, lights: Array, auds: Array, cams: Array, tilemaps: Array) -> void:
	if node == null:
		return
	if node is Skeleton3D:
		var s: Skeleton3D = node
		var bones: Array = []
		var i := 0
		while i < s.get_bone_count():
			bones.append(str(s.get_bone_name(i)))
			i += 1
		sk3.append({"path": relpath, "bone_count": bones.size(), "bones": bones})
	if node is Skeleton2D:
		var s2: Skeleton2D = node
		var bones2: Array = []
		for b in s2.get_children():
			if b is Bone2D:
				bones2.append(str(b.name))
		sk2.append({"path": relpath, "bone_count": bones2.size(), "bones": bones2})
	if node is AnimationPlayer:
		var ap: AnimationPlayer = node
		var libs: Array = []
		for lib_name in ap.get_animation_list():
			var anim_res: Animation = ap.get_animation(lib_name)
			var length: float = 0.0
			if anim_res != null:
				length = anim_res.length
			libs.append({"name": lib_name, "length": length})
		anims.append({"path": relpath, "libraries": libs})
	if node is AnimationTree:
		var at: AnimationTree = node
		trees.append({
			"path": relpath,
			"anim_player": str(at.get_node_or_null(at.anim_player).name) if at.anim_player != NodePath("") and at.get_node_or_null(at.anim_player) != null else "",
			"active": at.active,
		})
	if node is MeshInstance3D or node is Sprite2D or node is Sprite3D:
		var mat_out: Array = []
		var overrides: int = 0
		if node is MeshInstance3D:
			overrides = (node as MeshInstance3D).get_surface_override_material_count()
		var mat_count: int = node.get_material_count() if node.has_method("get_material_count") else 0
		for m_idx in range(mat_count):
			var m_res: Material = null
			if node.has_method("get_material"):
				m_res = node.get_material(m_idx)
			if m_res != null:
				mat_out.append({"index": m_idx, "path": m_res.resource_path if m_res.resource_path != "" else "<inline>", "class": m_res.get_class()})
		if mat_out.size() > 0:
			mats.append({"path": relpath, "materials": mat_out, "override_count": overrides})
	if node is Light3D:
		var l: Light3D = node
		lights.append({"path": relpath, "class": node.get_class(), "light_color": HerenCoordsScript.serialize_value(Color(l.light_color.r, l.light_color.g, l.light_color.b, l.light_color.a) if "light_color" in l else Color.WHITE, true), "light_energy": l.light_energy, "enabled": l.light_enabled if "light_enabled" in l else true})
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		var stream = node.stream if "stream" in node else null
		auds.append({"path": relpath, "class": node.get_class(), "stream_path": stream.resource_path if stream != null else "", "playing": node.playing})
	if node is Camera3D or node is Camera2D:
		cams.append({"path": relpath, "class": node.get_class(), "current": node.current if "current" in node else false})
	if node is TileMap or node is TileMapLayer:
		tilemaps.append({"path": relpath, "class": node.get_class()})
	for child in node.get_children():
		if child is Node:
			var child_relpath: String = relpath + "/" + str(child.name) if relpath != "." else "./" + str(child.name)
			_collect_into(child, child_relpath, depth + 1, max_depth, sk3, sk2, anims, trees, mats, lights, auds, cams, tilemaps)


# ============================================================
# Internals
# ============================================================

## Instancia un template transversal (puente para WorkerCtx.template).
func _instantiate_template(template_name: String, params: Dictionary) -> Node:
	return HerenTemplateRegistry.instantiate(template_name, params)


## Coords vía el sistema único (ADR-005) — puente para WorkerCtx.coords.
func _node_coords(node: Node, parent_path: String, tier: int) -> Dictionary:
	return HerenCoordsScript.coords_of_node(node, parent_path, tier)


## Coords del receipt: root (tier completo) + nodos tocados (tier 1).
## W4b: también agrega aggregates (skeleton bones, animations, materials, etc.)
## y subtrees solicitados via ctx.snapshot_subtree(path, tier).
## El tier efectivo sube a 3 automáticamente si el worker tocó un nodo
## "dynamic" (Skeleton3D, AnimationPlayer, AnimationTree, Light3D, audio,
## camera) — el agente ve los huesos/animaciones resultantes sin re-inspect.
func _receipt_coords(ctx: WorkerCtx, tier: int) -> Dictionary:
	var out := {}
	if ctx._root == null or not is_instance_valid(ctx._root):
		return out
	var effective_tier: int = tier
	if _touched_dynamic(ctx):
		effective_tier = maxi(effective_tier, 3)
	# Root coord (tier efectivo).
	out["root"] = HerenCoordsScript.coords_of_node(ctx._root, "", effective_tier)
	# Touched (siempre tier 1 para no explotar tokens — el agente quiere saber QUÉ).
	var touched: Array = []
	for node in ctx._touched:
		if is_instance_valid(node):
			touched.append(ctx._relpath(node))
	if touched.size() > 0:
		out["touched"] = touched
	# Agregados (skeleton bones, animations, materials, lights, audios, cameras).
	out["aggregates"] = _inspect_aggregates(ctx._root, effective_tier)
	# Subtrees solicitados via ctx.snapshot_subtree(path, tier).
	if ctx._snapshots.size() > 0:
		var subtrees: Array = []
		var expand_set: Dictionary = {}
		var opaques: Array = []
		for s in ctx._snapshots:
			var sp: String = str(s.get("path", ""))
			var st: int = int(s.get("tier", 1))
			var n: Node = ctx._root.get_node_or_null(NodePath(sp)) if sp != "" else ctx._root
			if n == null:
				continue
			subtrees.append({
				"path": sp,
				"tier": st,
				"tree": _inspect_walk(n, sp if sp != "" else ".", st, -1, 0, expand_set, opaques, sp == ""),
			})
		out["subtrees"] = subtrees
	return out


## Detecta si el worker tocó un nodo con estado dinámico (skeleton, anim,
## light, audio, camera). True = sube el tier del receipt a 3 para que
## el agente vea el estado resultante sin re-inspectar.
static func _touched_dynamic(ctx: WorkerCtx) -> bool:
	for n in ctx._touched:
		if not is_instance_valid(n):
			continue
		if n is Skeleton3D or n is Skeleton2D:
			return true
		if n is AnimationPlayer or n is AnimationTree:
			return true
		if n is Light3D:
			return true
		if n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is AudioStreamPlayer3D:
			return true
		if n is Camera3D or n is Camera2D:
			return true
	return false


## Save con el MISMO patrón que scene_handlers.handle_save (pack + ResourceSaver,
## SIN FLAG_BUNDLE_RESOURCES — ver §10 "Save no re-embebe scripts").
func _save_scene(root: Node, scene_path: String) -> Dictionary:
	if scene_path == "":
		return {"ok": false, "error": "scene has no scene_file_path; pasa scene_path"}
	ensure_dir(scene_path)
	HerenCoordsScript.ensure_owner_recursive(root)
	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		return {"ok": false, "error": "pack_failed: " + error_string(pack_err)}
	var err := ResourceSaver.save(packed, scene_path)
	if err != OK:
		return {"ok": false, "error": "save_failed: " + error_string(err)}
	var ei := _editor_interface()
	if ei != null:
		var efs: EditorFileSystem = ei.get_resource_filesystem()
		if efs:
			efs.update_file(scene_path)
	HerenSceneRegistryScript.update_mtime(scene_path)
	return {"ok": true, "saved_to": scene_path}


## Post-validación estructural (validate/scene): load + instantiate + free.
func _post_validate(scene_path: String) -> Dictionary:
	var vh := ValidateHandlersScript.new()
	vh.set_editor_plugin(_editor_plugin)
	var res := vh.handle_scene({"scene_path": scene_path})
	vh.free()
	return res


static func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		if child is Node:
			count += _count_nodes(child)
	return count


func _walk_gd(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		var full := dir_path.path_join(fname)
		if dir.current_is_dir():
			_walk_gd(full, out)
		elif fname.ends_with(".gd"):
			out.append(full)
		fname = dir.get_next()
	dir.list_dir_end()
