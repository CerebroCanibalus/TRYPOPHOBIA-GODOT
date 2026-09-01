#pragma once

#include "box3d_joint_impl_3d.hpp"

// PinJoint3D -> b3SphericalJointDef/b3CreateSphericalJoint (ball-and-socket). Chosen over
// b3_distanceJoint since Godot's PinJoint3D is 3-DOF-rotation-free/0-translation, matching
// spherical joint semantics far better.
class Box3DPinJointImpl3D final : public Box3DJointImpl3D {
public:
	using Param = PhysicsServer3D::PinJointParam;

	Box3DPinJointImpl3D(Box3DBodyImpl3D* p_body_a, Box3DBodyImpl3D* p_body_b, const Transform3D& p_local_frame_a, const Transform3D& p_local_frame_b);

	PhysicsServer3D::JointType get_type() const override { return PhysicsServer3D::JOINT_TYPE_PIN; }

	real_t get_param(Param p_param) const;

	void set_param(Param p_param, real_t p_value);

protected:
	b3JointId _create_joint_id(b3WorldId p_world_id, b3BodyId p_body_a, b3BodyId p_body_b, b3Transform p_local_frame_a, b3Transform p_local_frame_b) override;

private:
	// PinJointParam::DAMPING/BIAS map best-effort to hertz/dampingRatio; IMPULSE_CLAMP has
	// no Box3D equivalent (no-op + WARN_PRINT_ONCE).
	real_t damping = 1.0;
	real_t bias = 0.3;
	real_t impulse_clamp = 0.0;
};
