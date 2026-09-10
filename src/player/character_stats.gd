class_name CharacterStats
extends Resource

@export_group("Stamina")
@export_range(0.0, 100.0) var max_stamina: float = 100.0
@export var stamina_regen_rate: float = 10.0  # por segundo, mientras no se usa

@export_group("Movement")
@export var walk_speed: float = 5.0       # m/s
@export var sprint_speed: float = 9.0     # m/s
@export var jump_velocity: float = 5.0    # impulso vertical
@export var weight: float = 1.0           # multiplicador de gravedad (velocidad de caída)

@export_group("Push")
@export var push_force: float = 12.0      # fuerza de empuje a objetos y retroceso al jugador

@export_group("Stamina Costs")
@export var sprint_stamina_cost: float = 15.0  # por segundo
@export var jump_stamina_cost: float = 20.0    # por salto
@export var push_stamina_cost: float = 25.0    # por empuje
