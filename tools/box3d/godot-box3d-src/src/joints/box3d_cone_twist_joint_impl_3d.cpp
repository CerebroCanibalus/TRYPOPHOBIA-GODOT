#include "box3d_cone_twist_joint_impl_3d.hpp"

#include <box3d/box3d.h>

Box3DConeTwistJointImpl3D::Box3DConeTwistJointImpl3D(
		Box3DBodyImpl3D* p_body_a,
		Box3DBodyImpl3D* p_body_b,
		const Transform3D& p_local_frame_a,
		const Transform3D& p_local_frame_b) :
		Box3DJointImpl3D(p_body_a, p_body_b, p_local_frame_a, p_local_frame_b) {
}

b3JointId Box3DConeTwistJointImpl3D::_create_joint_id(b3WorldId p_world_id, b3BodyId p_body_a, b3BodyId p_body_b, b3Transform p_local_frame_a, b3Transform p_local_frame_b) {
	b3SphericalJointDef def = b3DefaultSphericalJointDef();
	def.base.bodyIdA = p_body_a;
	def.base.bodyIdB = p_body_b;
	def.base.localFrameA = p_local_frame_a;
	def.base.localFrameB = p_local_frame_b;

	// ConeTwist semantic: always enable both limits. The joint is the canonical use case
	// for these Box3D options (vs. PinJoint3D which enables only the spring).
	def.enableConeLimit = true;
	def.coneAngle = (float)swing_span;
	def.enableTwistLimit = true;
	def.lowerTwistAngle = (float)(-twist_span * 0.5);
	def.upperTwistAngle = (float)(twist_span * 0.5);

	// Godot's ConeTwistJoint3D SOFTNESS/BIAS/RELAXATION map 1:1 onto Box3D's per-limit
	// constraint tuning. With Godot's defaults (0.8 / 0.3 / 1.0) this reproduces the
	// previous joint-constraint softness, so existing scenes are unaffected.
	def.limitSoftness = (float)softness;
	def.limitBias = (float)bias;
	def.limitRelaxation = (float)relaxation;

	return b3CreateSphericalJoint(p_world_id, &def);
}

real_t Box3DConeTwistJointImpl3D::get_param(Param p_param) const {
	switch (p_param) {
		case PhysicsServer3D::CONE_TWIST_JOINT_SWING_SPAN:
			return swing_span;
		case PhysicsServer3D::CONE_TWIST_JOINT_TWIST_SPAN:
			return twist_span;
		case PhysicsServer3D::CONE_TWIST_JOINT_BIAS:
			return bias;
		case PhysicsServer3D::CONE_TWIST_JOINT_SOFTNESS:
			return softness;
		case PhysicsServer3D::CONE_TWIST_JOINT_RELAXATION:
			return relaxation;
		default:
			return 0.0;
	}
}

void Box3DConeTwistJointImpl3D::set_param(Param p_param, real_t p_value) {
	switch (p_param) {
		case PhysicsServer3D::CONE_TWIST_JOINT_SWING_SPAN: {
			// PhysicsServer3D delivers swing_span/twist_span ALREADY in radians:
			// PhysicalBone3D::ConeJointData and ConeTwistJoint3D call Math::deg_to_rad()
			// before forwarding to the server, and Box3D also expects radians. Store the
			// value as-is. Converting again here shrank a 45 degree cone to ~0.8 degrees
			// and locked every joint (the active ragdoll went rigid).
			swing_span = p_value;
			_apply_cone_limit();
		} break;
		case PhysicsServer3D::CONE_TWIST_JOINT_TWIST_SPAN: {
			twist_span = p_value;
			_apply_twist_limits();
		} break;
		case PhysicsServer3D::CONE_TWIST_JOINT_BIAS:
			bias = p_value;
			if (has_joint_id()) {
				b3SphericalJoint_SetLimitBias(get_joint_id(), (float)bias);
			}
			break;
		case PhysicsServer3D::CONE_TWIST_JOINT_SOFTNESS:
			softness = p_value;
			if (has_joint_id()) {
				b3SphericalJoint_SetLimitSoftness(get_joint_id(), (float)softness);
			}
			break;
		case PhysicsServer3D::CONE_TWIST_JOINT_RELAXATION:
			relaxation = p_value;
			if (has_joint_id()) {
				b3SphericalJoint_SetLimitRelaxation(get_joint_id(), (float)relaxation);
			}
			break;
		default:
			break;
	}
}

void Box3DConeTwistJointImpl3D::_apply_cone_limit() {
	if (has_joint_id()) {
		b3SphericalJoint_EnableConeLimit(get_joint_id(), true);
		b3SphericalJoint_SetConeLimit(get_joint_id(), (float)swing_span);
	}
}

void Box3DConeTwistJointImpl3D::_apply_twist_limits() {
	if (has_joint_id()) {
		b3SphericalJoint_EnableTwistLimit(get_joint_id(), true);
		b3SphericalJoint_SetTwistLimits(get_joint_id(), (float)(-twist_span * 0.5), (float)(twist_span * 0.5));
	}
}
