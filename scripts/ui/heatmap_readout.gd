class_name HeatmapReadout
extends PanelContainer
## Screen-space cell inspector for the active land-value heatmap.

const DEFAULT_TOP: float = 86.0
const DEFAULT_WIDTH: float = 300.0
const DEFAULT_HEIGHT: float = 48.0
const SIDE_MARGIN: float = 16.0
const MAX_VISIBLE_HEIGHT: float = 56.0

var _label: Label


func _ready() -> void:
	name = "LandValueReadoutPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	accessibility_name = "Hovered land value"
	accessibility_description = "Hovered cell land value, with a pollution-risk warning when applicable."
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.055, 0.08, 0.95)
	style.border_color = Color(0.92, 0.76, 0.38, 0.92)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	add_theme_stylebox_override(&"panel", style)

	_label = Label.new()
	_label.name = "LandValueReadoutLabel"
	_label.add_theme_font_size_override(&"font_size", 14)
	_label.add_theme_color_override(&"font_color", Color(0.96, 0.96, 0.98))
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)
	visibility_changed.connect(_update_screen_layout)
	get_viewport().size_changed.connect(_update_screen_layout)
	_update_screen_layout()


func invalidate_cell() -> void:
	if _label != null and not _label.text.is_empty():
		_label.text = ""


func show_cell(
		land_value_text: String,
		pollution_risk: bool,
		speculator_owned: bool = false) -> void:
	if not visible:
		return
	var pollution_text: String = " · Pollution risk" if pollution_risk else ""
	var speculator_text: String = " · Speculator Plot" if speculator_owned else ""
	var updated_text: String = "Value: %s%s%s" % [land_value_text, pollution_text, speculator_text]
	if _label.text == updated_text:
		return
	_label.text = updated_text
	accessibility_description = _label.text
	_update_screen_layout()


func _update_screen_layout() -> void:
	if not is_node_ready():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var horizontal_margin: float = minf(SIDE_MARGIN, viewport_size.x * 0.04)
	var width: float = minf(DEFAULT_WIDTH, maxf(1.0, viewport_size.x - horizontal_margin * 2.0))
	var height: float = minf(MAX_VISIBLE_HEIGHT, maxf(0.0, viewport_size.y - DEFAULT_TOP - 8.0))
	var panel_left: float = horizontal_margin
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(panel_left, DEFAULT_TOP)
	offset_left = panel_left
	offset_top = DEFAULT_TOP
	offset_right = panel_left + width
	offset_bottom = DEFAULT_TOP + height
