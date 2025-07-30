# Copyright (c) 2025 Kirill Rozhkov.
#
# This file is part of Roommate plugin: https://github.com/Hoork/Roommate
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

@tool
extends MenuButton


func _ready() -> void:
	get_popup().index_pressed.connect(_on_popup_menu_index_pressed)


func _on_popup_menu_index_pressed(index: int) -> void:
	var nodes := EditorPlugin.new().get_editor_interface().get_selection().get_selected_nodes()
	var is_extends := func (node: Node) -> bool:
		return node is RoommateRoot
	var filtered := nodes.filter(is_extends)
	if filtered.size() == 0:
		return
	for node in filtered:
		var root := node as RoommateRoot
		match index:
			0:
				root.generate()
			1:
				root.clear_scenes()
