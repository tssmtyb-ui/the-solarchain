class_name EconomyManager
extends Node
## Core macroeconomic loop for Spekulant's Land Value Tax (LVT) system.
##
## ### Responsibilities
##   - Maintain the universal flat LVT rate.
##   - Scan the grid at a timed interval and compute per-tile land value modifiers
##     based on adjacent environmental features (parks ↔ boost, industry ↔ penalty).
##   - Calculate total tax revenue across all occupied tiles.
##
## ### Decoupled design
##   This script only **reads** from GridManager via its public API (get_tile,
##   get_tile_type, get_all_occupied_positions). It never writes to the grid,
##   never touches rendering, and never handles UI input. Any system that needs
##   tax data reads from this manager.
##
## Usage (as a child of the root scene):
##   EconomyManager.set_flat_rate(0.15)
##   EconomyManager.calculate_all()
##   var rev := EconomyManager.total_revenue

# ---------------------------------------------------------------------------
#   Land-value modifier presets (per tile type)
# ---------------------------------------------------------------------------

## Boost applied by a single tile of this type to *neighbouring* land value.
## Positive = luxury (park, transit). Negative = nuisance (industry, road).
const ENV_EFFECT: Dictionary = {
	GridCellData.TileType.EMPTY:         0.0,
	GridCellData.TileType.GRASS:         0.05,
	GridCellData.TileType.DIRT:          -0.02,
	GridCellData.TileType.CONCRETE:      -0.05,
	GridCellData.TileType.ASPHALT:       -0.05,
	GridCellData.TileType.WATER:         0.10,
	GridCellData.TileType.ROAD:          -0.03,
	GridCellData.TileType.ROAD_CROSS:    -0.03,
	GridCellData.TileType.SIDEWALK:      0.02,
	GridCellData.TileType.SIDEWALK_CORNER: 0.02,
	GridCellData.TileType.RESIDENTIAL_LOW:   0.08,
	GridCellData.TileType.RESIDENTIAL_HIGH: 0.12,
	GridCellData.TileType.INDUSTRIAL:    -0.15,
	GridCellData.TileType.WAREHOUSE:     -0.08,
	GridCellData.TileType.SEED_HUB:      0.0,
}

## The base tax bill for one tile before any modifier is applied.
const BASE_TAX_PER_TILE: float = 10.0

# ---------------------------------------------------------------------------
#   Configuration
# ---------------------------------------------------------------------------

## Universal flat LVT rate applied to raw land value.
## A rate of 0.10 means 10 % of the base value is taxed per assessment period.
var flat_rate: float = 0.10:
	set(value):
		flat_rate = maxf(value, 0.0)

## Seconds between automatic assessment cycles.
var assessment_interval: float = 5.0

## Manhattan distance used when scanning for environmental neighbours.
## 1 = only the 4 direct cardinals.  2 = 8-neighbour + ring-2.
var env_scan_radius: int = 2

# ---------------------------------------------------------------------------
#   State — computed by calculate_all()
# ---------------------------------------------------------------------------

## Total LVT revenue from the last full assessment.
var total_revenue: float = 0.0

## Per-tile breakdowns from the last assessment, keyed by Vector2i.
## Each entry: { "base_value": float, "env_modifier": float, "tax_bill": float }
var tile_assessments: Dictionary = {}

## Signal fired after each full assessment cycle.
signal assessment_completed(total: float, tile_count: int)

# ---------------------------------------------------------------------------
#   Public API
# ---------------------------------------------------------------------------

## Run a full assessment NOW (bypasses the timer).
func calculate_all() -> void:
	total_revenue = 0.0
	tile_assessments.clear()

	var grid: GridManager = _resolve_grid()
	if grid == null:
		push_error("EconomyManager: GridManager not available.")
		return

	var positions: Array[Vector2i] = grid.get_all_occupied_positions()

	for pos in positions:
		var tile_type: int = grid.get_tile_type(pos)
		# Skip purely decorative tiles — they don't generate tax.
		if tile_type in _DECORATIVE:
			continue

		# 1) Base value = (per-tile constant + land_value_modifier) × flat rate.
		#    The land_value_modifier is a per-tile boost (e.g. +100 near the Seed Hub).
		var lvm: float = grid.get_land_value_modifier(pos)
		var base_value: float = (BASE_TAX_PER_TILE + lvm) * flat_rate

		# 2) Environmental modifier = sum of neighbour effects.
		var env_modifier: float = _compute_env_modifier(pos, grid)

		# 3) Tax bill = base × (1.0 + env_modifier).
		var tax_bill: float = base_value * (1.0 + env_modifier)

		var assessment: Dictionary = {
			"tile_type": tile_type,
			"base_value": base_value,
			"env_modifier": env_modifier,
			"tax_bill": maxf(tax_bill, 0.0),
		}
		tile_assessments[pos] = assessment
		total_revenue += assessment.tax_bill

	assessment_completed.emit(total_revenue, tile_assessments.size())


## Set the flat LVT rate and immediately re-assess.
func set_flat_rate(value: float) -> void:
	flat_rate = maxf(value, 0.0)
	calculate_all()


## Convenience: retrieve the last tax bill for a tile, or 0.0.
func get_tax_bill(grid_pos: Vector2i) -> float:
	var a: Dictionary = tile_assessments.get(grid_pos, {})
	return a.get("tax_bill", 0.0) as float


## Convenience: retrieve the last env modifier for a tile, or 0.0.
func get_env_modifier(grid_pos: Vector2i) -> float:
	var a: Dictionary = tile_assessments.get(grid_pos, {})
	return a.get("env_modifier", 0.0) as float

# ---------------------------------------------------------------------------
#   Internal helpers
# ---------------------------------------------------------------------------

## Tile types that are decorative / non-taxable.
const _DECORATIVE: Array[int] = [
	GridCellData.TileType.EMPTY,
	GridCellData.TileType.GRASS,
	GridCellData.TileType.DIRT,
	GridCellData.TileType.WATER,
	GridCellData.TileType.ROAD,
	GridCellData.TileType.ROAD_CROSS,
	GridCellData.TileType.SIDEWALK,
	GridCellData.TileType.SIDEWALK_CORNER,
]


## Scan `env_scan_radius` tiles around `pos` and sum the environmental
## effect of each neighbour.
func _compute_env_modifier(pos: Vector2i, grid: GridManager) -> float:
	var total: float = 0.0

	for dx in range(-env_scan_radius, env_scan_radius + 1):
		for dy in range(-env_scan_radius, env_scan_radius + 1):
			# Skip the centre tile itself.
			if dx == 0 and dy == 0:
				continue
			# Skip far diagonals to keep it roughly Manhattan-ish.
			if abs(dx) + abs(dy) > env_scan_radius:
				continue

			var neighbour := Vector2i(pos.x + dx, pos.y + dy)
			var nt: int = grid.get_tile_type(neighbour)
			total += ENV_EFFECT.get(nt, 0.0)

	# Clamp to a reasonable range so no tile gets a > ±1 modifier.
	return clampf(total, -1.0, 1.0)


## Try every reasonable way to find the GridManager singleton.
func _resolve_grid() -> GridManager:
	# 1) Sibling / scene-tree child of the same root.
	if Engine.get_main_loop() is SceneTree:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		var root: Window = tree.root
		if root:
			# Check the autoload first (registered in project.godot).
			var auto := root.get_node_or_null("/root/GridManager") as GridManager
			if auto != null:
				return auto
			# Check current scene.
			var scene: Node = root.get_child(root.get_child_count() - 1)
			if scene and scene.has_node("GridManager"):
				return scene.get_node("GridManager") as GridManager
	return null


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
	calculate_all()