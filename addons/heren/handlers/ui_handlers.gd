@tool
extends "res://addons/heren/handlers/heren_handler.gd"
# Heren MCP v4.7 - UI handlers (Fase UI-2).
# Tool `ui` modular (1 tool, N acciones) para UI 2D sobre viewports.
# El sistema de templates es TRANSVERSAL (template_registry.gd) — esta tool
# delega en él, no duplica lógica.
#
# Actions:
#   create        — Control desde template (template) o desde cero (node_type
#                   obligatorio si no viene template) + layout preset opcional
#   canvas_layer  — CanvasLayer (layer, follow_viewport) para HUD overlay
#   templates     — lista templates con params (del registry transversal)
#   get_info      — anchors/offsets/size_flags/min_size de un Control
#
# 2026-09-09 (§0.12 W4 cleanup):
#   - layout, theme: archivados a addons/heren/archive/handlers/ui_layout_theme_handlers.gd
#   Reemplazados por scene_script workers.

const HerenCoordsScript := preload("coords.gd")
const HerenSceneRegistryScript := preload("../scene_registry.gd")
const HerenTemplateRegistryScript := preload("../template_registry.gd")

# Presets de layout (nombres del General 2026-08-14) → Control.LayoutPreset.
# set_anchors_and_offsets_preset aplica anchors + offsets en una llamada.
const LAYOUT_PRESETS := {
	"full_rect": Control.PRESET_FULL_RECT,
	"bottom_center": Control.PRESET_CENTER_BOTTOM,
	"top_left": Control.PRESET_TOP_LEFT,
	"top_right": Control.PRESET_TOP_RIGHT,
	"center": Control.PRESET_CENTER,
	"bottom_left": Control.PRESET_BOTTOM_LEFT,
	"bottom_right": Control.PRESET_BOTTOM_RIGHT,
	"center_left": Control.PRESET_CENTER_LEFT,
	"center_right": Control.PRESET_CENTER_RIGHT,
}

var _undo_redo: Node


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin
	_undo_redo = plugin.get_undo_redo_wrapper()


# ---------------------------------------------------------------- helpers

func _editor_interface() -> EditorInterface:
	if _editor_plugin == null:
		return null
	return _editor_plugin.get_editor_interface()


func _scene_root(args: Dictionary = {}) -> Node:
	var ei := _editor_interface()
	if ei == null:
		return null
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


func _not_found_hint(root: Node, node_path: Variant) -> Dictionary:
	var hint := {"ok": false, "error": "node_not_found: " + str(node_path)}
	if root == null or node_path == null:
		return hint
	var normalized := HerenCoordsScript.normalize_node_path(node_path, root)
	if normalized == "" or normalized == ".":
		return hint
	# Recortar segmentos de atrás hasta encontrar un padre resoluble.
	var segments: Array = normalized.split("/")
	while segments.size() > 1:
		segments.pop_back()
		var parent := root.get_node_or_null(NodePath("/".join(segments)))
		if parent != null:
			var children: Array = []
			for child in parent.get_children():
				children.append(_node_path_relative(child, root))
			hint["parent"] = _node_path_relative(parent, root)
			hint["parent_children"] = children
			return hint
	return hint


func _node_path_relative(node: Node, root: Node) -> String:
	if node == null or root == null:
		return ""
	if node == root:
		return "."
	var path_str := str(node.get_path())
	var root_str := str(root.get_path())
	if path_str.begins_with(root_str + "/"):
		return path_str.substr(root_str.length() + 1)
	return path_str


# ---------------------------------------------------------------- actions

## ui/create — Control desde template O desde cero + layout preset.
func handle_ui_create(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return _err("no scene open in editor")

	var template_name: String = str(args.get("template", ""))
	var node: Node = null
	var source := ""

	if template_name != "":
		var params := _args_dict(args, "properties")
		node = HerenTemplateRegistryScript.instantiate(template_name, params)
		if node == null:
			return _err("template_not_found: " + template_name)
		source = "template:" + template_name
	else:
		var node_type: String = str(args.get("node_type", ""))
		if node_type == "":
			return _err("node_type required when no template")
		var node_name: String = str(args.get("node_name", ""))
		if node_name == "":
			return _err("node_name required")
		var new_node: Variant = ClassDB.instantiate(node_type)
		if new_node == null or not new_node is Node:
			return _err("invalid_node_type: " + node_type)
		node = new_node as Node
		node.name = node_name
		var properties := _args_dict(args, "properties")
		for prop_name in properties.keys():
			if prop_name in node:
				node.set(prop_name, HerenCoordsScript.deserialize_value(properties[prop_name]))
		source = node_type

	# Layout preset opcional (solo Control).
	var layout: String = str(args.get("layout", ""))
	if layout != "" and node is Control:
		var preset: int = LAYOUT_PRESETS.get(layout, -1)
		if preset == -1:
			node.free()
			return _err("invalid_layout: " + layout)
		(node as Control).set_anchors_and_offsets_preset(preset)

	var parent: Node = root
	if args.has("parent_path") and str(args.get("parent_path", "")) != "":
		parent = _resolve_node(root, args.get("parent_path"))
		if parent == null:
			node.free()
			return _err("parent_not_found: " + str(args.get("parent_path")))

	_undo_redo.begin_action("Heren UI Create %s" % node.name)
	_undo_redo.add_do_method(parent, &"add_child", [node])
	_undo_redo.add_do_property(node, &"owner", root)
	_undo_redo.add_undo_method(parent, &"remove_child", [node])
	_undo_redo.commit_action()

	return {
		"ok": true,
		"source": source,
		"node_name": node.name,
		"node_type": node.get_class(),
		"parent_path": _node_path_relative(parent, root),
		"node_path": _node_path_relative(node, root),
		"layout": layout,
	}


## ui/canvas_layer — CanvasLayer para HUD overlay.
func handle_ui_canvas_layer(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return _err("no scene open in editor")

	var layer_name: String = str(args.get("node_name", "CanvasLayer"))
	var layer: int = int(args.get("layer", 1))
	var follow_viewport: bool = bool(args.get("follow_viewport", false))

	var cl := CanvasLayer.new()
	cl.name = layer_name
	cl.layer = layer
	cl.follow_viewport_enabled = follow_viewport

	var parent: Node = root
	if args.has("parent_path") and str(args.get("parent_path", "")) != "":
		parent = _resolve_node(root, args.get("parent_path"))
		if parent == null:
			cl.free()
			return _err("parent_not_found: " + str(args.get("parent_path")))

	_undo_redo.begin_action("Heren UI CanvasLayer %s" % layer_name)
	_undo_redo.add_do_method(parent, &"add_child", [cl])
	_undo_redo.add_do_property(cl, &"owner", root)
	_undo_redo.add_undo_method(parent, &"remove_child", [cl])
	_undo_redo.commit_action()

	return {
		"ok": true,
		"node_name": cl.name,
		"node_type": "CanvasLayer",
		"layer": cl.layer,
		"follow_viewport": cl.follow_viewport_enabled,
		"parent_path": _node_path_relative(parent, root),
		"node_path": _node_path_relative(cl, root),
	}


## ui/templates — lista templates con params (del registry transversal).
func handle_ui_templates(args: Dictionary) -> Dictionary:
	var templates := HerenTemplateRegistryScript.list_templates()
	return {
		"ok": true,
		"templates": templates,
		"count": templates.size(),
	}


## ui/get_info — anchors/offsets/size_flags/min_size de un Control.
func handle_ui_get_info(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return _err("no scene open in editor")
	var node_path: Variant = args.get("node_path", "")
	if node_path == "":
		return _err("node_path required")

	var node := _resolve_node(root, node_path)
	if node == null:
		return _not_found_hint(root, node_path)
	if not node is Control:
		return _err("not_a_control: " + str(node_path))

	var ctl := node as Control
	return {
		"ok": true,
		"node_path": _node_path_relative(node, root),
		"node_type": node.get_class(),
		"anchors": _control_anchors(ctl),
		"offsets": _control_offsets(ctl),
		"size": {"x": ctl.size.x, "y": ctl.size.y},
		"min_size": {"x": ctl.custom_minimum_size.x, "y": ctl.custom_minimum_size.y},
		"size_flags": {
			"horizontal": ctl.size_flags_horizontal,
			"vertical": ctl.size_flags_vertical,
			"stretch_ratio": ctl.size_flags_stretch_ratio,
		},
		"grow": {"horizontal": ctl.grow_horizontal, "vertical": ctl.grow_vertical},
		"parent_is_container": ctl.get_parent() is Container,
	}


# ------------------- helpers internos (necesarios para ui/get_info) -------------------

static func _control_anchors(c: Control) -> Dictionary:
	return {
		"left": c.anchor_left,
		"top": c.anchor_top,
		"right": c.anchor_right,
		"bottom": c.anchor_bottom,
	}


static func _control_offsets(c: Control) -> Dictionary:
	return {
		"left": c.offset_left,
		"top": c.offset_top,
		"right": c.offset_right,
		"bottom": c.offset_bottom,
	}


