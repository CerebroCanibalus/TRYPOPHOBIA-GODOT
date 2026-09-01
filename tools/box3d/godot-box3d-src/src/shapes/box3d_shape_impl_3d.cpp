#include "box3d_shape_impl_3d.hpp"

void Box3DShapeImpl3D::add_owner(Box3DShapedObjectImpl3D* p_owner) {
	owners.insert(p_owner);
}

void Box3DShapeImpl3D::remove_owner(Box3DShapedObjectImpl3D* p_owner) {
	owners.erase(p_owner);
}
