# Copyright (c) 2025 Kirill Rozhkov.
#
# This file is part of Roommate plugin: https://github.com/Hoork/Roommate
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

@tool
extends EditorPlugin

const SETTINGS_PATH := "plugins/roommate/%s"
const GENERATE_SHORTCUT_SETTING := SETTINGS_PATH % "generate_root_nodes_shortcut"

const GENERATE_SHORTCUT_RESOURCE := preload("./defaults/default_generate_shortcut.tres")
const ROOT_ACTIONS_SCENE := preload("./controls/roommate_root_actions/roommate_root_actions.tscn")

var _root_actions: Control
var _gizmo_plugin := preload("./gizmos/gizmo_plugin.gd").new()


func _enter_tree() -> void:
	get_editor_interface().get_selection().selection_changed.connect(_update_controls_visibility)
	add_node_3d_gizmo_plugin(_gizmo_plugin)
	_root_actions = ROOT_ACTIONS_SCENE.instantiate() as Control
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _root_actions)
	_update_controls_visibility()


func _exit_tree() -> void:
	get_editor_interface().get_selection().selection_changed.disconnect(_update_controls_visibility)
	remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _root_actions)
	_root_actions.free()
	_root_actions = null
	remove_node_3d_gizmo_plugin(_gizmo_plugin)


func _shortcut_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo(): 
		return
	var settings := get_editor_interface().get_editor_settings()
	var shortcut := settings.get_setting(GENERATE_SHORTCUT_SETTING) as Shortcut
	if not shortcut:
		shortcut = GENERATE_SHORTCUT_RESOURCE.duplicate(true)
		settings.set_setting(GENERATE_SHORTCUT_SETTING, shortcut)
		settings.emit_changed()
	if shortcut.matches_event(event):
		_generate_root_nodes()


func _update_controls_visibility() -> void:
	if not _root_actions:
		return
	var nodes := get_editor_interface().get_selection().get_selected_nodes()
	var is_extends := func(node: Node) -> bool:
		return node is RoommateRoot
	_root_actions.visible = nodes.any(is_extends)


func _generate_root_nodes() -> void:
	var selected_nodes := get_editor_interface().get_selection().get_selected_nodes()
	var scene_root := get_editor_interface().get_edited_scene_root()
	var roots: Array[RoommateRoot] = []
	roots.assign(scene_root.find_children("*", RoommateRoot.get_class_name()))
	var filter_by_child := func(root: RoommateRoot) -> bool:
		for node in selected_nodes:
			if root == node or root.is_ancestor_of(node):
				return true
		return false
	for node in roots.filter(filter_by_child):
		var root := node as RoommateRoot
		root.generate()
