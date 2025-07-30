# Copyright (c) 2025 Kirill Rozhkov.
#
# This file is part of Roommate plugin: https://github.com/Hoork/Roommate
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

@tool
@icon("../icons/root.svg")
class_name RoommateRoot
extends Node3D
## Node that creates mesh, collision and scenes. 
## 
## Set [RoommateBlocksArea] or it's derived nodes as a child to affect generation.

const MESH_SINGLE := &"mtid_single"

const COLLISION_CONCAVE := &"csid_concave"
const COLLISION_CONVEX := &"csid_convex"

const NAV_BAKED := &"nmtid_baked"
const NAV_ASSEMBLED := &"nmtid_assembled"

@export var block_size := 1.0:
	set(value):
		block_size = value
		for node in find_children("*", RoommateBlocksArea.get_class_name()):
			var area := node as RoommateBlocksArea
			area.update_gizmos()
@export var scale_with_block_size := true
@export var force_white_vertex_color := true

@export var global_style: RoommateStyle = null

@export_group("Mesh")
@export_enum("Single Mesh") var mesh_type := "Single Mesh":
	set(value):
		const MESH_MAP := {
			"Single Mesh": MESH_SINGLE
		}
		mesh_type = value
		_mesh_type_id = MESH_MAP[value]
@export_node_path("Node3D") var linked_mesh_container: NodePath
@export var create_mesh_container_if_missing := true
@export var mesh_container_name := &"RoommateMeshContainer"
@export var index_mesh := true
@export var generate_normals := true
@export var generate_tangents := true

@export_group("Collision")
@export_enum("Concave", "Convex") var collision_shape := "Concave":
	set(value):
		const SHAPE_MAP := {
			"Concave": COLLISION_CONCAVE,
			"Convex": COLLISION_CONVEX,
		}
		collision_shape = value
		_collision_shape_id = SHAPE_MAP[value]
@export_node_path("CollisionShape3D") var linked_collision_shape: NodePath

@export_group("Scenes")
@export var scenes_group := &"roommate_generated_scenes"
@export var transform_scene_relative_to_part := true
@export var use_scenes_fallback_parent := true
@export var scenes_fallback_parent_name := &"RoommateSceneFallbackContainer"
@export var force_readable_scene_names := true

@export_group("Navigation")
@export_enum("Baked", "Assembled") var nav_mesh_type := "Baked":
	set(value):
		const NAV_MAP := {
			"Baked": NAV_BAKED,
			"Assembled": NAV_ASSEMBLED,
		}
		nav_mesh_type = value
		_nav_mesh_type_id = NAV_MAP[value]
@export_node_path("NavigationRegion3D") var linked_navigation_region: NodePath
@export var bake_nav_on_thread := true

var _mesh_type_id := MESH_SINGLE
var _collision_shape_id := COLLISION_CONCAVE
var _nav_mesh_type_id := NAV_BAKED
var _part_processors := {
	RoommateBlock.SPACE_TYPE: _process_space_block_part,
	RoommateBlock.OBLIQUE_TYPE: _process_oblique_block_part,
	RoommateBlock.NODRAW_TYPE: _process_nodraw_block_part,
}


static func get_class_name() -> StringName:
	return &"RoommateRoot"


func generate() -> void:
	# Searching for areas which are not children of other root nodes
	var child_areas := find_children("*", RoommateBlocksArea.get_class_name())
	var child_roots := find_children("*", get_class_name())

	var areas: Array[RoommateBlocksArea] = []
	areas.assign(child_areas.filter(_filter_by_parents.bind(child_roots)))
	areas.sort_custom(_sort_by_area_apply_order)
	if child_roots.size() > 0:
		push_warning("RoommateRoot has other RoommateRoots as a children. " + 
				"Their BlocksAreas are ignored.")
	if areas.size() == 0:
		push_warning("RoommateRoot doesnt own any blocks areas.")
		return
	
	# Creating all the blocks that defined by areas and applying styles
	var all_blocks := {}
	for area in areas:
		var area_blocks := area.create_blocks(global_transform, block_size)
		for new_block_position in area_blocks:
			var new_block := area_blocks[new_block_position] as RoommateBlock
			if not new_block:
				continue
			if new_block.type_id == RoommateBlock.OUT_OF_BOUNDS_TYPE:
				all_blocks.erase(new_block_position)
				continue
			all_blocks[new_block_position] = new_block
	
	# Applying internal style
	var internal_style := preload("../resources/internal_style.gd").new()
	if scale_with_block_size:
		internal_style.scale = Vector3.ONE * block_size
	internal_style.force_white_vertex_color = force_white_vertex_color
	internal_style.apply(all_blocks)
	
	# Applying global style
	if global_style:
		global_style.apply(all_blocks)
	
	# Applying area styles
	var areas_with_style := areas.filter(_filter_by_style) as Array[RoommateBlocksArea]
	areas_with_style.sort_custom(_sort_by_style)
	for area in areas_with_style:
		var area_blocks := {}
		for area_block_position in area.get_block_positions(global_transform, block_size):
			var area_block := all_blocks.get(area_block_position) as RoommateBlock
			if area_block:
				area_blocks[area_block_position] = area_block
		area.style.apply(area_blocks)
	
	# creating collections
	var surface_tools := {}
	var collision_faces := PackedVector3Array()
	var scene_infos: Array[Dictionary] = []
	var nav_tool := SurfaceTool.new()
	
	# generating everything
	for block_position in all_blocks:
		var block := all_blocks[block_position] as RoommateBlock
		if not _part_processors.has(block.type_id):
			push_error("Unknown block type: %s." % block.type_id)
			continue
		var processor := _part_processors[block.type_id] as Callable
		for slot_id in block.slots:
			var part := block.slots.get(slot_id) as RoommatePart
			var processed_part := processor.call(slot_id, part, block, all_blocks) as RoommatePart
			if processed_part:
				_generate_part(processed_part, block, surface_tools, 
						collision_faces, scene_infos, nav_tool)
	
	# applying mesh
	match _mesh_type_id:
		MESH_SINGLE:
			_generate_single_mesh(surface_tools)
		_:
			push_error("Unknown mesh type id %s." % _mesh_type_id)
	
	# applying collision
	var collision_shape_node := get_node_or_null(linked_collision_shape) as CollisionShape3D
	if collision_shape_node:
		var shape: Shape3D
		match _collision_shape_id:
			COLLISION_CONCAVE:
				var concave := ConcavePolygonShape3D.new()
				concave.set_faces(collision_faces)
				collision_shape_node.shape = concave
			COLLISION_CONVEX:
				var convex := ConvexPolygonShape3D.new()
				convex.points = collision_faces.duplicate()
				collision_shape_node.shape = convex
			_:
				push_error("Unknown collision shape id %s." % _collision_shape_id)
	
	#applying scenes
	clear_scenes()
	for info in scene_infos:
		var scene_parent := get_node_or_null(info[&"parent_path"])
		var valid_parent := scene_parent and (is_ancestor_of(scene_parent) or self == scene_parent)
		if info[&"parent_path"].is_empty():
			push_warning("Scene creation. Path is empty")
		elif not valid_parent:
			push_warning("Scene creation. There is no valid node on path %s" % info[&"parent_path"])
		
		if info[&"parent_path"].is_empty() or not valid_parent:
			if not use_scenes_fallback_parent:
				continue
			var fallback := get_node_or_null(NodePath(scenes_fallback_parent_name))
			if not fallback:
				fallback = Node3D.new()
				fallback.name = scenes_fallback_parent_name
				add_child(fallback)
				fallback.owner = owner
				fallback.add_to_group(scenes_group, true)
			scene_parent = fallback
		
		var new_scene := info[&"scene"].instantiate() as Node
		scene_parent.add_child(new_scene, force_readable_scene_names)
		new_scene.owner = owner
		new_scene.add_to_group(scenes_group, true)
		
		var node3d_scene := new_scene as Node3D
		if not node3d_scene:
			continue
		if transform_scene_relative_to_part:
			node3d_scene.global_transform = global_transform * info[&"scene_transform"]
		else:
			node3d_scene.transform = info[&"scene_transform"]
	
	# applying navigation
	var navigation_region := get_node_or_null(linked_navigation_region) as NavigationRegion3D
	if navigation_region:
		var nav_mesh := navigation_region.navigation_mesh
		if not nav_mesh:
			nav_mesh = NavigationMesh.new()
			navigation_region.navigation_mesh = nav_mesh
		match _nav_mesh_type_id:
			NAV_BAKED:
				navigation_region.bake_navigation_mesh(bake_nav_on_thread)
			NAV_ASSEMBLED:
				nav_tool.index()
				nav_mesh.create_from_mesh(nav_tool.commit())
				navigation_region.update_gizmos()
			_:
				push_error("Unknown nav mesh type id %s." % _nav_mesh_type_id)


func register_block_type_id(block_type_id: StringName, part_processor: Callable) -> void:
	if _part_processors.has(block_type_id):
		push_error("Block type %s already registered." % block_type_id)
		return
	_part_processors[block_type_id] = part_processor


func clear_scenes() -> void:
	var all_scenes := get_tree().get_nodes_in_group(scenes_group)
	var child_roots := find_children("*", get_class_name())
	var filter_by_self := func (target: Node) -> bool:
		return is_ancestor_of(target)
	var scenes := all_scenes.filter(filter_by_self).filter(_filter_by_parents.bind(child_roots)) as Array[Node]
	for scene in scenes:
		scene.get_parent().remove_child(scene)
		scene.queue_free()


func _generate_part(part: RoommatePart, parent_block: RoommateBlock, 
		surface_tools: Dictionary, collision_faces: PackedVector3Array,
		scene_infos: Array[Dictionary], nav_tool: SurfaceTool) -> void:
	if not part:
		return
	var part_origin := parent_block.position * block_size + block_size * part.anchor
	
	if part.collision_mesh:
		var part_collision_faces := part.collision_transform.translated(part_origin) * part.collision_mesh.get_faces()
		collision_faces.append_array(part_collision_faces)
	
	if part.scene:
		var info := {}
		info[&"scene"] = part.scene
		info[&"scene_transform"] = part.scene_transform.translated(part_origin)
		info[&"parent_path"] = part.scene_parent_path
		info.make_read_only()
		scene_infos.append(info)
	
	if part.nav_mesh:
		for surface_id in part.nav_mesh.get_surface_count():
			nav_tool.append_from(part.nav_mesh, surface_id, part.nav_transform.translated(part_origin))
	
	if not part.mesh:
		return
	for surface_id in part.mesh.get_surface_count():
		var part_surface_override := part.resolve_surface_override_with_fallback(surface_id)
		
		# modifying mesh
		var part_mesh := ArrayMesh.new()
		var mesh_arrays := part.mesh.surface_get_arrays(surface_id)
		if part_surface_override.flip_faces:
			if mesh_arrays[Mesh.ARRAY_INDEX] and mesh_arrays[Mesh.ARRAY_INDEX].size() > 0:
				mesh_arrays[Mesh.ARRAY_INDEX].reverse()
			else:
				push_warning("Cant flip faces. Mesh array doesnt have indexes.")
		part_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
		var mesh_data_tool := MeshDataTool.new()
		var create_error := mesh_data_tool.create_from_surface(part_mesh, 0)
		assert(create_error == OK)
		
		for vertex_id in mesh_data_tool.get_vertex_count():
			var uv := mesh_data_tool.get_vertex_uv(vertex_id)
			mesh_data_tool.set_vertex_uv(vertex_id, part_surface_override.uv_transform * uv)
			var color := mesh_data_tool.get_vertex_color(vertex_id)
			mesh_data_tool.set_vertex_color(vertex_id, color.lerp(part_surface_override.color, part_surface_override.color_weight))
		
		part_mesh.clear_surfaces()
		var commit_error := mesh_data_tool.commit_to_surface(part_mesh)
		assert(commit_error == OK)
		
		# appending surfaces
		var part_material := part.mesh.surface_get_material(surface_id)
		if part_surface_override.material:
			part_material = part_surface_override.material
			
		if not surface_tools.has(part_material):
			var new_surface_tool := SurfaceTool.new()
			new_surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			new_surface_tool.set_material(part_material)
			surface_tools[part_material] = new_surface_tool
		var surface_tool := surface_tools[part_material] as SurfaceTool
		surface_tool.append_from(part_mesh, 0, part.mesh_transform.translated(part_origin))


func _generate_single_mesh(surface_tools: Dictionary) -> void:
	var container := _resolve_mesh_container() as MeshInstance3D
	if not container:
		return
	var result_mesh := ArrayMesh.new()
	for surface_material in surface_tools:
		var tool := surface_tools[surface_material] as SurfaceTool
		if index_mesh:
			tool.index()
		if generate_normals:
			tool.generate_normals()
		if generate_tangents:
			tool.generate_tangents()
		tool.commit(result_mesh)
		result_mesh.surface_set_material(result_mesh.get_surface_count() - 1, surface_material)
	container.mesh = result_mesh


func _resolve_mesh_container() -> Node3D:
	var container := get_node_or_null(linked_mesh_container) as Node3D
	if container:
		if _mesh_type_id == MESH_SINGLE and not container is MeshInstance3D:
			push_error("Wrong type of mesh container. MeshInstance3D expected.")
			return null
		return container
	if create_mesh_container_if_missing:
		container = MeshInstance3D.new() if _mesh_type_id == MESH_SINGLE else Node3D.new()
		container.name = mesh_container_name
		add_child(container)
		container.owner = owner
		linked_mesh_container = get_path_to(container)
	return container


func _process_space_block_part(slot_id: StringName, part: RoommatePart, block: RoommateBlock, 
		all_blocks: Dictionary) -> RoommatePart:
	if not part:
		return null
	var next_position := block.position + (part.flow as Vector3i)
	var next_block := all_blocks.get(next_position) as RoommateBlock
	return part if not next_block or part.flow == Vector3.ZERO else null


func _process_oblique_block_part(slot_id: StringName, part: RoommatePart, block: RoommateBlock, 
		all_blocks: Dictionary) -> RoommatePart:
	if not part:
		return null
	var next_position := block.position + (part.flow as Vector3i)
	var next_block := all_blocks.get(next_position) as RoommateBlock
	if slot_id == RoommateBlock.Slot.OBLIQUE:
		return part
	return part if not next_block or part.flow == Vector3.ZERO else null


func _process_nodraw_block_part(slot_id: StringName, part: RoommatePart, block: RoommateBlock, 
		all_blocks: Dictionary) -> RoommatePart:
	return null


func _sort_by_area_apply_order(a: RoommateBlocksArea, b: RoommateBlocksArea) -> bool:
	return a.apply_order < b.apply_order


func _sort_by_style(a: RoommateBlocksArea, b: RoommateBlocksArea) -> bool:
	return a.style.apply_order < b.style.apply_order


func _filter_by_style(target: RoommateBlocksArea) -> bool:
	return target.style != null


func _filter_by_parents(target: Node, parents: Array[Node]) -> bool:
	for parent in parents:
		if parent.is_ancestor_of(target):
			return false
	return true
