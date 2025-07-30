# Copyright (c) 2025 Kirill Rozhkov.
#
# This file is part of Roommate plugin: https://github.com/Hoork/Roommate
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

@tool
extends RefCounted

# omid - operation mode id
var mode := &"omid_include"
var offset := Vector3i.ZERO
var check_selection: Callable


func update_inclusion(block: RoommateBlock, source_blocks: Dictionary, is_included: bool) -> bool:
	if not check_selection.is_valid():
		push_error("check_selection is not valid")
		return is_included
	var offset_position := block.position - offset
	var is_selected := check_selection.call(offset_position, block, source_blocks)
	if not is_selected is bool:
		push_error("check_selection returned value of type %s. Bool expected" % typeof(is_selected))
		is_selected = false
	
	if not is_selected:
		if mode == &"omid_intersect":
			return false
		return is_included
	
	match mode:
		&"omid_include":
			return true
		&"omid_exclude":
			return false
		&"omid_invert":
			return not is_included
		&"omid_intersect":
			return is_included
	
	push_warning("Unexpected mode id %s." % mode)
	return is_included


func include() -> void:
	mode = &"omid_include"


func exclude() -> void:
	mode = &"omid_exclude"


func invert() -> void:
	mode = &"omid_invert"


func intersect() -> void:
	mode = &"omid_intersect"


func set_offset(new_offset: Vector3i) -> void:
	offset = new_offset
