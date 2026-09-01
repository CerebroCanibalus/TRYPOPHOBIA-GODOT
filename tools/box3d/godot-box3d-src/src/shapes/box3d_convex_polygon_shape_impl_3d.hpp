#pragma once

#include "box3d_shape_impl_3d.hpp"

#include <godot_cpp/templates/vector.hpp>

#include <box3d/types.h>

// ConvexPolygonShape3D -> a b3HullData* built once via b3CreateHull() from the point
// cloud and shared by every attaching Box3DShapeInstance3D (mirrors how Godot's own
// Shape3D resources are shared across bodies). Recreated whenever the point data changes.
class Box3DConvexPolygonShapeImpl3D final : public Box3DShapeImpl3D {
public:
	~Box3DConvexPolygonShapeImpl3D() override;

	ShapeType get_type() const override { return PhysicsServer3D::SHAPE_CONVEX_POLYGON; }

	Variant get_data() const override;

	void set_data(const Variant& p_data) override;

	AABB get_aabb() const override { return aabb; }

	// Returns the shared hull, building it lazily if needed. Never null once points exist.
	const b3HullData* get_hull() const { return hull; }

private:
	void _rebuild_hull();

	PackedVector3Array points;
	b3HullData* hull = nullptr;
	AABB aabb;
};
