class_name PlacementController
extends Node
## Owns the player-build pipeline: cost lookup, placement rules, money
## deduction, grid writes, and sprite spawning — extracted from the root
## scene script (node_2d.gd) to stop it from becoming a God Object.
##
## Pure function API: `attempt_build()` / `attempt_bulldoze()` take the
## player's current money IN and return the NEW balance OUT, so the caller
## (root scene) stays the single owner of `current_money` and the money UI.
##
## Dependencies are injected by the root scene before use:
##   grid      (GridManager)        — data model reads/writes
##   tilemap   (TileMapLayer)       — ground tile rendering
##   placement (BuildingPlacement)  — building sprite spawning
##   speculator(SpeculatorManager)  — land-ownership check (can be null)

# ---------------------------------------------------------------------------
#   Build costs
# ---------------------------------------------------------------------------

## Monetary cost to build each tile type (deducted on success).
const BUILD_COSTS: Dictionary = {
	GridCellData.TileType.ROAD: 10,
	GridCellData.TileType.INDUSTRIAL: 100,
	GridCellData.TileType.WAREHOUSE: 60,
	GridCellData.TileType.RESIDENTIAL_LOW: 50,
	GridCellData.TileType.PARK: 50,
	GridCellData.TileType.SLUDGE: 10,
}

## Cost to upgrade an existing villa (RESIDENTIAL_LOW) to an apartment.
const UPGRADE_COST: int = 150

## Tile types the bulldozer may demolish back to grass.
const DEMOLISHABLE_TILES: Array[int] = [
	GridCellData.TileType.ROAD,
	GridCellData.TileType.ROAD_CROSS,
	GridCellData.TileType.INDUSTRIAL,
	GridCellData.TileType.WAREHOUSE,
	GridCellData.TileType.RESIDENTIAL_LOW,
	GridCellData.TileType.RESIDENTIAL_HIGH,
	GridCellData.TileType.PARK,
	GridCellData.TileType.SLUDGE,
]

## Tile types rendered purely as ground atlas tiles (no sprite overlay).
## Building sprites are skipped for these even when placed successfully.
const ATLAS_ONLY_TILES: Array[int] = [
	GridCellData.TileType.ROAD,
	GridCellData.TileType.ROAD_CROSS,
]

# ---------------------------------------------------------------------------
#   Injected dependencies (set by the root scene before use)
# ---------------------------------------------------------------------------

## The GridManager data model.
var grid: GridManager

## The TileMapLayer used to paint ground tiles.
var tilemap: TileMapLayer

## The BuildingPlacement manager that spawns/removes building sprites.
var placement: BuildingPlacement

## The corporate speculator AI; may be null (ownership checks are skipped).
var speculator: SpeculatorManager

## Grid dimensions for bounds checks — mirrors the root scene's GRID_SIZE.
var grid_size: int = 10

# ---------------------------------------------------------------------------
#   Ground atlas mapping
# ---------------------------------------------------------------------------

## Maps GridCellData.TileType → { source_id, atlas_coords } for TileSet lookup.
## Each texture is a single 512×256 isometric tile at atlas origin (0,0).
## This is the same map that lived on the root scene; the root copy is
## deleted when node_2d.gd is migrated onto this controller.
const TILE_TYPE_MAP: Dictionary = {
	GridCellData.TileType.GRASS:      { "source_id": 0,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.DIRT:       { "source_id": 1,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.ASPHALT:    { "source_id": 3,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.WATER:      { "source_id": 4,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.ROAD:       { "source_id": 5,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.ROAD_CROSS: { "source_id": 6,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.SIDEWALK:   { "source_id": 11, "coords": Vector2i(0, 0) },
	GridCellData.TileType.RESIDENTIAL_LOW: { "source_id": 0, "coords": Vector2i(0, 0) }, # ground: grass; building sprite spawned separately
	GridCellData.TileType.RESIDENTIAL_HIGH: { "source_id": 0, "coords": Vector2i(0, 0) }, # ground: grass; building sprite spawned separately
	GridCellData.TileType.INDUSTRIAL:  { "source_id": 0,  "coords": Vector2i(0, 0) }, # ground: grass blends in; building sprite spawned separately
	GridCellData.TileType.WAREHOUSE:  { "source_id": 0,  "coords": Vector2i(0, 0) }, # ground: grass blends in; building sprite spawned separately
	GridCellData.TileType.PARK:       { "source_id": 0,  "coords": Vector2i(0, 0) }, # ground: grass; gazebo spawned separately
	GridCellData.TileType.SLUDGE:     { "source_id": 0,  "coords": Vector2i(0, 0) }, # ground: grass; pipe spawned separately
	GridCellData.TileType.DIRT_LOT:   { "source_id": 1,  "coords": Vector2i(0, 0) }, # dirt lot — speculator-owned land
}

# ---------------------------------------------------------------------------
#   Public API
# ---------------------------------------------------------------------------

## Attempts to build `tile_type` at `grid_pos`, spending from `current_money`.
##
## Handles, in order: bounds, speculator ownership, already-occupied no-op,
## cost lookup, road-adjacency rules, villa→apartment upgrade, affordability,
## then applies the build (deduct → grid write → ground tile → sprite).
##
## Returns a Dictionary:
##   SUCCESS: { "ok": true, "money": <new balance>, "placed_type": <int> }
##   FAILURE: { "ok": false, "money": <unchanged>, "reason": "<message>" }
## A failure with `reason == ""` is a silent no-op (re-clicking an identical
## tile) — the caller can choose not to surface it.
func attempt_build(tile_type: int, grid_pos: Vector2i, current_money: int) -> Dictionary:
	if not _within_bounds(grid_pos):
		return _fail(current_money, "Out of bounds.")

	# Speculator-owned land is off-limits to the player.
	if speculator != null and speculator.owned_tiles.has(grid_pos):
		return _fail(current_money, "Blocked: owned by the speculator!")

	var existing: int = grid.get_tile_type(grid_pos)

	# Already built — silent no-op (except villas, which can be upgraded).
	if existing == tile_type and tile_type != GridCellData.TileType.RESIDENTIAL_LOW:
		return _fail(current_money, "")

	var cost: int = BUILD_COSTS.get(tile_type, -1)
	if cost < 0:
		return _fail(current_money, "Unbuildable tile type: %d" % tile_type)

	# Factories and warehouses must sit next to a road.
	if tile_type == GridCellData.TileType.INDUSTRIAL or tile_type == GridCellData.TileType.WAREHOUSE:
		if not _adjacent_to_road(grid_pos):
			return _fail(current_money, "Must be built next to a road!")

	# Villa → apartment upgrade when re-clicking an existing house.
	var placed_type: int = tile_type
	if tile_type == GridCellData.TileType.RESIDENTIAL_LOW and existing == GridCellData.TileType.RESIDENTIAL_LOW:
		placed_type = GridCellData.TileType.RESIDENTIAL_HIGH
		cost = UPGRADE_COST

	if current_money < cost:
		return _fail(current_money, "Not enough money!")

	var new_money: int = current_money - cost

	# Apply: data model → ground tile → building sprite.
	grid.set_tile(grid_pos, GridCellData.new(placed_type))
	place_tile(grid_pos, placed_type)
	if placement != null and not ATLAS_ONLY_TILES.has(placed_type):
		placement.spawn_building(grid_pos, placed_type)

	return { "ok": true, "money": new_money, "placed_type": placed_type }


## Demolishes the tile at `grid_pos` back to grass (free). Respects the
## speculator's ownership and the edge-highway connections — same result
## contract as `attempt_build()`; `money` is returned unchanged.
func attempt_bulldoze(grid_pos: Vector2i, current_money: int) -> Dictionary:
	if not _within_bounds(grid_pos):
		return _fail(current_money, "Out of bounds.")

	if speculator != null and speculator.owned_tiles.has(grid_pos):
		return _fail(current_money, "Blocked: owned by the speculator!")

	if _edge_highways().has(grid_pos):
		return _fail(current_money, "Cannot demolish edge highway connection.")

	var existing: int = grid.get_tile_type(grid_pos)
	if not DEMOLISHABLE_TILES.has(existing):
		return _fail(current_money, "Nothing to demolish.")

	if placement != null:
		placement.remove_building(grid_pos)
	grid.set_tile(grid_pos, GridCellData.new(GridCellData.TileType.GRASS))
	place_tile(grid_pos, GridCellData.TileType.GRASS)

	return { "ok": true, "money": current_money, "placed_type": GridCellData.TileType.GRASS }


## Looks up the TileSet source/coords for a GridCellData tile type and paints
## the ground tile on the TileMapLayer. Public so the root scene can reuse it
## for non-player writes (edge highways, evolution swaps, speculator claims).
func place_tile(cell: Vector2i, tile_type: int) -> void:
	if tilemap == null:
		return
	var entry: Dictionary = TILE_TYPE_MAP.get(tile_type, {})
	if entry.is_empty():
		push_warning("No TileSet mapping for tile type ", tile_type)
		return
	tilemap.set_cell(cell, entry.source_id, entry.coords)

# ---------------------------------------------------------------------------
#   Internal helpers
# ---------------------------------------------------------------------------

## Returns true if any cardinal neighbour of `grid_pos` is a road tile.
func _adjacent_to_road(grid_pos: Vector2i) -> bool:
	var cardinal: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
	]
	for off in cardinal:
		var adj: Vector2i = Vector2i(grid_pos.x + off.x, grid_pos.y + off.y)
		if not _within_bounds(adj):
			continue
		var adj_type: int = grid.get_tile_type(adj)
		if adj_type == GridCellData.TileType.ROAD or adj_type == GridCellData.TileType.ROAD_CROSS:
			return true
	return false


## Returns the protected edge-highway cells (west/east midpoints).
func _edge_highways() -> Array[Vector2i]:
	var mid_y: int = int(grid_size * 0.5)
	return [
		Vector2i(0, mid_y),
		Vector2i(grid_size - 1, mid_y),
	]


## Returns true if `pos` lies within the grid_size × grid_size map bounds.
func _within_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_size and pos.y >= 0 and pos.y < grid_size


## Builds the standard failure result dictionary.
func _fail(money: int, reason: String) -> Dictionary:
	return { "ok": false, "money": money, "reason": reason }
