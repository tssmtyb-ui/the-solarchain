class_name ResidentialEvolutionManager
extends Node
## Evaluates the 2-Step Residential Evolution Model (Step 1: LVT threshold,
## Step 2: Anno logistics checklist) with 2-cycle upgrade streaks and 2-cycle
## grace degradation.

const CYCLES_REQUIRED: int = 2
const UPGRADE_LVT: int = EconomyManager.UPGRADE_LVT
const DOWNGRADE_LVT: int = EconomyManager.DOWNGRADE_LVT

var grid: GridManager
var economy: EconomyManager
var road_connectivity: RoadConnectivityManager
var supply_chain: SupplyChainSimulator

## Consecutive assessment cycles where all upgrade requirements were met (Vector2i -> int).
var _upgrade_streaks: Dictionary = {}

## Consecutive assessment cycles where stay/livability requirements failed (Vector2i -> int).
var _grace_counters: Dictionary = {}


func configure(
		world_grid: GridManager,
		economy_manager: EconomyManager,
		connectivity: RoadConnectivityManager,
		supply_simulator: SupplyChainSimulator) -> void:
	grid = world_grid
	economy = economy_manager
	road_connectivity = connectivity
	supply_chain = supply_simulator


func clear_state() -> void:
	_upgrade_streaks.clear()
	_grace_counters.clear()


func get_upgrade_streak(grid_pos: Vector2i) -> int:
	return int(_upgrade_streaks.get(grid_pos, 0))


func get_grace_cycles(grid_pos: Vector2i) -> int:
	return int(_grace_counters.get(grid_pos, 0))


## Pure read-only evaluation of a cell's Step 1 (LVT) and Step 2 (Anno checklist) state.
func get_requirements_report(grid_pos: Vector2i) -> Dictionary:
	var tile_type: int = grid.get_tile_type(grid_pos) if grid != null else GridCellData.TileType.EMPTY
	var lv: int = economy.get_land_value(grid_pos) if economy != null else 0
	var road_ok: bool = road_connectivity != null and road_connectivity.is_road_connected(grid_pos)
	var water_ok: bool = supply_chain != null and supply_chain.is_water_supplied(grid_pos)
	var goods_ok: bool = supply_chain != null and supply_chain.is_home_supplied(grid_pos)
	var park_ok: bool = economy != null and economy.is_within_park_range(grid_pos)
	var clean_air_ok: bool = economy == null or not economy.is_within_pollution_risk(grid_pos)

	var step1_upgrade_ok: bool = lv >= UPGRADE_LVT
	var step1_stay_high_ok: bool = lv > DOWNGRADE_LVT
	var step2_checklist_ok: bool = road_ok and water_ok and goods_ok and park_ok and clean_air_ok
	var villa_livability_ok: bool = road_ok and clean_air_ok

	return {
		"tile_type": tile_type,
		"land_value": lv,
		"upgrade_lv_target": UPGRADE_LVT,
		"stay_lv_floor": DOWNGRADE_LVT,
		"road_ok": road_ok,
		"water_ok": water_ok,
		"goods_ok": goods_ok,
		"park_ok": park_ok,
		"clean_air_ok": clean_air_ok,
		"step1_upgrade_ok": step1_upgrade_ok,
		"step1_stay_high_ok": step1_stay_high_ok,
		"step2_checklist_ok": step2_checklist_ok,
		"villa_livability_ok": villa_livability_ok,
		"upgrade_ready": step1_upgrade_ok and step2_checklist_ok,
		"apartment_satisfied": step1_stay_high_ok and step2_checklist_ok,
		"upgrade_streak": get_upgrade_streak(grid_pos),
		"grace_cycles": get_grace_cycles(grid_pos),
	}


## Processes one economy assessment cycle across all residential tiles and returns
## an ordered array of evolution decisions: [{"pos": Vector2i, "new_type": int}].
func evaluate_assessment_cycle(current_time: int = -1) -> Array[Dictionary]:
	var decisions: Array[Dictionary] = []
	if grid == null or economy == null:
		return decisions

	var check_time: int = (
		economy.get_simulation_time_msec()
		if current_time < 0 and economy != null
		else (Time.get_ticks_msec() if current_time < 0 else current_time)
	)
	_prune_stale_entries()

	for pos: Vector2i in grid.get_all_occupied_positions():
		var tile_type: int = grid.get_tile_type(pos)
		if tile_type != GridCellData.TileType.RESIDENTIAL_LOW \
				and tile_type != GridCellData.TileType.RESIDENTIAL_HIGH:
			continue

		var report: Dictionary = get_requirements_report(pos)
		var cooldown_ok: bool = economy.is_evolution_cooldown_elapsed(pos, check_time)

		if tile_type == GridCellData.TileType.RESIDENTIAL_LOW:
			if bool(report["upgrade_ready"]):
				_grace_counters.erase(pos)
				var streak: int = get_upgrade_streak(pos) + 1
				_upgrade_streaks[pos] = streak
				if streak >= CYCLES_REQUIRED and cooldown_ok:
					_upgrade_streaks.erase(pos)
					decisions.append({
						"pos": pos,
						"new_type": GridCellData.TileType.RESIDENTIAL_HIGH,
					})
			elif not bool(report["villa_livability_ok"]):
				_upgrade_streaks.erase(pos)
				var grace: int = get_grace_cycles(pos) + 1
				_grace_counters[pos] = grace
				if grace >= CYCLES_REQUIRED and cooldown_ok:
					_grace_counters.erase(pos)
					decisions.append({
						"pos": pos,
						"new_type": GridCellData.TileType.ABANDONED,
					})
			else:
				# Stable villa: basic livability is met, but Tier-2 upgrade needs are not.
				_upgrade_streaks.erase(pos)
				_grace_counters.erase(pos)

		elif tile_type == GridCellData.TileType.RESIDENTIAL_HIGH:
			_upgrade_streaks.erase(pos)
			if bool(report["apartment_satisfied"]):
				_grace_counters.erase(pos)
			else:
				var grace_high: int = get_grace_cycles(pos) + 1
				_grace_counters[pos] = grace_high
				if grace_high >= CYCLES_REQUIRED and cooldown_ok:
					_grace_counters.erase(pos)
					decisions.append({
						"pos": pos,
						"new_type": GridCellData.TileType.RESIDENTIAL_LOW,
					})

	return decisions


## Formats a concise requirement checklist for the hovered residential building.
func get_inspection_text(grid_pos: Vector2i) -> String:
	var report: Dictionary = get_requirements_report(grid_pos)
	var tile_type: int = int(report["tile_type"])
	if tile_type == GridCellData.TileType.ABANDONED:
		return "HOUSING: Abandoned Residence\nSTATUS: Abandoned — bulldoze to rebuild"

	var lv: int = int(report["land_value"])
	var road_word: String = "OK" if bool(report["road_ok"]) else "Missing"
	var water_word: String = "OK" if bool(report["water_ok"]) else "Missing"
	var goods_word: String = "OK" if bool(report["goods_ok"]) else "Missing"
	var park_word: String = "OK" if bool(report["park_ok"]) else "Missing"
	var air_word: String = "OK" if bool(report["clean_air_ok"]) else "Polluted"

	if tile_type == GridCellData.TileType.RESIDENTIAL_LOW:
		var lv_word: String = "OK" if bool(report["step1_upgrade_ok"]) else "Missing"
		var status_line: String = "STATUS: Stable Villa"
		var grace_low: int = int(report["grace_cycles"])
		var streak_low: int = int(report["upgrade_streak"])
		if not bool(report["villa_livability_ok"]) or grace_low > 0:
			status_line = "STATUS: Unsatisfied Needs — Grace (%d/%d)" % [
				maxi(1, grace_low), CYCLES_REQUIRED
			]
		elif bool(report["upgrade_ready"]):
			status_line = "STATUS: Upgrading (%d/%d cycles)" % [
				streak_low, CYCLES_REQUIRED
			]
		return "\n".join([
			"HOUSING: Villa (Tier 1 -> Tier 2)",
			status_line,
			"Land Value: %d/%d (%s)" % [lv, UPGRADE_LVT, lv_word],
			"Road: %s · Goods: %s · Water: %s" % [road_word, goods_word, water_word],
			"Park: %s · Clean Air: %s" % [park_word, air_word],
		])

	if tile_type == GridCellData.TileType.RESIDENTIAL_HIGH:
		var stay_lv_word: String = "OK" if bool(report["step1_stay_high_ok"]) else "Low"
		var grace_high: int = int(report["grace_cycles"])
		var high_status: String = "STATUS: Thriving Apartment"
		if not bool(report["apartment_satisfied"]) or grace_high > 0:
			high_status = "STATUS: Unsatisfied Needs — Grace (%d/%d)" % [
				maxi(1, grace_high), CYCLES_REQUIRED
			]
		return "\n".join([
			"HOUSING: Apartment (Tier 2)",
			high_status,
			"Land Value: %d (>%d %s)" % [lv, DOWNGRADE_LVT, stay_lv_word],
			"Road: %s · Goods: %s · Water: %s" % [road_word, goods_word, water_word],
			"Park: %s · Clean Air: %s" % [park_word, air_word],
		])

	return ""


func _prune_stale_entries() -> void:
	for key: Variant in _upgrade_streaks.keys():
		var pos: Vector2i = key as Vector2i
		var t: int = grid.get_tile_type(pos)
		if t != GridCellData.TileType.RESIDENTIAL_LOW \
				and t != GridCellData.TileType.RESIDENTIAL_HIGH:
			_upgrade_streaks.erase(pos)
	for key: Variant in _grace_counters.keys():
		var pos: Vector2i = key as Vector2i
		var t: int = grid.get_tile_type(pos)
		if t != GridCellData.TileType.RESIDENTIAL_LOW \
				and t != GridCellData.TileType.RESIDENTIAL_HIGH:
			_grace_counters.erase(pos)
