class_name UIBuilder
extends RefCounted
## Builds programmatic UI overlays: the Game Over screen.
## Called once from the root scene's _ready().
## (Credits now live in the toggleable CreditsPanel popup instead.)

## Portrait of the game mascot shown on the game-over screen.
const MASCOT_TEXTURE_PATH := "res://Mascot/bobr the speculator.png"

## Clever Georgist/speculation one-liner shown to a bankrupt player.
const BANKRUPTCY_QUOTE := "Turns out holding out for land value appreciation doesn\u2019t pay... or rather, it cost you everything!"


func build_ui(canvas: CanvasLayer, restart_callback: Callable) -> void:
	_build_game_over(canvas, restart_callback)


func _build_game_over(canvas: CanvasLayer, restart_callback: Callable) -> void:
	var game_over_panel := ColorRect.new()
	game_over_panel.name = "GameOverPanel"
	game_over_panel.color = Color(0, 0, 0, 0.78)
	game_over_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_over_panel.hide()
	canvas.add_child(game_over_panel)

	var center_box := VBoxContainer.new()
	center_box.name = "CenterBox"
	center_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center_box.add_theme_constant_override("separation", 14)
	game_over_panel.add_child(center_box)

	# --- Mascot portrait (bobr the Speculator) ---
	var frame := PanelContainer.new()
	frame.name = "MascotFrame"
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.08, 0.09, 0.13)
	frame_style.border_color = Color(0.87, 0.73, 0.35, 0.6)
	frame_style.set_border_width_all(2)
	frame_style.set_corner_radius_all(12)
	frame_style.content_margin_left = 6
	frame_style.content_margin_right = 6
	frame_style.content_margin_top = 6
	frame_style.content_margin_bottom = 6
	frame.add_theme_stylebox_override("panel", frame_style)

	# EXPAND_IGNORE_SIZE lets layout define the rect; KEEP_ASPECT_CENTERED scales
	# the portrait to fit without stretching.
	var mascot := TextureRect.new()
	mascot.name = "Mascot"
	mascot.texture = load(MASCOT_TEXTURE_PATH)
	mascot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mascot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mascot.custom_minimum_size = Vector2(150, 163)
	frame.add_child(mascot)
	center_box.add_child(frame)

	var game_over_label := Label.new()
	game_over_label.name = "GameOverLabel"
	game_over_label.text = "GAME OVER"
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.add_theme_font_size_override(&"font_size", 46)
	game_over_label.add_theme_color_override(&"font_color", Color(0.95, 0.35, 0.30))
	center_box.add_child(game_over_label)

	var subtitle := Label.new()
	subtitle.name = "BankruptcySubtitle"
	subtitle.text = "You went bankrupt!"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override(&"font_size", 22)
	subtitle.add_theme_color_override(&"font_color", Color(0.9, 0.9, 0.9))
	center_box.add_child(subtitle)

	var quote := Label.new()
	quote.name = "BankruptcyQuote"
	quote.text = BANKRUPTCY_QUOTE
	quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote.custom_minimum_size = Vector2(560, 0)
	quote.add_theme_font_size_override(&"font_size", 18)
	quote.add_theme_color_override(&"font_color", Color(0.93, 0.80, 0.45))
	center_box.add_child(quote)

	var restart_button := Button.new()
	restart_button.name = "RestartButton"
	restart_button.text = "Restart Game"
	restart_button.custom_minimum_size = Vector2(200, 48)
	restart_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_button.pressed.connect(restart_callback)
	center_box.add_child(restart_button)
