#include "box3d_box_shape_impl_3d.hpp"

void Box3DBoxShapeImpl3D::set_data(const Variant& p_data) {
	ERR_FAIL_COND(p_data.get_type() != Variant::VECTOR3);
	half_extents = p_data;
}

AABB Box3DBoxShapeImpl3D::get_aabb() const {
	return AABB(-half_extents, half_extents * 2.0);
}
