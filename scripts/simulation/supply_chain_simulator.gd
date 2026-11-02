class_name SupplyChainSimulator
extends Node
## Owns the periodic supply-chain simulation and its workforce/resource state.
## Allocation loops intentionally preserve the established grid and network order.

const TICK_INTERVAL: float = 3.0
const WORKERS_PER_VILLA: int = 1
const WORKERS_PER_APARTMENT: int = 3
const WORKERS_PER_FACTORY: int = 2
const GOODS_PER_FACTORY_TICK: int = 3
const GOODS_PER_HOUSE_TICK: int = 1
const GOODS_LAND_VALUE_BOOST: int = 5
const WATER_CAPACITY_SMALL_TOWER: int = 30
const WATER_CAPACITY_LARGE_TOWER: int = 80
const WATER_PER_HOUSE_TICK: int = 1
const WATER_PER_FACTORY_TICK: int = 1
const UNWATERED_FACTORY_MULTIPLIER: float = 0.5

var grid: GridManager
var road_connectivity: RoadConnectivityManager
var economy: EconomyManager
var pipe_network: PipeNetworkManager
var farm_system: FarmSystem = FarmSystem.new()
var grid_size: int = 20
var is_load_rebuild_provider: Callable
var is_load_rebuild: bool = false

var worker_capacity: int = 0
var available_workers: int = 0
var goods_stock: int = 0
var goods_supplied: Dictionary = {}
var water_supplied: Dictionary = {}
var network_water_stats: Dictionary = {}
var water_capacity_last_tick: int = 0
var water_demand_last_tick: int = 0
var water_delivered_last_tick: int = 0
var water_supplied_homes_last_tick: int = 0
var water_supplied_factories_last_tick: int = 0
var operating_factories: int = 0
var factory_goods_delivered: Dictionary = {}
var goods_produced_last_tick: int = 0
var goods_consumed_last_tick: int = 0
var homes_supplied_last_tick: int = 0
var road_connected_homes_last_tick: int = 0
var total_homes_last_tick: int = 0
var operating_farmhouses: int = 0
var active_farm_fields_last_tick: int = 0
var farm_goods_produced_last_tick: int = 0
var farmhouse_field_counts: Dictionary = {}

var _supply_chain_timer: Timer
var _is_paused: bool = false

signal tick_started
signal tick_completed


func configure(
		world_grid: GridManager,
		connectivity: RoadConnectivityManager,
		economy_manager: EconomyManager,
		pipes: PipeNetworkManager,
		farms: FarmSystem,
		world_grid_size: int) -> void:
	grid = world_grid
	road_connectivity = connectivity
	economy = economy_manager
	pipe_network = pipes
	farm_system = farms
	grid_size = world_grid_size


func start_timer() -> void:
	if _supply_chain_timer != null:
		return
	_supply_chain_timer = Timer.new()
	_supply_chain_timer.name = "SupplyChainTimer"
	_supply_chain_timer.wait_time = TICK_INTERVAL
	_supply_chain_timer.autostart = true
	_supply_chain_timer.one_shot = false
	_supply_chain_timer.paused = _is_paused
	_supply_chain_timer.timeout.connect(_on_supply_chain_timer_timeout)
	add_child(_supply_chain_timer)


func get_supply_chain_timer() -> Timer:
	return _supply_chain_timer


func set_paused(paused: bool) -> void:
	_is_paused = paused
	if _supply_chain_timer != null:
		_supply_chain_timer.paused = paused


func is_paused() -> bool:
	return _is_paused


func clear_supplied_goods() -> void:
	goods_supplied.clear()


func set_supplied_goods(position: Vector2i, is_supplied: bool) -> void:
	goods_supplied[position] = is_supplied


func clear_supplied_water() -> void:
	water_supplied.clear()


func set_supplied_water(position: Vector2i, is_supplied: bool) -> void:
	water_supplied[position] = is_supplied


func is_water_supplied(grid_pos: Vector2i) -> bool:
	return bool(water_supplied.get(grid_pos, false))


func get_factory_water_multiplier(factory_pos: Vector2i) -> float:
	return 1.0 if is_water_supplied(factory_pos) else UNWATERED_FACTORY_MULTIPLIER


func get_network_water_stats(network_id: int) -> Dictionary:
	if network_id < 0 or not network_water_stats.has(network_id):
		return {"capacity": 0, "demand": 0, "delivered": 0, "bottleneck": false}
	return (network_water_stats[network_id] as Dictionary).duplicate(true)


func get_network_water_stats_for_cell(grid_pos: Vector2i) -> Dictionary:
	if road_connectivity == null:
		return {"capacity": 0, "demand": 0, "delivered": 0, "bottleneck": false}
	var net_id: int = road_connectivity.get_building_network_id(grid_pos)
	return get_network_water_stats(net_id)


func serialize_water_supplied() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for key: Variant in water_supplied:
		if not key is Vector2i:
			continue
		var pos: Vector2i = key as Vector2i
		entries.append({"x": pos.x, "y": pos.y, "supplied": bool(water_supplied[pos])})
	return entries


func restore_water_supplied(values: Variant) -> void:
	water_supplied.clear()
	if not values is Array:
		return
	for entry_value: Variant in values as Array:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value as Dictionary
		var pos: Vector2i = Vector2i(int(entry.get("x", -1)), int(entry.get("y", -1)))
		if pos.x >= 0 and pos.x < grid_size and pos.y >= 0 and pos.y < grid_size:
			water_supplied[pos] = bool(entry.get("supplied", false))


func residential_goods_tax_bonus_at(grid_pos: Vector2i) -> int:
	return GOODS_LAND_VALUE_BOOST if goods_supplied.get(grid_pos, false) else 0


func is_home_supplied(grid_pos: Vector2i) -> bool:
	return bool(goods_supplied.get(grid_pos, false))


func get_factory_delivered_goods(factory_pos: Vector2i) -> int:
	return int(factory_goods_delivered.get(factory_pos, 0))


func serialize_goods_supplied() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for key: Variant in goods_supplied:
		if not key is Vector2i:
			continue
		var pos: Vector2i = key as Vector2i
		entries.append({"x": pos.x, "y": pos.y, "supplied": bool(goods_supplied[pos])})
	return entries


func restore_goods_supplied(values: Variant) -> void:
	goods_supplied.clear()
	if not values is Array:
		return
	for entry_value: Variant in values as Array:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value as Dictionary
		var pos: Vector2i = Vector2i(int(entry.get("x", -1)), int(entry.get("y", -1)))
		if pos.x >= 0 and pos.x < grid_size and pos.y >= 0 and pos.y < grid_size:
			goods_supplied[pos] = bool(entry.get("supplied", false))


## Aggregates the live supply-chain and grid counts for EconomyHudPresenter.
func get_resource_hud_snapshot() -> Dictionary:
	var factory_count: int = 0
	var staffed_factory_count: int = 0
	var farmhouse_count: int = 0
	var farmland_count: int = 0
	var residences: int = 0
	var supplied_homes: int = 0
	if grid != null:
		for pos: Vector2i in grid.get_all_occupied_positions():
			var tile_type: int = grid.get_tile_type(pos)
			if tile_type == GridCellData.TileType.INDUSTRIAL:
				factory_count += 1
				if economy != null and economy.staffed_factories.has(pos):
					staffed_factory_count += 1
			elif tile_type == GridCellData.TileType.FARMHOUSE:
				farmhouse_count += 1
			elif tile_type == GridCellData.TileType.FARMLAND:
				farmland_count += 1
			elif tile_type == GridCellData.TileType.RESIDENTIAL_LOW \
					or tile_type == GridCellData.TileType.RESIDENTIAL_HIGH:
				residences += 1
				if goods_supplied.get(pos, false):
					supplied_homes += 1
	var employed_workers: int = maxi(0, worker_capacity - available_workers)
	return {
		"worker_capacity": worker_capacity,
		"employed_workers": employed_workers,
		"available_workers": available_workers,
		"goods_stock": goods_stock,
		"goods_produced_last_tick": goods_produced_last_tick,
		"goods_consumed_last_tick": goods_consumed_last_tick,
		"supplied_homes": supplied_homes,
		"residences": residences,
		"staffed_factory_count": staffed_factory_count,
		"factory_count": factory_count,
		"operating_farmhouses": operating_farmhouses,
		"farmhouse_count": farmhouse_count,
		"active_farm_fields_last_tick": active_farm_fields_last_tick,
		"farmland_count": farmland_count,
		"farm_goods_produced_last_tick": farm_goods_produced_last_tick,
		"road_connected_homes_last_tick": road_connected_homes_last_tick,
		"water_capacity_last_tick": water_capacity_last_tick,
		"water_demand_last_tick": water_demand_last_tick,
		"water_delivered_last_tick": water_delivered_last_tick,
		"water_supplied_homes_last_tick": water_supplied_homes_last_tick,
		"water_supplied_factories_last_tick": water_supplied_factories_last_tick,
	}


## One simulation tick. Residential tiles create workers, staffed road-connected
## factories and farms produce goods, and road-connected homes consume the pool.
## Factory staffing is written to EconomyManager so income and goods production
## use the same result until the next supply-chain tick.
func run_tick() -> void:
	if is_load_rebuild_provider.is_valid():
		is_load_rebuild = bool(is_load_rebuild_provider.call())
	tick_started.emit()
	# 1) Rebuild worker capacity from residential tiles.
	worker_capacity = 0
	for pos: Vector2i in grid.get_all_occupied_positions():
		match grid.get_tile_type(pos):
			GridCellData.TileType.RESIDENTIAL_LOW:
				worker_capacity += WORKERS_PER_VILLA
			GridCellData.TileType.RESIDENTIAL_HIGH:
				worker_capacity += WORKERS_PER_APARTMENT

	# 1.5) Pool water capacity from connected Water Towers and allocate water per
	# connected road network to residences (1/tick) and factories (1/tick).
	_run_water_allocation_pass()

	# 2) Factories draw workers first; the shared staffing set drives income too.
	available_workers = worker_capacity
	operating_factories = 0
	operating_farmhouses = 0
	active_farm_fields_last_tick = 0
	farm_goods_produced_last_tick = 0
	farmhouse_field_counts = farm_system.get_connected_farmhouse_field_counts(
			grid, road_connectivity)
	economy.staffed_factories.clear()
	pipe_network.reset_capacity_usage()
	var produced: int = 0
	factory_goods_delivered.clear()
	goods_produced_last_tick = 0
	goods_consumed_last_tick = 0
	homes_supplied_last_tick = 0
	road_connected_homes_last_tick = 0
	total_homes_last_tick = 0
	var hooked_factory_outputs: Array[Dictionary] = []
	var labor_efficiency: float = (
		economy.get_labor_efficiency_multiplier()
		if economy != null
		else 1.0
	)
	for pos: Vector2i in grid.get_all_occupied_positions():
		if grid.get_tile_type(pos) != GridCellData.TileType.INDUSTRIAL:
			continue
		if not road_connectivity.is_road_connected(pos):
			continue
		if economy.is_factory_on_strike(pos):
			continue
		if available_workers >= WORKERS_PER_FACTORY:
			available_workers -= WORKERS_PER_FACTORY
			operating_factories += 1
			economy.staffed_factories[pos] = true
			# Pipe hookup, water supply, and labor efficiency scale output; hooked output is capacity-limited per network.
			var pipe_mult: float = economy.factory_pipe_multiplier(pos)
			var water_mult: float = get_factory_water_multiplier(pos)
			var base_factory_output: float = GOODS_PER_FACTORY_TICK * pipe_mult * water_mult
			var requested_output: int = roundi(base_factory_output * labor_efficiency)
			var component_id: int = pipe_network.get_factory_network_id(pos)
			if component_id >= 0:
				var matching_output_index: int = -1
				for output_index: int in range(hooked_factory_outputs.size()):
					if int(hooked_factory_outputs[output_index]["component_id"]) == component_id:
						matching_output_index = output_index
						break
				if matching_output_index < 0:
					var initial_factory_positions: Array[Vector2i] = [pos]
					var initial_factory_outputs: Array[int] = [requested_output]
					hooked_factory_outputs.append({
						"component_id": component_id,
						"requested": requested_output,
						"factories": initial_factory_positions,
						"outputs": initial_factory_outputs
					})
				else:
					var output_record: Dictionary = hooked_factory_outputs[matching_output_index]
					output_record["requested"] = int(output_record["requested"]) + requested_output
					var recorded_factories: Array[Vector2i] = []
					recorded_factories.assign(output_record["factories"])
					recorded_factories.append(pos)
					output_record["factories"] = recorded_factories
					var recorded_outputs: Array[int] = []
					recorded_outputs.assign(output_record["outputs"])
					recorded_outputs.append(requested_output)
					output_record["outputs"] = recorded_outputs
					hooked_factory_outputs[matching_output_index] = output_record
			else:
				# Unhooked factories retain their existing reduced-output behavior.
				produced += requested_output
				factory_goods_delivered[pos] = requested_output

	# Farmhouses require one worker and a road hookup; each nearby field adds goods.
	for farmhouse_pos: Vector2i in farmhouse_field_counts:
		var assigned_fields: int = int(farmhouse_field_counts[farmhouse_pos])
		if assigned_fields <= 0 or available_workers < 1:
			continue
		available_workers -= 1
		operating_farmhouses += 1
		active_farm_fields_last_tick += assigned_fields
		var base_farm_output: int = farm_system.goods_for_field_count(assigned_fields)
		farm_goods_produced_last_tick += roundi(base_farm_output * labor_efficiency)
	produced += farm_goods_produced_last_tick

	# Allocate each connected network's capacity once per tick. Deterministic
	# factory iteration means the same earlier factories are served first.
	var remaining_by_network: Dictionary = {}
	for factory_output: Dictionary in hooked_factory_outputs:
		var component_id: int = int(factory_output["component_id"])
		var requested: int = int(factory_output["requested"])
		var capacity: int = pipe_network.get_network_capacity(component_id)
		var remaining: int = int(remaining_by_network.get(component_id, capacity))
		var delivered: int = mini(requested, remaining)
		remaining_by_network[component_id] = remaining - delivered
		produced += delivered
		pipe_network.record_network_flow(component_id, requested, delivered)
		var factory_positions: Array[Vector2i] = []
		factory_positions.assign(factory_output["factories"])
		var factory_outputs: Array[int] = []
		factory_outputs.assign(factory_output["outputs"])
		var remaining_delivery: int = delivered
		for factory_index: int in range(factory_positions.size()):
			var assigned: int = mini(remaining_delivery, factory_outputs[factory_index])
			factory_goods_delivered[factory_positions[factory_index]] = assigned
			remaining_delivery -= assigned
	pipe_network.finish_capacity_tick()
	if not is_load_rebuild:
		goods_stock += produced
		goods_produced_last_tick = produced

	# 3) Residences consume goods in grid order; fed residences receive a direct
	# tax bonus through residential_goods_tax_bonus_at(). During a load rebuild,
	# preserve the saved stock and last-tick supply results while still rebuilding
	# staffing and pipe-flow telemetry above.
	var supplied_houses: int = 0
	var road_connected_homes: int = 0
	var total_homes: int = 0
	for pos: Vector2i in grid.get_all_occupied_positions():
		var tile_type: int = grid.get_tile_type(pos)
		if tile_type == GridCellData.TileType.RESIDENTIAL_LOW \
				or tile_type == GridCellData.TileType.RESIDENTIAL_HIGH:
			total_homes += 1
			if road_connectivity.is_road_connected(pos):
				road_connected_homes += 1
	if not is_load_rebuild:
		var goods_demand_per_house: int = (
			economy.get_ubi_goods_demand_per_house()
			if economy != null
			else GOODS_PER_HOUSE_TICK
		)
		goods_supplied.clear()
		for pos: Vector2i in grid.get_all_occupied_positions():
			var tile_type: int = grid.get_tile_type(pos)
			if tile_type != GridCellData.TileType.RESIDENTIAL_LOW \
					and tile_type != GridCellData.TileType.RESIDENTIAL_HIGH:
				continue
			if not road_connectivity.is_road_connected(pos):
				goods_supplied[pos] = false
				continue
			if goods_stock >= goods_demand_per_house:
				goods_stock -= goods_demand_per_house
				goods_supplied[pos] = true
				supplied_houses += 1
				goods_consumed_last_tick += goods_demand_per_house
			else:
				goods_supplied[pos] = false
		homes_supplied_last_tick = supplied_houses
		road_connected_homes_last_tick = road_connected_homes
		total_homes_last_tick = total_homes

	prints("Supply chain: capacity=%d available=%d factories=%d goods=%d supplied=%d" % [
		worker_capacity, available_workers, operating_factories, goods_stock, supplied_houses])
	tick_completed.emit()


func _run_water_allocation_pass() -> void:
	network_water_stats.clear()
	water_capacity_last_tick = 0
	water_demand_last_tick = 0
	water_delivered_last_tick = 0
	water_supplied_homes_last_tick = 0
	water_supplied_factories_last_tick = 0
	if grid == null or road_connectivity == null:
		return

	var remaining_water_by_network: Dictionary = {}
	for pos: Vector2i in grid.get_all_occupied_positions():
		var tile_type: int = grid.get_tile_type(pos)
		var tower_capacity: int = 0
		if tile_type == GridCellData.TileType.WATER_TOWER_SMALL:
			tower_capacity = WATER_CAPACITY_SMALL_TOWER
		elif tile_type == GridCellData.TileType.WATER_TOWER_LARGE:
			tower_capacity = WATER_CAPACITY_LARGE_TOWER
		else:
			continue
		var net_id: int = road_connectivity.get_building_network_id(pos)
		if net_id < 0:
			continue
		if not network_water_stats.has(net_id):
			network_water_stats[net_id] = {
				"capacity": 0,
				"demand": 0,
				"delivered": 0,
				"bottleneck": false,
			}
		var stats: Dictionary = network_water_stats[net_id]
		stats["capacity"] = int(stats["capacity"]) + tower_capacity
		network_water_stats[net_id] = stats
		remaining_water_by_network[net_id] = int(remaining_water_by_network.get(net_id, 0)) + tower_capacity
		water_capacity_last_tick += tower_capacity

	var saved_water_flags: Dictionary = water_supplied.duplicate(true)
	if not is_load_rebuild or saved_water_flags.is_empty():
		water_supplied.clear()

	for pos: Vector2i in grid.get_all_occupied_positions():
		var tile_type: int = grid.get_tile_type(pos)
		var is_residence: bool = (
			tile_type == GridCellData.TileType.RESIDENTIAL_LOW
			or tile_type == GridCellData.TileType.RESIDENTIAL_HIGH
		)
		var is_factory: bool = tile_type == GridCellData.TileType.INDUSTRIAL
		if not is_residence and not is_factory:
			continue
		var demand_units: int = WATER_PER_HOUSE_TICK if is_residence else WATER_PER_FACTORY_TICK
		var adjacent_net_ids: Array[int] = road_connectivity.get_adjacent_network_ids(pos)
		if adjacent_net_ids.is_empty():
			if not is_load_rebuild or not saved_water_flags.has(pos):
				water_supplied[pos] = false
			continue
		var chosen_net_id: int = int(adjacent_net_ids[0])
		for candidate_net_id: int in adjacent_net_ids:
			if int(remaining_water_by_network.get(candidate_net_id, 0)) >= demand_units:
				chosen_net_id = candidate_net_id
				break
		if not network_water_stats.has(chosen_net_id):
			network_water_stats[chosen_net_id] = {
				"capacity": 0,
				"demand": 0,
				"delivered": 0,
				"bottleneck": false,
			}
		var net_stats: Dictionary = network_water_stats[chosen_net_id]
		net_stats["demand"] = int(net_stats["demand"]) + demand_units
		water_demand_last_tick += demand_units
		var remaining: int = int(remaining_water_by_network.get(chosen_net_id, 0))
		if remaining >= demand_units:
			remaining_water_by_network[chosen_net_id] = remaining - demand_units
			net_stats["delivered"] = int(net_stats["delivered"]) + demand_units
			water_delivered_last_tick += demand_units
			if not is_load_rebuild or not saved_water_flags.has(pos):
				water_supplied[pos] = true
		else:
			if not is_load_rebuild or not saved_water_flags.has(pos):
				water_supplied[pos] = false
		net_stats["bottleneck"] = int(net_stats["demand"]) > int(net_stats["capacity"])
		network_water_stats[chosen_net_id] = net_stats
		if bool(water_supplied.get(pos, false)):
			if is_residence:
				water_supplied_homes_last_tick += 1
			else:
				water_supplied_factories_last_tick += 1


func _on_supply_chain_timer_timeout() -> void:
	if _is_paused:
		return
	run_tick()
