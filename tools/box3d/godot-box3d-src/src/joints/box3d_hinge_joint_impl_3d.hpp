#pragma once

#include "box3d_joint_impl_3d.hpp"

// HingeJoint3D -> b3RevoluteJointDef/b3CreateRevoluteJoint. Confirmed: Box3D's revolute
// joint rotates about the LOCAL Z axis of the joint frames, whereas Godot's HingeJoint3D
// specifies its axis arbitrarily in local space. The joint frames passed to
// b3CreateRevoluteJoint (see Box3DHingeJoint3D::_bind_joint, which builds
// local_frame_a/b) must therefore already carry a rotation mapping local Z to the Godot
// hinge axis direction; this class only forwards params to the resulting b3JointId.
class Box3DHingeJointImpl3D final : public Box3DJointImpl3D {
public:
	using Param = PhysicsServer3D::HingeJointParam;
	using Flag = PhysicsServer3D::HingeJointFlag;

	Box3DHingeJointImpl3D(Box3DBodyImpl3D* p_body_a, Box3DBodyImpl3D* p_body_b, const Transform3D& p_local_frame_a, const Transform3D& p_local_frame_b);

	PhysicsServer3D::JointType get_type() const override { return PhysicsServer3D::JOINT_TYPE_HINGE; }

	real_t get_param(Param p_param) const;

	void set_param(Param p_param, real_t p_value);

	bool get_flag(Flag p_flag) const;

	void set_flag(Flag p_flag, bool p_enabled);

protected:
	b3JointId _create_joint_id(b3WorldId p_world_id, b3BodyId p_body_a, b3BodyId p_body_b, b3Transform p_local_frame_a, b3Transform p_local_frame_b) override;

private:
	void _apply_limit();

	void _apply_motor();

	real_t bias = 0.3;
	real_t limit_upper = Math_PI * 0.5;
	real_t limit_lower = -Math_PI * 0.5;
	real_t limit_bias = 0.3;
	real_t limit_softness = 0.9;
	real_t limit_relaxation = 1.0;
	real_t motor_target_velocity = 0.0;
	real_t motor_max_impulse = 1.0;

	bool use_limit = false;
	bool enable_motor = false;
};
