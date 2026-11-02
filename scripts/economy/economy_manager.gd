class_name EconomyManager
extends Node
## Core economic loop for the LVT system.
## Single source of truth for all income, upkeep, land-value, and worker
## calculations.  Emits `assessment_completed(net_income: int)` every interval.

# ---------------------------------------------------------------------------
#   Economy constants (moved from node_2d.gd)
# ---------------------------------------------------------------------------

## Per-cycle upkeep cost for each road tile.
const ROAD_UPKEEP: int = 1

## Land Value Tax constants — a tile's base economic value is determined by
## Manhattan distance to the nearest edge highway (outside-world connection).
## Values drop by LVT_DROP_OFF per tile of distance away from the highway.
const MAX_LAND_VALUE: int = 50
const LVT_DROP_OFF: int = 3

## Environmental magnets — placed tiles that alter the land-value field around
## them. Effects stack, so clustered parks (or sludge lines) compound.
const PARK_RADIUS: int = 3
## Diminishing park bonus tiers: the 1st park gives +15, 2nd +10, 3rd +6,
## 4th +3, 5th +1, and any beyond the array length add 0 (hard cap).
const PARK_BONUS_TIERS: Array[int] = [15, 10, 6, 3, 1]
const SLUDGE_RADIUS: int = 2
const SLUDGE_PENALTY: int = -25

## Absolute bounds for land value after all modifiers.
const LAND_VALUE_FLOOR: int = 0
const LAND_VALUE_CEIL: int = 100

## Maximum land value a low-density villa can afford before being priced out.
## Villas on land worth more than this provide 0 workers and 0 tax income.
const MAX_VILLA_LAND_VALUE: int = 30

## Auto-evolution thresholds — when land value crosses these, the simulation
## triggers a density change (villa <-> apartment) on the next assessment.
## Upgrade: land value at or above this turns a villa into an apartment.
const UPGRADE_LVT: int = 30
## Downgrade: land value at or below this turns an apartment back into a villa.
const DOWNGRADE_LVT: int = 18
## Buffer period (msec) protecting a tile from a second automatic density
## change (villa <-> apartment) — prevents flicker when land value oscillates
## near a threshold. Also stamped on manual upgrades so they can't downgrade
## prematurely. 20000 ms = 4 assessment cycles at the default 5 s interval.
const EVOLUTION_COOLDOWN_MSEC: int = 20000

# ---------------------------------------------------------------------------
#   If/Then event rules (GDD Priority 2)
# ---------------------------------------------------------------------------

## Pollution crash — residential tiles within this Manhattan radius of a
## factory suffer a catastrophic Land Value crash (see POLLUTION_LV_MULTIPLIER).
const POLLUTION_RADIUS: int = 5
## Catastrophic crash multiplier: residential land value × this (0.2 = −80%)
## when within POLLUTION_RADIUS of any factory. Purely Land Value-based.
const POLLUTION_LV_MULTIPLIER: float = 0.2

## Land-hoarding tax (Spekulationsspärren) — claimed land left unbuilt longer
## than this pays 2x LVT per tick (5 minutes).
const HOARDING_TIME_LIMIT_MSEC: int = 300000

## Universal Basic Income (Variable Surplus Dividend Policy) constants.
const UBI_LAND_VALUE_DIVISOR: int = 10
const MAX_UBI_LAND_VALUE_BONUS: int = 10
const UBI_HIGH_RATE_THRESHOLD: float = 0.5
const UBI_MIN_LABOR_PENALTY: float = 0.05
const UBI_MAX_LABOR_PENALTY: float = 0.15
const UBI_BASE_GOODS_DEMAND: int = 1
const UBI_HIGH_GOODS_DEMAND: int = 2

## Duration of a local factory strike (3 minutes) triggered by demolishing a park.
const STRIKE_DURATION_MSEC: int = 180000

## Logistics bonuses — factories hooked into a live pipe network (SLUDGE line
## reaching the map edge) run at a production bonus; unhooked ones at a penalty.
const HOOKED_FACTORY_MULTIPLIER: float = 1.3
const UNHOOKED_FACTORY_MULTIPLIER: float = 0.5

# ---------------------------------------------------------------------------
#   Configuration (set by root scene before use)
# ---------------------------------------------------------------------------

## Seconds between automatic assessment cycles.
var assessment_interval: float = 5.0

## Reference to the GridManager — injected by the root scene.
var grid: GridManager

## Pipe/logistics connectivity graph — injected by the root scene. May be null
## (no network), in which case factories run at base production.
var pipe_network: PipeNetworkManager

## Grid dimensions — injected by the root scene.
var grid_size: int = 10

# ---------------------------------------------------------------------------
#   State
# ---------------------------------------------------------------------------

## Tracks when each tile was last auto-evolved (msec ticks from
## Time.get_ticks_msec()) so the cooldown prevents density flickering.
var tile_build_times: Dictionary = {}

## Tracks when the player first claimed each tile (Time.get_ticks_msec()).
## Ownership persists after bulldozing — idle claimed land is exactly what the
## land-hoarding tax targets. Built tiles are naturally excluded from the check.
var tile_claimed_times: Dictionary = {}

## Factory grid positions mapped to their strike expiry (Time.get_ticks_msec()).
var factory_strike_until_msec: Dictionary = {}

## Citizen's Dividend Policy (0–100 %). Synchronized with normalized `ubi_rate`.
var dividend_percent: float = 0.0

## Normalized Universal Basic Income / Surplus Dividend rate (0.0–1.0).
var ubi_rate: float = 0.0

## Municipal Land Value Tax rate multiplier (default 1.0 = 100% baseline LVT).
const MIN_LVT_RATE: float = 0.5
const MAX_LVT_RATE: float = 2.5
var lvt_rate: float = 1.0

## Total gross LVT revenue from the most recent assessment cycle.
var last_lvt_revenue: int = 0

## Total LVT revenue paid by AI Speculator Syndicates in the most recent cycle.
var last_speculator_lvt_revenue: int = 0

## Total infrastructure maintenance + hoarding tax from the most recent assessment cycle.
var last_maintenance_cost: int = 0

## Non-negative net surplus (maxi(0, last_lvt_revenue - last_maintenance_cost)) from the latest cycle.
var last_net_surplus: int = 0

## UBI dividend payout distributed to citizens in the most recent assessment cycle.
var last_ubi_payout: int = 0

## Total factory income from the most recent assessment — retained for compatibility.
var last_factory_income: int = 0

## Cumulative gross LVT revenue collected across completed assessment cycles.
var cumulative_lvt_revenue: int = 0

## Town-level LVT efficiency multiplier (1.0 at Hamlet/Town, 1.15 at Metropolis).
var town_level_lvt_multiplier: float = 1.0

## Rolling history of the last 10 completed assessment cycles for the Budget Ledger.
const MAX_BUDGET_HISTORY: int = 10
var budget_history: Array[Dictionary] = []
var _assessment_cycle_count: int = 0

## Optional direct per-residence goods tax bonus from the root supply simulation.
## Callable(Vector2i) -> int; leave invalid to disable.
var residential_goods_tax_bonus_provider: Callable

## Optional per-factory water productivity multiplier from the supply simulation.
## Callable(Vector2i) -> float; leave invalid to default to 1.0.
var factory_water_multiplier_provider: Callable

## Optional per-factory water status description from the supply simulation.
## Callable(Vector2i) -> String; leave invalid to omit.
var factory_water_status_provider: Callable

## Optional residential evolution evaluator invoked once per assessment cycle.
## Callable(int) -> Array[Dictionary]; returns {"pos": Vector2i, "new_type": int} entries.
var residential_evolution_evaluator: Callable

## Optional speculator LVT provider returning total LVT paid by speculator lots.
## Callable() -> int
var speculator_lvt_provider: Callable

## Factory positions staffed by the latest supply-chain tick. Shared with the
## income assessment so production and factory income use identical staffing.
var staffed_factories: Dictionary = {}

## True when simulation time and assessment ticks are paused for active building.
var _is_paused: bool = false
var _pause_started_msec: int = 0
var _paused_accumulated_msec: int = 0

# ---------------------------------------------------------------------------
#   Signals
# ---------------------------------------------------------------------------

## Emitted after each full assessment cycle with the final net income.
signal assessment_completed(net_income: int)

## Emitted when a residential tile crosses a land-value threshold and should
## change density (villa <-> apartment). The root scene performs the swap.
signal residential_evolution_triggered(grid_pos: Vector2i, new_tile_type: int)

# ---------------------------------------------------------------------------
#   Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Start the periodic timer.
	var timer := Timer.new()
	timer.name = "AssessmentTimer"
	timer.wait_time = assessment_interval
	timer.autostart = true
	timer.one_shot = false
	timer.paused = _is_paused
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)


func _on_timer_timeout() -> void:
	if _is_paused:
		return
	calculate_net_income()


## Pauses or resumes the periodic assessment timer and freezes the simulation clock.
func set_paused(paused: bool) -> void:
	if _is_paused == paused:
		return
	var now: int = Time.get_ticks_msec()
	if paused:
		_is_paused = true
		_pause_started_msec = now
	else:
		_paused_accumulated_msec += maxi(0, now - _pause_started_msec)
		_is_paused = false
	var timer: Timer = get_node_or_null("AssessmentTimer") as Timer
	if timer != null:
		timer.paused = _is_paused


func is_paused() -> bool:
	return _is_paused


## Returns the simulation clock in msec, frozen while the simulation is paused.
func get_simulation_time_msec() -> int:
	if _is_paused:
		return _pause_started_msec - _paused_accumulated_msec
	return Time.get_ticks_msec() - _paused_accumulated_msec


# ---------------------------------------------------------------------------
#   Public API
# ---------------------------------------------------------------------------

## Starts a STRIKE_DURATION_MSEC strike at the factory nearest to `park_pos`.
## The root scene checks this state when simulating factory goods production.
## If no factory exists, the demolished park causes no strike.
## Removes expired strike entries and any strike references to nonexistent factories.
func prune_factory_strikes() -> void:
	var current_time: int = get_simulation_time_msec()
	for key: Variant in factory_strike_until_msec.keys():
		if not key is Vector2i:
			factory_strike_until_msec.erase(key)
			continue
		var factory_pos: Vector2i = key as Vector2i
		if grid.get_tile_type(factory_pos) != GridCellData.TileType.INDUSTRIAL \
				or current_time >= int(factory_strike_until_msec[factory_pos]):
			factory_strike_until_msec.erase(factory_pos)


func trigger_industrial_strike(park_pos: Vector2i) -> void:
	var nearest_factory: Vector2i = Vector2i(-1, -1)
	var nearest_distance: int = 2147483647
	for pos in grid.get_all_occupied_positions():
		if grid.get_tile_type(pos) != GridCellData.TileType.INDUSTRIAL:
			continue
		var distance: int = absi(pos.x - park_pos.x) + absi(pos.y - park_pos.y)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_factory = pos
	if nearest_factory == Vector2i(-1, -1):
		prints("Park demolished at", park_pos, "but no factory was available to strike.")
		return
	factory_strike_until_msec[nearest_factory] = get_simulation_time_msec() + STRIKE_DURATION_MSEC
	prints("Factory at", nearest_factory, "struck for %d ms." % STRIKE_DURATION_MSEC)


## True while the factory at `factory_pos` is serving its strike duration.
func is_factory_on_strike(factory_pos: Vector2i) -> bool:
	if not factory_strike_until_msec.has(factory_pos):
		return false
	if get_simulation_time_msec() >= int(factory_strike_until_msec[factory_pos]):
		factory_strike_until_msec.erase(factory_pos)
		return false
	return true


## Returns the active normalized UBI rate (0.0–1.0).
func get_ubi_rate() -> float:
	return ubi_rate


func set_lvt_rate(rate: float) -> void:
	lvt_rate = clampf(rate, MIN_LVT_RATE, MAX_LVT_RATE)


func get_lvt_rate() -> float:
	return lvt_rate


## Sets the normalized UBI rate (0.0–1.0) and synchronizes `dividend_percent` (0.0–100.0).
func set_ubi_rate(rate: float) -> void:
	ubi_rate = clampf(rate, 0.0, 1.0)
	dividend_percent = ubi_rate * 100.0
	last_ubi_payout = get_ubi_payout(ubi_rate)


## Sets the Citizen's Dividend payout percentage (0–100). Driven live by the UI
## HSlider's value_changed signal. Synchronizes normalized `ubi_rate`.
func set_dividend_percent(val: float) -> void:
	dividend_percent = clampf(val, 0.0, 100.0)
	ubi_rate = clampf(val / 100.0, 0.0, 1.0)
	last_ubi_payout = get_ubi_payout(ubi_rate)


## Arms the density-change buffer for a tile, recording its last change time.
## Call after ANY state change on a residential tile (e.g. a manual villa→
## apartment upgrade) so auto-evolution can't immediately undo it the next
## assessment while land value is still fluctuating.
func stamp_evolution_cooldown(grid_pos: Vector2i) -> void:
	tile_build_times[grid_pos] = get_simulation_time_msec()


## Returns the factory production multiplier for a given dividend %. Scaled so
## the boost is half the payout: 0 % → ×1.0 (no boost), 50 % → ×1.25, 100 % → ×1.5
## (+50 %). Preserved for HUD presentation backward compatibility.
func get_factory_boost_multiplier(percent: float) -> float:
	return 1.0 + percent / 200.0


## Returns the dividend payout cost per assessment tick for a given dividend %,
## based on the latest net surplus. Used for the live UI trade-off label.
func get_dividend_cost(percent: float) -> int:
	return get_ubi_payout(clampf(percent / 100.0, 0.0, 1.0))


## Returns the dynamic residential Land Value bonus from active UBI payout
## (+1 LV per $10 of UBI payout, up to +10 LV).
func get_ubi_land_value_bonus() -> int:
	if last_ubi_payout <= 0:
		return 0
	return clampi(int(float(last_ubi_payout) / float(UBI_LAND_VALUE_DIVISOR)), 0, MAX_UBI_LAND_VALUE_BONUS)


## Returns the labor efficiency multiplier for a given UBI rate.
## For rate <= 0.5 returns 1.0; for rate > 0.5 scales from 0.95 down to 0.85.
func get_labor_efficiency_multiplier(rate: float = ubi_rate) -> float:
	var clamped_rate: float = clampf(rate, 0.0, 1.0)
	if clamped_rate <= UBI_HIGH_RATE_THRESHOLD:
		return 1.0
	var high_ratio: float = clampf(
			(clamped_rate - UBI_HIGH_RATE_THRESHOLD) / (1.0 - UBI_HIGH_RATE_THRESHOLD),
			0.0,
			1.0)
	return 1.0 - lerpf(UBI_MIN_LABOR_PENALTY, UBI_MAX_LABOR_PENALTY, high_ratio)


## Returns residential goods demand per house per supply tick for a given UBI rate.
## Returns 1 good/tick when rate <= 0.5, and 2 goods/tick when rate > 0.5.
func get_ubi_goods_demand_per_house(rate: float = ubi_rate) -> int:
	return UBI_HIGH_GOODS_DEMAND if clampf(rate, 0.0, 1.0) > UBI_HIGH_RATE_THRESHOLD else UBI_BASE_GOODS_DEMAND


## Returns the non-negative net surplus from the most recent assessment cycle.
func get_net_surplus() -> int:
	return last_net_surplus


## Returns the UBI dividend payout for the given rate based on `last_net_surplus`.
## Safely drops to $0 when `last_net_surplus <= 0`.
func get_ubi_payout(rate: float = ubi_rate) -> int:
	if last_net_surplus <= 0:
		return 0
	var clamped_rate: float = clampf(rate, 0.0, 1.0)
	return roundi(last_net_surplus * clamped_rate)


## Returns the treasury revenue retained after maintenance costs and UBI payout.
func get_retained_treasury_revenue(rate: float = ubi_rate) -> int:
	var payout: int = get_ubi_payout(rate)
	return (last_lvt_revenue - last_maintenance_cost) - payout


## Returns a complete snapshot of the active or queried UBI policy metrics.
func get_policy_summary(rate: float = ubi_rate) -> Dictionary:
	var clamped_rate: float = clampf(rate, 0.0, 1.0)
	var payout: int = get_ubi_payout(clamped_rate)
	var retained: int = get_retained_treasury_revenue(clamped_rate)
	var lv_bonus: int = 0
	if payout > 0:
		lv_bonus = clampi(int(float(payout) / float(UBI_LAND_VALUE_DIVISOR)), 0, MAX_UBI_LAND_VALUE_BONUS)
	return {
		"ubi_rate": clamped_rate,
		"dividend_percent": clamped_rate * 100.0,
		"lvt_revenue": last_lvt_revenue,
		"maintenance_cost": last_maintenance_cost,
		"net_surplus": last_net_surplus,
		"ubi_payout": payout,
		"retained_treasury_revenue": retained,
		"land_value_bonus": lv_bonus,
		"labor_efficiency_multiplier": get_labor_efficiency_multiplier(clamped_rate),
		"goods_demand_per_house": get_ubi_goods_demand_per_house(clamped_rate),
	}


## Calculates an assessment NOW. When apply_changes is false, refreshes derived
## income values without stamping timestamps, evolving homes, or emitting income.
func calculate_net_income(apply_changes: bool = true) -> int:
	var road_count: int = 0
	var total_lvt_revenue: int = 0
	var factory_income: int = 0
	var current_time: int = get_simulation_time_msec()

	# Reset UBI payout during gross revenue assessment so residential base LVT
	# does not compound prior-cycle UBI bonuses into the new surplus calculation.
	last_ubi_payout = 0

	for pos in grid.get_all_occupied_positions():
		var t: int = grid.get_tile_type(pos)
		# Stamp the first time the player claims a tile (any non-canvas type).
		# Pre-filled GRASS canvas tiles are never stamped — only real claims
		# qualify for the hoarding check later.
		if apply_changes and t != GridCellData.TileType.GRASS \
				and not tile_claimed_times.has(pos):
			tile_claimed_times[pos] = current_time
		match t:
			GridCellData.TileType.ROAD, GridCellData.TileType.ROAD_CROSS:
				road_count += 1
			GridCellData.TileType.INDUSTRIAL:
				# Both goods production and factory income use the latest shared
				# staffing decision from the supply-chain simulation.
				if staffed_factories.has(pos) and not is_factory_on_strike(pos):
					var base_factory: int = get_land_value(pos)
					factory_income += base_factory
					# Logistics (pipe hookup) and water supply production modifiers.
					total_lvt_revenue += int(
						base_factory * _factory_pipe_multiplier(pos) * _factory_water_multiplier(pos))
			GridCellData.TileType.WAREHOUSE:
				total_lvt_revenue += get_land_value(pos)
			GridCellData.TileType.RESIDENTIAL_LOW:
				var lv: int = get_land_value(pos)
				if lv <= MAX_VILLA_LAND_VALUE:
					total_lvt_revenue += lv
				else:
					prints("RESIDENTIAL_LOW at", pos, "pays $0 — land value too high.")
			GridCellData.TileType.RESIDENTIAL_HIGH:
				var lv_high: int = get_land_value(pos)
				var goods_bonus: int = _goods_tax_bonus_for_residence(pos)
				total_lvt_revenue += (lv_high - goods_bonus) * 2 + goods_bonus

	if not is_equal_approx(lvt_rate, 1.0):
		total_lvt_revenue = roundi(float(total_lvt_revenue) * lvt_rate)

	if speculator_lvt_provider.is_valid():
		last_speculator_lvt_revenue = maxi(0, int(speculator_lvt_provider.call()))
		total_lvt_revenue += last_speculator_lvt_revenue
	else:
		last_speculator_lvt_revenue = 0

	if not is_equal_approx(town_level_lvt_multiplier, 1.0):
		total_lvt_revenue = roundi(float(total_lvt_revenue) * town_level_lvt_multiplier)

	last_factory_income = factory_income
	var road_upkeep: int = road_count * ROAD_UPKEEP
	var hoarding_tax: int = _hoarding_tax(current_time)
	var total_maintenance_costs: int = road_upkeep + hoarding_tax

	last_lvt_revenue = total_lvt_revenue
	last_maintenance_cost = total_maintenance_costs
	last_net_surplus = maxi(0, total_lvt_revenue - total_maintenance_costs)
	last_ubi_payout = roundi(last_net_surplus * ubi_rate) if last_net_surplus > 0 else 0
	var retained_treasury_revenue: int = (total_lvt_revenue - total_maintenance_costs) - last_ubi_payout

	if apply_changes:
		cumulative_lvt_revenue += maxi(0, total_lvt_revenue)
		_record_budget_entry(
				total_lvt_revenue,
				total_maintenance_costs,
				last_ubi_payout,
				retained_treasury_revenue)

	if apply_changes and residential_evolution_evaluator.is_valid():
		var decisions: Variant = residential_evolution_evaluator.call(current_time)
		if decisions is Array:
			for entry_value: Variant in decisions as Array:
				if not entry_value is Dictionary:
					continue
				var entry: Dictionary = entry_value as Dictionary
				var pos: Vector2i = entry.get("pos", Vector2i(-1, -1)) as Vector2i
				var new_type: int = int(entry.get("new_type", GridCellData.TileType.EMPTY))
				if pos.x >= 0 and new_type != GridCellData.TileType.EMPTY:
					tile_build_times[pos] = current_time
					residential_evolution_triggered.emit(pos, new_type)

	if apply_changes:
		assessment_completed.emit(retained_treasury_revenue)
	return retained_treasury_revenue


func get_budget_history() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for entry: Dictionary in budget_history:
		copy.append(entry.duplicate(true))
	return copy


func clear_budget_history() -> void:
	budget_history.clear()
	_assessment_cycle_count = 0


func _record_budget_entry(
		gross_lvt: int,
		maintenance: int,
		ubi_payout: int,
		net_income: int) -> Dictionary:
	_assessment_cycle_count += 1
	var entry: Dictionary = {
		"cycle": _assessment_cycle_count,
		"gross_lvt": gross_lvt,
		"maintenance": maintenance,
		"ubi_payout": ubi_payout,
		"net_income": net_income,
	}
	budget_history.append(entry)
	while budget_history.size() > MAX_BUDGET_HISTORY:
		budget_history.pop_front()
	return entry


## Returns the Land Value of a grid position based on Manhattan distance to the
## nearest edge highway, modified by nearby environmental magnets.
## Base: MAX_LAND_VALUE - (shortest_distance * LVT_DROP_OFF). Parks within
## PARK_RADIUS add a diminishing bonus (see PARK_BONUS_TIERS); sludge lines
## within SLUDGE_RADIUS add
## SLUDGE_PENALTY each. The result is clamped to [LAND_VALUE_FLOOR, LAND_VALUE_CEIL].
func get_land_value(grid_pos: Vector2i) -> int:
	var mid_y: int = int(grid_size * 0.5)

	var west := Vector2i(0, mid_y)
	var east := Vector2i(grid_size - 1, mid_y)

	var dist_west: int = abs(grid_pos.x - west.x) + abs(grid_pos.y - west.y)
	var dist_east: int = abs(grid_pos.x - east.x) + abs(grid_pos.y - east.y)
	var shortest: int = mini(dist_west, dist_east)

	var value: int = MAX_LAND_VALUE - (shortest * LVT_DROP_OFF)

	var t: int = grid.get_tile_type(grid_pos)
	var is_residence: bool = (
		t == GridCellData.TileType.RESIDENTIAL_LOW
		or t == GridCellData.TileType.RESIDENTIAL_HIGH
	)

	# Environmental magnets: parks raise the value, sludge lines depress it.
	# Effects stack — clustered magnets compound (chosen over "strongest only"
	# for simplicity and emergent park districts / toxic zones).
	# For residences, active goods delivery boosts LV directly.
	value += _calculate_park_bonus(_count_magnets_in_radius(grid_pos, PARK_RADIUS, GridCellData.TileType.PARK))
	value += _count_magnets_in_radius(grid_pos, SLUDGE_RADIUS, GridCellData.TileType.SLUDGE) * SLUDGE_PENALTY
	if is_residence:
		value += _goods_tax_bonus_for_residence(grid_pos)
		value += get_ubi_land_value_bonus()

	# Pollution crash: residential land within a factory's pollution radius
	# collapses catastrophically (× POLLUTION_LV_MULTIPLIER, i.e. −80%).
	if is_residence and _count_industrial_in_radius(grid_pos, POLLUTION_RADIUS) > 0:
		value = int(value * POLLUTION_LV_MULTIPLIER)

	return clampi(value, LAND_VALUE_FLOOR, LAND_VALUE_CEIL)


## True when a cell lies within any factory's pollution-risk radius.
## This is a planning overlay query only; existing tax penalties remain limited
## to residences in get_land_value().
func is_within_pollution_risk(grid_pos: Vector2i) -> bool:
	return _count_industrial_in_radius(grid_pos, POLLUTION_RADIUS) > 0


## True when at least one Park tile is within PARK_RADIUS of `grid_pos`.
func is_within_park_range(grid_pos: Vector2i) -> bool:
	return _count_magnets_in_radius(grid_pos, PARK_RADIUS, GridCellData.TileType.PARK) > 0


## Public check for whether a residential tile's evolution cooldown has elapsed.
func is_evolution_cooldown_elapsed(grid_pos: Vector2i, current_time: int = -1) -> bool:
	var check_time: int = get_simulation_time_msec() if current_time < 0 else current_time
	return _evolution_cooldown_elapsed(grid_pos, check_time)


# ---------------------------------------------------------------------------
#   Internal helpers
# ---------------------------------------------------------------------------

## Returns the direct tax bonus for a residence supplied on the latest goods tick.
func _goods_tax_bonus_for_residence(grid_pos: Vector2i) -> int:
	if not residential_goods_tax_bonus_provider.is_valid():
		return 0
	return residential_goods_tax_bonus_provider.call(grid_pos)


## Returns true if the tile's evolution cooldown has elapsed (or the tile has
## never been auto-evolved), so density changes can't flicker on thresholds.
func _evolution_cooldown_elapsed(grid_pos: Vector2i, current_time: int) -> bool:
	if not tile_build_times.has(grid_pos):
		return true
	return current_time - tile_build_times[grid_pos] >= EVOLUTION_COOLDOWN_MSEC


## Counts magnet tiles of the given type within Manhattan distance of a cell.
func _count_magnets_in_radius(grid_pos: Vector2i, radius: int, tile_type: int) -> int:
	var count: int = 0
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if abs(dx) + abs(dy) > radius:
				continue
			var pos: Vector2i = Vector2i(grid_pos.x + dx, grid_pos.y + dy)
			if pos.x < 0 or pos.x >= grid_size or pos.y < 0 or pos.y >= grid_size:
				continue
			if grid.get_tile_type(pos) == tile_type:
				count += 1
	return count


## Sums the diminishing park bonus for `park_count` neighbouring parks.
## Walks PARK_BONUS_TIERS in order (1st park +15, 2nd +10, …); any park beyond
## the tiers array length contributes 0 (hard cap against LVT exploitation).
func _calculate_park_bonus(park_count: int) -> int:
	var bonus: int = 0
	for i in range(park_count):
		if i < PARK_BONUS_TIERS.size():
			bonus += PARK_BONUS_TIERS[i]
	return bonus


## Counts factory (INDUSTRIAL) tiles within a Manhattan radius of a cell — used
## by the pollution crash in get_land_value(). Modeled after _count_magnets_in_radius().
func _count_industrial_in_radius(grid_pos: Vector2i, radius: int) -> int:
	var count: int = 0
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if abs(dx) + abs(dy) > radius:
				continue
			var pos: Vector2i = Vector2i(grid_pos.x + dx, grid_pos.y + dy)
			if pos.x < 0 or pos.x >= grid_size or pos.y < 0 or pos.y >= grid_size:
				continue
			if grid.get_tile_type(pos) == GridCellData.TileType.INDUSTRIAL:
				count += 1
	return count


## Logistics multiplier for a factory's base production. Hooked-up factories
## (a live pipe in a cardinal neighbour) get the hookup bonus; unhooked ones run
## at a penalty. No pipe network present → neutral (×1.0).
func _factory_pipe_multiplier(factory_pos: Vector2i) -> float:
	if pipe_network == null:
		return 1.0
	if pipe_network.is_factory_hooked_up(factory_pos):
		return HOOKED_FACTORY_MULTIPLIER
	prints("Factory at", factory_pos, "is unhooked! Reduced production.")
	return UNHOOKED_FACTORY_MULTIPLIER


## Public accessor for a factory's pipe/logistics production multiplier — the
## same value the income loop uses. Lets the supply-chain simulation scale goods
## output by the exact same hookup bonus/penalty.
func factory_pipe_multiplier(factory_pos: Vector2i) -> float:
	return _factory_pipe_multiplier(factory_pos)


func _factory_water_multiplier(factory_pos: Vector2i) -> float:
	if not factory_water_multiplier_provider.is_valid():
		return 1.0
	return float(factory_water_multiplier_provider.call(factory_pos))


func factory_water_multiplier(factory_pos: Vector2i) -> float:
	return _factory_water_multiplier(factory_pos)


## Human-readable pipe status for the factory hover panel, including the live
## network's delivered throughput and a bottleneck warning when fully utilized.
func factory_pipe_status(factory_pos: Vector2i) -> String:
	var pipe_text: String = ""
	if pipe_network == null:
		pipe_text = "LOGISTICS: No pipe network available — base output"
	elif not pipe_network.is_factory_hooked_up(factory_pos):
		pipe_text = "LOGISTICS: No live sludge line — output reduced by 50%"
	else:
		var stats: Dictionary = pipe_network.get_factory_network_stats(factory_pos)
		var status: String = "LOGISTICS: Live sludge connection — +%d%% output" \
				% int((HOOKED_FACTORY_MULTIPLIER - 1.0) * 100.0)
		var utilization_text: String = "Network flow: %d/%d capacity · demand %d" % [
			int(stats["delivered"]), int(stats["capacity"]), int(stats["demand"])
		]
		if bool(stats["bottleneck"]):
			utilization_text += " — BOTTLENECK"
		pipe_text = status + "\n" + utilization_text
	if factory_water_status_provider.is_valid():
		var water_text: String = str(factory_water_status_provider.call(factory_pos))
		if water_text != "":
			return pipe_text + "\n" + water_text
	return pipe_text


## Spekulationsspärren: sums 2x LVT for every claimed tile left unbuilt longer
## than HOARDING_TIME_LIMIT_MSEC. Only unbuilt tiles (EMPTY/GRASS) qualify, so
## tiles with structures naturally drop out of the check.
func _hoarding_tax(current_time: int) -> int:
	var tax: int = 0
	for pos in tile_claimed_times:
		if current_time - int(tile_claimed_times[pos]) <= HOARDING_TIME_LIMIT_MSEC:
			continue
		var tile_type: int = grid.get_tile_type(pos)
		if tile_type == GridCellData.TileType.EMPTY or tile_type == GridCellData.TileType.GRASS:
			tax += get_land_value(pos) * 2
	return tax
