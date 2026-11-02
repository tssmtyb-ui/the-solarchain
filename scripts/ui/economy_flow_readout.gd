class_name EconomyFlowReadout
extends PanelContainer
## Expandable explanation of the workforce, factory, and goods feedback loops.

const PANEL_WIDTH: float = 380.0
const PANEL_TOP: float = 330.0
const PANEL_HEIGHT: float = 250.0
const TOP_BAR_CLEARANCE: float = 74.0
const OBJECTIVE_TOP: float = 88.0
const OBJECTIVE_EXPANDED_HEIGHT: float = 252.0
const OBJECTIVE_COLLAPSED_HEIGHT: float = 164.0
const PANEL_GAP: float = 12.0

var _details_label: Label


func _ready() -> void:
	name = "EconomyFlowReadout"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = Vector2(minf(PANEL_WIDTH, get_viewport_rect().size.x - 32.0), PANEL_HEIGHT)
	clip_contents = true
	position = Vector2(16.0, PANEL_TOP)
	size = Vector2(minf(PANEL_WIDTH, get_viewport_rect().size.x - 32.0), PANEL_HEIGHT)
	get_viewport().size_changed.connect(_update_screen_layout)
	visibility_changed.connect(_update_screen_layout)
	accessibility_name = "Economic flow details"
	accessibility_description = "How housing, workers, factories, goods, and supplied homes connect."

	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.045, 0.055, 0.08, 0.97)
	panel_style.border_color = Color(0.92, 0.76, 0.38, 0.94)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_top = 6.0
	panel_style.content_margin_bottom = 6.0
	add_theme_stylebox_override(&"panel", panel_style)

	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 2)
	add_child(content)

	var heading: HBoxContainer = HBoxContainer.new()
	content.add_child(heading)
	var title: Label = Label.new()
	title.text = "Economic flow"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override(&"font_size", 19)
	title.add_theme_color_override(&"font_color", Color(0.96, 0.86, 0.52))
	heading.add_child(title)

	var close_button: Button = Button.new()
	close_button.text = "Close"
	close_button.tooltip_text = "Close economic flow details"
	close_button.pressed.connect(_on_close_pressed)
	heading.add_child(close_button)

	_details_label = Label.new()
	_details_label.name = "EconomyFlowDetails"
	_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_label.custom_minimum_size = Vector2(340.0, 0.0)
	_details_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_label.add_theme_font_size_override(&"font_size", 12)
	_details_label.add_theme_color_override(&"font_color", Color(0.94, 0.95, 0.98))
	content.add_child(_details_label)


func update_layout() -> void:
	_update_screen_layout()
	var objective_box: Control = get_parent().get_node_or_null("ObjectiveBox") as Control
	if objective_box == null or not objective_box.visible:
		position.y = TOP_BAR_CLEARANCE
		return
	var is_collapsed: bool = objective_box.size.y <= OBJECTIVE_COLLAPSED_HEIGHT
	var height_before_details: float = OBJECTIVE_COLLAPSED_HEIGHT if is_collapsed else OBJECTIVE_EXPANDED_HEIGHT
	var desired_top: float = OBJECTIVE_TOP + height_before_details + PANEL_GAP
	position.y = desired_top
	var available_height: float = get_viewport_rect().size.y - desired_top - 16.0
	if available_height > 80.0:
		custom_minimum_size.y = minf(PANEL_HEIGHT, available_height)
		size.y = custom_minimum_size.y


func _update_screen_layout() -> void:
	if not is_node_ready():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var panel_width: float = minf(PANEL_WIDTH, viewport_size.x - 32.0)
	var panel_height: float = minf(PANEL_HEIGHT, viewport_size.y - 16.0)
	custom_minimum_size = Vector2(panel_width, panel_height)
	size = Vector2(panel_width, panel_height)


func set_flow_summary(
		total_workers: int,
		employed_workers: int,
		available_workers: int,
		operating_factories: int,
		total_factories: int,
		workers_per_factory: int,
		goods_stock: int,
		goods_produced: int,
		goods_consumed: int,
		homes_supplied: int,
		connected_homes: int,
		total_homes: int,
		supply_tick_seconds: float,
		goods_land_value_bonus: int,
		operating_farmhouses: int,
		total_farmhouses: int,
		active_farm_fields: int,
		farm_goods_produced: int,
		water_delivered: int = 0,
		water_capacity: int = 0,
		water_demand: int = 0) -> void:
	if _details_label == null:
		return
	var tick_text: String = str(supply_tick_seconds)
	var flow_cycle_text: String = tick_text + " SEC SUPPLY CYCLE"
	_details_label.text = (
		"WORKERS " + str(total_workers) + " total · " + str(employed_workers)
		+ " employed · " + str(available_workers) + " available\n"
		+ "FACTORIES " + str(operating_factories) + "/" + str(total_factories)
		+ " operating · " + str(workers_per_factory) + " workers + road needed\n"
		+ "GOODS / " + flow_cycle_text + ": " + str(goods_stock) + " stock · +"
		+ str(goods_produced) + " produced · -" + str(goods_consumed) + " consumed\n"
		+ "WATER / " + flow_cycle_text + ": " + str(water_delivered) + "/"
		+ str(water_capacity) + " capacity · demand " + str(water_demand) + "\n"
		+ "HOMES " + str(homes_supplied) + "/" + str(total_homes)
		+ " supplied (" + str(connected_homes) + " road-connected) · +"
		+ str(goods_land_value_bonus) + " tax bonus each\n"
		+ "FARMS " + str(operating_farmhouses) + "/" + str(total_farmhouses)
		+ " operating · " + str(active_farm_fields) + " active fields · +"
		+ str(farm_goods_produced) + " goods this cycle\n"
		+ "SLUDGE: border connection = +30% output; unhooked factories = half output."
	)
	accessibility_description = _details_label.text.replace("\n", ". ")


func _on_close_pressed() -> void:
	visible = false


func _on_objective_box_changed() -> void:
	_update_screen_layout()
