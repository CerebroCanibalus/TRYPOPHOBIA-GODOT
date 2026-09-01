#pragma once

#include <box3d/id.h>

// Small wrappers around Godot's ERR_FAIL_* macros that additionally validate a Box3D
// handle via its *_IsValid() function before proceeding. These are meant to guard the
// common "handle is stale/null" failure mode without repeating the b3*_IsValid() call
// at every call site.

#define BOX3D_FAIL_COND(m_box3d_cond) ERR_FAIL_COND(m_box3d_cond)

#define BOX3D_FAIL_COND_V(m_box3d_cond, m_retval) ERR_FAIL_COND_V(m_box3d_cond, m_retval)

#define BOX3D_FAIL_COND_MSG(m_box3d_cond, m_msg) ERR_FAIL_COND_MSG(m_box3d_cond, m_msg)

#define BOX3D_FAIL_COND_V_MSG(m_box3d_cond, m_retval, m_msg) ERR_FAIL_COND_V_MSG(m_box3d_cond, m_retval, m_msg)

#define BOX3D_WORLD_FAIL_COND_V(m_world_id, m_retval) \
	ERR_FAIL_COND_V_MSG(!b3World_IsValid(m_world_id), m_retval, "Box3D world handle is invalid.")

#define BOX3D_BODY_FAIL_COND_V(m_body_id, m_retval) \
	ERR_FAIL_COND_V_MSG(!b3Body_IsValid(m_body_id), m_retval, "Box3D body handle is invalid.")

#define BOX3D_SHAPE_FAIL_COND_V(m_shape_id, m_retval) \
	ERR_FAIL_COND_V_MSG(!b3Shape_IsValid(m_shape_id), m_retval, "Box3D shape handle is invalid.")

#define BOX3D_JOINT_FAIL_COND_V(m_joint_id, m_retval) \
	ERR_FAIL_COND_V_MSG(!b3Joint_IsValid(m_joint_id), m_retval, "Box3D joint handle is invalid.")
