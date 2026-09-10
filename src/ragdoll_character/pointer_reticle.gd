extends Control
## Reticle MINIMALISTA: un punto. Los estados solo cambian opacidad y anillo.
##
## No usa textura ni material a proposito: se dibuja con _draw(), asi no hay
## ningun asset que importar ni mantener, y los radios/colores se tocan desde el
## inspector.

enum State {
	IDLE, ## nada alcanzable
	TARGET, ## hay algo a lo que la mano puede llegar
	BLOCKED, ## reservado (Fase 4: pared / objetivo invalido)
}

## Radio del punto central, en px.
@export var dot_radius := 1.5
## Radio del anillo que aparece solo cuando hay objetivo.
@export var ring_radius := 7.0
@export var ring_width := 1.0
@export var color_idle := Color(1.0, 1.0, 1.0, 0.30)
@export var color_target := Color(1.0, 1.0, 1.0, 0.95)
@export var color_blocked := Color(1.0, 0.3, 0.3, 0.55)

var state: State = State.IDLE:
	set(value):
		if state == value:
			return
		state = value
		queue_redraw()


func _ready() -> void:
	# Ocupa toda la pantalla y NO intercepta el raton.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center := size * 0.5
	var color := color_idle
	match state:
		State.TARGET:
			color = color_target
		State.BLOCKED:
			color = color_blocked
		_:
			color = color_idle
	draw_circle(center, dot_radius, color)
	if state == State.TARGET:
		draw_arc(center, ring_radius, 0.0, TAU, 24, color, ring_width, true)
