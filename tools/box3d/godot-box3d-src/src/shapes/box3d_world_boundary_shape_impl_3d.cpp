#include "box3d_world_boundary_shape_impl_3d.hpp"

void Box3DWorldBoundaryShapeImpl3D::set_data(const Variant& p_data) {
	ERR_FAIL_COND(p_data.get_type() != Variant::PLANE);
	plane = p_data;
}

AABB Box3DWorldBoundaryShapeImpl3D::get_aabb() const {
	const Vector3 half(PLATE_HALF_EXTENT, PLATE_HALF_THICKNESS, PLATE_HALF_EXTENT);
	return AABB(-half, half * 2.0);
}
