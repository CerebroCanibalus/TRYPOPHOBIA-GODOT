extends CharacterBody3D

@export var stats: CharacterStats

@export_group("Cámara")
@export var mouse_sensitivity: float = 0.002
@export var mouse_smoothness: float = 20.0  # Factor lerp: mayor = más inmediato
@export var base_fov: float = 100.0
@export var sprint_fov: float = 112.0
@export var fov_smoothness: float = 8.0

@export_group("Movimiento")
@export var acceleration: float = 14.0   # Qué tan rápido llega a la velocidad objetivo
@export var friction: float = 10.0       # Qué tan rápido frena al soltar teclas

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var push_ray: RayCast3D = $CameraPivot/Camera3D/PushRay
@onready var grab_cast: ShapeCast3D = $CameraPivot/Camera3D/GrabCast
@onready var iza_rig: Node3D = $iza_rig

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_stamina: float = 0.0
var is_sprinting: bool = false

var sprint_cooldown_timer: float = 0.0
var on_cooldown: bool = false
const SPRINT_COOLDOWN_DURATION: float = 2.5

var _target_yaw: float = 0.0
var _target_pitch: float = 0.0

# Agarre de objetos
var held_object: RigidBody3D = null
var hold_distance: float = 2.5
const GRAB_SPRING: float = 18.0
const MAX_GRAB_DISTANCE: float = 4.0
const MAX_HELD_MASS: float = 60.0

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if not stats:
		stats = CharacterStats.new()
	current_stamina = stats.max_stamina
	_target_yaw = rotation.y
	_target_pitch = camera_pivot.rotation.x
	camera.fov = base_fov
	var simulator := find_child("PhysicalBoneSimulator3D", true, false) as PhysicalBoneSimulator3D
	if simulator:
		simulator.active = false

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_target_yaw -= event.relative.x * mouse_sensitivity
		_target_pitch -= event.relative.y * mouse_sensitivity
		_target_pitch = clamp(_target_pitch, deg_to_rad(-89), deg_to_rad(89))
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_grab()

func _physics_process(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, _target_yaw, mouse_smoothness * delta)
	camera_pivot.rotation.x = lerp_angle(camera_pivot.rotation.x, _target_pitch, mouse_smoothness * delta)

	_apply_gravity(delta)
	_handle_jump()
	_handle_movement(delta)
	_update_sprint_cooldown(delta)
	_regen_stamina(delta)
	if Input.is_action_just_pressed("push"):
		_try_push()
	_update_held_object()
	move_and_slide()
	_update_fov(delta)
	_rotate_rig(delta)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * stats.weight * delta

func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		if current_stamina >= stats.jump_stamina_cost:
			velocity.y = stats.jump_velocity
			current_stamina -= stats.jump_stamina_cost

func _handle_movement(delta: float) -> void:
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var can_sprint := not on_cooldown and current_stamina > 0.0
	is_sprinting = Input.is_action_pressed("sprint") and can_sprint and direction.length() > 0.0

	var current_speed: float
	if is_sprinting:
		current_speed = stats.sprint_speed
		current_stamina = max(current_stamina - stats.sprint_stamina_cost * delta, 0.0)
		if current_stamina == 0.0 and not on_cooldown:
			on_cooldown = true
			sprint_cooldown_timer = SPRINT_COOLDOWN_DURATION
	else:
		current_speed = stats.walk_speed

	var target_vel := direction * current_speed
	var lerp_factor := acceleration if direction.length() > 0.0 else friction
	velocity.x = lerp(velocity.x, target_vel.x, lerp_factor * delta)
	velocity.z = lerp(velocity.z, target_vel.z, lerp_factor * delta)

func _update_sprint_cooldown(delta: float) -> void:
	if on_cooldown:
		sprint_cooldown_timer -= delta
		if sprint_cooldown_timer <= 0.0:
			on_cooldown = false
			sprint_cooldown_timer = 0.0

func _regen_stamina(delta: float) -> void:
	if not is_sprinting and not on_cooldown:
		current_stamina = min(current_stamina + stats.stamina_regen_rate * delta, stats.max_stamina)

func _update_fov(delta: float) -> void:
	var target_fov := sprint_fov if is_sprinting else base_fov
	camera.fov = lerp(camera.fov, target_fov, fov_smoothness * delta)

func _rotate_rig(delta: float) -> void:
	var horizontal_vel := Vector3(velocity.x, 0, velocity.z)
	if horizontal_vel.length() > 0.3:
		var global_angle := atan2(horizontal_vel.x, horizontal_vel.z)
		var local_angle := global_angle - rotation.y
		iza_rig.rotation.y = lerp_angle(iza_rig.rotation.y, local_angle, delta * 10.0)

func _try_push() -> void:
	if not stats or current_stamina < stats.push_stamina_cost:
		return

	current_stamina -= stats.push_stamina_cost

	push_ray.force_raycast_update()
	if push_ray.is_colliding():
		var body := push_ray.get_collider()
		if body is RigidBody3D:
			var push_dir := -camera_pivot.global_basis.z
			(body as RigidBody3D).apply_central_impulse(push_dir * stats.push_force)
		elif body.has_method("on_pushed"):
			body.on_pushed(-camera_pivot.global_basis.z * stats.push_force, self)

func _try_grab() -> void:
	if held_object:
		_release_object()
		return

	grab_cast.force_shapecast_update()
	for i in grab_cast.get_collision_count():
		var collider := grab_cast.get_collider(i)
		if collider == self:
			continue
		# Entidades con soporte de agarre explícito (interfaz futura)
		if collider.has_method("can_be_grabbed") and not collider.can_be_grabbed():
			continue
		if collider is RigidBody3D:
			var rb := collider as RigidBody3D
			if rb.mass <= MAX_HELD_MASS:
				_grab_object(rb)
				return
		elif collider.has_method("can_be_grabbed"):
			# Entidad futura que implementa la interfaz de agarre
			if collider is RigidBody3D:
				_grab_object(collider as RigidBody3D)
			elif collider.has_method("on_grabbed"):
				collider.on_grabbed(self)
			return

func _grab_object(body: RigidBody3D) -> void:
	held_object = body
	held_object.gravity_scale = 0.0
	held_object.add_collision_exception_with(self)
	hold_distance = clamp(
		camera.global_position.distance_to(body.global_position),
		1.2, MAX_GRAB_DISTANCE
	)
	if held_object.has_method("on_grabbed"):
		held_object.on_grabbed(self)

func _release_object() -> void:
	if not held_object:
		return
	held_object.gravity_scale = 1.0
	held_object.remove_collision_exception_with(self)
	if held_object.has_method("on_released"):
		held_object.on_released(self)
	held_object = null

func _update_held_object() -> void:
	if not held_object:
		return
	if not is_instance_valid(held_object):
		held_object = null
		return

	var hold_pos := camera.global_position + (-camera.global_basis.z * hold_distance)
	var dist := held_object.global_position.distance_to(camera.global_position)

	# Soltar si está demasiado lejos (bloqueado por geometría)
	if dist > MAX_GRAB_DISTANCE + 1.5:
		_release_object()
		return

	var diff := hold_pos - held_object.global_position
	held_object.linear_velocity = diff * GRAB_SPRING
	held_object.angular_velocity = Vector3.ZERO
