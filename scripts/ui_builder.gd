class_name UIBuilder
extends RefCounted
## Builds programmatic UI overlays: the credits watermark and the Game Over screen.
## Called once from the root scene's _ready().


func build_ui(canvas: CanvasLayer, restart_callback: Callable) -> void:
	_build_credits(canvas)
	_build_game_over(canvas, restart_callback)


func _build_credits(canvas: CanvasLayer) -> void:
	var credits_label := Label.new()
	credits_label.name = "CreditsLabel"
	credits_label.text = "Art: Isometric City Kit by Buggy Studio"
	credits_label.anchor_top = 1.0
	credits_label.anchor_bottom = 1.0
	credits_label.anchor_left = 0.0
	credits_label.anchor_right = 1.0
	credits_label.offset_top = -28.0
	credits_label.offset_bottom = -8.0
	credits_label.offset_right = -8.0
	credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credits_label.modulate.a = 0.5
	credits_label.add_theme_font_size_override(&"font_size", 12)
	canvas.add_child(credits_label)


func _build_game_over(canvas: CanvasLayer, restart_callback: Callable) -> void:
	var game_over_panel := ColorRect.new()
	game_over_panel.name = "GameOverPanel"
	game_over_panel.color = Color(0, 0, 0, 0.7)
	game_over_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_over_panel.hide()
	canvas.add_child(game_over_panel)

	var center_box := VBoxContainer.new()
	center_box.name = "CenterBox"
	center_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_box.alignment = BoxContainer.ALIGNMENT_CENTER
	game_over_panel.add_child(center_box)

	var game_over_label := Label.new()
	game_over_label.name = "GameOverLabel"
	game_over_label.text = "GAME OVER\nYou went bankrupt!"
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.add_theme_font_size_override(&"font_size", 40)
	game_over_label.add_theme_color_override(&"font_color", Color(1, 1, 1))
	center_box.add_child(game_over_label)

	var restart_button := Button.new()
	restart_button.name = "RestartButton"
	restart_button.text = "Restart Game"
	restart_button.custom_minimum_size = Vector2(180, 44)
	restart_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_button.pressed.connect(restart_callback)
	center_box.add_child(restart_button)
