extends Node


func _instantiate_game() -> Node:
	var game_scene: PackedScene = load("res://node_2d.tscn") as PackedScene
	assert(game_scene != null, "Could not load the gameplay scene.")
	var game: Node = game_scene.instantiate()
	get_tree().root.add_child(game)
	await get_tree().process_frame
	return game


func test_town_level_milestones_build_bar_locks_and_metropolis_lvt_bonus() -> void:
	var game: Node = await _instantiate_game()
	var progression: TownProgressionManager = game.get_node("TownProgressionManager") as TownProgressionManager
	var economy: EconomyManager = game.get_node("EconomyManager") as EconomyManager
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var build_bar: HBoxContainer = game.get_node("UI/BuildBar/HBoxContainer") as HBoxContainer
	var top_bar_row: HBoxContainer = game.get_node("UI/TopBar/HBoxContainer") as HBoxContainer
	var town_level_label: Label = top_bar_row.get_node("TownLevelBox/TownLevelLabel") as Label
	var town_level_progress: ProgressBar = top_bar_row.get_node("TownLevelBox/TownLevelProgress") as ProgressBar
	var dividend_slider: HSlider = top_bar_row.get_node("DividendBox/DividendSlider") as HSlider

	assert(progression != null, "Gameplay scene should own a TownProgressionManager.")
	assert(progression.get_town_level() == TownProgressionManager.TownLevel.HAMLET,
			"New city must start at Tier 1 (Hamlet).")
	assert(town_level_label != null and town_level_label.text.begins_with("Tier 1: Hamlet"),
			"TopBar should display Tier 1: Hamlet at start.")

	var road_btn: TextureButton = build_bar.get_node("RoadToggle") as TextureButton
	var villa_btn: TextureButton = build_bar.get_node("ResidentialToggle") as TextureButton
	var farm_btn: TextureButton = build_bar.get_node("FarmhouseToggle") as TextureButton
	var small_tower_btn: TextureButton = build_bar.get_node("WaterTowerSmallToggle") as TextureButton
	var factory_btn: TextureButton = build_bar.get_node("FactoryToggle") as TextureButton
	var large_tower_btn: TextureButton = build_bar.get_node("WaterTowerLargeToggle") as TextureButton

	assert(not road_btn.disabled and not villa_btn.disabled and not farm_btn.disabled and not small_tower_btn.disabled,
			"Tier 1 (Hamlet) tools (Road, Villa, Farm, Small Water Tower) must start unlocked.")
	assert(factory_btn.disabled and large_tower_btn.disabled,
			"Tier 2 tools (Factory, Large Water Tower) must start locked at Hamlet rank.")
	assert(factory_btn.tooltip_text.contains("Requires Town Level"),
			"Locked Factory button tooltip must explain the Town Level requirement.")
	assert(not dividend_slider.editable and dividend_slider.tooltip_text.contains("Requires Town Level"),
			"UBI Dividend Slider must be locked until Town Level is reached.")

	# Advance toward Tier 2 (Town): requires 15 population + $1,000 gross LVT revenue.
	for i: int in range(15):
		grid.set_tile(Vector2i(2 + (i % 10), 2 + int(i / 10)), GridCellData.new(GridCellData.TileType.RESIDENTIAL_LOW))
	economy.cumulative_lvt_revenue = 500
	game.call("_refresh_town_progression_and_budget_ui")
	assert(progression.get_town_level() == TownProgressionManager.TownLevel.HAMLET,
			"City should remain Hamlet when LVT revenue is below $1,000.")
	assert(town_level_progress.value > 70.0 and town_level_progress.value < 80.0,
			"Progress bar should reflect 100% population and 50% LVT progress (~75%).")

	economy.cumulative_lvt_revenue = 1000
	game.call("_refresh_town_progression_and_budget_ui")
	assert(progression.get_town_level() == TownProgressionManager.TownLevel.TOWN,
			"Meeting 15 population and $1,000 gross LVT must advance the city to Tier 2 (Town).")
	assert(town_level_label.text.begins_with("Tier 2: Town"),
			"TopBar should update to Tier 2: Town.")
	assert(not factory_btn.disabled and not large_tower_btn.disabled and dividend_slider.editable,
			"Reaching Town Level must unlock Factories, Large Water Tower, and the UBI Dividend Slider.")

	# Measure gross LVT at Tier 2 before Metropolis bonus.
	economy.calculate_net_income(false)
	var town_tier_lvt: int = economy.last_lvt_revenue
	assert(town_tier_lvt > 0, "Fixture residences should generate positive gross LVT.")

	# Advance to Tier 3 (Metropolis): requires 50 population + 5 Apartments.
	for i: int in range(15):
		grid.set_tile(Vector2i(2 + (i % 10), 5 + int(i / 10)), GridCellData.new(GridCellData.TileType.RESIDENTIAL_HIGH))
	game.call("_refresh_town_progression_and_budget_ui")
	assert(progression.get_town_level() == TownProgressionManager.TownLevel.METROPOLIS,
			"Meeting 50+ population and 5+ Apartments must advance the city to Tier 3 (Metropolis).")
	assert(town_level_label.text.begins_with("Tier 3: Metropolis"),
			"TopBar should display Tier 3: Metropolis.")
	assert(is_equal_approx(economy.town_level_lvt_multiplier, TownProgressionManager.METROPOLIS_LVT_MULTIPLIER),
			"Metropolis rank must activate the 1.15x LVT efficiency multiplier.")

	# Verify +15% Metropolis LVT bonus on the same grid compared to 1.0x multiplier.
	economy.town_level_lvt_multiplier = 1.0
	economy.calculate_net_income(false)
	var base_metropolis_lvt: int = economy.last_lvt_revenue
	economy.town_level_lvt_multiplier = TownProgressionManager.METROPOLIS_LVT_MULTIPLIER
	economy.calculate_net_income(false)
	var boosted_metropolis_lvt: int = economy.last_lvt_revenue
	assert(boosted_metropolis_lvt == roundi(float(base_metropolis_lvt) * TownProgressionManager.METROPOLIS_LVT_MULTIPLIER),
			"Metropolis LVT bonus should increase gross LVT revenue by +15%.")

	game.queue_free()
	await get_tree().process_frame


func test_town_level_save_load_roundtrip_and_legacy_save_fallback() -> void:
	var game: Node = await _instantiate_game()
	var progression: TownProgressionManager = game.get_node("TownProgressionManager") as TownProgressionManager
	var economy: EconomyManager = game.get_node("EconomyManager") as EconomyManager
	var save_manager: Node = get_node_or_null("/root/GameSave")

	progression.set_town_level(TownProgressionManager.TownLevel.TOWN)
	economy.cumulative_lvt_revenue = 1450
	var captured: Dictionary = game.call("_capture_game_state")
	assert(int(captured.get("town_level", -1)) == TownProgressionManager.TownLevel.TOWN,
			"Captured save state must include town_level.")
	assert(int(captured.get("cumulative_lvt_revenue", -1)) == 1450,
			"Captured save state must include cumulative_lvt_revenue.")
	assert(str(save_manager.call("_validate_game_state", captured)) == "",
			"Save validator must accept valid town_level and cumulative_lvt_revenue.")

	# Reset to Hamlet, then apply saved state and verify restoration.
	progression.set_town_level(TownProgressionManager.TownLevel.HAMLET)
	economy.cumulative_lvt_revenue = 0
	assert(bool(game.call("_apply_saved_state", captured)),
			"Applying saved state with town_level = 2 should succeed.")
	assert(progression.get_town_level() == TownProgressionManager.TownLevel.TOWN,
			"Restoring saved state must restore Town Level 2.")
	assert(economy.cumulative_lvt_revenue == 1450,
			"Restoring saved state must restore cumulative_lvt_revenue.")

	# Legacy save fallback: omit town_level and cumulative_lvt_revenue.
	var legacy_state: Dictionary = captured.duplicate(true)
	legacy_state.erase("town_level")
	legacy_state.erase("cumulative_lvt_revenue")
	assert(str(save_manager.call("_validate_game_state", legacy_state)) == "",
			"Legacy saves without town_level must remain valid.")
	assert(bool(game.call("_apply_saved_state", legacy_state)),
			"Applying legacy save state should succeed.")
	assert(progression.get_town_level() == TownProgressionManager.TownLevel.HAMLET,
			"Legacy saves without town_level should default cleanly to Tier 1 (Hamlet).")

	# Invalid town_level rejection.
	var invalid_state: Dictionary = captured.duplicate(true)
	invalid_state["town_level"] = 99
	assert(str(save_manager.call("_validate_game_state", invalid_state)) != "",
			"Save validator must reject out-of-range town_level values.")

	game.queue_free()
	await get_tree().process_frame


func test_municipal_budget_ledger_records_10_cycle_ring_buffer_and_renders_ui() -> void:
	var game: Node = await _instantiate_game()
	var economy: EconomyManager = game.get_node("EconomyManager") as EconomyManager
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var top_bar_row: HBoxContainer = game.get_node("UI/TopBar/HBoxContainer") as HBoxContainer
	var budget_btn: Button = top_bar_row.get_node("BudgetLedgerButton") as Button
	var budget_panel: BudgetLedgerPanel = game.get_node("UI/BudgetLedgerPanel") as BudgetLedgerPanel

	assert(budget_btn != null and budget_panel != null,
			"HUD should include BudgetLedgerButton and BudgetLedgerPanel.")
	assert(not budget_panel.visible, "BudgetLedgerPanel should start hidden.")

	economy.clear_budget_history()
	grid.set_tile(Vector2i(2, 10), GridCellData.new(GridCellData.TileType.RESIDENTIAL_HIGH))
	grid.set_tile(Vector2i(3, 10), GridCellData.new(GridCellData.TileType.ROAD))
	economy.set_ubi_rate(0.25)

	# Run 12 completed assessment cycles; only the last 10 should remain in the ring buffer.
	for i: int in range(12):
		economy.calculate_net_income(true)

	var history: Array[Dictionary] = economy.get_budget_history()
	assert(history.size() == EconomyManager.MAX_BUDGET_HISTORY,
			"Budget history ring buffer must cap at 10 assessment cycles.")
	assert(int(history[0]["cycle"]) == 3 and int(history[9]["cycle"]) == 12,
			"Ring buffer must retain cycles #3 through #12 in chronological order.")

	var latest: Dictionary = history[9]
	assert(int(latest["gross_lvt"]) == economy.last_lvt_revenue
			and int(latest["maintenance"]) == economy.last_maintenance_cost
			and int(latest["ubi_payout"]) == economy.last_ubi_payout
			and int(latest["net_income"]) == economy.get_retained_treasury_revenue(),
			"Recorded budget entry must match the cycle's LVT, maintenance, UBI payout, and net income.")

	# Toggle BudgetLedgerPanel open via TopBar button and verify rendered contents.
	budget_btn.pressed.emit()
	assert(budget_panel.visible, "Clicking BudgetLedgerButton should open BudgetLedgerPanel.")
	assert(budget_panel.get_rendered_entry_count() == 10,
			"BudgetLedgerPanel should render all 10 historical cycles.")
	var history_label: Label = budget_panel.get_node("VBoxContainer/BudgetHistoryLabel") as Label
	var chart_box: HBoxContainer = budget_panel.get_node("VBoxContainer/BudgetChartContainer") as HBoxContainer
	assert(history_label != null and history_label.text.contains("#12 |"),
			"BudgetHistoryLabel should list the latest cycle #12.")
	assert(chart_box != null and chart_box.get_child_count() == 10,
			"BudgetChartContainer should display 10 visual trend bars.")

	game.queue_free()
	await get_tree().process_frame

