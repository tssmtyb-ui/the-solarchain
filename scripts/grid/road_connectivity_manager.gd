class_name RoadConnectivityManager
extends Node
## Owns cached cardinal road adjacency and connected road-network components for
## residences, factories, Farmhouses, and Water Towers.
## Grid changes invalidate the cache; the next query rebuilds it from GridManager.

const CARDINAL_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]

var grid: GridManager
var grid_size: int = 20
var _road_connected: Dictionary = {}
var _road_component_by_cell: Dictionary = {}
var _components: Dictionary = {}
var _building_network_id: Dictionary = {}
var _building_network_ids: Dictionary = {}
var _cache_dirty: bool = true


func configure(world_grid: GridManager, world_grid_size: int) -> void:
	if grid != null:
		if grid.tile_changed.is_connected(_on_tile_changed):
			grid.tile_changed.disconnect(_on_tile_changed)
		if grid.grid_cleared.is_connected(_on_grid_cleared):
			grid.grid_cleared.disconnect(_on_grid_cleared)
	grid = world_grid
	grid_size = world_grid_size
	clear_cache()
	if grid != null:
		if not grid.tile_changed.is_connected(_on_tile_changed):
			grid.tile_changed.connect(_on_tile_changed)
		if not grid.grid_cleared.is_connected(_on_grid_cleared):
			grid.grid_cleared.connect(_on_grid_cleared)


func is_road_connected(pos: Vector2i) -> bool:
	if grid == null or not _is_in_bounds(pos):
		return false
	_ensure_cache()
	return bool(_road_connected.get(pos, false))


func is_road_adjacent(pos: Vector2i) -> bool:
	if grid == null or not _is_in_bounds(pos):
		return false
	return _has_adjacent_road(pos)


## Returns the connected road network ID for a road cell, or -1 if `pos` is not a road.
func get_road_network_id(pos: Vector2i) -> int:
	if grid == null or not _is_in_bounds(pos):
		return -1
	_ensure_cache()
	return int(_road_component_by_cell.get(pos, -1))


## Returns the primary connected road network ID adjacent to `pos`, or -1 if disconnected.
func get_building_network_id(pos: Vector2i) -> int:
	if grid == null or not _is_in_bounds(pos):
		return -1
	_ensure_cache()
	if _building_network_id.has(pos):
		return int(_building_network_id[pos])
	for offset: Vector2i in CARDINAL_OFFSETS:
		var neighbor: Vector2i = pos + offset
		if _road_component_by_cell.has(neighbor):
			return int(_road_component_by_cell[neighbor])
	return -1


## Returns all unique road network IDs cardinally adjacent to `pos` in deterministic order.
func get_adjacent_network_ids(pos: Vector2i) -> Array[int]:
	var empty_ids: Array[int] = []
	if grid == null or not _is_in_bounds(pos):
		return empty_ids
	_ensure_cache()
	if _building_network_ids.has(pos):
		var cached: Array[int] = []
		cached.assign(_building_network_ids[pos])
		return cached
	return _compute_adjacent_network_ids(pos)


## True if `pos_a` and `pos_b` share at least one connected road network.
func are_on_same_road_network(pos_a: Vector2i, pos_b: Vector2i) -> bool:
	var nets_a: Array[int] = get_adjacent_network_ids(pos_a)
	if nets_a.is_empty():
		return false
	var nets_b: Array[int] = get_adjacent_network_ids(pos_b)
	for net_id: int in nets_a:
		if net_id >= 0 and nets_b.has(net_id):
			return true
	return false


## Returns the road cells belonging to `component_id`.
func get_network_road_cells(component_id: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if grid == null:
		return cells
	_ensure_cache()
	if _components.has(component_id):
		cells.assign(_components[component_id])
	return cells


func invalidate() -> void:
	_cache_dirty = true


func clear_cache() -> void:
	_road_connected.clear()
	_road_component_by_cell.clear()
	_components.clear()
	_building_network_id.clear()
	_building_network_ids.clear()
	_cache_dirty = true


## Refresh known neighboring cells when the cache is already current. GridManager's
## tile_changed signal normally does this automatically; this public bridge is safe
## for callers that explicitly request a refresh after a placement operation.
func refresh_around(center: Vector2i) -> void:
	if _cache_dirty:
		return
	if _is_in_bounds(center):
		var is_now_road: bool = _is_road_tile(grid.get_tile_type(center))
		var was_road: bool = _road_component_by_cell.has(center)
		if is_now_road != was_road:
			_cache_dirty = true
			return
	_refresh_cached_position(center)
	for offset: Vector2i in CARDINAL_OFFSETS:
		_refresh_cached_position(center + offset)


func _ensure_cache() -> void:
	if not _cache_dirty:
		return
	_road_connected.clear()
	_road_component_by_cell.clear()
	_components.clear()
	_building_network_id.clear()
	_building_network_ids.clear()

	# 1) Build 4-connected road network components in deterministic grid-scan order.
	var next_component_id: int = 0
	for x: int in range(grid_size):
		for y: int in range(grid_size):
			var start_cell: Vector2i = Vector2i(x, y)
			if not _is_road_tile(grid.get_tile_type(start_cell)) \
					or _road_component_by_cell.has(start_cell):
				continue
			var component_cells: Array[Vector2i] = []
			var queue: Array[Vector2i] = [start_cell]
			var queue_index: int = 0
			_road_component_by_cell[start_cell] = next_component_id
			while queue_index < queue.size():
				var current: Vector2i = queue[queue_index]
				queue_index += 1
				component_cells.append(current)
				for offset: Vector2i in CARDINAL_OFFSETS:
					var neighbor: Vector2i = current + offset
					if not _is_in_bounds(neighbor) \
							or not _is_road_tile(grid.get_tile_type(neighbor)) \
							or _road_component_by_cell.has(neighbor):
						continue
					_road_component_by_cell[neighbor] = next_component_id
					queue.append(neighbor)
			_components[next_component_id] = component_cells
			next_component_id += 1

	# 2) Cache building road adjacency and road network membership.
	for pos: Vector2i in grid.get_all_occupied_positions():
		if _is_connectivity_building(grid.get_tile_type(pos)):
			_refresh_cached_position(pos)
	_cache_dirty = false


func _refresh_cached_position(pos: Vector2i) -> void:
	if not _is_in_bounds(pos):
		return
	if _is_connectivity_building(grid.get_tile_type(pos)):
		var net_ids: Array[int] = _compute_adjacent_network_ids(pos)
		_road_connected[pos] = not net_ids.is_empty()
		_building_network_ids[pos] = net_ids
		_building_network_id[pos] = net_ids[0] if not net_ids.is_empty() else -1
	else:
		_road_connected.erase(pos)
		_building_network_ids.erase(pos)
		_building_network_id.erase(pos)


func _compute_adjacent_network_ids(pos: Vector2i) -> Array[int]:
	var net_ids: Array[int] = []
	for offset: Vector2i in CARDINAL_OFFSETS:
		var neighbor: Vector2i = pos + offset
		if not _road_component_by_cell.has(neighbor):
			continue
		var net_id: int = int(_road_component_by_cell[neighbor])
		if not net_ids.has(net_id):
			net_ids.append(net_id)
	return net_ids


func _has_adjacent_road(pos: Vector2i) -> bool:
	for offset: Vector2i in CARDINAL_OFFSETS:
		var neighbor: Vector2i = pos + offset
		if not _is_in_bounds(neighbor):
			continue
		if _is_road_tile(grid.get_tile_type(neighbor)):
			return true
	return false


func _is_road_tile(tile_type: int) -> bool:
	return tile_type == GridCellData.TileType.ROAD \
			or tile_type == GridCellData.TileType.ROAD_CROSS


func _is_connectivity_building(tile_type: int) -> bool:
	return tile_type == GridCellData.TileType.RESIDENTIAL_LOW \
			or tile_type == GridCellData.TileType.RESIDENTIAL_HIGH \
			or tile_type == GridCellData.TileType.INDUSTRIAL \
			or tile_type == GridCellData.TileType.FARMHOUSE \
			or tile_type == GridCellData.TileType.WATER_TOWER_SMALL \
			or tile_type == GridCellData.TileType.WATER_TOWER_LARGE


func _is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_size and pos.y >= 0 and pos.y < grid_size


func _on_tile_changed(changed_pos: Vector2i) -> void:
	if _cache_dirty:
		return
	if _is_in_bounds(changed_pos):
		var is_now_road: bool = _is_road_tile(grid.get_tile_type(changed_pos))
		var was_road: bool = _road_component_by_cell.has(changed_pos)
		if is_now_road or was_road:
			_cache_dirty = true
			return
	_refresh_cached_position(changed_pos)
	for offset: Vector2i in CARDINAL_OFFSETS:
		_refresh_cached_position(changed_pos + offset)


func _on_grid_cleared() -> void:
	clear_cache()
