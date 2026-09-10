@tool
extends "res://addons/heren/handlers/heren_handler.gd"
# Heren MCP v4 - Visual handlers (Fase 3 §13.6, simplificado tras §0.11).
# "Ojos con JSON": jerarquía de costo (coords → ascii → summary → spatial).
#
# NIVEL 0: scene_coords  -> mapa textual de coordenadas {nodo: {pos, bbox, parent}}
# NIVEL 1: scene_summary -> snapshot recursivo (Fase D): node_count, by_type,
#                       tree_depth, bounds_2d/3d, warnings (z_fighting, etc.)
#          scene_ascii   -> árbol ASCII de la escena
# NIVEL 1.5: scene_spatial -> cálculos derivados (Fase B):
#                       overlaps / distance / neighbors / layout / bounds.
#
# Sin captura de imagen (visual_image/* ELIMINADO en §0.11 — el LLM no razona
# bien sobre PNGs renderizados, 800 tok vs 50-200 tok JSON, falla en play).
# Si el usuario humano quiere ver la escena, abre Godot visualmente.

const HerenCoordsScript := preload("coords.gd")
const HerenSceneRegistryScript := preload("../scene_registry.gd")
const HerenSpatialToolScript := preload("visual_tool/spatial_tool.gd")


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_editor_interface()


func _args_dict(args: Dictionary, key: String) -> Dictionary:
	var raw: Variant = args.get(key, {})
	if raw is Dictionary:
		return raw
	if raw is String:
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
	return {}


# ---------------------------------------------------------------- utils

func _root_node() -> Node:
	var ei := _editor_interface()
	if ei == null:
		return null
	return ei.get_edited_scene_root()


func _scene_root(args: Dictionary = {}) -> Node:
	var ei := _editor_interface()
	if ei == null:
		return null
	# Registry (escena creada por MCP en memoria) → pestaña → disco.
	return HerenSceneRegistryScript.resolve_root(ei, str(args.get("scene_path", "")))


func _path_relative(node: Node, root: Node) -> String:
	if node == root:
		return "."
	var path := node.get_path_to(root) if root else node.get_path()
	return str(path)


func _walk(node: Node, root: Node, out: Dictionary, depth: int, max_depth: int, tier: int = 1) -> void:
	if max_depth >= 0 and depth > max_depth:
		return
	# Fase A: coords unificadas — fuente única HerenCoords.coords_of_node.
	# El entry expone solo los campos que NIVEL 0 necesita en el mapa textual;
	# si el agente quiere más detalle (modulate, anchors, effective_rect),
	# llama a node_query/get_info o coords_of_node con tier=2.
	# Fase C: tier>=3 → añade bloque `dynamic` opt-in (animation/light/audio/camera/skeleton
	# summary). tier=4 → full (todas las poses, params completos).
	var coords := HerenCoordsScript.coords_of_node(node, _path_relative(node, root), tier)
	var entry: Dictionary = {
		"type": coords.get("kind", node.get_class()),
		"pos": coords.get("pos", {}),
	}
	if coords.has("bbox"):
		entry["bbox"] = coords["bbox"]
	if coords.has("dynamic"):
		entry["dynamic"] = coords["dynamic"]
	out[_path_relative(node, root)] = entry
	for child in node.get_children():
		_walk(child, root, out, depth + 1, max_depth, tier)


# ---------------------------------------------------------------- NIVEL 0: coords

func handle_scene_coords(args: Dictionary) -> Dictionary:
	# P0.2 (2026-09-03): usar _scene_root(args) para honrar scene_path del args
	# (antes _root_node ignoraba scene_path → retornaba pestaña activa incorrecta).
	# Fase C (2026-09-04): tier opt-in. tier=1 default (mapa visual barato);
	# tier=3 → añade bloque `dynamic` (resumen) por nodo; tier=4 → completo.
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var max_depth: int = int(args.get("max_depth", -1))
	var tier: int = int(args.get("tier", 1))
	var out := {}
	_walk(root, root, out, 0, max_depth, tier)
	return {"ok": true, "root": root.name, "node_count": out.size(), "coords": out}


# ---------------------------------------------------------------- NIVEL 1: summary + ascii

func handle_scene_summary(args: Dictionary) -> Dictionary:
	# Fase D (§0.11): delega a spatial_tool.summary (recursivo + bounds + warnings).
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	return HerenSpatialToolScript.summary(root)


func handle_scene_ascii(args: Dictionary) -> Dictionary:
	# P0.2 (2026-09-03): _scene_root(args) — soportar scene_path explícito.
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	var max_depth: int = int(args.get("max_depth", -1))
	var lines: Array[String] = []
	var build := _ascii_build.bind(lines, max_depth)
	build.call(root, "", true, 0)
	return {"ok": true, "ascii": "\n".join(lines)}


# ---------------------------------------------------------------- NIVEL 1.5: spatial (Fase B)
# Cálculos derivados sobre el sistema unificado de coordenadas (Fase A):
# overlaps / distance / neighbors / layout / bounds.

func handle_scene_spatial(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}
	return HerenSpatialToolScript.compute(root, args)


func _ascii_build(node: Node, prefix: String, is_last: bool, depth: int, lines: Array[String], max_depth: int) -> void:
	if max_depth >= 0 and depth > max_depth:
		return
	var branch := "└─ " if is_last else "├─ "
	lines.append(prefix + branch + node.name + " [" + node.get_class() + "]")
	var children := node.get_children()
	for i in children.size():
		var last := i == children.size() - 1
		var next_prefix := prefix + ("    " if is_last else "│   ")
		_ascii_build(children[i], next_prefix, last, depth + 1, lines, max_depth)
