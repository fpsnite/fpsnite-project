extends CanvasLayer
## Dynamic CS:GO-style crosshair, registered as an autoload named "Crosshair"
## (see project.godot). Rendered on a high canvas layer so it always draws on
## top of the 3D world and every HUD: the gap widens with movement speed
## (set_movement_spread, driven by player_instance) and on each shot
## (add_shot_kick, driven by weapon.gd), then decays back to base.

const BASE_GAP := 6.0          # gap while standing still & not firing
const MAX_MOVEMENT_GAP := 14.0 # extra gap at full movement speed
const SHOT_KICK := 5.0         # extra gap per shot
const MAX_SHOT_SPREAD := 20.0
const RECOVER_SPEED := 12.0    # how fast shot spread shrinks back
const LINE_LENGTH := 10.0
const LINE_WIDTH := 2.0
const CROSSHAIR_COLOR := Color(1.0, 1.0, 1.0, 1.0)

## In-game scenes - the crosshair is only shown while one of these is the
## current scene (not in the menu lobby, settings, launcher, etc).
const GAME_SCENES := ["res://Scenes/lobby.tscn", "res://GameScenes/AimTraining/aim_training.tscn"]

var _movement_spread := 0.0  # 0..1, set every physics frame
var _shot_spread := 0.0      # decays over time after each shot
var _force: int = -1         # -1 = auto (scene check), 0 = hide, 1 = show
var _style := "default"      # "default" = four lines, "square" = corner brackets

var _panel: Control

## Scene-level override: the aim training hub hides the crosshair (it is a
## menu, not combat), arenas force it on. Any scene that sets an override
## owns it from then on.
func set_override(visible: bool) -> void:
	_force = 1 if visible else 0

## Weapon-driven shape: "default" (four lines), "square" (squared corner
## brackets, no fill) or "dot" (static ring + center point for melee).
func set_style(style: String) -> void:
	if _style != style:
		_style = style
		_redraw()

func _ready() -> void:
	layer = 100
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.draw.connect(_on_draw)
	add_child(_panel)
	_panel.visible = false

func _process(delta: float) -> void:
	var in_game := get_tree().current_scene != null \
		and get_tree().current_scene.scene_file_path in GAME_SCENES
	var show := in_game if _force < 0 else _force == 1
	if _panel.visible != show:
		_panel.visible = show
	if _shot_spread > 0.0:
		_shot_spread = maxf(_shot_spread - RECOVER_SPEED * delta, 0.0)
		_redraw()

func set_movement_spread(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	if absf(ratio - _movement_spread) > 0.01:
		_movement_spread = ratio
		_redraw()

func add_shot_kick() -> void:
	_shot_spread = minf(_shot_spread + SHOT_KICK, MAX_SHOT_SPREAD)
	_redraw()

func _redraw() -> void:
	if _panel:
		_panel.queue_redraw()

func _on_draw() -> void:
	var center := _panel.size / 2.0
	var gap := BASE_GAP + (_movement_spread * MAX_MOVEMENT_GAP) + _shot_spread
	if _style == "square":
		_draw_square(center, gap)
		return
	if _style == "dot":
		_draw_dot(center)
		return
	_panel.draw_line(center + Vector2(0, -gap), center + Vector2(0, -gap - LINE_LENGTH), CROSSHAIR_COLOR, LINE_WIDTH)
	_panel.draw_line(center + Vector2(0, gap), center + Vector2(0, gap + LINE_LENGTH), CROSSHAIR_COLOR, LINE_WIDTH)
	_panel.draw_line(center + Vector2(-gap, 0), center + Vector2(-gap - LINE_LENGTH, 0), CROSSHAIR_COLOR, LINE_WIDTH)
	_panel.draw_line(center + Vector2(gap, 0), center + Vector2(gap + LINE_LENGTH, 0), CROSSHAIR_COLOR, LINE_WIDTH)

## Squared crosshair: four corner brackets (no fill, no center lines), sized
## by the same spread-driven gap. The corners point INWARD at the target.
## Used by the shotgun.
func _draw_square(center: Vector2, gap: float) -> void:
	var h := gap + LINE_LENGTH   # distance of each bracket from center
	var arm := LINE_LENGTH       # length of each bracket arm
	# Top-left corner (arms point right + down, toward center)
	_panel.draw_line(center + Vector2(-h, -h), center + Vector2(-h + arm, -h), CROSSHAIR_COLOR, LINE_WIDTH)
	_panel.draw_line(center + Vector2(-h, -h), center + Vector2(-h, -h + arm), CROSSHAIR_COLOR, LINE_WIDTH)
	# Top-right corner (arms point left + down)
	_panel.draw_line(center + Vector2(h, -h), center + Vector2(h - arm, -h), CROSSHAIR_COLOR, LINE_WIDTH)
	_panel.draw_line(center + Vector2(h, -h), center + Vector2(h, -h + arm), CROSSHAIR_COLOR, LINE_WIDTH)
	# Bottom-left corner (arms point right + up)
	_panel.draw_line(center + Vector2(-h, h), center + Vector2(-h + arm, h), CROSSHAIR_COLOR, LINE_WIDTH)
	_panel.draw_line(center + Vector2(-h, h), center + Vector2(-h, h - arm), CROSSHAIR_COLOR, LINE_WIDTH)
	# Bottom-right corner (arms point left + up)
	_panel.draw_line(center + Vector2(h, h), center + Vector2(h - arm, h), CROSSHAIR_COLOR, LINE_WIDTH)
	_panel.draw_line(center + Vector2(h, h), center + Vector2(h, h - arm), CROSSHAIR_COLOR, LINE_WIDTH)

## Dot crosshair: a ring with a filled center point, used by melee weapons
## (the knife). Static - spread is meaningless for melee, so the shape never
## moves with movement speed or shots.
func _draw_dot(center: Vector2) -> void:
	_panel.draw_circle(center, 2.5, CROSSHAIR_COLOR)
	_panel.draw_arc(center, 10.0, 0.0, TAU, 48, CROSSHAIR_COLOR, LINE_WIDTH)
