class_name FactoryStatusReadout
extends PanelContainer
## Screen-space status panel for the factory under the cursor.

const SIDE_MARGIN: float = 16.0
const TOP_CLEARANCE: float = 74.0
const BOTTOM_CLEARANCE: float = 94.0
const PREFERRED_WIDTH: float = 404.0
const PREFERRED_HEIGHT: float = 164.0
const OBJECTIVE_BOX_TOP: float = 88.0
const OBJECTIVE_PANEL_GAP: float = 16.0
const OBJECTIVE_BOX_COLLAPSED_HEIGHT: float = 220.0

var _label: Label
var _objective_panel_height: float = 252.0


func _ready() -> void:
	name = "FactoryStatusPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	accessibility_name = "Factory pipe status"
	accessibility_description = "Displays live sludge network connection, delivered throughput, and bottleneck status while hovering a factory."
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.13, 0.9)
	style.border_color = Color(0.87, 0.73, 0.35, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	add_theme_stylebox_override(&"panel", style)

	_label = Label.new()
	_label.name = "FactoryStatusLabel"
	_label.add_theme_font_size_override(&"font_size", 16)
	_label.add_theme_color_override(&"font_color", Color(0.9, 0.9, 0.9))
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)
	visibility_changed.connect(_update_screen_layout)
	get_viewport().size_changed.connect(_update_screen_layout)
	_update_screen_layout()
	var objective_box: Control = get_parent().get_node_or_null("ObjectiveBox") as Control
	if objective_box != null:
		objective_box.visibility_changed.connect(_on_objective_visibility_changed)
		objective_box.resized.connect(_on_objective_box_resized.bind(objective_box))
		_on_objective_box_resized(objective_box)


func _on_objective_visibility_changed() -> void:
	_update_screen_layout()


func _on_objective_box_resized(objective_box: Control) -> void:
	if objective_box == null:
		return
	_objective_panel_height = objective_box.size.y
	_update_screen_layout()


func set_objective_panel_height(panel_height: float) -> void:
	_objective_panel_height = panel_height
	_update_screen_layout()


func set_status_text(status: String) -> void:
	if _label.text == status:
		return
	_label.text = status
	accessibility_description = "Factory pipe status: " + status
	_update_screen_layout()


func _update_screen_layout() -> void:
	if not is_node_ready():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var horizontal_margin: float = minf(SIDE_MARGIN, viewport_size.x * 0.04)
	var width: float = minf(PREFERRED_WIDTH, maxf(1.0, viewport_size.x - horizontal_margin * 2.0))
	var height: float = minf(PREFERRED_HEIGHT, maxf(48.0, viewport_size.y - TOP_CLEARANCE - BOTTOM_CLEARANCE))
	var panel_left: float = viewport_size.x - horizontal_margin - width
	var objective_panel: Control = get_parent().get_node_or_null("ObjectiveBox") as Control
	var panel_top: float = TOP_CLEARANCE
	if objective_panel != null and objective_panel.visible:
		var clearance_height: float = maxf(_objective_panel_height, OBJECTIVE_BOX_COLLAPSED_HEIGHT)
		panel_top = maxf(OBJECTIVE_BOX_TOP + clearance_height + OBJECTIVE_PANEL_GAP, TOP_CLEARANCE)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(panel_left, panel_top)
	offset_left = panel_left
	offset_top = panel_top
	offset_right = panel_left + width
	offset_bottom = panel_top + height
