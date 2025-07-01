extends Node3D

@export var damage: int = 25
@export var fire_rate: float = 0.2
@export var max_distance: float = 100.0
@export var laser_color: Color = Color.red

@onready var raycast = $RayCast
@onready var cooldown = $CooldownTimer
@onready var shoot_sound = $ShootSound

var can_shoot := true

func _ready():
    cooldown.wait_time = fire_rate
    cooldown.one_shot = true

func _process(delta):
    if Input.is_action_just_pressed("shoot") and can_shoot:
        shoot()

func shoot():
    can_shoot = false
    cooldown.start()
    
    raycast.target_position = Vector3.FORWARD * max_distance
    raycast.force_raycast_update()

    if raycast.is_colliding():
        var hit = raycast.get_collider()
        if hit.has_method("apply_damage"):
            hit.apply_damage(damage)
        
        draw_laser(global_position, raycast.get_collision_point())
    else:
        draw_laser(global_position, raycast.to_global(raycast.target_position))

    if shoot_sound:
        shoot_sound.play()

func _on_CooldownTimer_timeout():
    can_shoot = true

func draw_laser(from_pos: Vector3, to_pos: Vector3):
    var line = ImmediateMesh.new()
    var mat = StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = laser_color
    
    line.surface_begin(Mesh.PRIMITIVE_LINES, mat)
    line.surface_add_vertex(from_pos)
    line.surface_add_vertex(to_pos)
    line.surface_end()

    var mesh_instance = MeshInstance3D.new()
    mesh_instance.mesh = line
    get_parent().add_child(mesh_instance)

    await get_tree().create_timer(0.1).timeout
    mesh_instance.queue_free()
