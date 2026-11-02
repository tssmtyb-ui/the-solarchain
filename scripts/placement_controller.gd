class_name PlacementController
extends Node
## Owns the player-build pipeline: costs, placement rules, money deduction,
## grid writes, and building sprite spawning.

## Preloaded water ground tile texture.
const WATER_TILE_TEXTURE: Texture2D = preload("res://assets/tileGroundWater.png")
const WATER_ATLAS_SOURCE_ID: int = 4

const BUILD_COSTS: Dictionary = {
	GridCellData.TileType.ROAD: 10,
	GridCellData.TileType.INDUSTRIAL: 100,
	GridCellData.TileType.WAREHOUSE: 60,
	GridCellData.TileType.RESIDENTIAL_LOW: 50,
	GridCellData.TileType.PARK: 50,
	GridCellData.TileType.SLUDGE: 10,
	GridCellData.TileType.FARMHOUSE: 140,
	GridCellData.TileType.FARMLAND: 20,
	GridCellData.TileType.WATER_TOWER_SMALL: 200,
	GridCellData.TileType.WATER_TOWER_LARGE: 500,
}
const UPGRADE_COST: int = 150
const DEMOLISHABLE_TILES: Array[int] = [
	GridCellData.TileType.ROAD,
	GridCellData.TileType.ROAD_CROSS,
	GridCellData.TileType.INDUSTRIAL,
	GridCellData.TileType.WAREHOUSE,
	GridCellData.TileType.RESIDENTIAL_LOW,
	GridCellData.TileType.RESIDENTIAL_HIGH,
	GridCellData.TileType.PARK,
	GridCellData.TileType.SLUDGE,
	GridCellData.TileType.FARMHOUSE,
	GridCellData.TileType.FARMLAND,
	GridCellData.TileType.ABANDONED,
	GridCellData.TileType.WATER_TOWER_SMALL,
	GridCellData.TileType.WATER_TOWER_LARGE,
]
const ATLAS_ONLY_TILES: Array[int] = [
	GridCellData.TileType.ROAD,
	GridCellData.TileType.ROAD_CROSS,
]
const CARDINAL_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]
const DIR_N: int = 1
const DIR_E: int = 2
const DIR_S: int = 4
const DIR_W: int = 8
const ROAD_SOURCE_BY_MASK: Dictionary = {
	(DIR_W | DIR_E): 5,
	(DIR_N | DIR_S): 6,
	(DIR_N | DIR_E): 7,
	(DIR_E | DIR_S): 7,
	(DIR_S | DIR_W): 7,
	(DIR_W | DIR_N): 7,
	(DIR_N | DIR_E | DIR_S): 8,
	(DIR_E | DIR_S | DIR_W): 8,
	(DIR_S | DIR_W | DIR_N): 8,
	(DIR_W | DIR_N | DIR_E): 8,
	(DIR_N | DIR_E | DIR_S | DIR_W): 9,
}
const ROAD_SOURCE_FALLBACK: int = 10

var grid: GridManager
var tilemap: TileMapLayer
var placement: BuildingPlacement
var pipe_network: PipeNetworkManager
var road_connectivity: RoadConnectivityManager
var speculator_manager: SpeculatorManager
var farm_system: FarmSystem = FarmSystem.new()
var grid_size: int = 30
var _water_basin_cells: Dictionary = {}

const TILE_TYPE_MAP: Dictionary = {
	GridCellData.TileType.GRASS: {"source_id": 0, "coords": Vector2i(0, 0)},
	GridCellData.TileType.DIRT: {"source_id": 0, "coords": Vector2i(0, 0)},
	GridCellData.TileType.ASPHALT: {"source_id": 3, "coords": Vector2i(0, 0)},
	GridCellData.TileType.WATER: {"source_id": WATER_ATLAS_SOURCE_ID, "coords": Vector2i(0, 0)},
	GridCellData.TileType.ROAD: {"source_id": 5, "coords": Vector2i(0, 0)},
	GridCellData.TileType.ROAD_CROSS: {"source_id": 6, "coords": Vector2i(0, 0)},
	GridCellData.TileType.SIDEWALK: {"source_id": 11, "coords": Vector2i(0, 0)},
	GridCellData.TileType.RESIDENTIAL_LOW: {"source_id": 0, "coords": Vector2i(0, 0)},
	GridCellData.TileType.RESIDENTIAL_HIGH: {"source_id": 0, "coords": Vector2i(0, 0)},
	GridCellData.TileType.INDUSTRIAL: {"source_id": 0, "coords": Vector2i(0, 0)},
	GridCellData.TileType.WAREHOUSE: {"source_id": 0, "coords": Vector2i(0, 0)},
	GridCellData.TileType.PARK: {"source_id": 0, "coords": Vector2i(0, 0)},
	GridCellData.TileType.SLUDGE: {"source_id": 0, "coords": Vector2i(0, 0)},
	GridCellData.TileType.FARMHOUSE: {"source_id": 0, "coords": Vector2i(0, 0)},
	GridCellData.TileType.FARMLAND: {"source_id": 0, "coords": Vector2i(0, 0)},
	GridCellData.TileType.ABANDONED: {"source_id": 0, "coords": Vector2i(0, 0)},
	GridCellData.TileType.WATER_TOWER_SMALL: {"source_id": 0, "coords": Vector2i(0, 0)},
	GridCellData.TileType.WATER_TOWER_LARGE: {"source_id": 0, "coords": Vector2i(0, 0)},
}

signal park_demolished(park_pos: Vector2i)


func attempt_build(tile_type: int, grid_pos: Vector2i, current_money: int) -> Dictionary:
	if not _within_bounds(grid_pos):
		return _fail(current_money, "Out of bounds.")

	var existing: int = grid.get_tile_type(grid_pos)
	var is_water_tower: bool = _is_water_tower_type(tile_type)
	if existing == GridCellData.TileType.WATER and not is_water_tower:
		return _fail(current_money, "Cannot build on water!")
	var is_buildable_ground: bool = existing == GridCellData.TileType.EMPTY \
			or existing == GridCellData.TileType.GRASS \
			or existing == GridCellData.TileType.DIRT
	var is_villa_upgrade: bool = tile_type == GridCellData.TileType.RESIDENTIAL_LOW \
			and existing == GridCellData.TileType.RESIDENTIAL_LOW
	var is_water_tower_on_water: bool = is_water_tower \
			and existing == GridCellData.TileType.WATER
	if not is_buildable_ground and not is_villa_upgrade and not is_water_tower_on_water:
		if existing == tile_type:
			return _fail(current_money, "")
		return _fail(current_money, "Tile already occupied! Bulldoze it first.")

	var cost: int = BUILD_COSTS.get(tile_type, -1)
	if cost < 0:
		return _fail(current_money, "Unbuildable tile type: %d" % tile_type)
	if is_water_tower:
		if not is_water_tower_on_water and not _has_adjacent_water(grid_pos):
			return _fail(
				current_money,
				"Water Tower must be placed on water or adjacent to water!")
		if not _adjacent_to_road(grid_pos):
			return _fail(current_money, "Must be built next to a road!")
	elif tile_type == GridCellData.TileType.INDUSTRIAL \
			or tile_type == GridCellData.TileType.WAREHOUSE \
			or tile_type == GridCellData.TileType.FARMHOUSE:
		if not _adjacent_to_road(grid_pos):
			return _fail(current_money, "Must be built next to a road!")
	if tile_type == GridCellData.TileType.FARMLAND \
			and not farm_system.is_near_farmhouse(grid, grid_pos):
		return _fail(current_money, "Farmland must be within 3 tiles of a Farmhouse!")

	var placed_type: int = tile_type
	if tile_type == GridCellData.TileType.RESIDENTIAL_LOW \
			and existing == GridCellData.TileType.RESIDENTIAL_LOW:
		placed_type = GridCellData.TileType.RESIDENTIAL_HIGH
		cost = UPGRADE_COST
	var is_speculator_lot: bool = (
		speculator_manager != null
		and speculator_manager.is_speculator_owned(grid_pos)
	)
	var eminent_domain_fee: int = (
		speculator_manager.get_eminent_domain_cost(grid_pos)
		if is_speculator_lot
		else 0
	)
	cost += eminent_domain_fee
	if current_money < cost:
		return _fail(current_money, "Not enough money!")

	if is_speculator_lot:
		speculator_manager.release_lot(grid_pos, "eminent_domain")
	if existing == GridCellData.TileType.WATER:
		_water_basin_cells[grid_pos] = true
	var new_money: int = current_money - cost
	grid.set_tile(grid_pos, GridCellData.new(placed_type))
	place_tile(grid_pos, placed_type)
	if placement != null and not ATLAS_ONLY_TILES.has(placed_type):
		placement.spawn_building(grid_pos, placed_type)
	if placed_type == GridCellData.TileType.ROAD \
			or placed_type == GridCellData.TileType.ROAD_CROSS:
		refresh_road_neighbors(grid_pos)
	return {
		"ok": true,
		"money": new_money,
		"placed_type": placed_type,
		"eminent_domain_fee": eminent_domain_fee,
	}


func attempt_bulldoze(grid_pos: Vector2i, current_money: int) -> Dictionary:
	if not _within_bounds(grid_pos):
		return _fail(current_money, "Out of bounds.")
	if _edge_highways().has(grid_pos):
		return _fail(current_money, "Cannot demolish edge highway connection.")
	var existing: int = grid.get_tile_type(grid_pos)
	if speculator_manager != null and speculator_manager.is_speculator_owned(grid_pos):
		var fee: int = speculator_manager.get_eminent_domain_cost(grid_pos)
		if current_money < fee:
			return _fail(current_money, "Not enough money!")
		speculator_manager.release_lot(grid_pos, "eminent_domain")
		return {
			"ok": true,
			"money": current_money - fee,
			"placed_type": existing,
			"eminent_domain_fee": fee,
		}
	if existing == GridCellData.TileType.WATER:
		return _fail(current_money, "Cannot demolish water.")
	if not DEMOLISHABLE_TILES.has(existing):
		return _fail(current_money, "Nothing to demolish.")
	if placement != null:
		placement.remove_building(grid_pos)
	var restored_type: int = GridCellData.TileType.WATER \
			if _water_basin_cells.has(grid_pos) \
			else GridCellData.TileType.GRASS
	grid.set_tile(grid_pos, GridCellData.new(restored_type))
	place_tile(grid_pos, restored_type)
	if existing == GridCellData.TileType.ROAD \
			or existing == GridCellData.TileType.ROAD_CROSS:
		refresh_road_neighbors(grid_pos)
	if pipe_network != null and _is_network_relevant(existing):
		pipe_network.mark_dirty()
	if existing == GridCellData.TileType.PARK:
		park_demolished.emit(grid_pos)
	return {"ok": true, "money": current_money, "placed_type": restored_type}


func place_tile(cell: Vector2i, tile_type: int) -> void:
	if tile_type == GridCellData.TileType.WATER:
		_water_basin_cells[cell] = true
	if tilemap == null:
		return
	var entry: Dictionary = TILE_TYPE_MAP.get(tile_type, {})
	if entry.is_empty():
		push_warning("No TileSet mapping for tile type ", tile_type)
		return
	var source_id: int = int(entry.source_id)
	if _is_water_tower_type(tile_type) and _water_basin_cells.has(cell):
		source_id = WATER_ATLAS_SOURCE_ID
	tilemap.set_cell(cell, source_id, entry.coords)
	if pipe_network != null and _is_network_relevant(tile_type):
		pipe_network.mark_dirty()


func _is_water_tower_type(tile_type: int) -> bool:
	return tile_type == GridCellData.TileType.WATER_TOWER_SMALL \
			or tile_type == GridCellData.TileType.WATER_TOWER_LARGE


func _is_water_cell(pos: Vector2i) -> bool:
	if not _within_bounds(pos) or grid == null:
		return false
	return grid.get_tile_type(pos) == GridCellData.TileType.WATER \
			or _water_basin_cells.has(pos)


func _has_adjacent_water(grid_pos: Vector2i) -> bool:
	for off: Vector2i in CARDINAL_OFFSETS:
		if _is_water_cell(grid_pos + off):
			return true
	return false


func _is_network_relevant(tile_type: int) -> bool:
	return tile_type == GridCellData.TileType.SLUDGE \
			or tile_type == GridCellData.TileType.INDUSTRIAL


func _road_connection(cell: Vector2i, off: Vector2i) -> bool:
	var adj: Vector2i = cell + off
	if not _within_bounds(adj):
		return false
	var adj_type: int = grid.get_tile_type(adj)
	return adj_type == GridCellData.TileType.ROAD \
			or adj_type == GridCellData.TileType.ROAD_CROSS


func _road_mask(cell: Vector2i) -> int:
	var mask: int = 0
	if _road_connection(cell, Vector2i(0, -1)): mask |= DIR_N
	if _road_connection(cell, Vector2i(1, 0)): mask |= DIR_E
	if _road_connection(cell, Vector2i(0, 1)): mask |= DIR_S
	if _road_connection(cell, Vector2i(-1, 0)): mask |= DIR_W
	return mask


func refresh_road_connection(cell: Vector2i) -> void:
	if tilemap == null or not _within_bounds(cell):
		return
	var tile_type: int = grid.get_tile_type(cell)
	if tile_type != GridCellData.TileType.ROAD \
			and tile_type != GridCellData.TileType.ROAD_CROSS:
		return
	var mask: int = _road_mask(cell)
	var source: int = ROAD_SOURCE_BY_MASK.get(mask, ROAD_SOURCE_FALLBACK)
	tilemap.set_cell(cell, source, Vector2i.ZERO)


func refresh_road_neighbors(cell: Vector2i) -> void:
	refresh_road_connection(cell)
	for off: Vector2i in CARDINAL_OFFSETS:
		refresh_road_connection(cell + off)


func _adjacent_to_road(grid_pos: Vector2i) -> bool:
	return road_connectivity != null \
			and road_connectivity.is_road_adjacent(grid_pos)


func _edge_highways() -> Array[Vector2i]:
	var mid_y: int = int(grid_size * 0.5)
	return [Vector2i(0, mid_y), Vector2i(grid_size - 1, mid_y)]


func _within_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_size and pos.y >= 0 and pos.y < grid_size


func _fail(money: int, reason: String) -> Dictionary:
	return {"ok": false, "money": money, "reason": reason}
