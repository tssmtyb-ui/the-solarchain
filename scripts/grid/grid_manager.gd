class_name GridManager
extends Node
## Central data store for every tile's state.
##
## Responsibilities:
##   - Store every tile's state in a Dictionary keyed by Vector2i.
##   - Expose clean query methods so other systems (economy, building,
##     event-system) never reach into the internal Dictionary directly.
##
## Coordinate conversion is handled by the TileMapLayer node
## (TileMapLayer.local_to_map / map_to_local) — do NOT reimplement it here.
##
## Usage:
##   GridManager.set_tile(Vector2i(5, 3), GridCellData.new(GridCellData.TileType.ROAD))
##   var data := GridManager.get_tile(Vector2i(5, 3))

# ---------------------------------------------------------------------------
#   Internal storage
# ---------------------------------------------------------------------------

## Dictionary of Vector2i → GridCellData. Only stores non-empty tiles to save memory.
var _grid: Dictionary = {}

# ---------------------------------------------------------------------------
#   Public API – tile manipulation
# ---------------------------------------------------------------------------

## Store a GridCellData at the given grid position.
## Passing `null` for data removes the entry (treated as empty).
func set_tile(grid_pos: Vector2i, data: GridCellData) -> void:
	if data == null:
		_grid.erase(grid_pos)
		return
	_grid[grid_pos] = data


## Retrieve the GridCellData at a grid position, or null if the tile is empty.
func get_tile(grid_pos: Vector2i) -> GridCellData:
	return _grid.get(grid_pos) as GridCellData


## Returns true when the cell has no data or its type is EMPTY.
func is_empty(grid_pos: Vector2i) -> bool:
	var data: GridCellData = _grid.get(grid_pos) as GridCellData
	return data == null or data.is_empty()


## Returns the land-value modifier of the tile at `grid_pos`, or 0.0 if empty.
func get_land_value_modifier(grid_pos: Vector2i) -> float:
	var data: GridCellData = _grid.get(grid_pos) as GridCellData
	return data.land_value_modifier if data != null else 0.0


## Returns the tile type of the cell, or GridCellData.TileType.EMPTY if empty.
func get_tile_type(grid_pos: Vector2i) -> int:
	var data: GridCellData = _grid.get(grid_pos) as GridCellData
	return data.tile_type if data != null else GridCellData.TileType.EMPTY


## Returns an array of all grid positions that currently have tile data.
func get_all_occupied_positions() -> Array[Vector2i]:
	var keys: Array = _grid.keys()
	var result: Array[Vector2i] = []
	for k in keys:
		result.append(k as Vector2i)
	return result


## Clears the entire grid.
func clear_all() -> void:
	_grid.clear()
