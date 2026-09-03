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

## Worker radius and requirement for the factory labour dependency loop.
## Factories scan for nearby housing within this Manhattan distance.
const WORKER_RADIUS: int = 3
## Workers required for a factory to operate at full efficiency.
const REQUIRED_WORKERS: int = 2

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

## Duration of a global industrial strike (3 minutes) triggered by demolishing
## a public park. Factories produce $0 while one is active.
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

## Absolute tick (Time.get_ticks_msec()) until which a global industrial strike
## is active. Factories earn $0 while Time.get_ticks_msec() < this. 0 = no strike.
var industrial_strike_until_msec: int = 0

## Citizen's Dividend Policy (0–100 %). Higher payout boosts factory production
## but deducts a matching dividend cost from the treasury each assessment.
var dividend_percent: float = 0.0

## Total factory income from the most recent assessment — the basis for live
## dividend-cost previews in the UI (updated every assessment cycle).
var last_factory_income: int = 0

## Optional provider of a per-tile goods-supply land-value bonus. Set by the
## root scene's supply-chain simulation so well-supplied housing raises LVT and
## thus tax/dividend output. Callable(Vector2i) -> int; leave invalid to disable.
var goods_supply_bonus_provider: Callable

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
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)


func _on_timer_timeout() -> void:
	calculate_net_income()


# ---------------------------------------------------------------------------
#   Public API
# ---------------------------------------------------------------------------

## Starts a global industrial strike for STRIKE_DURATION_MSEC. While active,
## factories produce no income. Called when the player demolishes a public park.
func trigger_industrial_strike() -> void:
	industrial_strike_until_msec = Time.get_ticks_msec() + STRIKE_DURATION_MSEC
	prints("Industrial strike triggered for %d ms." % STRIKE_DURATION_MSEC)


## Sets the Citizen's Dividend payout percentage (0–100). Driven live by the UI
## HSlider's value_changed signal.
func set_dividend_percent(val: float) -> void:
	dividend_percent = val


## Arms the density-change buffer for a tile, recording its last change time.
## Call after ANY state change on a residential tile (e.g. a manual villa→
## apartment upgrade) so auto-evolution can't immediately undo it the next
## assessment while land value is still fluctuating.
func stamp_evolution_cooldown(grid_pos: Vector2i) -> void:
	tile_build_times[grid_pos] = Time.get_ticks_msec()


## Returns the factory production multiplier for a given dividend %. Scaled so
## the boost is half the payout: 0 % → ×1.0 (no boost), 50 % → ×1.25, 100 % → ×1.5
## (+50 %). Single source of truth for both the economy loop and the UI label.
func get_factory_boost_multiplier(percent: float) -> float:
	return 1.0 + percent / 200.0


## Returns the dividend payout cost per assessment tick for a given dividend %,
## based on the most recent factory income. Used for the live UI trade-off label.
func get_dividend_cost(percent: float) -> int:
	return int(last_factory_income * percent / 100.0)


## Runs a full assessment NOW (bypasses the timer) and emits the signal.
func calculate_net_income() -> void:
	var road_count: int = 0
	var income: int = 0
	var factory_income: int = 0
	var current_time: int = Time.get_ticks_msec()

	for pos in grid.get_all_occupied_positions():
		var t: int = grid.get_tile_type(pos)
		# Stamp the first time the player claims a tile (any non-canvas type).
		# Pre-filled GRASS canvas tiles are never stamped — only real claims
		# qualify for the hoarding check later.
		if t != GridCellData.TileType.GRASS and t != GridCellData.TileType.DIRT_LOT \
				and not tile_claimed_times.has(pos):
			tile_claimed_times[pos] = current_time
		match t:
			GridCellData.TileType.ROAD, GridCellData.TileType.ROAD_CROSS:
				road_count += 1
			GridCellData.TileType.INDUSTRIAL:
				# Pollution is now purely Land Value-based (see get_land_value()).
				# A park-demolition strike shuts down all factories: they earn $0
				# while Time.get_ticks_msec() < industrial_strike_until_msec.
				if Time.get_ticks_msec() >= industrial_strike_until_msec:
					if _get_local_workers(pos) >= REQUIRED_WORKERS:
						var base_factory: int = get_land_value(pos)
						factory_income += base_factory
						# Logistics (pipe hookup) + Dividend Policy production modifiers.
						income += int(base_factory * _factory_pipe_multiplier(pos) \
								* get_factory_boost_multiplier(dividend_percent))
					else:
						prints("Factory at", pos, "is idle! Not enough workers.")
			GridCellData.TileType.WAREHOUSE:
				income += get_land_value(pos)
			GridCellData.TileType.RESIDENTIAL_LOW:
				var lv: int = get_land_value(pos)
				if lv <= MAX_VILLA_LAND_VALUE:
					income += lv
				else:
					prints("RESIDENTIAL_LOW at", pos, "pays $0 — land value too high.")
				# Auto-evolution: land value crossed the upgrade threshold.
				if lv >= UPGRADE_LVT and _evolution_cooldown_elapsed(pos, current_time):
					tile_build_times[pos] = current_time
					residential_evolution_triggered.emit(pos, GridCellData.TileType.RESIDENTIAL_HIGH)
			GridCellData.TileType.RESIDENTIAL_HIGH:
				var lv_high: int = get_land_value(pos)
				income += lv_high * 2
				# Auto-evolution: land value collapsed below the downgrade threshold.
				if lv_high <= DOWNGRADE_LVT and _evolution_cooldown_elapsed(pos, current_time):
					tile_build_times[pos] = current_time
					residential_evolution_triggered.emit(pos, GridCellData.TileType.RESIDENTIAL_LOW)

	last_factory_income = factory_income
	var upkeep: int = road_count * ROAD_UPKEEP
	var hoarding_tax: int = _hoarding_tax(current_time)
	# Citizen's Dividend: the treasury pays out a % of factory income to citizens.
	var dividend_payout: int = int(factory_income * dividend_percent / 100.0)
	var net: int = income - upkeep - hoarding_tax - dividend_payout
	assessment_completed.emit(net)


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

	# Environmental magnets: parks raise the value, sludge lines depress it.
	# Effects stack — clustered magnets compound (chosen over "strongest only"
	# for simplicity and emergent park districts / toxic zones).
	value += _calculate_park_bonus(_count_magnets_in_radius(grid_pos, PARK_RADIUS, GridCellData.TileType.PARK))
	value += _count_magnets_in_radius(grid_pos, SLUDGE_RADIUS, GridCellData.TileType.SLUDGE) * SLUDGE_PENALTY

	# Pollution crash: residential land within a factory's pollution radius
	# collapses catastrophically (× POLLUTION_LV_MULTIPLIER, i.e. −80%).
	var t: int = grid.get_tile_type(grid_pos)
	if (t == GridCellData.TileType.RESIDENTIAL_LOW or t == GridCellData.TileType.RESIDENTIAL_HIGH) \
			and _count_industrial_in_radius(grid_pos, POLLUTION_RADIUS) > 0:
		value = int(value * POLLUTION_LV_MULTIPLIER)

	# Supply-chain Step 1: well-supplied housing raises land value nearby, which
	# flows straight into tax revenue (and the factory income that pays the
	# dividend). Additive and clamped with everything else below.
	if goods_supply_bonus_provider.is_valid():
		value += goods_supply_bonus_provider.call(grid_pos)

	return clampi(value, LAND_VALUE_FLOOR, LAND_VALUE_CEIL)


# ---------------------------------------------------------------------------
#   Internal helpers
# ---------------------------------------------------------------------------

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


## Human-readable pipe-connectivity status for a factory, for the hover/inspect
## UI. Mirrors factory_pipe_multiplier() so the readout always matches the math.
func factory_pipe_status(factory_pos: Vector2i) -> String:
	if pipe_network == null:
		return "Pipe Status: No Network (Base Production)"
	if pipe_network.is_factory_hooked_up(factory_pos):
		return "Pipe Status: Connected (+%d%% Goods)" % int((HOOKED_FACTORY_MULTIPLIER - 1.0) * 100.0)
	return "Pipe Status: Missing (-%d%% Penalty)" % int((1.0 - UNHOOKED_FACTORY_MULTIPLIER) * 100.0)


## Scans within WORKER_RADIUS of a factory position and counts nearby workers.
## RESIDENTIAL_LOW tiles contribute 1 worker, RESIDENTIAL_HIGH tiles contribute 3.
## Uses Manhattan distance (abs(dx) + abs(dy) <= WORKER_RADIUS) for the scan.
func _get_local_workers(factory_pos: Vector2i) -> int:
	var count: int = 0
	for dx in range(-WORKER_RADIUS, WORKER_RADIUS + 1):
		for dy in range(-WORKER_RADIUS, WORKER_RADIUS + 1):
			if abs(dx) + abs(dy) > WORKER_RADIUS:
				continue
			var pos: Vector2i = Vector2i(factory_pos.x + dx, factory_pos.y + dy)
			if pos.x < 0 or pos.x >= grid_size or pos.y < 0 or pos.y >= grid_size:
				continue
			var tile_type: int = grid.get_tile_type(pos)
			match tile_type:
				GridCellData.TileType.RESIDENTIAL_LOW:
					if get_land_value(pos) > MAX_VILLA_LAND_VALUE:
						prints("Villa at", pos, "abandoned! Land value too high.")
					else:
						count += 1
				GridCellData.TileType.RESIDENTIAL_HIGH:
					count += 3
	return count


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
