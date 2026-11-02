class_name EconomyHudPresenter
extends RefCounted
## Renders resource and dividend summaries without owning simulation state.

var _workers_label: Label
var _goods_label: Label
var _factories_label: Label
var _dividend_label: Label
var _town_level_label: Label
var _town_level_progress: ProgressBar
var _economy_flow_panel: EconomyFlowReadout
var _budget_ledger_panel: BudgetLedgerPanel


func configure(
		workers_label: Label,
		goods_label: Label,
		factories_label: Label,
		dividend_label: Label) -> void:
	_workers_label = workers_label
	_goods_label = goods_label
	_factories_label = factories_label
	_dividend_label = dividend_label


func set_economy_flow_panel(panel: EconomyFlowReadout) -> void:
	_economy_flow_panel = panel


func set_town_level_controls(level_label: Label, progress_bar: ProgressBar) -> void:
	_town_level_label = level_label
	_town_level_progress = progress_bar


func set_budget_ledger_panel(panel: BudgetLedgerPanel) -> void:
	_budget_ledger_panel = panel


func render_town_level(report: Dictionary) -> void:
	var summary_text: String = str(report.get("summary_text", "Tier 1: Hamlet"))
	var tooltip_text: String = str(report.get("tooltip_text", ""))
	var progress_pct: float = clampf(float(report.get("progress_percent", 0.0)), 0.0, 100.0)
	if _town_level_label != null:
		_town_level_label.text = summary_text
		_town_level_label.tooltip_text = tooltip_text
		_town_level_label.accessibility_name = "Town Level Progression"
		_town_level_label.accessibility_description = tooltip_text
	if _town_level_progress != null:
		_town_level_progress.value = progress_pct
		_town_level_progress.tooltip_text = tooltip_text


func render_budget_ledger(
		history: Array[Dictionary],
		gross_lvt: int,
		maintenance: int,
		ubi_payout: int,
		net_income: int,
		cumulative_lvt: int = 0) -> void:
	if _budget_ledger_panel != null:
		_budget_ledger_panel.render_ledger(
				history,
				gross_lvt,
				maintenance,
				ubi_payout,
				net_income,
				cumulative_lvt)


func render_resources(
		total_workers: int,
		employed_workers: int,
		available_workers: int,
		goods_stock: int,
		goods_produced: int,
		goods_consumed: int,
		homes_supplied: int,
		total_homes: int,
		staffed_factories: int,
		total_factories: int,
		operating_farmhouses: int,
		total_farmhouses: int,
		active_farm_fields: int,
		total_farm_fields: int,
		farm_goods_produced: int,
		workers_per_factory: int,
		supply_tick_seconds: float,
		goods_land_value_bonus: int,
		farmland_radius: int,
		road_connected_homes: int,
		water_delivered: int = 0,
		water_capacity: int = 0,
		water_demand: int = 0) -> void:
	_workers_label.text = "Workers %d · E %d · A %d" % [
		total_workers, employed_workers, available_workers]
	_goods_label.text = "Goods %d · +%d/-%d · Homes %d/%d" % [
		goods_stock, goods_produced, goods_consumed, homes_supplied, total_homes]
	_factories_label.text = "Factories %d/%d · Farms %d/%d" % [
		staffed_factories, total_factories, operating_farmhouses, total_farmhouses]
	_workers_label.accessibility_name = "Workforce"
	_workers_label.tooltip_text = "Housing provides %d workers total. %d are assigned to operating factories and %d remain available. Each factory needs %d workers." % [
		total_workers, employed_workers, available_workers, workers_per_factory]
	_workers_label.accessibility_description = _workers_label.tooltip_text
	_goods_label.accessibility_name = "Goods and home delivery"
	_goods_label.tooltip_text = "Goods in stock: %d. Each supply cycle (%s seconds): +%d produced, -%d consumed. %d of %d homes received goods." % [
		goods_stock, str(supply_tick_seconds), goods_produced,
		goods_consumed, homes_supplied, total_homes]
	_goods_label.accessibility_description = _goods_label.tooltip_text
	_factories_label.accessibility_name = "Factories operating"
	_factories_label.tooltip_text = "%d/%d factories operating; each needs a road and %d workers. Farms: %d/%d Farmhouses operating with %d active of %d fields (+%d goods/tick). Farmhouses need one worker plus a road; fields must be within radius %d. Sludge improves factory output." % [
		staffed_factories, total_factories, workers_per_factory,
		operating_farmhouses, total_farmhouses, active_farm_fields,
		total_farm_fields, farm_goods_produced, farmland_radius]
	if _economy_flow_panel != null:
		_economy_flow_panel.set_flow_summary(
				total_workers,
				employed_workers,
				available_workers,
				staffed_factories,
				total_factories,
				workers_per_factory,
				goods_stock,
				goods_produced,
				goods_consumed,
				homes_supplied,
				road_connected_homes,
				total_homes,
				supply_tick_seconds,
				goods_land_value_bonus,
				operating_farmhouses,
				total_farmhouses,
				active_farm_fields,
				farm_goods_produced,
				water_delivered,
				water_capacity,
				water_demand)


func render_dividend(value: float, dividend_cost: int, boost_percent: int) -> void:
	if _dividend_label == null:
		return
	if value <= 0.0:
		_dividend_label.text = "Dividend: 0% (No production boost, keeping 100% tax revenue)"
	elif value >= 100.0:
		_dividend_label.text = "Dividend: 100%% (Costs all tax revenue, boosts factory production by +%d%%)" % boost_percent
	else:
		_dividend_label.text = "Dividend: %d%% (Costs $%d/tick, boosts factory production by +%d%%)" % [
			int(value), dividend_cost, boost_percent
		]
