class_name TownProgressionManager
extends Node
## Owns the 3-tier municipal progression system (Hamlet -> Town -> Metropolis),
## milestone evaluation, build-tool unlock rules, and Metropolis LVT bonus.

enum TownLevel {
	HAMLET = 1,
	TOWN = 2,
	METROPOLIS = 3,
}

const TOWN_POPULATION_TARGET: int = 15
const TOWN_GROSS_LVT_TARGET: int = 1000
const METROPOLIS_POPULATION_TARGET: int = 50
const METROPOLIS_APARTMENTS_TARGET: int = 5
const METROPOLIS_LVT_MULTIPLIER: float = 1.15

signal town_level_changed(new_level: int, level_name: String)

var current_level: int = TownLevel.HAMLET


func reset() -> void:
	current_level = TownLevel.HAMLET


func get_town_level() -> int:
	return current_level


func set_town_level(level: int, emit_on_change: bool = false) -> void:
	var clamped: int = clampi(level, TownLevel.HAMLET, TownLevel.METROPOLIS)
	var changed: bool = clamped != current_level
	current_level = clamped
	if changed and emit_on_change:
		town_level_changed.emit(current_level, get_level_name(current_level))


func get_level_name(level: int = -1) -> String:
	var target_level: int = current_level if level < 0 else level
	match target_level:
		TownLevel.HAMLET:
			return "Hamlet"
		TownLevel.TOWN:
			return "Town"
		TownLevel.METROPOLIS:
			return "Metropolis"
	return "Hamlet"


func get_lvt_efficiency_multiplier() -> float:
	if current_level >= TownLevel.METROPOLIS:
		return METROPOLIS_LVT_MULTIPLIER
	return 1.0


func get_required_level_for_tile_type(tile_type: int) -> int:
	match tile_type:
		GridCellData.TileType.RESIDENTIAL_HIGH, \
		GridCellData.TileType.WATER_TOWER_LARGE, \
		GridCellData.TileType.INDUSTRIAL, \
		GridCellData.TileType.WAREHOUSE, \
		GridCellData.TileType.SLUDGE:
			return TownLevel.TOWN
		_:
			return TownLevel.HAMLET


func is_tile_type_unlocked(tile_type: int) -> bool:
	return current_level >= get_required_level_for_tile_type(tile_type)


func is_ubi_unlocked() -> bool:
	return current_level >= TownLevel.TOWN


func get_lock_requirement_text(tile_type: int) -> String:
	var req_level: int = get_required_level_for_tile_type(tile_type)
	if req_level == TownLevel.TOWN:
		return "Requires Town Level (%d Population & $%d Gross LVT)" % [
			TOWN_POPULATION_TARGET, TOWN_GROSS_LVT_TARGET
		]
	if req_level == TownLevel.METROPOLIS:
		return "Requires Metropolis Level (%d Population & %d Apartments)" % [
			METROPOLIS_POPULATION_TARGET, METROPOLIS_APARTMENTS_TARGET
		]
	return ""


## Evaluates whether the city meets the criteria for a higher Town Level.
## Returns true if `current_level` advanced.
func evaluate_progression(
		population: int,
		gross_lvt_revenue: int,
		apartment_count: int) -> bool:
	var previous_level: int = current_level
	if current_level < TownLevel.TOWN:
		if population >= TOWN_POPULATION_TARGET and gross_lvt_revenue >= TOWN_GROSS_LVT_TARGET:
			current_level = TownLevel.TOWN
	if current_level < TownLevel.METROPOLIS:
		if population >= METROPOLIS_POPULATION_TARGET and apartment_count >= METROPOLIS_APARTMENTS_TARGET:
			current_level = TownLevel.METROPOLIS
	if current_level != previous_level:
		town_level_changed.emit(current_level, get_level_name(current_level))
		return true
	return false


func get_progress_report(
		population: int,
		gross_lvt_revenue: int,
		apartment_count: int) -> Dictionary:
	var level_name: String = get_level_name(current_level)
	var next_name: String = "Max Rank"
	var progress_pct: float = 100.0
	var summary_text: String = ""
	var tooltip_text: String = ""

	if current_level == TownLevel.HAMLET:
		next_name = "Town"
		var pop_ratio: float = clampf(float(population) / float(TOWN_POPULATION_TARGET), 0.0, 1.0)
		var lvt_ratio: float = clampf(float(gross_lvt_revenue) / float(TOWN_GROSS_LVT_TARGET), 0.0, 1.0)
		progress_pct = ((pop_ratio + lvt_ratio) * 0.5) * 100.0
		summary_text = "Tier 1: Hamlet · Pop %d/%d · LVT $%d/$%d" % [
			population, TOWN_POPULATION_TARGET, gross_lvt_revenue, TOWN_GROSS_LVT_TARGET
		]
		tooltip_text = (
			"Town Level 1: Hamlet\n"
			+ "Unlocked: Roads, Villas, Modular Farms, Small Water Tower, Parks.\n"
			+ "Next Milestone — Town: %d/%d Population and $%d/$%d Gross LVT Revenue.\n"
			+ "Unlocks: Apartments, Large Water Tower, Factories, and UBI Dividend Slider."
		) % [population, TOWN_POPULATION_TARGET, gross_lvt_revenue, TOWN_GROSS_LVT_TARGET]
	elif current_level == TownLevel.TOWN:
		next_name = "Metropolis"
		var pop_ratio: float = clampf(float(population) / float(METROPOLIS_POPULATION_TARGET), 0.0, 1.0)
		var apt_ratio: float = clampf(float(apartment_count) / float(METROPOLIS_APARTMENTS_TARGET), 0.0, 1.0)
		progress_pct = ((pop_ratio + apt_ratio) * 0.5) * 100.0
		summary_text = "Tier 2: Town · Pop %d/%d · Apts %d/%d" % [
			population, METROPOLIS_POPULATION_TARGET, apartment_count, METROPOLIS_APARTMENTS_TARGET
		]
		tooltip_text = (
			"Town Level 2: Town\n"
			+ "Unlocked: Apartments, Large Water Tower, Factories, Warehouses, Sludge, UBI Policy.\n"
			+ "Next Milestone — Metropolis: %d/%d Population and %d/%d Apartments.\n"
			+ "Unlocks: Metropolis rank and +15%% Gross LVT Efficiency Bonus."
		) % [population, METROPOLIS_POPULATION_TARGET, apartment_count, METROPOLIS_APARTMENTS_TARGET]
	else:
		progress_pct = 100.0
		summary_text = "Tier 3: Metropolis · +15% LVT Bonus"
		tooltip_text = (
			"Town Level 3: Metropolis (Max Rank)\n"
			+ "All municipal infrastructure unlocked.\n"
			+ "Active Bonus: +15% Gross Land Value Tax Efficiency."
		)

	return {
		"level": current_level,
		"level_name": level_name,
		"next_level_name": next_name,
		"progress_percent": progress_pct,
		"population": population,
		"gross_lvt_revenue": gross_lvt_revenue,
		"apartment_count": apartment_count,
		"summary_text": summary_text,
		"tooltip_text": tooltip_text,
	}
