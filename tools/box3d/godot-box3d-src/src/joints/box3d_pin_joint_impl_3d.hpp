#pragma once

#include "box3d_joint_impl_3d.hpp"

// PinJoint3D -> b3SphericalJoint (ball-and-socket).
//
// Godot's PinJoint3D is a PURE point-to-point constraint: both anchors are kept coincident and
// rotation is free. Box3D's spherical joint provides exactly that through its point-to-point
// solve, so the angular spring is always disabled. BIAS (fraction of the positional error
// corrected per step) and DAMPING are mapped onto Box3D's joint constraint tuning (stiffness
// in Hz + damping ratio); IMPULSE_CLAMP has no Box3D equivalent.
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
	// BIAS (tau, ~0.3) is the fraction of the anchor separation that is corrected per step;
	// DAMPING (~1.0) scales the relative-velocity term. Both are converted to Box3D's
	// constraint hertz/dampingRatio in _create_joint_id and set_param.
	real_t damping = 1.0;
	real_t bias = 0.3;
	real_t impulse_clamp = 0.0;
};
