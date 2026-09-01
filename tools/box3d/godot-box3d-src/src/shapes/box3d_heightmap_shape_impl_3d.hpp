#pragma once

#include "box3d_shape_impl_3d.hpp"

#include <godot_cpp/variant/packed_float32_array.hpp>

#include <box3d/types.h>

// HeightMapShape3D -> a b3HeightFieldData* built via b3CreateHeightField() and shared by
// every attaching Box3DShapeInstance3D. Static bodies only (matches Box3D's own
// restriction). Box3D's height field places its local origin at grid corner (0,0); Godot
// (and godot-jolt) center the grid on the shape origin instead, so the shape instance
// applies a corner-centering offset when creating the b3ShapeId (see
// Box3DShapeInstance3D::_create_shape).
class Box3DHeightMapShapeImpl3D final : public Box3DShapeImpl3D {
public:
	~Box3DHeightMapShapeImpl3D() override;

	ShapeType get_type() const override { return PhysicsServer3D::SHAPE_HEIGHTMAP; }

	Variant get_data() const override;

	void set_data(const Variant& p_data) override;

	AABB get_aabb() const override { return aabb; }

	const b3HeightFieldData* get_height_field() const { return height_field; }

	int get_width() const { return width; }

	int get_depth() const { return depth; }

private:
	void _rebuild();

	PackedFloat32Array heights;
	int width = 0;
	int depth = 0;
	b3HeightFieldData* height_field = nullptr;
	AABB aabb;
};
