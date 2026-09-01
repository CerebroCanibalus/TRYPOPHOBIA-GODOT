#pragma once

#include "box3d_shape_impl_3d.hpp"

#include <godot_cpp/variant/plane.hpp>

// WorldBoundaryShape3D -> Box3D has no infinite-plane primitive. Approximated with a very
// large flattened box hull, positioned/oriented to match the plane's normal and distance
// (baked into the shape instance's local transform, see Box3DShapeInstance3D). Documented
// limitation: this is a large finite plate, not a true infinite half-space.
class Box3DWorldBoundaryShapeImpl3D final : public Box3DShapeImpl3D {
public:
	ShapeType get_type() const override { return PhysicsServer3D::SHAPE_WORLD_BOUNDARY; }

	Variant get_data() const override { return plane; }

	void set_data(const Variant& p_data) override;

	AABB get_aabb() const override;

	Plane get_plane() const { return plane; }

	// Half-extent of the approximating plate, in meters. Large enough to behave like an
	// infinite plane for typical scene scales.
	static constexpr real_t PLATE_HALF_EXTENT = 5000.0;
	static constexpr real_t PLATE_HALF_THICKNESS = 5.0;

private:
	Plane plane = Plane(Vector3(0, 1, 0), 0);
};
