#include "box3d_pin_joint_impl_3d.hpp"

#include <box3d/box3d.h>

namespace {
// Godot's PinJoint3D corrects the positional error with a Baumgarte term
// `depth * bias / h`, i.e. `bias` is the fraction of the error removed per step
// (default 0.3). Box3D instead tunes the point-to-point constraint with a stiffness in
// Hz, whose bias rate is `h*w / (2*zeta + h*w)` with `w = 2*pi*hertz`. Solving for the
// frequency that yields the same per-step fraction at the nominal 60 Hz tick keeps the
// two solvers behaviourally close.
float pin_bias_to_hertz(real_t p_bias) {
	const float tau = (float)(p_bias < 0.01 ? 0.01 : (p_bias > 0.99 ? 0.99 : p_bias));
	const float h = 1.0f / 60.0f;
	return tau / ((float)Math_PI * h * (1.0f - tau));
}

float pin_damping_ratio(real_t p_damping) {
	return (float)(p_damping < 0.01 ? 0.01 : p_damping);
}
} // namespace

Box3DPinJointImpl3D::Box3DPinJointImpl3D(
		Box3DBodyImpl3D* p_body_a,
		Box3DBodyImpl3D* p_body_b,
		const Transform3D& p_local_frame_a,
		const Transform3D& p_local_frame_b) :
		Box3DJointImpl3D(p_body_a, p_body_b, p_local_frame_a, p_local_frame_b) {
}

b3JointId Box3DPinJointImpl3D::_create_joint_id(b3WorldId p_world_id, b3BodyId p_body_a, b3BodyId p_body_b, b3Transform p_local_frame_a, b3Transform p_local_frame_b) {
	b3SphericalJointDef def = b3DefaultSphericalJointDef();
	def.base.bodyIdA = p_body_a;
	def.base.bodyIdB = p_body_b;
	def.base.localFrameA = p_local_frame_a;
	def.base.localFrameB = p_local_frame_b;

	// Godot's PinJoint3D is a pure point-to-point constraint: the two anchors are kept
	// coincident and ROTATION IS FREE. Box3D's spherical joint already provides exactly
	// that through its point-to-point solve, so the angular spring MUST stay disabled.
	// An earlier revision enabled it (hertz = bias * 30), which added a rotational PD
	// controller pulling the frames toward identity and made every pinned pair rigid
	// (most visible on the ragdoll's grab joints).
	def.enableSpring = false;

	// Godot's BIAS/DAMPING tune the positional constraint; map them onto Box3D's joint
	// constraint tuning rather than onto the (now unused) angular spring.
	def.base.constraintHertz = pin_bias_to_hertz(bias);
	def.base.constraintDampingRatio = pin_damping_ratio(damping);

	return b3CreateSphericalJoint(p_world_id, &def);
}

real_t Box3DPinJointImpl3D::get_param(Param p_param) const {
	switch (p_param) {
		case PhysicsServer3D::PIN_JOINT_DAMPING:
			return damping;
		case PhysicsServer3D::PIN_JOINT_BIAS:
			return bias;
		case PhysicsServer3D::PIN_JOINT_IMPULSE_CLAMP:
			return impulse_clamp;
		default:
			return 0.0;
	}
}

void Box3DPinJointImpl3D::set_param(Param p_param, real_t p_value) {
	switch (p_param) {
		case PhysicsServer3D::PIN_JOINT_DAMPING:
			damping = p_value;
			if (has_joint_id()) {
				b3Joint_SetConstraintTuning(get_joint_id(), pin_bias_to_hertz(bias), pin_damping_ratio(damping));
			}
			break;
		case PhysicsServer3D::PIN_JOINT_BIAS:
			bias = p_value;
			if (has_joint_id()) {
				b3Joint_SetConstraintTuning(get_joint_id(), pin_bias_to_hertz(bias), pin_damping_ratio(damping));
			}
			break;
		case PhysicsServer3D::PIN_JOINT_IMPULSE_CLAMP:
			impulse_clamp = p_value;
			WARN_PRINT_ONCE("Box3D: PinJoint3D's IMPULSE_CLAMP parameter has no Box3D equivalent and is ignored.");
			break;
		default:
			break;
	}
}
