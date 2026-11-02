class_name SpeculatorManager
extends Node
## Manages AI Speculator Syndicates (Dynamic Land Speculation) and Georgist LVT
## counterplay. Active at Town Level 2 ("Town") and above.
##
## Responsibilities:
##   - Identify high-value empty/grass tiles (LV > 25 or adjacent to Park/Water)
##     and claim small contiguous parcels (1–3 tiles).
##   - Pay baseline LVT * lvt_rate into the municipal treasury each assessment.
##   - React dynamically when LVT holding pressure exceeds speculative tolerance:
##       * Option A (Development): Build a Residential unit on road-connected
##         clean plots, expanding the city for the player.
##       * Option B (Forfeiture/Bankruptcy): Abandon the plot back to municipal
##         GRASS/WATER terrain at $0 cost to the player.
##   - Support Eminent Domain acquisition when the player builds over a plot.

const MIN_SPECULATION_LAND_VALUE: int = 25
const PARK_WATER_MIN_LAND_VALUE: int = 18
const MAX_PARCEL_SIZE: int = 3
const MAX_SPECULATOR_TILES: int = 24
const EMINENT_DOMAIN_FEE: int = 25
const HOLDING_COST_THRESHOLD: int = 38
const HIGH_LVT_RATE_THRESHOLD: float = 1.5
const FORFEITURE_LAND_VALUE: int = 15

const CARDINAL_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]

signal lots_changed
signal lot_developed(grid_pos: Vector2i, placed_tile_type: int)
signal lot_forfeited(grid_pos: Vector2i, restored_tile_type: int)
signal eminent_domain_exercised(grid_pos: Vector2i, fee_paid: int)

var grid: GridManager
var economy: EconomyManager
var town_progression: TownProgressionManager
var road_connectivity: RoadConnectivityManager
var placement_controller: PlacementController
var building_placement: BuildingPlacement
var grid_size: int = 30

## Dictionary of Vector2i -> Dictionary {"entry_land_value", "cumulative_tax_paid", "cycles_held"}
var _speculator_lots: Dictionary = {}


func configure(
		world_grid: GridManager,
		economy_manager: EconomyManager,
		progression_manager: TownProgressionManager,
		connectivity: RoadConnectivityManager,
		build_controller: PlacementController,
		placement_visuals: BuildingPlacement,
		world_grid_size: int) -> void:
	grid = world_grid
	economy = economy_manager
	town_progression = progression_manager
	road_connectivity = connectivity
	placement_controller = build_controller
	building_placement = placement_visuals
	grid_size = world_grid_size


func is_active() -> bool:
	if town_progression == null:
		return true
	return town_progression.get_town_level() >= TownProgressionManager.TownLevel.TOWN


func is_speculator_owned(grid_pos: Vector2i) -> bool:
	return _speculator_lots.has(grid_pos)


func get_speculator_lot_count() -> int:
	return _speculator_lots.size()


func get_speculator_positions() -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	for key: Variant in _speculator_lots.keys():
		positions.append(key as Vector2i)
	return positions


func get_lot_data(grid_pos: Vector2i) -> Dictionary:
	if not _speculator_lots.has(grid_pos):
		return {}
	return (_speculator_lots[grid_pos] as Dictionary).duplicate(true)


func get_eminent_domain_cost(grid_pos: Vector2i) -> int:
	if not _speculator_lots.has(grid_pos):
		return 0
	return EMINENT_DOMAIN_FEE


func get_lot_tax_per_cycle(grid_pos: Vector2i) -> int:
	if not _speculator_lots.has(grid_pos) or economy == null:
		return 0
	var lv: int = economy.get_land_value(grid_pos)
	var rate: float = economy.get_lvt_rate()
	var multiplier: float = economy.town_level_lvt_multiplier
	return maxi(0, roundi(float(lv) * rate * multiplier))


func calculate_total_speculator_lvt() -> int:
	if economy == null:
		return 0
	_prune_invalid_lots()
	var total: int = 0
	for key: Variant in _speculator_lots.keys():
		var pos: Vector2i = key as Vector2i
		var lv: int = economy.get_land_value(pos)
		total += maxi(0, roundi(float(lv) * economy.get_lvt_rate()))
	return total


func clear_all_lots() -> void:
	if _speculator_lots.is_empty():
		return
	_speculator_lots.clear()
	lots_changed.emit()


func release_lot(grid_pos: Vector2i, reason: String = "manual") -> bool:
	if not _speculator_lots.has(grid_pos):
		return false
	_speculator_lots.erase(grid_pos)
	if reason == "eminent_domain":
		eminent_domain_exercised.emit(grid_pos, EMINENT_DOMAIN_FEE)
	lots_changed.emit()
	return true


## Claims a single specific cell if eligible (or forces claim when `allow_any_ground` is true).
func claim_cell(grid_pos: Vector2i, allow_any_ground: bool = false) -> bool:
	if not _is_in_bounds(grid_pos) or _speculator_lots.has(grid_pos):
		return false
	if not _is_unbuilt_ground(grid_pos):
		return false
	if not allow_any_ground and not is_eligible_for_speculation(grid_pos):
		return false
	var lv: int = economy.get_land_value(grid_pos) if economy != null else 0
	_speculator_lots[grid_pos] = {
		"entry_land_value": lv,
		"cumulative_tax_paid": 0,
		"cycles_held": 0,
	}
	lots_changed.emit()
	return true


## Identifies the highest-value eligible empty/grass seed and claims up to `max_cells`
## contiguous cells as a speculative parcel.
func claim_contiguous_parcel(max_cells: int = MAX_PARCEL_SIZE) -> Array[Vector2i]:
	var claimed: Array[Vector2i] = []
	if not is_active() or grid == null or economy == null:
		return claimed
	_prune_invalid_lots()
	if _speculator_lots.size() >= MAX_SPECULATOR_TILES:
		return claimed

	var best_seed: Vector2i = Vector2i(-1, -1)
	var best_score: int = -1
	for x: int in range(grid_size):
		for y: int in range(grid_size):
			var candidate: Vector2i = Vector2i(x, y)
			if not is_eligible_for_speculation(candidate):
				continue
			var score: int = _score_cell(candidate)
			if score > best_score:
				best_score = score
				best_seed = candidate

	if best_seed == Vector2i(-1, -1):
		return claimed

	var limit: int = mini(max_cells, MAX_SPECULATOR_TILES - _speculator_lots.size())
	var queue: Array[Vector2i] = [best_seed]
	var visited: Dictionary = {best_seed: true}
	while not queue.is_empty() and claimed.size() < limit:
		var current: Vector2i = queue.pop_front()
		if not is_eligible_for_speculation(current):
			continue
		var lv: int = economy.get_land_value(current)
		_speculator_lots[current] = {
			"entry_land_value": lv,
			"cumulative_tax_paid": 0,
			"cycles_held": 0,
		}
		claimed.append(current)
		var neighbors: Array[Vector2i] = []
		for off: Vector2i in CARDINAL_OFFSETS:
			var next_pos: Vector2i = current + off
			if not visited.has(next_pos) and is_eligible_for_speculation(next_pos):
				visited[next_pos] = true
				neighbors.append(next_pos)
		neighbors.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return _score_cell(a) > _score_cell(b)
		)
		for n: Vector2i in neighbors:
			queue.append(n)

	if not claimed.is_empty():
		lots_changed.emit()
	return claimed


## Evaluates one assessment cycle of Georgist LVT counterplay and optionally claims
## a new parcel when speculative conditions are favorable.
func process_assessment_cycle(claim_new_parcel: bool = true) -> Dictionary:
	var developed: Array[Vector2i] = []
	var forfeited: Array[Vector2i] = []
	var claimed: Array[Vector2i] = []
	if not is_active() or grid == null or economy == null:
		return {
			"active": false,
			"claimed": claimed,
			"developed": developed,
			"forfeited": forfeited,
		}

	_prune_invalid_lots()
	var current_rate: float = economy.get_lvt_rate()
	var held_positions: Array[Vector2i] = get_speculator_positions()
	var any_mutated: bool = false

	for pos: Vector2i in held_positions:
		if not _speculator_lots.has(pos):
			continue
		var lot: Dictionary = _speculator_lots[pos] as Dictionary
		var current_lv: int = economy.get_land_value(pos)
		var tax_this_cycle: int = get_lot_tax_per_cycle(pos)
		var cum_tax: int = int(lot.get("cumulative_tax_paid", 0)) + tax_this_cycle
		var cycles: int = int(lot.get("cycles_held", 0)) + 1
		lot["cumulative_tax_paid"] = cum_tax
		lot["cycles_held"] = cycles
		_speculator_lots[pos] = lot

		var pressure_exceeded: bool = (
			tax_this_cycle >= HOLDING_COST_THRESHOLD
			or current_rate >= HIGH_LVT_RATE_THRESHOLD
			or cum_tax >= maxi(45, current_lv * 2)
			or current_lv <= FORFEITURE_LAND_VALUE
		)
		if not pressure_exceeded:
			continue

		_speculator_lots.erase(pos)
		any_mutated = true
		if _can_develop_lot(pos, current_lv):
			var dev_type: int = _develop_lot(pos)
			developed.append(pos)
			lot_developed.emit(pos, dev_type)
		else:
			var restored_type: int = _forfeit_lot(pos)
			forfeited.append(pos)
			lot_forfeited.emit(pos, restored_type)

	if claim_new_parcel and current_rate < HIGH_LVT_RATE_THRESHOLD:
		claimed = claim_contiguous_parcel(MAX_PARCEL_SIZE)

	if any_mutated:
		lots_changed.emit()

	return {
		"active": true,
		"claimed": claimed,
		"developed": developed,
		"forfeited": forfeited,
	}


func is_eligible_for_speculation(grid_pos: Vector2i) -> bool:
	if not _is_in_bounds(grid_pos) or grid == null or economy == null:
		return false
	if _speculator_lots.has(grid_pos) or _is_edge_highway(grid_pos):
		return false
	if not _is_unbuilt_ground(grid_pos):
		return false
	if economy.is_within_pollution_risk(grid_pos):
		return false
	var lv: int = economy.get_land_value(grid_pos)
	if lv > MIN_SPECULATION_LAND_VALUE:
		return true
	return _has_adjacent_park_or_water(grid_pos) and lv >= PARK_WATER_MIN_LAND_VALUE


func get_lot_inspection_text(grid_pos: Vector2i) -> String:
	if not _speculator_lots.has(grid_pos) or economy == null:
		return ""
	var lot: Dictionary = _speculator_lots[grid_pos] as Dictionary
	var lv: int = economy.get_land_value(grid_pos)
	var tax_per_cycle: int = get_lot_tax_per_cycle(grid_pos)
	var cum_tax: int = int(lot.get("cumulative_tax_paid", 0))
	var cycles: int = int(lot.get("cycles_held", 0))
	var reaction_hint: String = (
		"Will Develop (Road-connected)"
		if _can_develop_lot(grid_pos, lv)
		else "Will Forfeit to Municipal Terrain (No Road / Polluted)"
	)
	return "\n".join([
		"SPECULATOR SYNDICATE: Hoarded Plot",
		"Land Value: %d/100 · LVT Paid: $%d/cycle ($%d total over %d cycles)" % [
			lv, tax_per_cycle, cum_tax, cycles
		],
		"High LVT Counterplay: %s" % reaction_hint,
		"Eminent Domain Buyout: Build Road/Pipe/Structure for +$%d fee" % EMINENT_DOMAIN_FEE,
	])


func serialize_lots() -> Array[Dictionary]:
	_prune_invalid_lots()
	var serialized: Array[Dictionary] = []
	for key: Variant in _speculator_lots.keys():
		var pos: Vector2i = key as Vector2i
		var lot: Dictionary = _speculator_lots[pos] as Dictionary
		serialized.append({
			"x": pos.x,
			"y": pos.y,
			"entry_land_value": int(lot.get("entry_land_value", 0)),
			"cumulative_tax_paid": int(lot.get("cumulative_tax_paid", 0)),
			"cycles_held": int(lot.get("cycles_held", 0)),
		})
	return serialized


func restore_lots(entries: Variant) -> void:
	_speculator_lots.clear()
	if not entries is Array:
		lots_changed.emit()
		return
	for item_variant: Variant in entries as Array:
		if not item_variant is Dictionary:
			continue
		var item: Dictionary = item_variant as Dictionary
		var pos: Vector2i = Vector2i(int(item.get("x", -1)), int(item.get("y", -1)))
		if not _is_in_bounds(pos):
			continue
		_speculator_lots[pos] = {
			"entry_land_value": maxi(0, int(item.get("entry_land_value", 0))),
			"cumulative_tax_paid": maxi(0, int(item.get("cumulative_tax_paid", 0))),
			"cycles_held": maxi(0, int(item.get("cycles_held", 0))),
		}
	lots_changed.emit()


func _can_develop_lot(grid_pos: Vector2i, current_lv: int) -> bool:
	if current_lv <= FORFEITURE_LAND_VALUE:
		return false
	if economy != null and economy.is_within_pollution_risk(grid_pos):
		return false
	return road_connectivity != null and road_connectivity.is_road_adjacent(grid_pos)


func _develop_lot(grid_pos: Vector2i) -> int:
	var placed_type: int = GridCellData.TileType.RESIDENTIAL_LOW
	grid.set_tile(grid_pos, GridCellData.new(placed_type))
	if placement_controller != null:
		placement_controller.place_tile(grid_pos, placed_type)
	if building_placement != null:
		building_placement.spawn_building(grid_pos, placed_type)
	if road_connectivity != null:
		road_connectivity.refresh_around(grid_pos)
	return placed_type


func _forfeit_lot(grid_pos: Vector2i) -> int:
	var restored_type: int = GridCellData.TileType.GRASS
	if placement_controller != null and placement_controller._is_water_cell(grid_pos):
		restored_type = GridCellData.TileType.WATER
	grid.set_tile(grid_pos, GridCellData.new(restored_type))
	if placement_controller != null:
		placement_controller.place_tile(grid_pos, restored_type)
	if building_placement != null:
		building_placement.remove_building(grid_pos)
	return restored_type


func _prune_invalid_lots() -> void:
	if grid == null:
		return
	for key: Variant in _speculator_lots.keys():
		var pos: Vector2i = key as Vector2i
		if not _is_unbuilt_ground(pos):
			_speculator_lots.erase(pos)


func _score_cell(grid_pos: Vector2i) -> int:
	var lv: int = economy.get_land_value(grid_pos) if economy != null else 0
	var bonus: int = 8 if _has_adjacent_park_or_water(grid_pos) else 0
	var road_bonus: int = 5 if (road_connectivity != null and road_connectivity.is_road_adjacent(grid_pos)) else 0
	return lv + bonus + road_bonus


func _has_adjacent_park_or_water(grid_pos: Vector2i) -> bool:
	for off: Vector2i in CARDINAL_OFFSETS:
		var neighbor: Vector2i = grid_pos + off
		if not _is_in_bounds(neighbor):
			continue
		var t: int = grid.get_tile_type(neighbor)
		if t == GridCellData.TileType.PARK or t == GridCellData.TileType.WATER:
			return true
	return false


func _is_unbuilt_ground(grid_pos: Vector2i) -> bool:
	var t: int = grid.get_tile_type(grid_pos)
	return t == GridCellData.TileType.EMPTY or t == GridCellData.TileType.GRASS


func _is_edge_highway(grid_pos: Vector2i) -> bool:
	var mid_y: int = int(grid_size * 0.5)
	return grid_pos == Vector2i(0, mid_y) or grid_pos == Vector2i(grid_size - 1, mid_y)


func _is_in_bounds(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < grid_size \
			and grid_pos.y >= 0 and grid_pos.y < grid_size


