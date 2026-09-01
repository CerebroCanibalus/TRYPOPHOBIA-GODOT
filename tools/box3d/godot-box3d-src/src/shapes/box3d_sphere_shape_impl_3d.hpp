#pragma once

#include "box3d_shape_impl_3d.hpp"

class Box3DSphereShapeImpl3D final : public Box3DShapeImpl3D {
public:
	ShapeType get_type() const override { return PhysicsServer3D::SHAPE_SPHERE; }

	Variant get_data() const override { return radius; }

	void set_data(const Variant& p_data) override;

	AABB get_aabb() const override;

	real_t get_radius() const { return radius; }

private:
	real_t radius = 0.5;
};
