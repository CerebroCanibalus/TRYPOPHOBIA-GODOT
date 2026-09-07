#pragma once

#include "box3d_joint_impl_3d.hpp"

// ConeTwistJoint3D -> b3SphericalJointDef/b3CreateSphericalJoint + cone/twist limits.
//
// Box3D does not expose a dedicated ConeTwist joint type; instead, its SphericalJoint
// (which we also use for PinJoint3D) exposes optional cone (swing) and twist limits via
// dedicated API. We configure both at creation time and apply runtime updates via
// b3SphericalJoint_SetConeLimit / b3SphericalJoint_SetTwistLimits.
//
// Godot's ConeTwistJointParam uses degrees for SWING_SPAN / TWIST_SPAN; Box3D uses
// radians. Conversions happen in set_param().
class Box3DConeTwistJointImpl3D final : public Box3DJointImpl3D {
public:
	using Param = PhysicsServer3D::ConeTwistJointParam;

	Box3DConeTwistJointImpl3D(Box3DBodyImpl3D* p_body_a, Box3DBodyImpl3D* p_body_b, const Transform3D& p_local_frame_a, const Transform3D& p_local_frame_b);

	PhysicsServer3D::JointType get_type() const override { return PhysicsServer3D::JOINT_TYPE_CONE_TWIST; }

	real_t get_param(Param p_param) const;

	void set_param(Param p_param, real_t p_value);

protected:
	b3JointId _create_joint_id(b3WorldId p_world_id, b3BodyId p_body_a, b3BodyId p_body_b, b3Transform p_local_frame_a, b3Transform p_local_frame_b) override;

private:
	// SWING_SPAN is stored as the cone half-angle in radians.
	// TWIST_SPAN is the full symmetric range around 0 in radians; we expand it into
	// lower = -span/2 and upper = +span/2 when calling b3SphericalJoint_SetTwistLimits.
	real_t swing_span = Math_PI; // default: unrestricted (180 degrees)
	real_t twist_span = Math_PI; // default: unrestricted (180 degrees)

	// Bias / softness / relaxation are exposed by Godot but have no direct Box3D
	// equivalent; the cone/twist limit constraints in Box3D are hard. We accept the
	// values so the .tscn loads without error, and warn the user that they are ignored.
	real_t bias = 0.3;
	real_t softness = 0.8;
	real_t relaxation = 1.0;

	bool warned_bias = false;
	bool warned_softness = false;
	bool warned_relaxation = false;

	void _apply_cone_limit();
	void _apply_twist_limits();
};
