class_name AimPad
extends Area3D
## Teleporter pad: glowing disc + pole + name label (all scene nodes in
## aim_pad.tscn). Walking onto it emits activated(pad_id) once (re-entry
## re-triggers). The script only tints the scene materials with pad_color,
## pulses the glow, and wires the label - no geometry is built in code.
## Reused by the hub (one per arena) and by every arena (the exit pad back
## to the hub).

signal activated(pad_id: String)

@export var pad_id := "hub"
@export var label_text := "HUB"
@export var pad_color := Color(0.3, 0.85, 0.9)
@export var show_label := true

@onready var _ring: MeshInstance3D = $Ring
@onready var _pole: MeshInstance3D = $Pole
@onready var _label: Label3D = $PadLabel

var _ring_material: StandardMaterial3D

func _ready() -> void:
	add_to_group("aim_pad")
	collision_mask = 1
	collision_layer = 0
	body_entered.connect(_on_body_entered)
	_ring_material = _tint(_ring, pad_color)
	_tint(_pole, pad_color.darkened(0.25))
	_label.text = label_text
	_label.visible = show_label

## Duplicates the scene material so each pad instance tints independently.
func _tint(mesh_instance: MeshInstance3D, color: Color) -> StandardMaterial3D:
	var material := mesh_instance.material_override.duplicate() as StandardMaterial3D
	material.albedo_color = color
	material.emission = color
	mesh_instance.material_override = material
	return material

## Gentle breathing glow so pads read as interactive.
func _process(_delta: float) -> void:
	if _ring_material:
		_ring_material.emission_energy_multiplier = 1.0 + 0.4 * sin(Time.get_ticks_msec() * 0.003)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("aim_player"):
		activated.emit(pad_id)
