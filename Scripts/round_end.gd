extends CanvasLayer
## End-of-match screen: VICTORY / DEFEAT / DRAW title, winner name, final
## score and a countdown back to the menu. Driven by game_round.gd on every
## client once the round state hits VICTORY.

const WIN_COLOR := Color(1, 0.85, 0.2)
const LOSE_COLOR := Color(0.91, 0.28, 0.35)
const DRAW_COLOR := Color(0.75, 0.78, 0.82)

@onready var overlay: ColorRect = $Overlay
@onready var title_label: Label = $CenterBox/TitleLabel
@onready var winner_label: Label = $CenterBox/WinnerLabel
@onready var score_label: Label = $CenterBox/ScoreLabel
@onready var countdown_label: Label = $CenterBox/CountdownLabel

func _ready() -> void:
	hide_result()

func show_result(is_draw: bool, local_won: bool, winner_name: String, score_text: String) -> void:
	visible = true
	overlay.color.a = 0.0
	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 0.65, 0.35)
	if is_draw:
		title_label.text = "DRAW"
		title_label.add_theme_color_override("font_color", DRAW_COLOR)
		winner_label.text = "NOBODY WINS"
	elif local_won:
		title_label.text = "VICTORY"
		title_label.add_theme_color_override("font_color", WIN_COLOR)
		winner_label.text = "%s WINS" % winner_name
	else:
		title_label.text = "DEFEAT"
		title_label.add_theme_color_override("font_color", LOSE_COLOR)
		winner_label.text = "%s WINS" % winner_name
	score_label.text = score_text
	countdown_label.text = ""

func update_countdown(seconds: int) -> void:
	if visible:
		countdown_label.text = "returning to menu in %d" % seconds

func hide_result() -> void:
	visible = false