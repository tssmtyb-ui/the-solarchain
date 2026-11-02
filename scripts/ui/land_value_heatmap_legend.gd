class_name LandValueHeatmapLegend
extends Control
## Fixed-screen legend for the land-value overlay.

const HIGH_VALUE_COLOR: Color = Color(0.18, 0.9, 0.38, 0.78)
const MEDIUM_VALUE_COLOR: Color = Color(1.0, 0.82, 0.18, 0.78)
const LOW_VALUE_COLOR: Color = Color(0.96, 0.18, 0.2, 0.82)
const POLLUTION_RISK_COLOR: Color = Color(0.65, 0.2, 0.88, 0.82)
const PANEL_SIZE: Vector2 = Vector2(600.0, 42.0)
const HORIZONTAL_MARGIN: float = 16.0
const BOTTOM_CLEARANCE: float = 94.0


func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 120
	accessibility_name = "Land value legend"
	accessibility_description = "Green: high land value, 30 or more. Yellow: medium, 18 to 29. Red: low, 0 to 17. Purple: factory pollution risk within five Manhattan tiles, including grass. Press V or activate Map to toggle."
	visible = false
	get_viewport().size_changed.connect(_update_screen_layout)
	_update_screen_layout()
	queue_redraw()


func _update_screen_layout() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var margin: float = minf(HORIZONTAL_MARGIN, viewport_size.x * 0.04)
	var width: float = minf(PANEL_SIZE.x, viewport_size.x - margin * 2.0)
	var panel_left: float = HORIZONTAL_MARGIN
	var panel_top: float = viewport_size.y - PANEL_SIZE.y - BOTTOM_CLEARANCE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = panel_left
	offset_top = panel_top
	offset_right = panel_left + width
	offset_bottom = panel_top + PANEL_SIZE.y


func set_heatmap_visible(show_heatmap: bool) -> void:
	visible = show_heatmap
	queue_redraw()


func _draw() -> void:
	if not visible:
		return

	var panel_rect: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(panel_rect, Color(0.035, 0.045, 0.07, 0.94), true)
	draw_rect(panel_rect, Color(0.92, 0.76, 0.38, 0.96), false, 2.0, true)

	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(12.0, 25.0), "VALUE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(1.0, 0.88, 0.54))
	_draw_row(Vector2(72.0, 21.0), HIGH_VALUE_COLOR, "High 30+")
	_draw_row(Vector2(174.0, 21.0), MEDIUM_VALUE_COLOR, "Medium 18–29")
	_draw_row(Vector2(320.0, 21.0), LOW_VALUE_COLOR, "Low 0–17")
	_draw_row(Vector2(424.0, 21.0), POLLUTION_RISK_COLOR, "Pollution")


func _draw_row(row_position: Vector2, color: Color, text: String) -> void:
	var swatch_position: Vector2 = row_position - Vector2(0.0, 9.0)
	draw_rect(Rect2(swatch_position, Vector2(14.0, 14.0)), color, true)
	draw_rect(Rect2(swatch_position, Vector2(14.0, 14.0)), Color(0.95, 0.95, 0.95, 0.72), false, 1.0)
	draw_string(ThemeDB.fallback_font, row_position + Vector2(20.0, 5.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.96, 0.96, 0.98))
