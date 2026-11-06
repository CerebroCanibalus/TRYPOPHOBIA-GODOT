@tool
extends Control

signal create_root_bone
signal mode_changed(mode: int)
signal snap_enabled_changed(enabled: bool)
signal snap_amount_changed(amount: float)
signal show_bones_changed(enabled: bool)
signal show_joints_changed(enabled: bool)
signal insert_tracks_pressed(mask: int)
signal insert_modified_pressed(mask: int)

enum MODE { POSE, EDIT }

## Mascara de tipos de pista. Valores = ArmatureAnimationKeyService.MASK_*.
const MASK_POSITION := 1
const MASK_ROTATION := 2
const MASK_SCALE := 4

@onready var _root_bone:Button = %RootBone
@onready var _mode_selector: OptionButton = %ModeSelector
@onready var _snap_button: CheckButton = %Snap
@onready var _snap_amount: SpinBox = %SnapAmount

var mode: MODE = MODE.POSE
var snap_enabled: bool = true
var snap_amount: float = 0.1

var _mask_position: CheckButton = null
var _mask_rotation: CheckButton = null
var _mask_scale: CheckButton = null
var _insert_tracks: Button = null
var _insert_modified: Button = null
var _show_bones: CheckButton = null
var _show_joints: CheckButton = null

## Si es false, el viewport muestra solo los puntos de las articulaciones.
var show_bones: bool = true

## Si es false, no se dibujan las bolitas de las articulaciones (ni se pueden
## agarrar: un handle invisible no debe robar clicks).
var show_joints: bool = true


func _ready() -> void:
	_initialize_ui()
	_connect_signals()
	_build_animation_row()

func _initialize_ui() -> void:
	_mode_selector.clear()
	_mode_selector.add_item("Pose", MODE.POSE)
	_mode_selector.add_item("Edit", MODE.EDIT)
	_mode_selector.select(mode)
	_snap_button.button_pressed = snap_enabled
	_snap_amount.value = snap_amount
	_snap_amount.editable = snap_enabled

func _connect_signals() -> void:
	# `item_selected` NO se conecta aqui a proposito: el toolbar.tscn ya lo
	# conecta a `_on_option_button_item_selected` (ver alias mas abajo).
	_snap_button.toggled.connect(_on_snap_toggled)
	_snap_amount.value_changed.connect(_on_snap_amount_changed)
	_root_bone.pressed.connect(func():create_root_bone.emit())


## Crea los controles de animacion (mascara + 2 botones) dentro del HBoxContainer.
##
## Se construye por codigo (no en el .tscn) para que el addon no dependa de que
## el .tscn este regenerado con la escena versionada.
func _build_animation_row() -> void:
	var row := get_node_or_null("HBoxContainer") as HBoxContainer
	if row == null:
		push_warning("ArmatureEditor: no se encontro el HBoxContainer del toolbar.")
		return

	var separator := VSeparator.new()
	row.add_child(separator)

	# Interruptor de visualizacion de huesos.
	#
	# Godot dibuja sus propios huesos (el gizmo nativo "Skeleton3D") ADEMAS de
	# los del armature editor, y se solapan. Con esto apagamos los dos:
	# el nativo se oculta y el addon deja de pintar los cuerpos de los huesos.
	# Lo que queda son los puntos redondos de las articulaciones.
	_show_bones = CheckButton.new()
	_show_bones.text = "Bones"
	_show_bones.button_pressed = show_bones
	_show_bones.tooltip_text = "Muestra los huesos. Desmarcado: solo se ven los puntos de las articulaciones."
	_show_bones.toggled.connect(_on_show_bones_toggled)
	row.add_child(_show_bones)

	# Toggle de las bolitas de las articulaciones. Sin el, en un rig con dedos
	# son decenas de esferas tapando la malla (y comiendose los clicks).
	_show_joints = CheckButton.new()
	_show_joints.text = "Joints"
	_show_joints.button_pressed = show_joints
	_show_joints.tooltip_text = "Dibuja los puntos de las articulaciones. Desmarcado no hay bolitas (ojo: con 'Bones' tambien desmarcado no queda ningun handle que agarrar)."
	_show_joints.toggled.connect(_on_show_joints_toggled)
	row.add_child(_show_joints)

	_mask_position = CheckButton.new()
	_mask_position.text = "Pos"
	_mask_position.button_pressed = false
	_mask_position.tooltip_text = "Incluir pistas position_3d"
	row.add_child(_mask_position)

	_mask_rotation = CheckButton.new()
	_mask_rotation.text = "Rot"
	_mask_rotation.button_pressed = true
	_mask_rotation.tooltip_text = "Incluir pistas rotation_3d"
	row.add_child(_mask_rotation)

	_mask_scale = CheckButton.new()
	_mask_scale.text = "Scale"
	_mask_scale.button_pressed = false
	_mask_scale.tooltip_text = "Incluir pistas scale_3d"
	row.add_child(_mask_scale)

	_insert_tracks = Button.new()
	_insert_tracks.text = "Insert Tracks"
	_insert_tracks.tooltip_text = "Crea las pistas que falten (pos/rot/scale) de los huesos MODIFICADOS y mete una clave con la pose actual. Las pistas que ya existen tambien reciben su clave."
	_insert_tracks.pressed.connect(_on_insert_tracks_pressed)
	row.add_child(_insert_tracks)

	_insert_modified = Button.new()
	_insert_modified.text = "Insert Modified"
	_insert_modified.tooltip_text = "Mete claves en las pistas EXISTENTES de los huesos MODIFICADOS, en el tiempo actual del panel Animation. No crea pistas. Si el playhead esta encima de una clave, la REEMPLAZA."
	_insert_modified.pressed.connect(_on_insert_modified_pressed)
	row.add_child(_insert_modified)


## Mascara de tipos de pista seleccionada actualmente.
##
## @return Combinacion de MASK_POSITION / MASK_ROTATION / MASK_SCALE.
func get_track_mask() -> int:
	var mask := 0
	if _mask_position != null and _mask_position.button_pressed:
		mask |= MASK_POSITION
	if _mask_rotation != null and _mask_rotation.button_pressed:
		mask |= MASK_ROTATION
	if _mask_scale != null and _mask_scale.button_pressed:
		mask |= MASK_SCALE
	return mask


func _on_mode_selected(index: int) -> void:
	mode = index
	mode_changed.emit(mode)


## Metodo al que apunta la conexion `item_selected` del toolbar.tscn.
##
## Ese .tscn referenciaba un metodo inexistente (error en consola al cargar el
## toolbar); este alias lo mantiene vivo.
func _on_option_button_item_selected(index: int) -> void:
	_on_mode_selected(index)


func _on_snap_toggled(enabled: bool) -> void:
	snap_enabled = enabled
	_snap_amount.editable = enabled
	snap_enabled_changed.emit(enabled)

func _on_snap_amount_changed(amount: float) -> void:
	snap_amount = amount
	snap_amount_changed.emit(amount)


## Emite el cambio de la visibilidad de los huesos.
func _on_show_bones_toggled(enabled: bool) -> void:
	show_bones = enabled
	show_bones_changed.emit(enabled)


## Emite el cambio de la visibilidad de las articulaciones.
func _on_show_joints_toggled(enabled: bool) -> void:
	show_joints = enabled
	show_joints_changed.emit(enabled)

func set_can_create_root_bone(visible: bool) -> void:
	_root_bone.visible = visible


## Emite la peticion de crear pistas.
func _on_insert_tracks_pressed() -> void:
	insert_tracks_pressed.emit(get_track_mask())


## Emite la peticion de insertar claves.
func _on_insert_modified_pressed() -> void:
	insert_modified_pressed.emit(get_track_mask())
