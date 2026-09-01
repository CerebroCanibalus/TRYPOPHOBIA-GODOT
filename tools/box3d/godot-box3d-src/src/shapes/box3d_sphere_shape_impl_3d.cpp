#include "box3d_sphere_shape_impl_3d.hpp"

void Box3DSphereShapeImpl3D::set_data(const Variant& p_data) {
	ERR_FAIL_COND(p_data.get_type() != Variant::FLOAT && p_data.get_type() != Variant::INT);
	radius = p_data;
}

AABB Box3DSphereShapeImpl3D::get_aabb() const {
	const Vector3 half(radius, radius, radius);
	return AABB(-half, half * 2.0);
}
