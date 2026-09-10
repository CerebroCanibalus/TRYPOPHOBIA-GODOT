@tool
extends "res://addons/heren/handlers/heren_handler.gd"
# Heren MCP v4 - ARCHIVADO 2026-09-09 (§0.12 W4 cleanup).
# TileMap handlers completos. Reemplazados por scene_script workers.
#
# Para restaurar, ver addons/heren/archive/handlers/README.md.

# Actions (heredadas de v3 tilemap_tool.py + daemon project_ops, adaptadas):
#   inspect_set -> fuentes del TileSet (atlas: textura, grid, márgenes)
#   inspect_map -> capas + celdas usadas del TileMap
#   set_cell    -> set_cell en layer/coords/source/atlas/alternative
#   terrain     -> set_cells_terrain_connect (autoconnect peering)
#   pattern     -> get_pattern desde región + add_pattern al TileSet
#
# NOTA: en Godot 4.x el TileMap "clásico" se usa para edición; el editor real
# prefiere TileMapLayer. Mantenemos TileMap para compat con v3. El TileMap
# debe estar en la escena viva; el TileSet puede ser recurso externo o
# propiedad del nodo.

const HerenCoordsScript := preload("coords.gd")
const HerenSceneRegistryScript := preload("../scene_registry.gd")



func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_editor_interface()


func _scene_root(args: Dictionary = {}) -> Node:
	var ei := _editor_interface()
	if ei == null:
		return null
	# Registry (escena creada por MCP en memoria) → pestaña → disco.
	return HerenSceneRegistryScript.resolve_root(ei, str(args.get("scene_path", "")))


func _resolve_node(root: Node, node_path: Variant) -> Node:
	if root == null or node_path == null:
		return null
	var normalized := HerenCoordsScript.normalize_node_path(node_path, root)
	if normalized == ".":
		return root
	if normalized == "":
		return null
	return root.get_node_or_null(NodePath(normalized))


func _args_dict(args: Dictionary, key: String) -> Dictionary:
	var raw: Variant = args.get(key, {})
	if raw is Dictionary:
		return raw
	if raw is String:
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
	return {}


func _vec2i_from_dict(d: Dictionary) -> Vector2i:
	return Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))


# ---------------------------------------------------------------- handlers

func handle_inspect_set(args: Dictionary) -> Dictionary:
	var tileset_path: String = str(args.get("tileset_path", ""))
	if tileset_path == "":
		return {"ok": false, "error": "tileset_path required"}
	if not ResourceLoader.exists(tileset_path):
		return {"ok": false, "error": "tileset_not_found: " + tileset_path}

	var tileset: Resource = load(tileset_path)
	if tileset == null or not tileset is TileSet:
		return {"ok": false, "error": "invalid_tileset: " + tileset_path}
	var ts := tileset as TileSet

	var sources: Array = []
	for i in range(ts.get_source_count()):
		var source_id := ts.get_source_id(i)
		var source := ts.get_source(source_id)
		var info := {"id": source_id, "type": source.get_class()}

		if source is TileSetAtlasSource:
			var atlas := source as TileSetAtlasSource
			info["texture"] = atlas.texture.resource_path if atlas.texture else ""
			info["margins"] = {"x": atlas.margins.x, "y": atlas.margins.y}
			info["separation"] = {"x": atlas.separation.x, "y": atlas.separation.y}
			info["texture_region_size"] = {"x": atlas.texture_region_size.x, "y": atlas.texture_region_size.y}
			if atlas.texture:
				var tex_size := atlas.texture.get_size()
				var cols := 0
				var rows := 0
				if atlas.texture_region_size.x > 0 and atlas.texture_region_size.y > 0:
					cols = int((tex_size.x - atlas.margins.x + atlas.separation.x) / (atlas.texture_region_size.x + atlas.separation.x))
					rows = int((tex_size.y - atlas.margins.y + atlas.separation.y) / (atlas.texture_region_size.y + atlas.separation.y))
				info["grid"] = {"cols": cols, "rows": rows}

		var terrains: Array = []
		for t in range(ts.get_terrain_sets_count()):
			terrains.append({
				"set": t,
				"name": ts.get_terrain_set_name(t),
			})
		if not terrains.is_empty():
			info["terrains"] = terrains
		sources.append(info)

	return {"ok": true, "tileset_path": tileset_path, "source_count": ts.get_source_count(), "sources": sources}


func handle_inspect_map(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var tilemap := _resolve_node(root, args.get("tilemap_path", "")) as TileMap
	if tilemap == null:
		return {"ok": false, "error": "tilemap_not_found"}

	var layers: Array = []
	for i in range(tilemap.get_layers_count()):
		layers.append({
			"index": i,
			"name": tilemap.get_layer_name(i),
			"enabled": tilemap.is_layer_enabled(i),
		})

	var used_cells: Array = []
	for i in range(tilemap.get_layers_count()):
		for cell in tilemap.get_used_cells(i):
			var atlas_coords := tilemap.get_cell_atlas_coords(i, cell)
			used_cells.append({
				"layer": i,
				"x": cell.x,
				"y": cell.y,
				"atlas_x": atlas_coords.x,
				"atlas_y": atlas_coords.y,
			})

	return {
		"ok": true,
		"tilemap_path": tilemap.name,
		"layers_count": tilemap.get_layers_count(),
		"layers": layers,
		"used_cells_count": used_cells.size(),
		"used_cells": used_cells,
		"tile_set": tilemap.tile_set.resource_path if tilemap.tile_set else "",
	}


func handle_set_cell(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var tilemap := _resolve_node(root, args.get("tilemap_path", "")) as TileMap
	if tilemap == null:
		return {"ok": false, "error": "tilemap_not_found"}

	var layer: int = int(args.get("layer", 0))
	var coords := _vec2i_from_dict(_args_dict(args, "coords"))
	var atlas_coords := _vec2i_from_dict(_args_dict(args, "atlas_coords"))
	var source_id: int = int(args.get("source_id", 0))
	var alternative_tile: int = int(args.get("alternative_tile", 0))

	if tilemap.get_layers_count() <= layer:
		return {"ok": false, "error": "layer_out_of_range: " + str(layer)}

	tilemap.set_cell(layer, coords, source_id, atlas_coords, alternative_tile)
	# FAIL-FAST (2026-09-03): set_cell falla silenciosamente si source_id no
	# existe en el TileSet. Verificar leyendo get_cell_source_id.
	var actual_source: int = tilemap.get_cell_source_id(layer, coords)
	if source_id != 0 and actual_source != source_id:
		var valid_ids := []
		for s in tilemap.tile_set.get_source_count():
			valid_ids.append(tilemap.tile_set.get_source_id(s))
		return {
			"ok": false,
			"error": "set_cell_failed: source_id=%d no existe en TileSet" % source_id,
			"hint": "source_ids disponibles: %s" % str(valid_ids),
		}
	return {"ok": true, "position": {"x": coords.x, "y": coords.y}, "atlas": {"x": atlas_coords.x, "y": atlas_coords.y}, "verified": true}


func handle_terrain(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var tilemap := _resolve_node(root, args.get("tilemap_path", "")) as TileMap
	if tilemap == null:
		return {"ok": false, "error": "tilemap_not_found"}

	var layer: int = int(args.get("layer", 0))
	var terrain_set: int = int(args.get("terrain_set", 0))
	var terrain: int = int(args.get("terrain", 0))
	var cells: Array = args.get("cells", [])

	var positions: Array[Vector2i] = []
	for cell_data in cells:
		var d: Dictionary = cell_data if cell_data is Dictionary else {}
		positions.append(Vector2i(int(d.get("x", 0)), int(d.get("y", 0))))

	if positions.is_empty():
		return {"ok": false, "error": "cells required"}

	tilemap.set_cells_terrain_connect(layer, positions, terrain_set, terrain, true)
	# FAIL-FAST (2026-09-03): contar cuántas celdas quedaron realmente con el
	# terrain solicitado. Antes reportaba `applied: positions.size()` (input,
	# no output). get_cell_tile_data(layer, pos).terrain_set/terrain.
	var actually_applied := 0
	for pos in positions:
		var td := tilemap.get_cell_tile_data(layer, pos)
		if td != null and td.terrain_set == terrain_set and td.terrain == terrain:
			actually_applied += 1
	if actually_applied != positions.size():
		return {
			"ok": false,
			"error": "terrain_partial: %d/%d celdas aplicadas" % [actually_applied, positions.size()],
			"applied": actually_applied,
			"requested": positions.size(),
		}
	return {"ok": true, "applied": actually_applied, "terrain_set": terrain_set, "terrain": terrain, "verified": true}


func handle_pattern(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return {"ok": false, "error": "no scene open in editor"}

	var tilemap := _resolve_node(root, args.get("tilemap_path", "")) as TileMap
	if tilemap == null:
		return {"ok": false, "error": "tilemap_not_found"}
	if tilemap.tile_set == null:
		return {"ok": false, "error": "tilemap_has_no_tile_set"}

	var layer: int = int(args.get("layer", 0))
	var region := _args_dict(args, "region")
	var pattern_name: String = str(args.get("pattern_name", "Pattern"))

	var start := Vector2i(int(region.get("x", 0)), int(region.get("y", 0)))
	var size := Vector2i(int(region.get("w", 1)), int(region.get("h", 1)))

	var pattern: TileMapPattern = tilemap.get_pattern(layer, [start, start + size - Vector2i(1, 1)])
	if pattern == null:
		return {"ok": false, "error": "pattern_creation_failed"}

	var pattern_id := tilemap.tile_set.get_patterns_count()
	tilemap.tile_set.add_pattern(pattern, pattern_id)
	tilemap.tile_set.set_pattern_name(pattern_id, pattern_name)

	return {"ok": true, "pattern_id": pattern_id, "pattern_name": pattern_name, "size": {"w": size.x, "h": size.y}}
