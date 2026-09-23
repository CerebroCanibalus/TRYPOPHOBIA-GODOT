@tool
extends SceneTree
## Constructor-first: genera src/ragdoll_character/scenes/coneja_player.tscn
## desde codigo. La idea: dado que el MCP no expone tools constructor en
## este runtime, replico el patron localmente -- la escena se construye por
## datos, no a mano.
##
## El resultado es IDENTICO al ragdoll_character.tscn viejo pero con:
##   - ext_resource del GLB cambiado a coneja.glb
##   - nombres de PhysicalBone3D cambiados al rig coneja
##   - transforms REST medidos del coneja.glb (los que Godot ve)
##   - rig_config = coneja_rig_config.tres (Resource)
##   - colliders ajustados al tamano del rig coneja
##
## Ejecutar UNA vez para (re)generar la escena:
##   godot --headless --path . --script src/ragdoll_character/construct_coneja.gd

const GLB_PATH := "res://assets/players/coneja_p/coneja.glb"
const OUTPUT_PATH := "res://src/ragdoll_character/scenes/coneja_player.tscn"

func _initialize() -> void:
	print("[construct_coneja] construyendo %s ..." % OUTPUT_PATH)
	# 1) Cargar el coneja.glb para leer las transforms REST exactas
	var ps: PackedScene = ResourceLoader.load(GLB_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if ps == null:
		printerr("ERROR: no se pudo cargar ", GLB_PATH)
		quit(1)
		return
	var root: Node = ps.instantiate()
	var skel: Skeleton3D = root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		printerr("ERROR: Skeleton3D no encontrado en coneja.glb")
		quit(1)
		return

	# 2) Medir transforms REST de los huesos que seran PhysicalBone3D
	# Mapeo: nombre del hueso en el rig -> nombre logico del ragdoll
	var bones := {
		"espina2":   "espina2",
		"cabeza":    "cabeza",
		"brazo1_L":  "brazo1_L",
		"brazo2_L":  "brazo2_L",
		"mano_L":    "mano_L",
		"brazo1_R":  "brazo1_R",
		"brazo2_R":  "brazo2_R",
		"mano_R":    "mano_R",
		"pierna1_L": "pierna1_L",
		"pierna2_L": "pierna2_L",
		"pie_L":     "pie_L",
		"pierna1_R": "pierna1_R",
		"pierna2_R": "pierna2_R",
		"pie_R":     "pie_R",
	}
	var rests: Dictionary = {}
	for bone_name in bones:
		var idx: int = skel.find_bone(bone_name)
		if idx < 0:
			printerr("ERROR: hueso ", bone_name, " no existe en el coneja.glb")
			quit(1)
			return
		rests[bone_name] = skel.get_bone_rest(idx)
	print("[construct_coneja] %d transforms REST capturadas" % rests.size())

	# 3) Construir la escena como texto .tscn (Godot 4 format=3).
	# Es MUCHO codigo, pero data-driven y reproducible.
	var text := _build_tscn(rests)

	# 4) Escribir el archivo
	var out_path: String = ProjectSettings.globalize_path(OUTPUT_PATH)
	var f: FileAccess = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if f == null:
		printerr("ERROR: no se pudo escribir ", OUTPUT_PATH, " err=", FileAccess.get_open_error())
		quit(1)
		return
	f.store_string(text)
	f.close()
	print("[construct_coneja] escrito: ", out_path, " (%d bytes)" % text.length())
	quit(0)


func _fmt_xform(t: Transform3D) -> String:
	# Formato Godot 4 .tscn: Transform3D(basis_xx, basis_xy, ..., origin_z)
	# = 12 floats en una sola tupla, sin coma separadora.
	var b: Basis = t.basis
	var o: Vector3 = t.origin
	return "Transform3D(%f, %f, %f, %f, %f, %f, %f, %f, %f, %f, %f, %f)" % [
		b.x.x, b.x.y, b.x.z,
		b.y.x, b.y.y, b.y.z,
		b.z.x, b.z.y, b.z.z,
		o.x, o.y, o.z,
	]


## Construye la cadena .tscn completa para la coneja.
## Estructura (identica a ragdoll_character.tscn):
##   Character (root, script)
##     Physical (instancia de coneja.glb)
##       Armature/Skeleton3D/[...PhysicalBone3D...]
##       AnimationPlayer
##       GrabJointLeft, GrabJointRight
##       JumpTimer
##     Animated (instancia de coneja.glb, visible=false)
##       Armature/Skeleton3D/{ArmIK, PoleTargetL, PoleTargetR}
##       AnimationTree
##     CameraPivot (con Camera3D + SpringArm3D + PointerRay)
##     Pointer, HUD/Reticle, HandTargetL, HandTargetR
func _build_tscn(rests: Dictionary) -> String:
	var s: String = ""
	s += "[gd_scene format=3 uid=\"uid://coneja_player_001\"]\n\n"
	# Ext resources
	s += "[ext_resource type=\"Script\" path=\"res://src/ragdoll_character/ragdoll_character.gd\" id=\"1_lo1uq\"]\n"
	s += "[ext_resource type=\"PackedScene\" path=\"res://assets/players/coneja_p/coneja.glb\" id=\"1_nfcse\"]\n"
	s += "[ext_resource type=\"Material\" path=\"res://src/ragdoll_character/materials/fp_body_clip.tres\" id=\"3_k507y\"]\n"
	s += "[ext_resource type=\"Script\" path=\"res://src/ragdoll_character/ragdoll_camera.gd\" id=\"3_ya0u6\"]\n"
	s += "[ext_resource type=\"Script\" path=\"res://src/ragdoll_character/ragdoll_pointer.gd\" id=\"5_e7a7b\"]\n"
	s += "[ext_resource type=\"Script\" path=\"res://src/ragdoll_character/pointer_reticle.gd\" id=\"6_mn3uv\"]\n"
	s += "[ext_resource type=\"Resource\" path=\"res://src/ragdoll_character/resources/coneja_rig_config.tres\" id=\"7_rig\"]\n\n"

	# Sub-resources: colliders (mas pequenos que el rig viejo: coneja ~3.7m vs rig viejo ~1.7m)
	s += "[sub_resource type=\"BoxShape3D\" id=\"BoxShape3D_body\"]\nsize = Vector3(0.95, 1.4, 0.55)\n\n"
	s += "[sub_resource type=\"CapsuleShape3D\" id=\"CapsuleShape3D_arm\"]\nradius = 0.13\nheight = 0.32\n\n"
	s += "[sub_resource type=\"CapsuleShape3D\" id=\"CapsuleShape3D_forearm\"]\nradius = 0.11\nheight = 0.30\n\n"
	s += "[sub_resource type=\"SphereShape3D\" id=\"SphereShape3D_grab\"]\nradius = 0.16\n\n"
	s += "[sub_resource type=\"CapsuleShape3D\" id=\"CapsuleShape3D_thigh\"]\nradius = 0.16\nheight = 0.42\n\n"
	s += "[sub_resource type=\"CapsuleShape3D\" id=\"CapsuleShape3D_calf\"]\nradius = 0.13\nheight = 0.50\n\n"
	s += "[sub_resource type=\"SphereShape3D\" id=\"SphereShape3D_floor\"]\nradius = 0.18\n\n"
	s += "[sub_resource type=\"CapsuleShape3D\" id=\"CapsuleShape3D_head\"]\nradius = 0.18\nheight = 0.35\n\n"

	# Nodos raices
	s += "[node name=\"Character\" type=\"Node3D\"]\n"
	s += "script = ExtResource(\"1_lo1uq\")\n"
	s += "rig_config = ExtResource(\"7_rig\")\n"
	s += "angular_spring_stiffness = 3000.0\n"  # coneja es mas grande, PD mas blando
	s += "fp_clip_radius = 0.30\n"  # la cabeza es mas grande
	s += "ik_pole_offset = Vector3(0.30, -0.50, -0.30)\n"
	s += "lean_max_degrees = 2.0\n\n"

	# === Physical (instancia del GLB) ===
	s += "[node name=\"Physical\" parent=\".\" instance=ExtResource(\"1_nfcse\")]\n"
	s += "transform = Transform3D(-1, 0, -8.74228e-08, 0, 1, 0, 8.74228e-08, 0, -1, 0, 0, 0)\n\n"

	# Skeleton3D del Physical (heredado del GLB)
	# Necesitamos declarar los PhysicalBone3D como hijos del Skeleton3D
	# Por cada hueso fisico: nombre del nodo "Physical Bone <bone_name>"
	s += "[node name=\"Skeleton3D\" parent=\"Physical/Armature\" index=\"0\"]\n\n"

	# Helper para escribir un PhysicalBone3D
	var physical_bones_order := ["espina2", "cabeza",
		"brazo1_L", "brazo2_L", "mano_L",
		"brazo1_R", "brazo2_R", "mano_R",
		"pierna1_L", "pierna2_L", "pie_L",
		"pierna1_R", "pierna2_R", "pie_R"]

	# Joint type y constraints segun hueso
	# (las piernas y torso usan ConeJoint con swing/twist grandes; los brazos tienen mas libertad)
	var joint_configs := {
		"espina2":   {"joint_type": 2, "swing": 30.0, "twist": 30.0, "shape": "BoxShape3D_body", "offset": Vector3(0, 0.4, 0)},
		"cabeza":    {"joint_type": 2, "swing": 45.0, "twist": 60.0, "shape": "CapsuleShape3D_head", "offset": Vector3(0, 0.18, 0)},
		"brazo1_L":  {"joint_type": 2, "swing": 90.0, "twist": 45.0, "shape": "CapsuleShape3D_arm", "offset": Vector3(0, -0.16, 0)},
		"brazo2_L":  {"joint_type": 2, "swing": 120.0, "twist": 60.0, "shape": "CapsuleShape3D_forearm", "offset": Vector3(0, -0.15, 0)},
		"mano_L":    {"joint_type": 2, "swing": 60.0, "twist": 30.0, "shape": "SphereShape3D_grab", "offset": Vector3(0, -0.08, 0)},
		"brazo1_R":  {"joint_type": 2, "swing": 90.0, "twist": 45.0, "shape": "CapsuleShape3D_arm", "offset": Vector3(0, -0.16, 0)},
		"brazo2_R":  {"joint_type": 2, "swing": 120.0, "twist": 60.0, "shape": "CapsuleShape3D_forearm", "offset": Vector3(0, -0.15, 0)},
		"mano_R":    {"joint_type": 2, "swing": 60.0, "twist": 30.0, "shape": "SphereShape3D_grab", "offset": Vector3(0, -0.08, 0)},
		"pierna1_L": {"joint_type": 2, "swing": 45.0, "twist": 30.0, "shape": "CapsuleShape3D_thigh", "offset": Vector3(0, -0.21, 0)},
		"pierna2_L": {"joint_type": 2, "swing": 30.0, "twist": 20.0, "shape": "CapsuleShape3D_calf", "offset": Vector3(0, -0.25, 0)},
		"pie_L":     {"joint_type": 2, "swing": 30.0, "twist": 15.0, "shape": "SphereShape3D_floor", "offset": Vector3(0, 0.1, 0.2)},
		"pierna1_R": {"joint_type": 2, "swing": 45.0, "twist": 30.0, "shape": "CapsuleShape3D_thigh", "offset": Vector3(0, -0.21, 0)},
		"pierna2_R": {"joint_type": 2, "swing": 30.0, "twist": 20.0, "shape": "CapsuleShape3D_calf", "offset": Vector3(0, -0.25, 0)},
		"pie_R":     {"joint_type": 2, "swing": 30.0, "twist": 15.0, "shape": "SphereShape3D_floor", "offset": Vector3(0, 0.1, 0.2)},
	}

	for bone_name in physical_bones_order:
		var rest: Transform3D = rests[bone_name]
		var cfg: Dictionary = joint_configs[bone_name]
		var has_grab: bool = (bone_name == "brazo2_L" or bone_name == "brazo2_R")
		var has_floor: bool = (bone_name == "pie_L" or bone_name == "pie_R")
		s += "[node name=\"Physical Bone %s\" type=\"PhysicalBone3D\" parent=\"Physical/Armature/Skeleton3D\" index=\"%d\"]\n" % [bone_name, physical_bones_order.find(bone_name) + 1]
		s += "transform = %s\n" % _fmt_xform(rest)
		s += "collision_layer = 2\n"
		s += "collision_mask = 7\n"
		s += "joint_type = %d\n" % cfg["joint_type"]
		s += "joint_constraints/swing_span = %f\n" % cfg["swing"]
		s += "joint_constraints/twist_span = %f\n" % cfg["twist"]
		s += "joint_constraints/bias = 0.3\n"
		s += "joint_constraints/softness = 0.8\n"
		s += "joint_constraints/relaxation = 1.0\n"
		s += "friction = 0.2\n"
		s += "linear_damp_mode = 1\n"
		s += "angular_damp = 1.0\n"
		s += "can_sleep = false\n"
		s += "bone_name = \"%s\"\n" % bone_name
		# CollisionShape3D hijo
		s += "\n[node name=\"CollisionShape3D\" type=\"CollisionShape3D\" parent=\"Physical/Armature/Skeleton3D/Physical Bone %s\"]\n" % bone_name
		s += "transform = Transform3D(1, 0, 0, 0, 0, 1, 0, -1, 0, %f, %f, %f)\n" % [cfg["offset"].x, cfg["offset"].y, cfg["offset"].z]
		s += "shape = SubResource(\"%s\")\n\n" % cfg["shape"]
		# GrabArea en brazo2
		if has_grab:
			var side: String = "L" if bone_name.ends_with("_L") else "R"
			s += "[node name=\"%sGrabArea\" type=\"Area3D\" parent=\"Physical/Armature/Skeleton3D/Physical Bone %s\"]\n" % [side, bone_name]
			s += "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.05, -0.2)\n"
			s += "collision_layer = 0\n"
			s += "collision_mask = 4\n\n"
			s += "[node name=\"CollisionShape3D\" type=\"CollisionShape3D\" parent=\"Physical/Armature/Skeleton3D/Physical Bone %s/%sGrabArea\"]\n" % [bone_name, side]
			s += "shape = SubResource(\"SphereShape3D_grab\")\n\n"
		# OnFloor en pies
		if has_floor:
			s += "[node name=\"OnFloor%s\" type=\"ShapeCast3D\" parent=\"Physical/Armature/Skeleton3D/Physical Bone %s\"]\n" % [("Left" if bone_name == "pie_L" else "Right"), bone_name]
			s += "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0.2)\n"
			s += "shape = SubResource(\"SphereShape3D_floor\")\n"
			s += "target_position = Vector3(0, 0, -0.4)\n"
			s += "max_results = 10\n\n"

	# AnimationPlayer y nodos auxiliares del Physical (van ANTES de los
	# PhysicalBone3D para que el orden de nodos sea coherente con el GLB)
	s += "[node name=\"AnimationPlayer\" parent=\"Physical\" index=\"1\"]\n"
	s += "autoplay = &\"idle\"\n\n"

	# Body mesh (Character visual) - se reasigna el mesh del Skeleton3D con fp_body_clip
	# Va como index="0" para reemplazar el mesh "Character" que ya trae el GLB
	s += "[node name=\"Character\" parent=\"Physical/Armature/Skeleton3D\" index=\"0\"]\n"
	s += "material_override = ExtResource(\"3_k507y\")\n\n"

	# GrabJoints y JumpTimer
	s += "[node name=\"GrabJointRight\" type=\"PinJoint3D\" parent=\"Physical\"]\n\n"
	s += "[node name=\"GrabJointLeft\" type=\"PinJoint3D\" parent=\"Physical\"]\n\n"
	s += "[node name=\"JumpTimer\" type=\"Timer\" parent=\"Physical\"]\n"
	s += "one_shot = true\n\n"

	# === Animated (instancia del GLB, invisible) ===
	s += "[node name=\"Animated\" parent=\".\" instance=ExtResource(\"1_nfcse\")]\n"
	s += "transform = Transform3D(-1, 0, -8.74228e-08, 0, 1, 0, 8.74228e-08, 0, -1, 0, 0, 0)\n\n"
	s += "[node name=\"Skeleton3D\" parent=\"Animated/Armature\" index=\"0\"]\n"
	s += "visible = false\n\n"

	# IK nodes del Animated
	s += "[node name=\"ArmIK\" type=\"TwoBoneIK3D\" parent=\"Animated/Armature/Skeleton3D\" index=\"1\"]\n\n"
	s += "[node name=\"PoleTargetL\" type=\"Node3D\" parent=\"Animated/Armature/Skeleton3D\" index=\"2\"]\n\n"
	s += "[node name=\"PoleTargetR\" type=\"Node3D\" parent=\"Animated/Armature/Skeleton3D\" index=\"3\"]\n\n"

	# AnimationTree del Animated (con parametros para los clips que existan)
	s += "[node name=\"AnimationTree\" type=\"AnimationTree\" parent=\"Animated\"]\n"
	s += "deterministic = false\n"
	s += "anim_player = NodePath(\"../AnimationPlayer\")\n\n"

	# === Camera, Pointer, HUD, HandTargets ===
	s += "[node name=\"CameraPivot\" type=\"Node3D\" parent=\".\" node_paths=PackedStringArray(\"target_node\", \"physical_skel\")]\n"
	s += "script = ExtResource(\"3_ya0u6\")\n"
	s += "target_node = NodePath(\"../Physical/Armature/Skeleton3D/Physical Bone cabeza\")\n"
	s += "head_distance = 0.25\n"
	s += "physical_skel = NodePath(\"../Physical/Armature/Skeleton3D\")\n\n"
	s += "[node name=\"SpringArm3D\" type=\"SpringArm3D\" parent=\"CameraPivot\"]\n"
	s += "spring_length = 0.0\n"
	s += "margin = 0.2\n\n"
	s += "[node name=\"Camera3D\" type=\"Camera3D\" parent=\"CameraPivot/SpringArm3D\"]\n"
	s += "current = true\n\n"
	s += "[node name=\"PointerRay\" type=\"RayCast3D\" parent=\"CameraPivot/SpringArm3D/Camera3D\"]\n"
	s += "script = ExtResource(\"5_e7a7b\")\n"
	s += "interact_range = 1.0\n\n"
	s += "[node name=\"Pointer\" type=\"Node3D\" parent=\".\"]\n\n"
	s += "[node name=\"HUD\" type=\"CanvasLayer\" parent=\".\"]\n\n"
	s += "[node name=\"Reticle\" type=\"Control\" parent=\"HUD\"]\n"
	s += "anchors_preset = 0\n"
	s += "script = ExtResource(\"6_mn3uv\")\n\n"
	s += "[node name=\"HandTargetL\" type=\"Node3D\" parent=\".\"]\n\n"
	s += "[node name=\"HandTargetR\" type=\"Node3D\" parent=\".\"]\n\n"

	# Connections
	s += "[connection signal=\"skeleton_updated\" from=\"Physical/Armature/Skeleton3D\" to=\".\" method=\"_on_skeleton_3d_skeleton_updated\"]\n"
	s += "[connection signal=\"body_entered\" from=\"Physical/Armature/Skeleton3D/Physical Bone brazo2_L/LGrabArea\" to=\".\" method=\"_on_l_grab_area_body_entered\"]\n"
	s += "[connection signal=\"body_entered\" from=\"Physical/Armature/Skeleton3D/Physical Bone brazo2_R/RGrabArea\" to=\".\" method=\"_on_r_grab_area_body_entered\"]\n"
	s += "[connection signal=\"timeout\" from=\"Physical/JumpTimer\" to=\".\" method=\"_on_jump_timer_timeout\"]\n\n"

	# Editable paths
	s += "[editable path=\"Physical\"]\n"
	s += "[editable path=\"Animated\"]\n"

	return s