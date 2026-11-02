class_name LandValueHeatmap
extends Node
## Maintains per-cell isometric heatmap polygons beneath y-sorted building sprites.

const VALUE_HIGH_MIN: int = 30
const VALUE_MEDIUM_MIN: int = 18

const HIGH_VALUE_COLOR: Color = Color(0.18, 0.9, 0.38, 0.48)
const MEDIUM_VALUE_COLOR: Color = Color(1.0, 0.82, 0.18, 0.48)
const LOW_VALUE_COLOR: Color = Color(0.96, 0.18, 0.2, 0.52)
const POLLUTION_RISK_COLOR: Color = Color(0.65, 0.2, 0.88, 0.58)
const SPECULATOR_LOT_COLOR: Color = Color(0.98, 0.52, 0.12, 0.64)

const INSET: float = 3.0

var grid: GridManager
var economy: EconomyManager
var tilemap: TileMapLayer
var speculator_manager: SpeculatorManager
var grid_size: int = 20
var _is_heatmap_visible: bool = false
var _colors_dirty: bool = true
var _color_update_pending: bool = false
var _cell_polygons: Array[Polygon2D] = []
var _cell_positions: Array[Vector2i] = []


## Receives the live city systems and subscribes to every heatmap input source.
func configure(
		grid_manager: GridManager,
		economy_manager: EconomyManager,
		world_tilemap: TileMapLayer,
		world_grid_size: int) -> void:
	grid = grid_manager
	economy = economy_manager
	tilemap = world_tilemap
	grid_size = world_grid_size
	if not grid.grid_changed.is_connected(_on_grid_changed):
		grid.grid_changed.connect(_on_grid_changed)
	_create_cell_polygons()
	_mark_colors_dirty()


## Creates one y-sorted ground diamond per cell so building sprites remain crisp.
func _create_cell_polygons() -> void:
	if tilemap == null or tilemap.tile_set == null:
		push_error("LandValueHeatmap requires a TileMapLayer with a TileSet.")
		return

	for polygon: Polygon2D in _cell_polygons:
		if is_instance_valid(polygon):
			polygon.queue_free()
	_cell_polygons.clear()
	_cell_positions.clear()

	var tile_size: Vector2 = Vector2(tilemap.tile_set.tile_size)
	var half_width: float = tile_size.x * 0.5
	var half_height: float = tile_size.y * 0.5
	var diamond: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, -half_height + INSET * 0.5),
		Vector2(half_width - INSET, 0.0),
		Vector2(0.0, half_height - INSET * 0.5),
		Vector2(-half_width + INSET, 0.0),
	])
	for x in range(grid_size):
		for y in range(grid_size):
			var cell: Vector2i = Vector2i(x, y)
			var polygon: Polygon2D = Polygon2D.new()
			polygon.name = "LandValue_%d_%d" % [x, y]
			polygon.position = tilemap.map_to_local(cell)
			polygon.polygon = diamond
			polygon.color = LOW_VALUE_COLOR
			polygon.z_index = 0
			polygon.z_as_relative = true
			polygon.y_sort_enabled = true
			polygon.visible = _is_heatmap_visible
			tilemap.add_child(polygon)
			_cell_polygons.append(polygon)
			_cell_positions.append(cell)


## Grid changes invalidate colors; hidden overlays defer all color queries.
func _on_grid_changed() -> void:
	_mark_colors_dirty()


func _mark_colors_dirty() -> void:
	_colors_dirty = true
	if _is_heatmap_visible:
		_schedule_color_update()


## Coalesces visible refreshes and avoids scheduling work while hidden.
func _schedule_color_update() -> void:
	if not _is_heatmap_visible or not _colors_dirty or _color_update_pending:
		return
	_color_update_pending = true
	call_deferred("_update_cell_colors")


func _update_cell_colors() -> void:
	_color_update_pending = false
	if not _is_heatmap_visible or not _colors_dirty:
		return
	for i in range(_cell_polygons.size()):
		var polygon: Polygon2D = _cell_polygons[i]
		if not is_instance_valid(polygon):
			continue
		polygon.color = _color_for_cell(_cell_positions[i], grid.get_tile_type(_cell_positions[i]))
	_colors_dirty = false


## Shows the overlay and refreshes once if hidden-time grid changes made it dirty.
func set_heatmap_visible(show_heatmap: bool) -> void:
	if _is_heatmap_visible == show_heatmap:
		return
	_is_heatmap_visible = show_heatmap
	for polygon: Polygon2D in _cell_polygons:
		if is_instance_valid(polygon):
			polygon.visible = show_heatmap
	if show_heatmap:
		_schedule_color_update()


func is_heatmap_visible() -> bool:
	return _is_heatmap_visible


func set_speculator_manager(manager: SpeculatorManager) -> void:
	speculator_manager = manager
	if speculator_manager != null and not speculator_manager.lots_changed.is_connected(_on_grid_changed):
		speculator_manager.lots_changed.connect(_on_grid_changed)
	_mark_colors_dirty()


func _color_for_cell(cell: Vector2i, _tile_type: int) -> Color:
	if speculator_manager != null and speculator_manager.is_speculator_owned(cell):
		return SPECULATOR_LOT_COLOR
	if economy.is_within_pollution_risk(cell):
		return POLLUTION_RISK_COLOR
	var land_value: int = economy.get_land_value(cell)
	if land_value >= VALUE_HIGH_MIN:
		return HIGH_VALUE_COLOR
	if land_value >= VALUE_MEDIUM_MIN:
		return MEDIUM_VALUE_COLOR
	return LOW_VALUE_COLOR
