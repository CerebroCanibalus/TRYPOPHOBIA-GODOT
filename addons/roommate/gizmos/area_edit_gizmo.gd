# Copyright (c) 2025 Kirill Rozhkov.
#
# This file is part of Roommate plugin: https://github.com/Hoork/Roommate
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

@tool
extends EditorNode3DGizmo

const GIZMO_PLUGIN := preload("./gizmo_plugin.gd")
const MIN_AREA_SIZE := 0.002
const HANDLE_NAMES: Array[String] = ["X", "Y", "Z"]
const HANDLE_DIRECTIONS: Array[Vector3] = [
	Vector3.UP,
	Vector3.DOWN,
	Vector3.LEFT,
	Vector3.RIGHT,
	Vector3.FORWARD,
	Vector3.BACK,
]

var handles_3d_size: float = 0.0
var _original_area_global_transform: Variant = null
var _original_area_size: Variant = null


func _init() -> void:
	var version := Engine.get_version_info()
	if version["major"] == 4 and version["minor"] == 0:
		handles_3d_size = 0.1


func _get_handle_name(handle_id: int, secondary: bool) -> String:
	return "Axis Size %s" % HANDLE_NAMES[_get_handle_axis_index(handle_id)]


func _get_handle_value(handle_id: int, secondary: bool) -> Variant:
	var area := get_node_3d() as RoommateBlocksArea
	if _original_area_global_transform == null:
		_original_area_global_transform = area.global_transform
	if _original_area_size == null:
		_original_area_size = area.size
	return area.size


func _set_handle(handle_id: int, secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var area := get_node_3d() as RoommateBlocksArea
	var original_area_global_transform := _original_area_global_transform as Transform3D
	var original_area_size := _original_area_size as Vector3
	
	var handle_direction := HANDLE_DIRECTIONS[handle_id]
	var handle_axis_index := _get_handle_axis_index(handle_id)
	var handle_position := area.global_transform * _get_handle_position(handle_id, area.box)
	var handle_normal := (area.global_transform.basis * handle_direction).normalized()
	var projected_cam := (camera.global_position - handle_position).project(handle_normal) + handle_position
	var to_cam_normal := projected_cam.direction_to(camera.global_position)
	var plane := Plane(to_cam_normal, handle_position)
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_direction := camera.project_ray_normal(screen_pos)
	var hit_result := plane.intersects_ray(ray_origin, ray_direction)
	if hit_result == null:
		return
	var hit_position := hit_result as Vector3
	var projected_hit := (hit_position - handle_position).project(handle_normal) + handle_position
	
	var local_hit := original_area_global_transform.affine_inverse() * projected_hit
	var distance_sign := signf((projected_hit - original_area_global_transform.origin).dot(handle_normal))
	var delta_to_center := local_hit.length() * distance_sign
	
	if Input.is_physical_key_pressed(KEY_ALT):
		# growing in both sides
		area.global_position = original_area_global_transform.origin
		var new_area_size := delta_to_center * 2
		if Input.is_physical_key_pressed(KEY_CTRL):
			new_area_size = snappedf(new_area_size, 1)
		area.size[handle_axis_index] = maxf(new_area_size, MIN_AREA_SIZE)
		return
#
#	# growing in one side
	var new_area_size := delta_to_center + original_area_size[handle_axis_index] / 2
	if Input.is_physical_key_pressed(KEY_CTRL):
		new_area_size = snappedf(new_area_size, 1)
	new_area_size = maxf(new_area_size, MIN_AREA_SIZE)
	var grow_direction := area.global_transform.basis * handle_direction
	var grow_start := original_area_global_transform.origin - grow_direction * original_area_size[handle_axis_index] / 2
	area.global_position = grow_start + grow_direction * new_area_size / 2
	area.size[handle_axis_index] = new_area_size


func _commit_handle(handle_id: int, secondary: bool, restore, cancel: bool) -> void:
	_original_area_global_transform = null
	_original_area_size = null


func _draw_area_edit() -> void:
	var area := get_node_3d() as RoommateBlocksArea
	var area_selected := EditorPlugin.new().get_editor_interface().get_selection().get_selected_nodes().has(area)
	
	if not area_selected:
		return
	
	# area
	var area_material := get_plugin().get_material("area", self)
	add_lines(_get_aabb_lines(area.box), area_material)
	
	# handles
	var direction_to_point := func (handle_id: int) -> Vector3: 
		return _get_handle_position(handle_id, area.box)
	var handles_positions := range(HANDLE_DIRECTIONS.size()).map(direction_to_point)
	if handles_3d_size > 0:
		var handle_3d_material := get_plugin().get_material("handles_3d", self)
		for handle_position in handles_positions:
			var mesh := SphereMesh.new()
			mesh.height = handles_3d_size
			mesh.radius = handles_3d_size / 2
			add_mesh(mesh, handle_3d_material, Transform3D.IDENTITY.translated(handle_position))
	
	var handle_material := get_plugin().get_material("handles", self)
	add_handles(handles_positions, handle_material, [])


func _get_aabb_lines(aabb: AABB) -> PackedVector3Array:
	var result := PackedVector3Array()
	const TOP := [[2, 1], [0, 3]]
	const BOTTOM := [[6, 5], [4, 7]]
	for i in 2:
		for j in 2:
			# corner 1
			result.push_back(aabb.get_endpoint(TOP[0][i]))
			result.push_back(aabb.get_endpoint(TOP[1][j]))
			# corner 2
			result.push_back(aabb.get_endpoint(BOTTOM[0][i]))
			result.push_back(aabb.get_endpoint(BOTTOM[1][j]))
			# vertical line
			result.push_back(aabb.get_endpoint(TOP[i][j]))
			result.push_back(aabb.get_endpoint(BOTTOM[i][j]))
	return result


func _get_handle_axis_index(handle_id: int) -> int:
	var direction := HANDLE_DIRECTIONS[handle_id]
	if direction.x != 0:
		return Vector3.AXIS_X
	if direction.y != 0:
		return Vector3.AXIS_Y
	if direction.z != 0:
		return Vector3.AXIS_Z
	return -1


func _get_handle_position(handle_id: int, box: AABB) -> Vector3:
	return box.get_center() + box.size * HANDLE_DIRECTIONS[handle_id] * 0.5
