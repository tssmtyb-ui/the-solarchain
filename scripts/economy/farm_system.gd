class_name FarmSystem
extends RefCounted
## Assigns nearby wheat fields to road-connected Farmhouse HQs and calculates
## their shared-pool goods output. Each field belongs to one closest eligible HQ.

const FARMLAND_RADIUS: int = 3
const MAX_PRODUCTIVE_FIELDS_PER_FARMHOUSE: int = 6
const GOODS_PER_FIELD_PER_TICK: int = 1


## True when at least one Farmhouse is within the Manhattan work radius.
func is_near_farmhouse(grid: GridManager, field_pos: Vector2i) -> bool:
	for pos: Vector2i in grid.get_all_occupied_positions():
		if grid.get_tile_type(pos) != GridCellData.TileType.FARMHOUSE:
			continue
		if _manhattan_distance(field_pos, pos) <= FARMLAND_RADIUS:
			return true
	return false


## Assigns fields to their nearest road-connected Farmhouse, up to each HQ's
## productive-field capacity. Equal-distance ties resolve by x then y.
func get_connected_farmhouse_field_counts(
		grid: GridManager, road_connectivity: RoadConnectivityManager) -> Dictionary:
	var farmhouses: Array[Vector2i] = []
	for pos: Vector2i in grid.get_all_occupied_positions():
		if grid.get_tile_type(pos) == GridCellData.TileType.FARMHOUSE \
				and road_connectivity != null \
				and road_connectivity.is_road_connected(pos):
			farmhouses.append(pos)
	farmhouses.sort_custom(_position_precedes)

	var field_counts: Dictionary = {}
	for farmhouse_pos: Vector2i in farmhouses:
		field_counts[farmhouse_pos] = 0

	var fields: Array[Vector2i] = []
	for pos: Vector2i in grid.get_all_occupied_positions():
		if grid.get_tile_type(pos) == GridCellData.TileType.FARMLAND:
			fields.append(pos)
	fields.sort_custom(_position_precedes)

	for field_pos: Vector2i in fields:
		var nearest_farmhouse: Vector2i = Vector2i(-1, -1)
		var nearest_distance: int = FARMLAND_RADIUS + 1
		for farmhouse_pos: Vector2i in farmhouses:
			if int(field_counts[farmhouse_pos]) >= MAX_PRODUCTIVE_FIELDS_PER_FARMHOUSE:
				continue
			var distance: int = _manhattan_distance(field_pos, farmhouse_pos)
			if distance > FARMLAND_RADIUS or distance >= nearest_distance:
				continue
			nearest_distance = distance
			nearest_farmhouse = farmhouse_pos
		if nearest_farmhouse != Vector2i(-1, -1):
			field_counts[nearest_farmhouse] = int(field_counts[nearest_farmhouse]) + 1
	return field_counts


## Output scales with fields, with a per-farm cap to avoid unlimited production.
func goods_for_field_count(field_count: int) -> int:
	return mini(maxi(field_count, 0), MAX_PRODUCTIVE_FIELDS_PER_FARMHOUSE) \
			* GOODS_PER_FIELD_PER_TICK


func _manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _position_precedes(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y
