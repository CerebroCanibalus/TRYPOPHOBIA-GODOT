# Copyright (c) 2025 Kirill Rozhkov.
#
# This file is part of Roommate plugin: https://github.com/Hoork/Roommate
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

@tool
@icon("../icons/oblique.svg")
class_name RoommateOblique
extends RoommateBlocksArea
## Area that represents sloped surface

@export_enum("X:0", "Y:1", "Z:2") var extend_axis := 0:
	set(value):
		extend_axis = value
		update_gizmos()
@export var oblique_part_rotated := false:
	set(value):
		oblique_part_rotated = value
		update_gizmos()
@export var oblique_part_flipped := false:
	set(value):
		oblique_part_flipped = value
		update_gizmos()

@export var clear_blocks := true
@export var fill := false
@export var fill_start_distance := 0.7


func _process_block(new_block: RoommateBlock, blocks_range: AABB) -> RoommateBlock:
	new_block.type_id = RoommateBlock.OBLIQUE_TYPE
	
	var used_size := blocks_range.size
	used_size[extend_axis] = 0
	
	var max_side_size := used_size[used_size.max_axis_index()]
	
	var up_axis := Vector3.ONE
	up_axis[extend_axis] = 0
	up_axis[used_size.max_axis_index()] = 0
	var forward_axis := Vector3.ONE
	forward_axis[extend_axis] = 0
	forward_axis[up_axis.max_axis_index()] = 0
	
	var plane := get_oblique_plane(blocks_range)
	var ray_front := plane.intersects_ray(new_block.center, up_axis)
	var ray_back := plane.intersects_ray(new_block.center, -up_axis)
	var intersection := ray_front as Vector3 if ray_front else ray_back as Vector3
	var anchor := intersection - new_block.center + Vector3.ONE / 2
	var plane_distance := plane.distance_to(new_block.center)
	var has_fill := plane_distance <= minf(-fill_start_distance, 0) and fill
	
	if not anchor.clamp(Vector3.ZERO, Vector3.ONE).is_equal_approx(anchor):
		if has_fill:
			new_block.type_id = RoommateBlock.OUT_OF_BOUNDS_TYPE
			return new_block
		if not clear_blocks:
			return null
		new_block.type_id = RoommateBlock.SPACE_TYPE
		var space_hide_predicate := func(part: RoommatePart) -> bool:
			var extend_axis_vector := Vector3.ZERO
			extend_axis_vector[extend_axis] = 1
			return not plane.is_point_over(new_block.center) and part.flow * extend_axis_vector == Vector3.ZERO
		new_block.slots = _create_visible_space_parts(space_hide_predicate)
		new_block.slots[RoommateBlock.Slot.OBLIQUE] = _create_default_part(Vector3.ONE / 2, 
				plane.normal if fill else Vector3.ZERO, Transform3D.IDENTITY, false)
		return new_block
	
	var part_scale := (used_size.length() - max_side_size) / max_side_size + 1
	var part_transform := Transform3D.IDENTITY.looking_at(-plane.normal, up_axis).scaled_local(Vector3(1, part_scale, 1))
	var is_top_facing := extend_axis != Vector3.AXIS_Y and not oblique_part_flipped
	var oblique_part := _create_default_part(anchor, plane.normal if fill else Vector3.ZERO, 
			part_transform, true, is_top_facing)
	
	var oblique_hide_predicate := func(part: RoommatePart) -> bool:
		var flow_dot := plane.normal.dot(part.flow)
		return flow_dot < 0 and not is_zero_approx(flow_dot)
	var slots := _create_visible_space_parts(oblique_hide_predicate)
	slots[RoommateBlock.Slot.OBLIQUE] = oblique_part
	new_block.slots = slots
	return new_block


func get_oblique_plane(blocks_range: AABB) -> Plane:
	var extend_axis_vector := Vector3.ZERO
	extend_axis_vector[extend_axis] = -1 if extend_axis == Vector3.AXIS_X else 1
	var used_size := blocks_range.size
	used_size[extend_axis] = 0
	var plane_normal := used_size.normalized().rotated(extend_axis_vector, PI / 2)
	if not oblique_part_rotated:
		plane_normal *= plane_normal.sign()
	if oblique_part_flipped:
		plane_normal *= -1
	return Plane(plane_normal, blocks_range.get_center())


func _create_visible_space_parts(hide_predicate: Callable) -> Dictionary:
	var slots := _create_space_parts()
	if not fill:
		return slots
	for slot_id in slots:
		var part := slots[slot_id] as RoommatePart
		if part and hide_predicate.call(part):
			slots[slot_id] = null
	return slots
