extends Node


func _instantiate_game() -> Node:
	var game_scene: PackedScene = load("res://node_2d.tscn") as PackedScene
	assert(game_scene != null, "Could not load the gameplay scene.")
	var game: Node = game_scene.instantiate()
	get_tree().root.add_child(game)
	await get_tree().process_frame
	return game


func test_surplus_and_safety_math_distributes_ubi_and_protects_deficit_treasury() -> void:
	var game: Node = await _instantiate_game()
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var economy: EconomyManager = game.get_node("EconomyManager") as EconomyManager

	var apt_pos: Vector2i = Vector2i(2, 10)
	var factory_pos: Vector2i = Vector2i(10, 10)
	grid.set_tile(apt_pos, GridCellData.new(GridCellData.TileType.RESIDENTIAL_HIGH))
	grid.set_tile(factory_pos, GridCellData.new(GridCellData.TileType.INDUSTRIAL))
	economy.staffed_factories[factory_pos] = true

	economy.set_ubi_rate(0.5)
	assert(is_equal_approx(economy.get_ubi_rate(), 0.5), "UBI rate should clamp and store 0.5.")
	assert(is_equal_approx(economy.dividend_percent, 50.0), "dividend_percent should sync to 50%.")

	var retained: int = economy.calculate_net_income(false)
	var expected_surplus: int = maxi(0, economy.last_lvt_revenue - economy.last_maintenance_cost)
	var expected_payout: int = roundi(expected_surplus * 0.5)
	assert(economy.last_net_surplus == expected_surplus and expected_surplus > 0,
			"Positive LVT surplus should equal gross LVT revenue minus maintenance costs.")
	assert(economy.last_ubi_payout == expected_payout,
			"UBI payout should equal roundi(Net_Surplus * ubi_rate).")
	assert(retained == (economy.last_lvt_revenue - economy.last_maintenance_cost) - expected_payout,
			"Retained treasury revenue should deduct maintenance costs and UBI payout.")
	assert(economy.get_retained_treasury_revenue() == retained,
			"get_retained_treasury_revenue() should match the assessment cycle result.")

	# Deficit safety check: remove revenue buildings and add roads so maintenance exceeds LVT revenue.
	economy.staffed_factories.clear()
	grid.set_tile(apt_pos, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(factory_pos, GridCellData.new(GridCellData.TileType.ROAD))
	for x: int in range(2, 12):
		grid.set_tile(Vector2i(x, 5), GridCellData.new(GridCellData.TileType.ROAD))

	var deficit_retained: int = economy.calculate_net_income(false)
	assert(economy.last_lvt_revenue < economy.last_maintenance_cost,
			"Fixture should be in a fiscal deficit where maintenance exceeds LVT revenue.")
	assert(economy.last_net_surplus == 0 and economy.get_net_surplus() == 0,
			"Net surplus must floor at $0 when maintenance exceeds LVT revenue.")
	assert(economy.last_ubi_payout == 0 and economy.get_ubi_payout() == 0,
			"UBI payout must safely drop to $0 when net surplus is $0.")
	assert(deficit_retained == economy.last_lvt_revenue - economy.last_maintenance_cost,
			"Deficit treasury should not incur any UBI payout deduction.")

	game.queue_free()
	await get_tree().process_frame


func test_ubi_land_value_bonus_applies_to_residential_tiles() -> void:
	var game: Node = await _instantiate_game()
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var economy: EconomyManager = game.get_node("EconomyManager") as EconomyManager

	var villa_pos: Vector2i = Vector2i(6, 10)
	var apt_pos: Vector2i = Vector2i(2, 10)
	var non_res_pos: Vector2i = Vector2i(6, 11)
	grid.set_tile(villa_pos, GridCellData.new(GridCellData.TileType.RESIDENTIAL_LOW))
	grid.set_tile(apt_pos, GridCellData.new(GridCellData.TileType.RESIDENTIAL_HIGH))
	grid.set_tile(non_res_pos, GridCellData.new(GridCellData.TileType.WAREHOUSE))

	economy.set_ubi_rate(0.0)
	economy.calculate_net_income(false)
	var base_villa_lv: int = economy.get_land_value(villa_pos)
	var base_apt_lv: int = economy.get_land_value(apt_pos)
	var base_non_res_lv: int = economy.get_land_value(non_res_pos)
	assert(economy.get_ubi_land_value_bonus() == 0,
			"Zero UBI payout should yield 0 land value bonus.")

	economy.set_ubi_rate(1.0)
	economy.calculate_net_income(false)
	var bonus: int = economy.get_ubi_land_value_bonus()
	assert(bonus > 0 and bonus <= EconomyManager.MAX_UBI_LAND_VALUE_BONUS,
			"Active UBI payout should generate a positive capped Land Value bonus.")
	assert(economy.get_land_value(villa_pos) == base_villa_lv + bonus,
			"RESIDENTIAL_LOW Land Value should increase by the active UBI Land Value bonus.")
	assert(economy.get_land_value(apt_pos) == base_apt_lv + bonus,
			"RESIDENTIAL_HIGH Land Value should increase by the active UBI Land Value bonus.")
	assert(economy.get_land_value(non_res_pos) == base_non_res_lv,
			"Non-residential tiles should not receive the residential UBI Land Value bonus.")

	game.queue_free()
	await get_tree().process_frame


func test_high_ubi_increases_residential_goods_consumption_pressure() -> void:
	var game: Node = await _instantiate_game()
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var economy: EconomyManager = game.get_node("EconomyManager") as EconomyManager
	var simulator: SupplyChainSimulator = game.get_node("SupplyChainSimulator") as SupplyChainSimulator

	var road_a: Vector2i = Vector2i(5, 8)
	var house_a: Vector2i = Vector2i(5, 9)
	var road_b: Vector2i = Vector2i(7, 8)
	var house_b: Vector2i = Vector2i(7, 9)
	grid.set_tile(road_a, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(house_a, GridCellData.new(GridCellData.TileType.RESIDENTIAL_LOW))
	grid.set_tile(road_b, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(house_b, GridCellData.new(GridCellData.TileType.RESIDENTIAL_LOW))
	game.call("refresh_road_connections", house_a)
	game.call("refresh_road_connections", house_b)

	# Baseline UBI (<= 0.5): 1 good per house -> 2 houses consume 2 goods total.
	economy.set_ubi_rate(0.5)
	assert(economy.get_ubi_goods_demand_per_house() == 1,
			"UBI rate <= 0.5 should demand 1 good per house per tick.")
	simulator.goods_stock = 3
	simulator.run_tick()
	assert(simulator.goods_consumed_last_tick == 2,
			"Two homes should consume 2 goods when UBI rate <= 0.5.")
	assert(simulator.homes_supplied_last_tick == 2 and simulator.goods_stock == 1,
			"Both homes should be supplied with 1 good left in stock.")

	# High UBI (> 0.5): 2 goods per house -> 2 houses consume 4 goods total.
	economy.set_ubi_rate(0.8)
	assert(economy.get_ubi_goods_demand_per_house() == 2,
			"UBI rate > 0.5 should demand 2 goods per house per tick.")
	simulator.goods_stock = 4
	simulator.run_tick()
	assert(simulator.goods_consumed_last_tick == 4,
			"Two homes should consume 4 goods when UBI rate > 0.5.")
	assert(simulator.homes_supplied_last_tick == 2 and simulator.goods_stock == 0,
			"Both homes should be supplied and consume all 4 goods.")

	game.queue_free()
	await get_tree().process_frame


func test_reservation_wage_penalizes_factory_and_farm_production_at_high_ubi() -> void:
	var game: Node = await _instantiate_game()
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var economy: EconomyManager = game.get_node("EconomyManager") as EconomyManager
	var simulator: SupplyChainSimulator = game.get_node("SupplyChainSimulator") as SupplyChainSimulator

	assert(is_equal_approx(economy.get_labor_efficiency_multiplier(0.0), 1.0),
			"Zero UBI should have 1.0 labor efficiency.")
	assert(is_equal_approx(economy.get_labor_efficiency_multiplier(0.5), 1.0),
			"50% UBI threshold should retain 1.0 labor efficiency.")
	assert(is_equal_approx(economy.get_labor_efficiency_multiplier(0.75), 0.90),
			"75% UBI should apply a 10% reservation wage penalty (0.90 multiplier).")
	assert(is_equal_approx(economy.get_labor_efficiency_multiplier(1.0), 0.85),
			"100% UBI should apply the maximum 15% reservation wage penalty (0.85 multiplier).")

	# Set up 1 apartment (3 workers), 1 hooked factory (needs 2 workers), and 1 farmhouse (needs 1 worker) with 6 fields.
	var apt_pos: Vector2i = Vector2i(2, 4)
	var apt_road: Vector2i = Vector2i(2, 5)
	var factory_pos: Vector2i = Vector2i(1, 10)
	var factory_road: Vector2i = Vector2i(1, 9)
	var sludge_edge: Vector2i = Vector2i(0, 9)
	var sludge_link: Vector2i = Vector2i(0, 10)
	var farmhouse_pos: Vector2i = Vector2i(10, 10)
	var farmhouse_road: Vector2i = Vector2i(10, 9)
	var fields: Array[Vector2i] = [
		Vector2i(10, 11), Vector2i(10, 12), Vector2i(11, 10),
		Vector2i(11, 11), Vector2i(9, 10), Vector2i(9, 11),
	]

	grid.set_tile(apt_pos, GridCellData.new(GridCellData.TileType.RESIDENTIAL_HIGH))
	grid.set_tile(apt_road, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(factory_pos, GridCellData.new(GridCellData.TileType.INDUSTRIAL))
	grid.set_tile(factory_road, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(Vector2i(2, 9), GridCellData.new(GridCellData.TileType.WATER_TOWER_SMALL))
	grid.set_tile(sludge_edge, GridCellData.new(GridCellData.TileType.SLUDGE))
	grid.set_tile(sludge_link, GridCellData.new(GridCellData.TileType.SLUDGE))
	grid.set_tile(farmhouse_pos, GridCellData.new(GridCellData.TileType.FARMHOUSE))
	grid.set_tile(farmhouse_road, GridCellData.new(GridCellData.TileType.ROAD))
	for field_pos: Vector2i in fields:
		grid.set_tile(field_pos, GridCellData.new(GridCellData.TileType.FARMLAND))

	var pipe_network: PipeNetworkManager = game.get("_pipe_network") as PipeNetworkManager
	pipe_network.mark_dirty()
	pipe_network.get_live_pipe_cells()
	game.call("refresh_road_connections", apt_pos)
	game.call("refresh_road_connections", factory_pos)
	game.call("refresh_road_connections", farmhouse_pos)

	# Baseline at 50% UBI (multiplier 1.0): hooked factory produces 4, 6-field farm produces 6.
	economy.set_ubi_rate(0.5)
	simulator.run_tick()
	var baseline_factory_goods: int = simulator.get_factory_delivered_goods(factory_pos)
	var baseline_farm_goods: int = simulator.farm_goods_produced_last_tick
	assert(baseline_factory_goods == 4,
			"Hooked factory at <=50% UBI should produce 4 goods.")
	assert(baseline_farm_goods == 6,
			"6-field farmhouse at <=50% UBI should produce 6 goods.")

	# High UBI at 100% (multiplier 0.85): hooked factory 3.9 * 0.85 -> 3, 6-field farm 6 * 0.85 -> 5.
	economy.set_ubi_rate(1.0)
	simulator.run_tick()
	var penalized_factory_goods: int = simulator.get_factory_delivered_goods(factory_pos)
	var penalized_farm_goods: int = simulator.farm_goods_produced_last_tick
	assert(penalized_factory_goods < baseline_factory_goods and penalized_factory_goods == 3,
			"High UBI reservation wage should reduce hooked factory output from 4 to 3.")
	assert(penalized_farm_goods < baseline_farm_goods and penalized_farm_goods == 5,
			"High UBI reservation wage should reduce 6-field farmhouse output from 6 to 5.")

	var summary: Dictionary = economy.get_policy_summary()
	assert(is_equal_approx(float(summary["ubi_rate"]), 1.0)
			and is_equal_approx(float(summary["dividend_percent"]), 100.0)
			and int(summary["goods_demand_per_house"]) == 2
			and is_equal_approx(float(summary["labor_efficiency_multiplier"]), 0.85),
			"get_policy_summary() should expose consistent UBI policy metrics.")

	# Verify UI slider handler and save/load state synchronization.
	game.call("_on_dividend_changed", 60.0)
	assert(is_equal_approx(economy.get_ubi_rate(), 0.6)
			and is_equal_approx(economy.dividend_percent, 60.0),
			"_on_dividend_changed should synchronize ubi_rate and dividend_percent.")
	assert(bool(game.get("_land_value_readout_dirty")),
			"_on_dividend_changed should mark the land value readout cache dirty.")

	var saved_state: Dictionary = game.call("_capture_game_state")
	assert(is_equal_approx(float(saved_state.get("ubi_rate", -1.0)), 0.6)
			and is_equal_approx(float(saved_state.get("dividend_percent", -1.0)), 60.0),
			"Captured save state should store both ubi_rate and dividend_percent.")
	economy.set_ubi_rate(0.0)
	assert(bool(game.call("_apply_saved_state", saved_state)),
			"Applying saved state with ubi_rate should succeed.")
	assert(is_equal_approx(economy.get_ubi_rate(), 0.6)
			and is_equal_approx(economy.dividend_percent, 60.0),
			"Restoring saved state should restore both ubi_rate and dividend_percent.")

	game.queue_free()
	await get_tree().process_frame



