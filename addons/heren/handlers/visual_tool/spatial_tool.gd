@tool
class_name HerenSpatialTool extends RefCounted

# Heren MCP v4 - Spatial calculations for visual_text(action="spatial", ...).
# Fase B de §0.11 — "cálculos derivados" sobre el sistema unificado de
# coordenadas (Fase A). Permite al agente verificar layout/overlaps/distancia
# SIN captura de imagen.
#
# Funciones PURAS y TESTEABLES (reciben root + args, NO acceden a
# EditorInterface). El handler visual_handlers.handle_scene_spatial es un
# thin wrapper que parsea args y delega aquí.
#
# Modes:
#   overlaps(node_path, padding=0)  → lista nodos cuya bbox/aabb intersecta
#   distance(from, to)              → vector + magnitud entre dos puntos/nodos
#   neighbors(of, radius)           → nodos dentro de un radio de un punto/nodo
#   layout(node_path)               → Control: effective_rect + Container padding
#   bounds(of=".")                  → AABB total escena (2D + 3D, separadas)
#
# Costes típicos (50-200 tok). Reemplaza la necesidad de captura de imagen
# para validación geométrica.

const HerenCoordsScript := preload("res://addons/heren/handlers/coords.gd")


## Dispatcher principal. `mode` decide qué función se llama.
static func compute(root: Node, args: Dictionary) -> Dictionary:
	if root == null:
		return {"ok": false, "error": "no_scene_open"}
	var mode: String = str(args.get("mode", ""))
	match mode:
		"overlaps":
			return overlaps(root, str(args.get("node_path", "")), float(args.get("padding", 0.0)))
		"distance":
			return distance(root, str(args.get("from", "")), str(args.get("to", "")))
		"neighbors":
			return neighbors(root, str(args.get("of", ".")), float(args.get("radius", 100.0)))
		"layout":
			return layout(root, str(args.get("node_path", "")))
		"bounds":
			return bounds(root, str(args.get("of", ".")))
		_:
			return {"ok": false, "error": "unknown spatial mode: '%s' (overlaps|distance|neighbors|layout|bounds)" % mode}


## overlaps: lista de paths cuya bbox/aabb intersecta la del nodo.
## `padding` (px) extiende la bbox del nodo referencia (útil para proximity).
## Excluye self y descendientes (overlap consigo mismo no tiene sentido).
static func overlaps(root: Node, node_path: String, padding: float) -> Dictionary:
	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}
	var a: Dictionary = HerenCoordsScript.coords_of_node(node, "", 1)
	var flags: Dictionary = a.get("flags", {})
	var is_3d: bool = bool(flags.get("is_3d", false))

	var results: Array = []
	if is_3d:
		var aabb_a: Dictionary = a.get("aabb", {})
		if aabb_a.is_empty():
			return {"ok": false, "error": "node_has_no_aabb (MeshInstance3D + mesh required)"}
		_walk3d_overlaps(root, node, padding, aabb_a, results)
	else:
		var bbox_a: Dictionary = a.get("bbox", {})
		if bbox_a.is_empty():
			return {"ok": false, "error": "node_has_no_bbox (Sprite2D/CollisionShape2D/Label/Control/Polygon2D/Line2D/TextureRect required)"}
		_walk2d_overlaps(root, node, padding, bbox_a, results)

	return {
		"ok": true, "mode": "overlaps",
		"node_path": node_path,
		"kind": a.get("kind", node.get_class()),
		"padding": padding,
		"count": results.size(),
		"results": results,
	}


## distance: vector + magnitud entre dos puntos (resueltos desde nodos o paths).
## Si uno es 3D y otro 2D, devuelve ambos 3D (z=0 para el 2D) y `distance_2d` (proyección XY).
static func distance(root: Node, from_path: String, to_path: String) -> Dictionary:
	var from_node := _resolve_node(root, from_path)
	if from_node == null:
		return {"ok": false, "error": "from_not_found: " + str(from_path)}
	var to_node := _resolve_node(root, to_path)
	if to_node == null:
		return {"ok": false, "error": "to_not_found: " + str(to_path)}
	var is_3d: bool = (from_node is Node3D) or (to_node is Node3D)
	if is_3d:
		var fp: Vector3 = _global_pos3(from_node)
		var tp: Vector3 = _global_pos3(to_node)
		var diff: Vector3 = tp - fp
		return {
			"ok": true, "mode": "distance",
			"from": from_path, "to": to_path,
			"kind": "3d",
			"from_pos": {"x": fp.x, "y": fp.y, "z": fp.z},
			"to_pos": {"x": tp.x, "y": tp.y, "z": tp.z},
			"vector": {"x": diff.x, "y": diff.y, "z": diff.z},
			"distance": diff.length(),
			"distance_2d": Vector2(diff.x, diff.y).length(),
		}
	var fp2: Vector2 = _global_pos2(from_node)
	var tp2: Vector2 = _global_pos2(to_node)
	var diff2: Vector2 = tp2 - fp2
	return {
		"ok": true, "mode": "distance",
		"from": from_path, "to": to_path,
		"kind": "2d",
		"from_pos": {"x": fp2.x, "y": fp2.y},
		"to_pos": {"x": tp2.x, "y": tp2.y},
		"vector": {"x": diff2.x, "y": diff2.y},
		"distance": diff2.length(),
	}


## neighbors: nodos dentro de `radius` del centro (`of` puede ser path o ".").
## Proyección 3D si `of` es Node3D; 2D (con z=0) si es Node2D. Devuelve distancia por nodo.
static func neighbors(root: Node, of_path: String, radius: float) -> Dictionary:
	var of_node := _resolve_node(root, of_path)
	if of_node == null:
		return {"ok": false, "error": "of_not_found: " + str(of_path)}
	if not (of_node is Node3D or of_node is Node2D):
		return {"ok": false, "error": "of_must_be_node2d_or_node3d (got %s)" % of_node.get_class()}

	var is_3d: bool = of_node is Node3D
	var center: Vector3 = _global_pos3(of_node) if is_3d else _global_pos3(of_node)
	var results: Array = []
	_walk_neighbors(root, of_node, radius, center, is_3d, results)

	return {
		"ok": true, "mode": "neighbors",
		"of": of_path,
		"radius": radius,
		"kind": "3d" if is_3d else "2d",
		"count": results.size(),
		"results": results,
	}


## layout: para Control — devuelve effective_rect (post-anchors/post-Container)
## + Container padding del padre (MarginContainer/BoxContainer). Lo que el
## usuario REALMENTE ve, no los anchors/offsets por separado.
static func layout(root: Node, node_path: String) -> Dictionary:
	var node := _resolve_node(root, node_path)
	if node == null:
		return {"ok": false, "error": "node_not_found: " + str(node_path)}
	if not (node is Control):
		return {"ok": false, "error": "layout mode applies to Control only (got %s)" % node.get_class()}

	var ctl: Control = node
	var out := {
		"ok": true, "mode": "layout",
		"node_path": node_path,
		"kind": node.get_class(),
		"size": {"w": ctl.size.x, "h": ctl.size.y},
		"position": {"x": ctl.position.x, "y": ctl.position.y},
		"anchors": {
			"left": ctl.anchor_left, "top": ctl.anchor_top,
			"right": ctl.anchor_right, "bottom": ctl.anchor_bottom,
		},
		"offsets": {
			"left": ctl.offset_left, "top": ctl.offset_top,
			"right": ctl.offset_right, "bottom": ctl.offset_bottom,
		},
	}
	if ctl.is_inside_tree():
		var eff: Rect2 = ctl.get_global_rect()
		out["effective_rect"] = {"x": eff.position.x, "y": eff.position.y, "w": eff.size.x, "h": eff.size.y}
	else:
		# Nodo detached — effective_rect colapsa al size local (sin transform).
		# Es lo que el desarrollador VERÍA en el inspector.
		out["effective_rect"] = {"x": ctl.position.x, "y": ctl.position.y, "w": ctl.size.x, "h": ctl.size.y}
	var parent := ctl.get_parent()
	if parent is Container:
		out["parent_is_container"] = true
		out["parent_class"] = parent.get_class()
		if parent is MarginContainer:
			out["parent_margin"] = {
				"left": parent.get_theme_constant("margin_left"),
				"top": parent.get_theme_constant("margin_top"),
				"right": parent.get_theme_constant("margin_right"),
				"bottom": parent.get_theme_constant("margin_bottom"),
			}
		elif parent is BoxContainer:
			out["parent_spacing"] = parent.get_theme_constant("separation")
	return out


## bounds: AABB total de `of` (path o "." para root), separada en 2D y 3D.
## Ignora nodos sin bbox/aabb (Node, Resource). Devuelve node_count del scope.
static func bounds(root: Node, of_path: String) -> Dictionary:
	var of_node: Node = root if of_path == "" or of_path == "." else _resolve_node(root, of_path)
	if of_node == null:
		return {"ok": false, "error": "of_not_found: " + str(of_path)}

	var acc: Dictionary = {"bbox_2d": Rect2(), "bbox_3d": AABB(), "has_2d": false, "has_3d": false}
	_walk_bounds(of_node, acc)

	var out := {
		"ok": true, "mode": "bounds",
		"of": of_path,
		"node_count": _count_descendants(of_node) + 1,
	}
	if bool(acc.get("has_2d", false)):
		var b2: Rect2 = acc["bbox_2d"]
		out["bounds_2d"] = {"x": b2.position.x, "y": b2.position.y, "w": b2.size.x, "h": b2.size.y}
	if bool(acc.get("has_3d", false)):
		var b3: AABB = acc["bbox_3d"]
		out["bounds_3d"] = {
			"min": {"x": b3.position.x, "y": b3.position.y, "z": b3.position.z},
			"max": {"x": b3.end.x, "y": b3.end.y, "z": b3.end.z},
			"size": {"x": b3.size.x, "y": b3.size.y, "z": b3.size.z},
		}
	if not bool(acc.get("has_2d", false)) and not bool(acc.get("has_3d", false)):
		out["warning"] = "no spatial nodes with bbox/aabb in this scope"
	return out


## summary: snapshot recursivo completo de la escena (Fase D §0.11).
## Reemplaza el `handle_scene_summary` inline (2 niveles) por recursividad +
## bounds + tree_depth + warnings. Es el sustituto de `visual_image/capture`
## para validación Engine B (validator.rs) — JSON puro, sin imagen.
##
## Output:
##   node_count       — total recursivo (no solo hijos directos)
##   by_type          — mapa {class_name: count}
##   tree_depth       — profundidad máxima (root = 1)
##   bounds_2d        — AABB escena 2D (si hay CanvasItems)
##   bounds_3d        — AABB escena 3D (si hay GeometryInstance3D)
##   warnings         — Array de {level, kind, node, message, ...}
static func summary(root: Node) -> Dictionary:
	if root == null:
		return {"ok": false, "error": "no_scene_open"}

	var acc: Dictionary = {
		"by_type": {},
		"node_count": 0,
		"tree_depth": 0,
		"warnings": [],
		"bounds_2d": Rect2(),
		"has_2d": false,
		"bounds_3d": AABB(),
		"has_3d": false,
		"positions_3d": {},  # String pos_key → Array[Node3D] para z_fighting
	}
	_walk_summary(root, 1, acc)

	# Post-process: warnings de z_fighting (2+ GeometryInstance3D misma posición).
	var z_warnings := _detect_z_fighting(acc.get("positions_3d", {}), root)
	for w in z_warnings:
		acc["warnings"].append(w)

	var warnings: Array = acc.get("warnings", [])
	var out := {
		"ok": true,
		"mode": "summary",
		"root": root.name,
		"node_count": int(acc.get("node_count", 0)),
		"by_type": acc.get("by_type", {}),
		"tree_depth": int(acc.get("tree_depth", 0)),
		"warnings": warnings,
		"warning_count": warnings.size(),
	}
	if bool(acc.get("has_2d", false)):
		var b2: Rect2 = acc["bounds_2d"]
		out["bounds_2d"] = {"x": b2.position.x, "y": b2.position.y, "w": b2.size.x, "h": b2.size.y}
	if bool(acc.get("has_3d", false)):
		var b3: AABB = acc["bounds_3d"]
		out["bounds_3d"] = {
			"min": {"x": b3.position.x, "y": b3.position.y, "z": b3.position.z},
			"max": {"x": b3.end.x, "y": b3.end.y, "z": b3.end.z},
			"size": {"x": b3.size.x, "y": b3.size.y, "z": b3.size.z},
		}
	if not bool(acc.get("has_2d", false)) and not bool(acc.get("has_3d", false)):
		out["hint"] = "no spatial nodes with bbox/aabb in this scope"
	return out


# ============================================================== private walkers

static func _walk3d_overlaps(root: Node, exclude: Node, padding: float, aabb_a: Dictionary, out: Array) -> void:
	var stack: Array[Node] = []
	for c in root.get_children():
		stack.append(c)
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == exclude or exclude.is_ancestor_of(n):
			for c in n.get_children():
				stack.append(c)
			continue
		var coords: Dictionary = HerenCoordsScript.coords_of_node(n, "", 1)
		var b: Dictionary = coords.get("aabb", {})
		if not b.is_empty() and _aabb3_intersects(aabb_a, b, padding):
			out.append({
				"path": _relpath(n, root),
				"kind": coords.get("kind", n.get_class()),
			})
		for c in n.get_children():
			stack.append(c)


static func _walk2d_overlaps(root: Node, exclude: Node, padding: float, bbox_a: Dictionary, out: Array) -> void:
	var rect_a: Rect2 = Rect2(
		float(bbox_a.get("x", 0)), float(bbox_a.get("y", 0)),
		float(bbox_a.get("w", 0)), float(bbox_a.get("h", 0))
	).grow(padding)
	var stack: Array[Node] = []
	for c in root.get_children():
		stack.append(c)
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == exclude or exclude.is_ancestor_of(n):
			for c in n.get_children():
				stack.append(c)
			continue
		var coords: Dictionary = HerenCoordsScript.coords_of_node(n, "", 1)
		var b: Dictionary = coords.get("bbox", {})
		if not b.is_empty():
			var rect_b: Rect2 = Rect2(
				float(b.get("x", 0)), float(b.get("y", 0)),
				float(b.get("w", 0)), float(b.get("h", 0))
			)
			if rect_a.intersects(rect_b):
				out.append({
					"path": _relpath(n, root),
					"kind": coords.get("kind", n.get_class()),
				})
		for c in n.get_children():
			stack.append(c)


static func _walk_neighbors(root: Node, exclude: Node, radius: float, center: Vector3, is_3d: bool, out: Array) -> void:
	var radius_sq: float = radius * radius
	var stack: Array[Node] = []
	for c in root.get_children():
		stack.append(c)
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == exclude or exclude.is_ancestor_of(n):
			for c in n.get_children():
				stack.append(c)
			continue
		var p: Vector3
		if is_3d:
			if not (n is Node3D):
				for c in n.get_children():
					stack.append(c)
				continue
			p = (n as Node3D).global_position
		else:
			if not (n is Node2D):
				for c in n.get_children():
					stack.append(c)
				continue
			p = Vector3((n as Node2D).global_position.x, (n as Node2D).global_position.y, 0)
		if center.distance_squared_to(p) <= radius_sq:
			out.append({
				"path": _relpath(n, root),
				"kind": n.get_class(),
				"distance": center.distance_to(p),
			})
		for c in n.get_children():
			stack.append(c)


static func _walk_bounds(n: Node, acc: Dictionary) -> Dictionary:
	var coords: Dictionary = HerenCoordsScript.coords_of_node(n, "", 1)
	var b: Dictionary = coords.get("bbox", {})
	if float(b.get("w", 0)) > 0.0 and float(b.get("h", 0)) > 0.0:
		var r: Rect2 = Rect2(float(b.get("x", 0)), float(b.get("y", 0)), float(b.get("w", 0)), float(b.get("h", 0)))
		if not bool(acc.get("has_2d", false)):
			acc["bbox_2d"] = r
			acc["has_2d"] = true
		else:
			acc["bbox_2d"] = (acc["bbox_2d"] as Rect2).merge(r)
	var a: Dictionary = coords.get("aabb", {})
	var a_size: Dictionary = a.get("size", {})
	if float(a_size.get("x", 0)) > 0.0:
		var pos: Vector3 = Vector3(
			float(a.get("position", {}).get("x", 0)),
			float(a.get("position", {}).get("y", 0)),
			float(a.get("position", {}).get("z", 0))
		)
		var size: Vector3 = Vector3(
			float(a_size.get("x", 0)),
			float(a_size.get("y", 0)),
			float(a_size.get("z", 0))
		)
		var bb: AABB = AABB(pos, size)
		if not bool(acc.get("has_3d", false)):
			acc["bbox_3d"] = bb
			acc["has_3d"] = true
		else:
			acc["bbox_3d"] = (acc["bbox_3d"] as AABB).merge(bb)
	for c in n.get_children():
		acc = _walk_bounds(c, acc)
	return acc


static func _walk_summary(n: Node, depth: int, acc: Dictionary) -> void:
	var node_class: String = n.get_class()
	var by_type: Dictionary = acc.get("by_type", {})
	by_type[node_class] = int(by_type.get(node_class, 0)) + 1
	acc["by_type"] = by_type
	acc["node_count"] = int(acc.get("node_count", 0)) + 1
	if depth > int(acc.get("tree_depth", 0)):
		acc["tree_depth"] = depth

	# Bbox/AABB via coords_of_node (Fase A — fuente única).
	var coords: Dictionary = HerenCoordsScript.coords_of_node(n, "", 1)
	var bbox: Dictionary = coords.get("bbox", {})
	if float(bbox.get("w", 0)) > 0.0 and float(bbox.get("h", 0)) > 0.0:
		var r: Rect2 = Rect2(float(bbox.get("x", 0)), float(bbox.get("y", 0)), float(bbox.get("w", 0)), float(bbox.get("h", 0)))
		if not bool(acc.get("has_2d", false)):
			acc["bounds_2d"] = r
			acc["has_2d"] = true
		else:
			acc["bounds_2d"] = (acc["bounds_2d"] as Rect2).merge(r)
	var aabb: Dictionary = coords.get("aabb", {})
	var aabb_size: Dictionary = aabb.get("size", {})
	if float(aabb_size.get("x", 0)) > 0.0:
		var pos: Vector3 = Vector3(
			float(aabb.get("position", {}).get("x", 0)),
			float(aabb.get("position", {}).get("y", 0)),
			float(aabb.get("position", {}).get("z", 0))
		)
		var size: Vector3 = Vector3(
			float(aabb_size.get("x", 0)),
			float(aabb_size.get("y", 0)),
			float(aabb_size.get("z", 0))
		)
		var bb: AABB = AABB(pos, size)
		if not bool(acc.get("has_3d", false)):
			acc["bounds_3d"] = bb
			acc["has_3d"] = true
		else:
			acc["bounds_3d"] = (acc["bounds_3d"] as AABB).merge(bb)

	# Positions 3D para z_fighting detection (solo GeometryInstance3D, no Node3D puro).
	if n is GeometryInstance3D:
		var gi: GeometryInstance3D = n
		var p: Vector3 = gi.global_position if gi.is_inside_tree() else (gi as Node3D).position
		var key: String = "%.3f,%.3f,%.3f" % [p.x, p.y, p.z]
		var positions: Dictionary = acc.get("positions_3d", {})
		var existing: Array = positions.get(key, [])
		existing.append(n)
		positions[key] = existing
		acc["positions_3d"] = positions

	# Warnings — detección heurística (no rompe si la propiedad no existe).
	var warnings: Array = acc.get("warnings", [])
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		if mi.mesh != null and mi.get_active_material(0) == null:
			warnings.append({
				"level": "info",
				"kind": "missing_material",
				"node": str(n.name),
				"node_path": _relpath(n, acc.get("_root", n)),
				"message": "MeshInstance3D sin material_override ni material en mesh",
			})
	if n is Sprite2D and (n as Sprite2D).texture == null:
		warnings.append({
			"level": "warning",
			"kind": "missing_texture",
			"node": str(n.name),
			"node_path": _relpath(n, acc.get("_root", n)),
			"message": "Sprite2D sin texture (se renderiza vacío)",
		})
	if n is Sprite3D and (n as Sprite3D).texture == null:
		warnings.append({
			"level": "warning",
			"kind": "missing_texture",
			"node": str(n.name),
			"node_path": _relpath(n, acc.get("_root", n)),
			"message": "Sprite3D sin texture",
		})
	if n is CollisionShape2D and (n as CollisionShape2D).shape == null:
		warnings.append({
			"level": "warning",
			"kind": "missing_shape",
			"node": str(n.name),
			"node_path": _relpath(n, acc.get("_root", n)),
			"message": "CollisionShape2D sin shape (no detecta colisiones)",
		})
	if n is CollisionShape3D and (n as CollisionShape3D).shape == null:
		warnings.append({
			"level": "warning",
			"kind": "missing_shape",
			"node": str(n.name),
			"node_path": _relpath(n, acc.get("_root", n)),
			"message": "CollisionShape3D sin shape",
		})
	acc["warnings"] = warnings

	for c in n.get_children():
		_walk_summary(c, depth + 1, acc)


static func _detect_z_fighting(positions: Dictionary, root: Node) -> Array:
	var warnings: Array = []
	for key in positions.keys():
		var nodes: Array = positions[key]
		if nodes.size() < 2:
			continue
		var paths: Array = []
		for n in nodes:
			paths.append(_relpath(n, root))
		warnings.append({
			"level": "warning",
			"kind": "z_fighting_risk",
			"position": key,
			"nodes": paths,
			"count": nodes.size(),
			"message": "%d GeometryInstance3D en posición %s (riesgo de z-fighting)" % [nodes.size(), key],
		})
	return warnings


# ============================================================== utils

static func _resolve_node(root: Node, path: String) -> Node:
	if path == "" or path == ".":
		return root
	return root.get_node_or_null(NodePath(path))


static func _global_pos3(n: Node) -> Vector3:
	if n is Node3D:
		return (n as Node3D).global_position
	if n is Node2D:
		var p: Vector2 = (n as Node2D).global_position
		return Vector3(p.x, p.y, 0)
	return Vector3.ZERO


static func _global_pos2(n: Node) -> Vector2:
	if n is Node2D:
		return (n as Node2D).global_position
	if n is Node3D:
		var p: Vector3 = (n as Node3D).global_position
		return Vector2(p.x, p.y)
	return Vector2.ZERO


static func _aabb3_intersects(a: Dictionary, b: Dictionary, padding: float) -> bool:
	var a_min: Vector3 = Vector3(
		float(a.get("position", {}).get("x", 0)),
		float(a.get("position", {}).get("y", 0)),
		float(a.get("position", {}).get("z", 0))
	)
	var a_max: Vector3 = a_min + Vector3(
		float(a.get("size", {}).get("x", 0)),
		float(a.get("size", {}).get("y", 0)),
		float(a.get("size", {}).get("z", 0))
	)
	var b_min: Vector3 = Vector3(
		float(b.get("position", {}).get("x", 0)),
		float(b.get("position", {}).get("y", 0)),
		float(b.get("position", {}).get("z", 0))
	)
	var b_max: Vector3 = b_min + Vector3(
		float(b.get("size", {}).get("x", 0)),
		float(b.get("size", {}).get("y", 0)),
		float(b.get("size", {}).get("z", 0))
	)
	a_min -= Vector3(padding, padding, padding)
	a_max += Vector3(padding, padding, padding)
	return (a_min.x <= b_max.x and a_max.x >= b_min.x
		and a_min.y <= b_max.y and a_max.y >= b_min.y
		and a_min.z <= b_max.z and a_max.z >= b_min.z)


static func _count_descendants(n: Node) -> int:
	var total := 0
	for c in n.get_children():
		total += 1 + _count_descendants(c)
	return total


static func _relpath(n: Node, root: Node) -> String:
	# Path relativo construido manualmente — NO usa get_path() (que requiere
	# SceneTree root). Funciona con nodos detached (tests headless).
	if n == root:
		return "."
	var parts: Array[String] = []
	var current: Node = n
	while current != null and current != root:
		parts.append(str(current.name))
		current = current.get_parent()
	if current != root:
		# n NO es descendiente de root. Devolver nombres concatenados.
		return "<not_under_root:" + str(n.name) + ">"
	parts.reverse()
	return "/".join(parts) if parts.size() > 0 else "."
