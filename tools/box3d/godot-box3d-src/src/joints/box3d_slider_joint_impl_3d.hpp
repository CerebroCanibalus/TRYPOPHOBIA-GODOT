#pragma once

#include "box3d_joint_impl_3d.hpp"

#include <godot_cpp/templates/hash_map.hpp>

// SliderJoint3D -> b3PrismaticJointDef/b3CreatePrismaticJoint. Confirmed: Box3D's
// prismatic joint slides along the LOCAL X axis in local frame A (doc comment explicit),
// whereas Godot's SliderJoint3D slides along the local X axis of its own node too, so no
// axis remap is needed here (see Box3DSliderJoint3D::_bind_joint for the local frame
// construction). Only LINEAR_LIMIT_UPPER/LOWER map to Box3D's 1-DOF slider limits; every
// other SliderJointParam (angular limits, softness/restitution/damping tuning) has no
// Box3D equivalent and is a no-op + WARN_PRINT_ONCE, since Box3D's prismatic joint is a
// pure 1-DOF slider with no angular sub-parameters.
class Box3DSliderJointImpl3D final : public Box3DJointImpl3D {
public:
	using Param = PhysicsServer3D::SliderJointParam;

	Box3DSliderJointImpl3D(Box3DBodyImpl3D* p_body_a, Box3DBodyImpl3D* p_body_b, const Transform3D& p_local_frame_a, const Transform3D& p_local_frame_b);

	PhysicsServer3D::JointType get_type() const override { return PhysicsServer3D::JOINT_TYPE_SLIDER; }

	real_t get_param(Param p_param) const;

	void set_param(Param p_param, real_t p_value);

protected:
	b3JointId _create_joint_id(b3WorldId p_world_id, b3BodyId p_body_a, b3BodyId p_body_b, b3Transform p_local_frame_a, b3Transform p_local_frame_b) override;

private:
	void _apply_limit();

	real_t limit_upper = 1.0;
	real_t limit_lower = -1.0;

	HashMap<int, real_t> unsupported_params;
};
