#pragma once

#include "box3d_joint_impl_3d.hpp"

// ConeTwistJoint3D -> b3SphericalJointDef/b3CreateSphericalJoint + cone/twist limits.
//
// Box3D does not expose a dedicated ConeTwist joint type; instead, its SphericalJoint
// (which we also use for PinJoint3D) exposes optional cone (swing) and twist limits via
// dedicated API. We configure both at creation time and apply runtime updates via
// b3SphericalJoint_SetConeLimit / b3SphericalJoint_SetTwistLimits.
//
// Span units: PhysicsServer3D delivers SWING_SPAN / TWIST_SPAN in RADIANS (the scene
// nodes convert degrees->radians before calling the server), and Box3D also works in
// radians, so set_param() stores them as-is. Do not convert again.
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
	// Both spans are stored in RADIANS. SWING_SPAN is the cone half-angle; TWIST_SPAN is
	// the full symmetric range around 0 (expanded to lower = -span/2 / upper = +span/2
	// when calling b3SphericalJoint_SetTwistLimits). Defaults mirror Godot's
	// PhysicalBone3D::ConeJointData so a ragdoll that never overrides them behaves the
	// same as with the built-in/Jolt solvers.
	real_t swing_span = Math_PI * 0.25; // 45 degrees
	real_t twist_span = Math_PI;        // 180 degrees

	// Godot's ConeTwistJoint3D tuning parameters. They map 1:1 onto Box3D's per-limit
	// constraint softness via b3SphericalJoint_SetLimitSoftness/SetLimitBias/
	// SetLimitRelaxation. SOFTNESS = limit stiffness (higher = softer), BIAS = position
	// correction factor, RELAXATION = impulse damping.
	real_t bias = 0.3;
	real_t softness = 0.8;
	real_t relaxation = 1.0;

	void _apply_cone_limit();
	void _apply_twist_limits();
};
