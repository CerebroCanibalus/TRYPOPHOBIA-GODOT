#pragma once

#include <godot_cpp/classes/physics_server3d.hpp>
#include <godot_cpp/templates/hash_set.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/variant.hpp>

using namespace godot;

class Box3DShapedObjectImpl3D;

// One instance per Shape3D RID. Holds the Godot-facing configuration (radius, half-extents,
// mesh data, ...) plus the set of owning bodies/areas. Box3D has no equivalent "detached
// shape resource" object of its own -- geometry only exists once baked into a live
// b3ShapeId attached to a body -- so this class exists purely on the Godot side to cache
// the Variant configuration and let multiple Box3DShapeInstance3D attachments share it.
class Box3DShapeImpl3D {
public:
	using ShapeType = PhysicsServer3D::ShapeType;

	virtual ~Box3DShapeImpl3D() = default;

	RID get_rid() const { return rid; }

	void set_rid(const RID& p_rid) { rid = p_rid; }

	virtual ShapeType get_type() const = 0;

	virtual Variant get_data() const = 0;

	virtual void set_data(const Variant& p_data) = 0;

	virtual AABB get_aabb() const = 0;

	void add_owner(Box3DShapedObjectImpl3D* p_owner);

	void remove_owner(Box3DShapedObjectImpl3D* p_owner);

	const HashSet<Box3DShapedObjectImpl3D*>& get_owners() const { return owners; }

protected:
	RID rid;
	HashSet<Box3DShapedObjectImpl3D*> owners;
};
