# Copyright (c) 2025 Kirill Rozhkov.
#
# This file is part of Roommate plugin: https://github.com/Hoork/Roommate
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

@tool
extends "./object_setter.gd"

const SURFACE_OVERRIDE_SETTER := preload("./surface_override_setter.gd")

var selected_slot_ids: Array[StringName] = []
var inverse_selection := false
var handle_part: Callable

var anchor: VECTOR3_SETTER:
	get: return resolve_value_setter(&"anchor", VECTOR3_SETTER)
var flow: VECTOR3_SETTER:
	get: return resolve_value_setter(&"flow", VECTOR3_SETTER)

var mesh_transform: TRANSFORM3D_SETTER:
	get: return resolve_value_setter(&"mesh_transform", TRANSFORM3D_SETTER)
var collision_transform: TRANSFORM3D_SETTER:
	get: return resolve_value_setter(&"collision_transform", TRANSFORM3D_SETTER)
var scene_transform: TRANSFORM3D_SETTER:
	get: return resolve_value_setter(&"scene_transform", TRANSFORM3D_SETTER)
var nav_transform: TRANSFORM3D_SETTER:
	get: return resolve_value_setter(&"nav_transform", TRANSFORM3D_SETTER)

var mesh: MESH_SETTER:
	get: return resolve_value_setter(&"mesh", MESH_SETTER)
var collision_mesh: MESH_SETTER:
	get: return resolve_value_setter(&"collision_mesh", MESH_SETTER)
var scene: PACKED_SCENE_SETTER:
	get: return resolve_value_setter(&"scene", PACKED_SCENE_SETTER)
var nav_mesh: MESH_SETTER:
	get: return resolve_value_setter(&"nav_mesh", MESH_SETTER)

var scene_parent_path: NODE_PATH_SETTER:
	get: return resolve_value_setter(&"scene_parent_path", NODE_PATH_SETTER)

var surface_overrides := {}
var fallback_surface_override: SURFACE_OVERRIDE_SETTER = null


func apply(block: RoommateBlock) -> void:
	for slot_id in block.slots:
		var selected := selected_slot_ids.has(slot_id)
		if (not inverse_selection and not selected) or (inverse_selection and selected):
			continue
		var current_part := block.slots.get(slot_id) as RoommatePart
		if not current_part:
			continue
		
		for property_name in _value_setters:
			var setter := _value_setters[property_name] as BASE_VALUE_SETTER
			setter.apply(current_part)
		if fallback_surface_override:
			fallback_surface_override.apply(current_part.fallback_surface_override)
		for surface_id in surface_overrides:
			var override_setter := surface_overrides[surface_id] as SURFACE_OVERRIDE_SETTER
			if not override_setter:
				push_warning("Surface override setter is null.")
				continue
			var current_override := current_part.resolve_surface_override(surface_id)
			override_setter.apply(current_override)
		
		if handle_part.is_valid():
			handle_part.call(slot_id, current_part, block)


func override_surface(surface_id: int) -> SURFACE_OVERRIDE_SETTER:
	if surface_overrides.has(surface_id):
		return surface_overrides[surface_id] as SURFACE_OVERRIDE_SETTER
	var new_override := SURFACE_OVERRIDE_SETTER.new()
	surface_overrides[surface_id] = new_override
	return new_override


func override_fallback_surface() -> SURFACE_OVERRIDE_SETTER:
	if not fallback_surface_override:
		fallback_surface_override = SURFACE_OVERRIDE_SETTER.new()
	return fallback_surface_override
