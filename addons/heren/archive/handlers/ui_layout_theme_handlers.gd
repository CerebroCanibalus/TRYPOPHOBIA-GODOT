@tool
extends "res://addons/heren/handlers/ui_handlers.gd"

# Heren MCP v4 - ARCHIVADO 2026-09-09 (§0.12 W4 cleanup).
# ui/layout + ui/theme. Reemplazados por scene_script workers — la lógica de
# layout (anchors/offsets/margins por preset) y theming (Theme resource + apply)
# es trivial en GDScript con acceso directo a Control.
#
# Hereda de ui_handlers.gd (que sigue activo) para reutilizar helpers
# (_scene_root, _resolve_node, LAYOUT_PRESETS, etc.).
# Para restaurar, ver addons/heren/archive/handlers/README.md.

func handle_ui_layout(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return _err("no scene open in editor")
	var node_path: Variant = args.get("node_path", "")
	var layout: String = str(args.get("layout", ""))
	if node_path == "" or layout == "":
		return _err("node_path and layout required")

	var node := _resolve_node(root, node_path)
	if node == null:
		return _not_found_hint(root, node_path)
	if not node is Control:
		return _err("not_a_control: " + str(node_path))
	var preset: int = LAYOUT_PRESETS.get(layout, -1)
	if preset == -1:
		return _err("unknown_layout: " + layout + " (use ui/templates for list)")

	var ctl: Control = node as Control
	ctl.set_anchors_preset(preset, true)
	if ctl is Container:
		(ctl as Container).add_theme_constant_override("separation",
			int(args.get("separation", 8)))

	var result: Dictionary = {
		"ok": true,
		"node_path": _node_path_relative(ctl, root),
		"layout": layout,
		"anchors": {"preset": preset},
		"offset": {
			"left": ctl.offset_left,
			"top": ctl.offset_top,
			"right": ctl.offset_right,
			"bottom": ctl.offset_bottom,
		},
	}
	var warning := _container_layout_warning(ctl)
	if warning != "":
		result["warning"] = warning
	return result


## ui/theme — aplica Theme (.tres) al Control; crea default si no existe.
func handle_ui_theme(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return _err("no scene open in editor")
	var node_path: Variant = args.get("node_path", "")
	var theme_path: String = str(args.get("theme_path", ""))
	if node_path == "":
		return _err("node_path required")

	var node := _resolve_node(root, node_path)
	if node == null:
		return _not_found_hint(root, node_path)
	if not node is Control:
		return _err("not_a_control: " + str(node_path))

	var ctl: Control = node as Control
	var theme: Theme = null
	if theme_path != "":
		if not ResourceLoader.exists(theme_path):
			return _err("theme_not_found: " + theme_path)
		theme = load(theme_path)
		ctl.theme = theme
	else:
		# Generar un Theme vacío si no se pasa uno.
		theme = Theme.new()
		ctl.theme = theme

	return {
		"ok": true,
		"node_path": _node_path_relative(ctl, root),
		"theme_path": theme_path,
		"theme_resource_path": theme.resource_path if theme != null else "",
		"font_size_default": theme.get_default_font_size() if theme != null else 0,
		"offset": {
			"left": ctl.offset_left,
			"top": ctl.offset_top,
			"right": ctl.offset_right,
			"bottom": ctl.offset_bottom,
		},
	}
