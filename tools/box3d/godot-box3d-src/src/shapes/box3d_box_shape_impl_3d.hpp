#pragma once

#include "box3d_shape_impl_3d.hpp"

class Box3DBoxShapeImpl3D final : public Box3DShapeImpl3D {
public:
	ShapeType get_type() const override { return PhysicsServer3D::SHAPE_BOX; }

	Variant get_data() const override { return half_extents; }

	void set_data(const Variant& p_data) override;

	AABB get_aabb() const override;

	Vector3 get_half_extents() const { return half_extents; }

private:
	Vector3 half_extents = Vector3(0.5, 0.5, 0.5);
};
