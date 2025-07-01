extends Node3D

var health := 100

func apply_damage(amount: int):
    health -= amount
    print("¡Impacto! Vida restante: %d" % health)
    if health <= 0:
        queue_free()
