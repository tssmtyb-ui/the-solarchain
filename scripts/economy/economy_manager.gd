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
const PARK_BONUS: int = 15
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
## Minimum time (msec) between automatic density changes on the same tile,
## preventing flicker when land value hovers near a threshold.
const EVOLUTION_COOLDOWN_MSEC: int = 15000

## Worker radius and requirement for the factory labour dependency loop.
## Factories scan for nearby housing within this Manhattan distance.
const WORKER_RADIUS: int = 3
## Workers required for a factory to operate at full efficiency.
const REQUIRED_WORKERS: int = 2

# ---------------------------------------------------------------------------
#   Configuration (set by root scene before use)
# ---------------------------------------------------------------------------

## Seconds between automatic assessment cycles.
var assessment_interval: float = 5.0

## Reference to the GridManager — injected by the root scene.
var grid: GridManager

## Grid dimensions — injected by the root scene.
var grid_size: int = 10

# ---------------------------------------------------------------------------
#   State
# ---------------------------------------------------------------------------

## Tracks when each tile was last auto-evolved (msec ticks from
## Time.get_ticks_msec()) so the cooldown prevents density flickering.
var tile_build_times: Dictionary = {}

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

## Runs a full assessment NOW (bypasses the timer) and emits the signal.
func calculate_net_income() -> void:
	var road_count: int = 0
	var income: int = 0
	var current_time: int = Time.get_ticks_msec()

	for pos in grid.get_all_occupied_positions():
		var t: int = grid.get_tile_type(pos)
		match t:
			GridCellData.TileType.ROAD, GridCellData.TileType.ROAD_CROSS:
				road_count += 1
			GridCellData.TileType.INDUSTRIAL:
				if _get_local_workers(pos) >= REQUIRED_WORKERS:
					income += get_land_value(pos)
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

	var upkeep: int = road_count * ROAD_UPKEEP
	var net: int = income - upkeep
	assessment_completed.emit(net)


## Returns the Land Value of a grid position based on Manhattan distance to the
## nearest edge highway, modified by nearby environmental magnets.
## Base: MAX_LAND_VALUE - (shortest_distance * LVT_DROP_OFF). Parks within
## PARK_RADIUS add PARK_BONUS each; sludge lines within SLUDGE_RADIUS add
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
	value += _count_magnets_in_radius(grid_pos, PARK_RADIUS, GridCellData.TileType.PARK) * PARK_BONUS
	value += _count_magnets_in_radius(grid_pos, SLUDGE_RADIUS, GridCellData.TileType.SLUDGE) * SLUDGE_PENALTY

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
