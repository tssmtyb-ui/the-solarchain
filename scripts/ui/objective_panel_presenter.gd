class_name ObjectivePanelPresenter
extends RefCounted
## Renders tutorial objective state and its existing panel layout.

var _objective_box: Control
var _objective_header: Button
var _completion_summary: Label
var _residential_check: CheckBox
var _factory_check: CheckBox
var _road_check: CheckBox
var _sludge_check: CheckBox
var _factory_status_panel: FactoryStatusReadout
var _economy_flow_panel: EconomyFlowReadout


func configure(
		objective_box: Control,
		objective_header: Button,
		completion_summary: Label,
		residential_check: CheckBox,
		factory_check: CheckBox,
		road_check: CheckBox,
		sludge_check: CheckBox) -> void:
	_objective_box = objective_box
	_objective_header = objective_header
	_completion_summary = completion_summary
	_residential_check = residential_check
	_factory_check = factory_check
	_road_check = road_check
	_sludge_check = sludge_check


func set_related_panels(
		factory_status_panel: FactoryStatusReadout,
		economy_flow_panel: EconomyFlowReadout) -> void:
	_factory_status_panel = factory_status_panel
	_economy_flow_panel = economy_flow_panel


func render(
		residential_count: int,
		factory_count: int,
		road_connected: bool,
		factories_hooked_up: bool,
		foundations_complete: bool,
		objectives_collapsed: bool,
		tutorial_resolved: bool,
		residential_target: int,
		factory_target: int) -> void:
	var residential_done: bool = residential_count >= residential_target
	var factory_done: bool = factory_count >= factory_target
	_residential_check.button_pressed = residential_done or foundations_complete
	_factory_check.button_pressed = factory_done or foundations_complete
	_road_check.button_pressed = road_connected or foundations_complete
	_residential_check.text = "Build %d Residential zones (%d/%d)" % [
		residential_target, residential_count, residential_target]
	_factory_check.text = "Build %d Factory (%d/%d)" % [
		factory_target, factory_count, factory_target]
	_road_check.text = "Connect them with a Road (%s)" % (
		"Connected" if road_connected or foundations_complete else "Pending")
	_sludge_check.button_pressed = factories_hooked_up
	_sludge_check.text = "Optional: sludge to map edge (+30% output)"
	var disclosure: String = "▸" if objectives_collapsed else "▾"
	_objective_header.text = ("City Foundations  ✓  %s" % disclosure) \
			if foundations_complete else ("Objectives  %s" % disclosure)
	_completion_summary.text = (
		"Foundations complete!\nNext: set Dividend above 0% to resolve Bobr's challenge."
		if not tutorial_resolved else
		"Foundations complete · tutorial resolved.\nYour city is yours to grow."
	)
	_completion_summary.visible = foundations_complete and objectives_collapsed
	_residential_check.visible = not objectives_collapsed
	_factory_check.visible = not objectives_collapsed
	_road_check.visible = not objectives_collapsed
	_sludge_check.visible = not objectives_collapsed and factory_count > 0
	if foundations_complete and objectives_collapsed:
		_objective_box.offset_bottom = 252.0 if not tutorial_resolved else 232.0
	else:
		_objective_box.offset_bottom = 340.0 if factory_count > 0 else 308.0
	_objective_box.custom_minimum_size.y = \
			_objective_box.offset_bottom - _objective_box.offset_top
	_objective_box.size.y = _objective_box.custom_minimum_size.y
	update_related_layout()
	if _economy_flow_panel != null and _economy_flow_panel.visible:
		_economy_flow_panel.call("update_layout")


func update_related_layout() -> void:
	if _factory_status_panel != null:
		var objective_panel_height: float = 0.0
		if _objective_box.visible:
			objective_panel_height = _objective_box.size.y
		_factory_status_panel.set_objective_panel_height(objective_panel_height)
