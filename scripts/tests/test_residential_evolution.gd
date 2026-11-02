extends Node


func _instantiate_game() -> Node:
	var game_scene: PackedScene = load("res://node_2d.tscn") as PackedScene
	assert(game_scene != null, "Could not load the gameplay scene.")
	var game: Node = game_scene.instantiate()
	get_tree().root.add_child(game)
	await get_tree().process_frame
	return game


func test_lvt_synergy_parks_goods_sludge_and_pollution() -> void:
	var game: Node = await _instantiate_game()
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var economy: EconomyManager = game.get_node("EconomyManager") as EconomyManager
	var simulator: SupplyChainSimulator = game.get_node("SupplyChainSimulator") as SupplyChainSimulator

	var home_pos: Vector2i = Vector2i(2, 10)
	grid.set_tile(home_pos, GridCellData.new(GridCellData.TileType.RESIDENTIAL_LOW))
	var base_lv: int = economy.get_land_value(home_pos)

	# 1) Goods delivery boosts residential Land Value directly (+5).
	simulator.set_supplied_goods(home_pos, true)
	var supplied_lv: int = economy.get_land_value(home_pos)
	assert(supplied_lv == base_lv + SupplyChainSimulator.GOODS_LAND_VALUE_BOOST,
			"Supplied goods should boost residential land value by +5.")

	# 2) Nearby Park boosts Land Value (+15 for first park).
	var park_pos: Vector2i = Vector2i(2, 9)
	grid.set_tile(park_pos, GridCellData.new(GridCellData.TileType.PARK))
	var park_lv: int = economy.get_land_value(home_pos)
	assert(park_lv == supplied_lv + 15,
			"A park within radius should add +15 to residential land value.")

	# 3) Sludge pipe within radius consistently applies the -25 LV penalty.
	var pipe_pos: Vector2i = Vector2i(2, 11)
	grid.set_tile(pipe_pos, GridCellData.new(GridCellData.TileType.SLUDGE))
	var sludge_lv: int = economy.get_land_value(home_pos)
	assert(sludge_lv == park_lv + EconomyManager.SLUDGE_PENALTY,
			"Sludge pipes near housing should apply the standard -25 land-value penalty.")
	grid.set_tile(pipe_pos, GridCellData.new(GridCellData.TileType.GRASS))

	# 4) Factory pollution within radius crashes residential Land Value.
	var factory_pos: Vector2i = Vector2i(4, 10)
	grid.set_tile(factory_pos, GridCellData.new(GridCellData.TileType.INDUSTRIAL))
	var polluted_lv: int = economy.get_land_value(home_pos)
	assert(polluted_lv == int(park_lv * EconomyManager.POLLUTION_LV_MULTIPLIER),
			"Factory pollution within radius should crash residential land value by 80%.")

	game.queue_free()
	await get_tree().process_frame


func test_dual_trigger_upgrade_requires_both_steps_for_two_cycles() -> void:
	var game: Node = await _instantiate_game()
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var economy: EconomyManager = game.get_node("EconomyManager") as EconomyManager
	var simulator: SupplyChainSimulator = game.get_node("SupplyChainSimulator") as SupplyChainSimulator
	var evolution: ResidentialEvolutionManager = game.get_node(
			"ResidentialEvolutionManager") as ResidentialEvolutionManager

	var home_pos: Vector2i = Vector2i(2, 10)
	grid.set_tile(home_pos, GridCellData.new(GridCellData.TileType.RESIDENTIAL_LOW))
	grid.set_tile(Vector2i(2, 9), GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(Vector2i(3, 10), GridCellData.new(GridCellData.TileType.PARK))

	# Step 1 LV is well above 30, and road/park/clean_air are met, but Goods is missing.
	assert(economy.get_land_value(home_pos) >= EconomyManager.UPGRADE_LVT,
			"Fixture home should satisfy Step 1 LV threshold.")
	economy.calculate_net_income(true)
	economy.calculate_net_income(true)
	assert(grid.get_tile_type(home_pos) == GridCellData.TileType.RESIDENTIAL_LOW,
			"Villa must not upgrade when Goods delivery is missing, even with high LV.")
	assert(evolution.get_upgrade_streak(home_pos) == 0,
			"Missing a Step 2 checklist item must keep the upgrade streak at 0.")

	# Supply goods first without water: missing water must still block Step 2 upgrade.
	simulator.set_supplied_goods(home_pos, true)
	simulator.set_supplied_water(home_pos, false)
	economy.calculate_net_income(true)
	assert(grid.get_tile_type(home_pos) == GridCellData.TileType.RESIDENTIAL_LOW,
			"Villa must not upgrade when Water supply is missing.")
	assert(evolution.get_upgrade_streak(home_pos) == 0,
			"Missing Water must keep the upgrade streak at 0.")
	assert(evolution.get_inspection_text(home_pos).contains("Water: Missing"),
			"Inspection readout should report Water: Missing when unsupplied.")

	# Supply both goods and water so all Step 1 + Step 2 requirements (Road, Water, Goods, Park, Clean Air) are met.
	simulator.set_supplied_water(home_pos, true)
	economy.calculate_net_income(true)
	assert(grid.get_tile_type(home_pos) == GridCellData.TileType.RESIDENTIAL_LOW,
			"Villa must not upgrade after only 1 satisfied assessment cycle.")
	assert(evolution.get_upgrade_streak(home_pos) == 1,
			"First satisfied cycle should advance the upgrade streak to 1.")

	var readout_text: String = evolution.get_inspection_text(home_pos)
	assert(readout_text.contains("Upgrading (1/2 cycles)"),
			"Inspection readout should show the 1/2 upgrade streak progress.")
	assert(readout_text.contains("Road: OK · Goods: OK · Water: OK") and readout_text.contains("Park: OK · Clean Air: OK"),
			"Inspection readout should show all checklist items including Water as OK.")

	# Second consecutive satisfied cycle triggers the upgrade to RESIDENTIAL_HIGH.
	economy.calculate_net_income(true)
	assert(grid.get_tile_type(home_pos) == GridCellData.TileType.RESIDENTIAL_HIGH,
			"Second consecutive satisfied cycle should upgrade Villa to Apartment.")

	game.queue_free()
	await get_tree().process_frame


func test_grace_period_and_degradation_for_apartment_and_villa() -> void:
	var game: Node = await _instantiate_game()
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var economy: EconomyManager = game.get_node("EconomyManager") as EconomyManager
	var simulator: SupplyChainSimulator = game.get_node("SupplyChainSimulator") as SupplyChainSimulator
	var evolution: ResidentialEvolutionManager = game.get_node(
			"ResidentialEvolutionManager") as ResidentialEvolutionManager
	var placement_controller: PlacementController = game.get_node(
			"PlacementController") as PlacementController

	var apt_pos: Vector2i = Vector2i(2, 10)
	grid.set_tile(apt_pos, GridCellData.new(GridCellData.TileType.RESIDENTIAL_HIGH))
	grid.set_tile(Vector2i(2, 9), GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(Vector2i(3, 10), GridCellData.new(GridCellData.TileType.PARK))
	simulator.set_supplied_water(apt_pos, true)

	# Cut off goods: Cycle 1 enters Grace (1/2), does not downgrade yet.
	simulator.set_supplied_goods(apt_pos, false)
	economy.calculate_net_income(true)
	assert(grid.get_tile_type(apt_pos) == GridCellData.TileType.RESIDENTIAL_HIGH,
			"Apartment should remain Tier 2 during the first grace cycle.")
	assert(evolution.get_grace_cycles(apt_pos) == 1,
			"First unsatisfied cycle should record 1 grace cycle.")
	assert(evolution.get_inspection_text(apt_pos).contains("Unsatisfied Needs — Grace (1/2)"),
			"Apartment readout should warn about Grace (1/2).")

	# Restoring goods resets grace back to 0.
	simulator.set_supplied_goods(apt_pos, true)
	economy.calculate_net_income(true)
	assert(evolution.get_grace_cycles(apt_pos) == 0,
			"Restoring missing needs should clear the grace counter.")

	# Cut off goods for 2 consecutive cycles -> downgrades to RESIDENTIAL_LOW.
	simulator.set_supplied_goods(apt_pos, false)
	economy.calculate_net_income(true)
	economy.calculate_net_income(true)
	assert(grid.get_tile_type(apt_pos) == GridCellData.TileType.RESIDENTIAL_LOW,
			"Two consecutive unsatisfied cycles should degrade Apartment to Villa.")

	# Clear cooldown so we can test Villa stability and abandonment immediately.
	economy.tile_build_times.erase(apt_pos)

	# Missing Tier-2 luxuries (no goods, remove park) keeps Villa stable (no grace).
	grid.set_tile(Vector2i(3, 10), GridCellData.new(GridCellData.TileType.GRASS))
	economy.calculate_net_income(true)
	economy.calculate_net_income(true)
	assert(grid.get_tile_type(apt_pos) == GridCellData.TileType.RESIDENTIAL_LOW,
			"Missing Tier-2 luxuries should keep a road-connected, clean-air Villa stable.")
	assert(evolution.get_grace_cycles(apt_pos) == 0,
			"Stable Villa should not accumulate grace cycles.")

	# Pollute the Villa by placing a factory nearby: 2 cycles degrades Villa to ABANDONED.
	grid.set_tile(Vector2i(4, 10), GridCellData.new(GridCellData.TileType.INDUSTRIAL))
	economy.calculate_net_income(true)
	assert(grid.get_tile_type(apt_pos) == GridCellData.TileType.RESIDENTIAL_LOW,
			"Villa should survive the first cycle of pollution in Grace (1/2).")
	assert(evolution.get_grace_cycles(apt_pos) == 1,
			"Polluted Villa should enter Grace (1/2).")
	economy.calculate_net_income(true)
	assert(grid.get_tile_type(apt_pos) == GridCellData.TileType.ABANDONED,
			"Two consecutive cycles without basic livability should abandon the Villa.")
	assert(evolution.get_inspection_text(apt_pos).contains("Abandoned"),
			"Abandoned tile should report its abandoned status in the inspection readout.")

	# Player can bulldoze an ABANDONED residence back to GRASS.
	var bulldoze_result: Dictionary = placement_controller.attempt_bulldoze(apt_pos, 500)
	assert(bool(bulldoze_result["ok"]) and grid.get_tile_type(apt_pos) == GridCellData.TileType.GRASS,
			"Abandoned residences should be demolishable back to grass.")

	game.queue_free()
	await get_tree().process_frame
