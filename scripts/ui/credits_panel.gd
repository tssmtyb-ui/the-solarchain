class_name CreditsPanel
extends PanelContainer
## Toggleable credits popup for Spekulant.
##
## Opens from the "Credits" button in the TopBar and lists the game's full
## attributions. Content is built programmatically so the scene node stays
## minimal; the Credits button is resolved relative to this panel's position
## under the UI CanvasLayer.

## Relative path from this panel to the Credits button that toggles it.
const CREDITS_BUTTON_PATH := "../TopBar/HBoxContainer/CreditsButton"

## The full, ordered list of attributions shown in the panel.
const CREDITS: Array[Dictionary] = [
	{"title": "Playtesting & Feedback", "text": "Reddit user white112506-2"},
	{"title": "Art Assets", "text": "Isometric City Kit by Buggy Studio"},
	{"title": "Music", "text": "\u201cThe Jazz Piano\u201d & \u201cJazz Comedy\u201d by Benjamin Tissot (Bensound)"},
	{"title": "AI Assistants / Collaboration", "text": "Gemini & DeepSeek"},
]

## Portrait of the game mascot, shown beside the attribution text.
const MASCOT_TEXTURE_PATH := "res://Mascot/bobr the speculator.png"


func _ready() -> void:
	hide()
	_build_content()
	var button := get_node_or_null(CREDITS_BUTTON_PATH) as Button
	if button:
		button.pressed.connect(toggle)


## Flips the panel between open and closed.
func toggle() -> void:
	visible = not visible


## Opens the credits panel.
func open() -> void:
	show()


## Closes the credits panel.
func close() -> void:
	hide()


## Builds the panel's contents: framed mascot portrait on the left, with the
## title, attribution sections and Close button in a text column on the right —
## a clean two-column, studio-style credits layout.
func _build_content() -> void:
	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	add_child(margin)

	var row := HBoxContainer.new()
	row.name = "ContentRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	margin.add_child(row)

	# --- Mascot portrait (Sammy the Speculator) ---
	var frame := PanelContainer.new()
	frame.name = "MascotFrame"
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.08, 0.09, 0.13)
	frame_style.border_color = Color(0.87, 0.73, 0.35, 0.6)
	frame_style.set_border_width_all(2)
	frame_style.set_corner_radius_all(10)
	frame_style.content_margin_left = 6
	frame_style.content_margin_right = 6
	frame_style.content_margin_top = 6
	frame_style.content_margin_bottom = 6
	frame.add_theme_stylebox_override("panel", frame_style)

	# EXPAND_IGNORE_SIZE lets the node's layout define the rect, and
	# STRETCH_KEEP_ASPECT_CENTERED scales the portrait to fit without distorting.
	var mascot := TextureRect.new()
	mascot.name = "Mascot"
	mascot.texture = load(MASCOT_TEXTURE_PATH)
	mascot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mascot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mascot.custom_minimum_size = Vector2(156, 169)
	frame.add_child(mascot)
	row.add_child(frame)

	# --- Text column: title + attributions + Close ---
	var col := VBoxContainer.new()
	col.name = "TextColumn"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)

	var title := Label.new()
	title.text = "Credits"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	col.add_child(title)

	var rule := HSeparator.new()
	col.add_child(rule)

	for entry: Dictionary in CREDITS:
		var section_title := Label.new()
		section_title.text = entry.title
		section_title.add_theme_font_size_override("font_size", 14)
		section_title.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
		col.add_child(section_title)

		var body := Label.new()
		body.text = entry.text
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(360, 0)
		body.add_theme_font_size_override("font_size", 16)
		col.add_child(body)

	# Spacer pushes the Close button to the bottom of the column.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(120, 36)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close)
	col.add_child(close_button)
