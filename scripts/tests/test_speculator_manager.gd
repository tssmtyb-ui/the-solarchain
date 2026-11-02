extends Node


func _instantiate_game() -> Node:
	var game_scene: PackedScene = load("res://node_2d.tscn") as PackedScene
	assert(game_scene != null, "Could not load the gameplay scene.")
	var game: Node = game_scene.instantiate()
	get_tree().root.add_child(game)
	await get_tree().process_frame
	return game


func test_speculator_unlock_gating_parcel_claiming_and_lvt_contribution() -> void:
	var game: Node = await _instantiate_game()
	var speculator: SpeculatorManager = game.get_node("SpeculatorManager") as SpeculatorManager
	var progression: TownProgressionManager = game.get_node("TownProgressionManager") as TownProgressionManager
	var economy: EconomyManager = game.get_node("EconomyManager") as EconomyManager
	var grid: GridManager = game.get_node("GridManager") as GridManager

	assert(speculator != null, "Gameplay scene should own a SpeculatorManager.")
	assert(progression.get_town_level() == TownProgressionManager.TownLevel.HAMLET,
			"City should start at Tier 1 (Hamlet).")
	assert(not speculator.is_active(),
			"SpeculatorManager must remain inactive at Tier 1 (Hamlet).")

	var hamlet_claimed: Array[Vector2i] = speculator.claim_contiguous_parcel()
	assert(hamlet_claimed.is_empty() and speculator.get_speculator_lot_count() == 0,
			"Speculators must not claim any parcels while city is at Hamlet rank.")

	# Unlock Tier 2 (Town) and place a Park at (2, 14) near the highway to create prime land.
	progression.set_town_level(TownProgressionManager.TownLevel.TOWN)
	assert(speculator.is_active(), "SpeculatorManager must activate at Tier 2 (Town).")
	grid.set_tile(Vector2i(2, 14), GridCellData.new(GridCellData.TileType.PARK))

	economy.calculate_net_income(false)
	var base_lvt_before_speculators: int = economy.last_lvt_revenue

	var parcel: Array[Vector2i] = speculator.claim_contiguous_parcel()
	assert(parcel.size() == SpeculatorManager.MAX_PARCEL_SIZE,
			"Speculator should claim a contiguous parcel of 3 high-value tiles.")
	for cell: Vector2i in parcel:
		assert(speculator.is_speculator_owned(cell),
				"Each claimed parcel cell must be marked as speculator-owned.")
		assert(economy.get_land_value(cell) > SpeculatorManager.MIN_SPECULATION_LAND_VALUE,
				"Claimed speculator cells should be high-value prime land.")

	# Verify contiguity: every cell in the parcel after the first is cardinally adjacent to an earlier cell.
	for i: int in range(1, parcel.size()):
		var connected: bool = false
		for j: int in range(i):
			var diff: Vector2i = parcel[i] - parcel[j]
			if absi(diff.x) + absi(diff.y) == 1:
				connected = true
				break
		assert(connected, "Claimed speculator parcel cells must be cardinally contiguous.")

	# Verify speculators pay standard baseline LVT into the municipal treasury.
	economy.calculate_net_income(false)
	var expected_spec_lvt: int = speculator.calculate_total_speculator_lvt()
	assert(expected_spec_lvt > 0 and economy.last_speculator_lvt_revenue == expected_spec_lvt,
			"EconomyManager must record LVT revenue paid by speculator-held lots.")
	assert(economy.last_lvt_revenue == base_lvt_before_speculators + expected_spec_lvt,
			"Speculator LVT payments must be added to gross municipal LVT revenue.")

	game.queue_free()
	await get_tree().process_frame


func test_georgist_lvt_counterplay_development_vs_forfeiture() -> void:
	var game: Node = await _instantiate_game()
	var speculator: SpeculatorManager = game.get_node("SpeculatorManager") as SpeculatorManager
	var progression: TownProgressionManager = game.get_node("TownProgressionManager") as TownProgressionManager
	var economy: EconomyManager = game.get_node("EconomyManager") as EconomyManager
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var placement: BuildingPlacement = game.get("_placement") as BuildingPlacement

	progression.set_town_level(TownProgressionManager.TownLevel.TOWN)
	speculator.clear_all_lots()

	# Plot A at (2, 15): road-adjacent to (2, 14) and high land value -> should DEVELOP under high LVT.
	var road_pos: Vector2i = Vector2i(2, 14)
	var dev_lot: Vector2i = Vector2i(2, 15)
	grid.set_tile(road_pos, GridCellData.new(GridCellData.TileType.ROAD))
	game.call("refresh_road_connections", road_pos)

	# Plot B at (4, 12): no adjacent road -> should FORFEIT back to GRASS under high LVT.
	var forfeit_lot: Vector2i = Vector2i(4, 12)

	assert(speculator.claim_cell(dev_lot, true), "Should claim road-adjacent Plot A.")
	assert(speculator.claim_cell(forfeit_lot, true), "Should claim isolated Plot B.")

	var money_before: int = int(game.get("current_money"))
	# Raise LVT rate to 1.6x to trigger Georgist holding-cost counterplay.
	economy.set_lvt_rate(1.6)
	var result: Dictionary = speculator.process_assessment_cycle(false)

	var developed: Array = result["developed"] as Array
	var forfeited: Array = result["forfeited"] as Array
	assert(developed.has(dev_lot),
			"Road-connected speculator lot must trigger Option A (Development) under high LVT.")
	assert(grid.get_tile_type(dev_lot) == GridCellData.TileType.RESIDENTIAL_LOW,
			"Developed speculator lot should become a RESIDENTIAL_LOW unit.")
	assert(placement.has_building(dev_lot),
			"Developing a speculator lot should spawn the building sprite.")

	assert(forfeited.has(forfeit_lot),
			"Unconnected speculator lot must trigger Option B (Forfeiture) under high LVT.")
	assert(grid.get_tile_type(forfeit_lot) == GridCellData.TileType.GRASS,
			"Forfeited speculator lot must return to municipal GRASS terrain.")
	assert(int(game.get("current_money")) == money_before,
			"Speculator development and forfeiture must cost $0 to the player.")
	assert(speculator.get_speculator_lot_count() == 0,
			"Both lots should be released from speculator ownership after reacting.")

	game.queue_free()
	await get_tree().process_frame


func test_eminent_domain_road_and_pipe_building_heatmap_and_save_load() -> void:
	var game: Node = await _instantiate_game()
	var speculator: SpeculatorManager = game.get_node("SpeculatorManager") as SpeculatorManager
	var progression: TownProgressionManager = game.get_node("TownProgressionManager") as TownProgressionManager
	var placement_controller: PlacementController = game.get_node("PlacementController") as PlacementController
	var heatmap: LandValueHeatmap = game.get_node("LandValueHeatmap") as LandValueHeatmap
	var economy: EconomyManager = game.get_node("EconomyManager") as EconomyManager
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var save_manager: Node = get_node_or_null("/root/GameSave")

	progression.set_town_level(TownProgressionManager.TownLevel.TOWN)
	var lot_road: Vector2i = Vector2i(3, 15)
	var lot_pipe: Vector2i = Vector2i(3, 16)
	var lot_saved: Vector2i = Vector2i(4, 15)
	assert(speculator.claim_cell(lot_road, true))
	assert(speculator.claim_cell(lot_pipe, true))
	assert(speculator.claim_cell(lot_saved, true))

	# Verify LandValueHeatmap highlights speculator lots and hover readouts show syndicate telemetry.
	var lot_color: Color = heatmap.call("_color_for_cell", lot_road, GridCellData.TileType.GRASS)
	assert(lot_color == LandValueHeatmap.SPECULATOR_LOT_COLOR,
			"LandValueHeatmap must highlight speculator-owned lots with SPECULATOR_LOT_COLOR.")

	game.call("_on_heatmap_toggle_toggled", true)
	game.call("_update_land_value_readout", lot_road)
	var lv_label: Label = game.get_node("UI/LandValueReadoutPanel/LandValueReadoutLabel") as Label
	assert(lv_label.text.contains("Speculator Plot"),
			"Heatmap hover readout should identify speculator-owned plots.")

	game.call("_update_factory_status", lot_road)
	var status_panel: Control = game.get_node("UI/FactoryStatusPanel") as Control
	var status_label: Label = status_panel.get_node("FactoryStatusLabel") as Label
	assert(status_panel.visible and status_label.text.contains("SPECULATOR SYNDICATE: Hoarded Plot"),
			"Hovering a speculator lot should display the Speculator Syndicate inspection panel.")

	# Player builds a ROAD over lot_road via Eminent Domain ($10 road + $25 fee = $35).
	var build_road: Dictionary = placement_controller.attempt_build(
			GridCellData.TileType.ROAD, lot_road, 200)
	assert(bool(build_road["ok"]),
			"Player must be able to build a Road directly over a speculator-held tile via Eminent Domain.")
	assert(int(build_road["eminent_domain_fee"]) == SpeculatorManager.EMINENT_DOMAIN_FEE,
			"Building over a speculator lot must record the Eminent Domain fee.")
	assert(int(build_road["money"]) == 200 - (10 + SpeculatorManager.EMINENT_DOMAIN_FEE),
			"Building a road over a speculator lot must deduct build cost plus Eminent Domain fee.")
	assert(not speculator.is_speculator_owned(lot_road)
			and grid.get_tile_type(lot_road) == GridCellData.TileType.ROAD,
			"Eminent Domain road placement must release the speculator claim and place the road.")

	# Player builds a SLUDGE pipe over lot_pipe via Eminent Domain ($10 pipe + $25 fee = $35).
	var build_pipe: Dictionary = placement_controller.attempt_build(
			GridCellData.TileType.SLUDGE, lot_pipe, 200)
	assert(bool(build_pipe["ok"]) and not speculator.is_speculator_owned(lot_pipe)
			and grid.get_tile_type(lot_pipe) == GridCellData.TileType.SLUDGE,
			"Player must be able to build a Sludge Pipe over a speculator lot via Eminent Domain.")

	# Verify save and load round-trip of speculator_lots and lvt_rate.
	economy.set_lvt_rate(1.35)
	var captured: Dictionary = game.call("_capture_game_state")
	assert(str(save_manager.call("_validate_game_state", captured)) == "",
			"Save validator must accept speculator_lots and lvt_rate.")
	speculator.clear_all_lots()
	economy.set_lvt_rate(1.0)
	assert(bool(game.call("_apply_saved_state", captured)),
			"Applying saved state with speculator_lots and lvt_rate should succeed.")
	assert(speculator.is_speculator_owned(lot_saved) and speculator.get_speculator_lot_count() == 1,
			"Restoring saved state must restore speculator-owned lots.")
	assert(is_equal_approx(economy.get_lvt_rate(), 1.35),
			"Restoring saved state must restore lvt_rate.")

	game.queue_free()
	await get_tree().process_frame

