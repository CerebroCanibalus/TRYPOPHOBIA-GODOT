@tool
extends RefCounted

## Heren MCP — Routing declarativo (Fase 3 §0.8, 2026-09-03).
##
## Tabla `(tool_prefix, action) → handler_method` EXPLÍCITA. Reemplaza los
## 3 fallbacks mágicos del dispatcher.gd que dependían de convenciones
## implícitas (`handle_scene_X`, `handle_X` por action, strip del prefix).
##
## CONTRATO:
## - Cada handler PÚBLICO (expuesto como tool MCP) DEBE tener una entrada aquí.
## - Tests (tools_parity.rs) verifican que cada tool/action del schema público
##   está mapeado. Renames rompen tests, no producción.
## - Las tools sin action (solo `tool_name`, ej. `health`) usan la key "_default".
##
## Formato:
##   "{tool_prefix}/{action}" → "{handler_method}"
##   "{tool_prefix}/_default" → handler cuando NO hay action


# Scene
const ROUTES := {
	# Low-level (sin action o action específica).
	"scene/get_open_scenes": "handle_get_open_scenes",
	"scene/get_edited_scene_root": "handle_get_edited_scene_root",
	"scene/open": "handle_open",
	"scene/save": "handle_save",
	"scene/create": "handle_create",
	"scene/unload": "handle_unload",
	"scene/health": "handle_health",
	"scene/project_info": "handle_project_info",
	# Planning (Fase 1 §0.8: single source of truth).
	"scene/plan": "handle_plan",
	"scene/get_plan": "handle_get_plan",
	"scene/set_qa_report": "handle_set_qa_report",
	"scene/get_qa_report": "handle_get_qa_report",
	"scene/orchestrate": "handle_orchestrate",
	"scene/validate": "handle_validate",
	"scene/commit": "handle_commit",
	"scene/status": "handle_status",
	"scene/list": "handle_list",

	# Node
	"node/add": "handle_add",
	"node/remove": "handle_remove",
	"node/duplicate": "handle_duplicate",
	"node/rename": "handle_rename",
	"node/move": "handle_move",
	"node/set_owner": "handle_set_owner",
	"node/reorder": "handle_reorder",
	"node/instantiate": "handle_instantiate",
	"node/array_append": "handle_array_append",
	"node/array_remove": "handle_array_remove",
	"node/set_script": "handle_set_script",
	"node/get_prop": "handle_get_prop",
	"node/get_info": "handle_get_info",
	"node/get_children": "handle_get_children",
	"node/find": "handle_find",
	"node/set_prop": "handle_set_prop",
	"node/set_props": "handle_set_props",

	# Resource
	"resource/create": "handle_create",
	"resource/read": "handle_read",
	"resource/update": "handle_update",
	"resource/delete": "handle_delete",
	"resource/list": "handle_list",
	"resource/create_script": "handle_create_script",
	"resource/read_script": "handle_read_script",
	"resource/edit_script": "handle_edit_script",
	"resource/set_script": "handle_set_script",

	# Project
	"project/setting": "handle_setting",
	"project/autoload": "handle_autoload",
	"project/remove_autoload": "handle_remove_autoload",
	"project/input_map": "handle_input_map",
	"project/shader_global": "handle_shader_global",

	# Shader
	"shader/create": "handle_create",
	"shader/edit": "handle_edit",
	"shader/get": "handle_get",
	"shader/inspect": "handle_inspect",
	"shader/validate": "handle_validate",
	"shader/apply": "handle_apply",
	"shader/material": "handle_material",
	"shader/uniform": "handle_uniform",

	# Animation
	"animation/create_player": "handle_create_player",
	"animation/create": "handle_create",
	"animation/add_track": "handle_add_track",
	"animation/add_key": "handle_add_key",
	"animation/state_machine": "handle_state_machine",
	"animation/one_shot": "handle_one_shot",
	"animation/tween": "handle_tween",
	"animation/record": "handle_record",
	"animation/from_path": "handle_from_path",
	"animation/loop_pose": "handle_loop_pose",
	"animation/preview": "handle_preview",
	"animation/curve": "handle_curve",
	"animation/play": "handle_play",
	"animation/stop": "handle_stop",
	"animation/seek": "handle_seek",
	"animation/speed": "handle_speed",
	"animation/get_animations": "handle_get_animations",
	"animation/get_tracks": "handle_get_tracks",
	"animation/get_keyframes": "handle_get_keyframes",
	"animation/get_state_machine": "handle_get_state_machine",
	"animation/update_props": "handle_update_props",
	"animation/remove_track": "handle_remove_track",
	"animation/remove_key": "handle_remove_key",
	"animation/update_key": "handle_update_key",
	"animation/duplicate": "handle_duplicate",
	"animation/delete": "handle_delete",
	"animation/rename": "handle_rename",
	"animation/reverse": "handle_reverse",
	"animation/blend_pose": "handle_blend_pose",
	"animation/retarget": "handle_retarget",
	# AnimationTree
	"animation/tree_activate": "handle_tree_activate",
	"animation/tree_travel": "handle_tree_travel",
	"animation/tree_set_param": "handle_tree_set_param",
	"animation/tree_get_param": "handle_tree_get_param",
	"animation/tree_add_blend_node": "handle_tree_add_blend_node",
	"animation/tree_connect_blend_nodes": "handle_tree_connect_blend_nodes",
	"animation/tree_set_anim_player": "handle_tree_set_anim_player",

	# Skeleton
	"skeleton/skeleton_create": "handle_skeleton_create",
	"skeleton/skeleton_add_bone": "handle_skeleton_add_bone",
	"skeleton/skeleton_set_rest": "handle_skeleton_set_rest",
	"skeleton/skeleton_skin": "handle_skeleton_skin",
	"skeleton/skeleton_attachment": "handle_skeleton_attachment",
	"skeleton/skeleton_get_bones": "handle_skeleton_get_bones",
	"skeleton/skeleton_get_pose": "handle_skeleton_get_pose",
	"skeleton/skeleton_set_pose": "handle_skeleton_set_pose",
	"skeleton/skeleton_ik": "handle_skeleton_ik",
	"skeleton/skeleton_fabrik": "handle_skeleton_fabrik",
	"skeleton/capture_pose": "handle_capture_pose",

	# Tilemap
	"tilemap/inspect_set": "handle_inspect_set",
	"tilemap/inspect_map": "handle_inspect_map",
	"tilemap/set_cell": "handle_set_cell",
	"tilemap/terrain": "handle_terrain",
	"tilemap/pattern": "handle_pattern",

	# Debug
	"debug/summary": "handle_summary",
	"debug/breakpoint": "handle_breakpoint",
	"debug/control": "handle_control",
	"debug/stack": "handle_stack",
	"debug/vars": "handle_vars",
	"debug/profiler": "handle_profiler",
	"debug/run_scene": "handle_run_scene",
	"debug/output": "handle_output",

	# Validate
	"validate/scene": "handle_scene",
	"validate/script": "handle_script",
	"validate/node": "handle_node",
	"validate/resource": "handle_resource",

	# Signal
	"signal/connect": "handle_connect",
	"signal/disconnect": "handle_disconnect",
	"signal/list": "handle_list",
	"signal/set_script": "handle_set_script",

	# Visual (server side `visual` tool, 4 actions)
	"visual/coords": "handle_coords",
	"visual/summary": "handle_summary",
	"visual/ascii": "handle_ascii",
	"visual/spatial": "handle_scene_spatial",
	"visual/scene_summary": "handle_summary",  # alias interno usado por validator

	# UI
	"ui/create": "handle_ui_create",
	"ui/layout": "handle_ui_layout",
	"ui/canvas_layer": "handle_ui_canvas_layer",
	"ui/templates": "handle_ui_templates",
	"ui/get_info": "handle_ui_get_info",
	"ui/theme": "handle_ui_theme",
}


## Devuelve el handler method para (prefix, action) o "" si no está registrado.
static func lookup(prefix: String, action: String) -> String:
	if action == "":
		return ""
	return ROUTES.get("%s/%s" % [prefix, action], "")


## Devuelve todos los routes como Array de "{prefix}/{action}".
static func all_routes() -> Array:
	return ROUTES.keys()
