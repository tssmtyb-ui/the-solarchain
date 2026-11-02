class_name MapInputController
extends Node2D
## Owns map hover, player build-tool selection, and map input routing.
## PlacementController remains the authority for placement rules and world writes.

const BULLDOZE: int = -1
const HIGHLIGHT_TEXTURE: Texture2D = preload("res://assets/generated/highlight_diamond_clean.png")
const FACTORY_TEXTURE: Texture2D = preload("res://assets/factory/FactoryC.png")
const BULLDOZE_ACTIVE_TEXTURE: Texture2D = preload("res://Ui/Switch01.png")
const BULLDOZE_INACTIVE_TEXTURE: Texture2D = preload("res://Ui/Switch02.png")
const WATER_TOWER_SMALL_TEXTURE: Texture2D = preload("res://watertower/waterTowerA.png")
const WATER_TOWER_LARGE_TEXTURE: Texture2D = preload("res://watertower/waterTowerB.png")

signal hover_cell_changed(cell: Vector2i)
signal money_value_changed(new_money: int)
signal money_display_refresh_requested
signal build_committed(grid_pos: Vector2i, existing_type: int, result: Dictionary)
signal road_connection_refresh_requested(grid_pos: Vector2i)
signal drag_ui_refresh_requested
signal park_factory_heatmap_auto_mode_requested(is_enabled: bool)
signal heatmap_toggle_requested

var grid: GridManager
var tilemap: TileMapLayer
var hover_layer: Node2D
var placement_controller: PlacementController
var placement: BuildingPlacement
var grid_size: int = 20
var current_build_mode: int = GridCellData.TileType.EMPTY
var _build_bar: HBoxContainer
var _money_provider: Callable
var _input_allowed: Callable
var _hover_sprite: Sprite2D
var _last_hovered_cell: Vector2i = Vector2i(-1, -1)
var _road_drag_active: bool = false
var _last_drag_cell: Vector2i = Vector2i(-1, -1)
var _sludge_drag_active: bool = false
var _last_sludge_drag_cell: Vector2i = Vector2i(-1, -1)
var _is_configured: bool = false
var _tool_base_tooltips: Dictionary = {}
var _tool_tile_types: Dictionary = {}


func configure(
		world_grid: GridManager,
		world_tilemap: TileMapLayer,
		world_hover_layer: Node2D,
		build_bar: HBoxContainer,
		build_service: PlacementController,
		building_placement: BuildingPlacement,
		world_grid_size: int,
		money_provider: Callable,
		input_allowed: Callable) -> void:
	grid = world_grid
	tilemap = world_tilemap
	hover_layer = world_hover_layer
	_build_bar = build_bar
	placement_controller = build_service
	placement = building_placement
	grid_size = world_grid_size
	_money_provider = money_provider
	_input_allowed = input_allowed
	_setup_hover_sprite()
	_connect_build_tools()
	_is_configured = true


func get_hovered_cell() -> Vector2i:
	return _last_hovered_cell


func rasterize_line(start: Vector2i, finish: Vector2i) -> Array[Vector2i]:
	return _line_between(start, finish)


func cancel_drag() -> void:
	_road_drag_active = false
	_last_drag_cell = Vector2i(-1, -1)
	_sludge_drag_active = false
	_last_sludge_drag_cell = Vector2i(-1, -1)


func _setup_hover_sprite() -> void:
	_hover_sprite = Sprite2D.new()
	_hover_sprite.texture = HIGHLIGHT_TEXTURE
	_hover_sprite.centered = true
	_hover_sprite.z_index = 100
	hover_layer.add_child(_hover_sprite)


func _connect_build_tools() -> void:
	_ensure_water_tower_buttons()
	_connect_tool("RoadToggle", GridCellData.TileType.ROAD, "Build Road")
	_connect_tool("FactoryToggle", GridCellData.TileType.INDUSTRIAL, "Build Factory")
	_connect_tool("WarehouseToggle", GridCellData.TileType.WAREHOUSE, "Build Warehouse")
	_connect_tool("ResidentialToggle", GridCellData.TileType.RESIDENTIAL_LOW, "Build Residential")
	_connect_tool("ParkToggle", GridCellData.TileType.PARK, "Build Park")
	_connect_tool("SludgeToggle", GridCellData.TileType.SLUDGE, "Build Sludge Line")
	_connect_tool("FarmhouseToggle", GridCellData.TileType.FARMHOUSE, "Build Farmhouse HQ — must touch a road")
	_connect_tool("FarmlandToggle", GridCellData.TileType.FARMLAND, "Build Wheat Farmland — within 3 tiles of a Farmhouse")
	_connect_tool("WaterTowerSmallToggle", GridCellData.TileType.WATER_TOWER_SMALL, "Build Small Water Tower ($200, +30 Water) — place on/adjacent to water & road")
	_connect_tool("WaterTowerLargeToggle", GridCellData.TileType.WATER_TOWER_LARGE, "Build Large Water Tower ($500, +80 Water) — place on/adjacent to water & road")
	_connect_tool("BulldozeToggle", BULLDOZE, "Bulldozer (Demolish)")


func _ensure_water_tower_buttons() -> void:
	if _build_bar == null:
		return
	var group: ButtonGroup = null
	var road_btn: TextureButton = _build_bar.get_node_or_null("RoadToggle") as TextureButton
	if road_btn != null:
		group = road_btn.button_group
	var bulldoze_btn: Node = _build_bar.get_node_or_null("BulldozeToggle")
	if _build_bar.get_node_or_null("WaterTowerSmallToggle") == null:
		var small_btn := TextureButton.new()
		small_btn.name = "WaterTowerSmallToggle"
		small_btn.custom_minimum_size = Vector2(56, 56)
		small_btn.toggle_mode = true
		small_btn.button_group = group
		small_btn.texture_normal = WATER_TOWER_SMALL_TEXTURE
		small_btn.texture_pressed = WATER_TOWER_SMALL_TEXTURE
		small_btn.ignore_texture_size = true
		small_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		_build_bar.add_child(small_btn)
		if bulldoze_btn != null:
			_build_bar.move_child(small_btn, bulldoze_btn.get_index())
	if _build_bar.get_node_or_null("WaterTowerLargeToggle") == null:
		var large_btn := TextureButton.new()
		large_btn.name = "WaterTowerLargeToggle"
		large_btn.custom_minimum_size = Vector2(56, 56)
		large_btn.toggle_mode = true
		large_btn.button_group = group
		large_btn.texture_normal = WATER_TOWER_LARGE_TEXTURE
		large_btn.texture_pressed = WATER_TOWER_LARGE_TEXTURE
		large_btn.ignore_texture_size = true
		large_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		_build_bar.add_child(large_btn)
		if bulldoze_btn != null:
			_build_bar.move_child(large_btn, bulldoze_btn.get_index())


func _connect_tool(button_name: String, tile_type: int, tooltip: String) -> void:
	var tool_button: TextureButton = _build_bar.get_node_or_null(button_name) as TextureButton
	if tool_button == null:
		return
	_tool_base_tooltips[button_name] = tooltip
	_tool_tile_types[button_name] = tile_type
	tool_button.tooltip_text = tooltip
	if not tool_button.toggled.is_connected(_on_tool_toggled):
		tool_button.toggled.connect(_on_tool_toggled.bind(tile_type, button_name))


func apply_town_progression_locks(progression: TownProgressionManager) -> void:
	if _build_bar == null or progression == null:
		return
	for button_name_variant: Variant in _tool_tile_types.keys():
		var button_name: String = str(button_name_variant)
		var tile_type: int = int(_tool_tile_types[button_name])
		var tool_button: TextureButton = _build_bar.get_node_or_null(button_name) as TextureButton
		if tool_button == null:
			continue
		var base_tooltip: String = str(_tool_base_tooltips.get(button_name, tool_button.tooltip_text))
		if tile_type == BULLDOZE or progression.is_tile_type_unlocked(tile_type):
			tool_button.disabled = false
			tool_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
			tool_button.tooltip_text = base_tooltip
		else:
			tool_button.disabled = true
			tool_button.modulate = Color(0.45, 0.45, 0.50, 0.65)
			var req_text: String = progression.get_lock_requirement_text(tile_type)
			tool_button.tooltip_text = "%s — Locked (%s)" % [base_tooltip, req_text]


func _map_cell_at_pointer() -> Vector2i:
	var viewport_mouse: Vector2 = get_viewport().get_mouse_position()
	var map_local: Vector2 = tilemap.get_global_transform_with_canvas().affine_inverse() \
			* viewport_mouse
	return tilemap.local_to_map(map_local)


func _process(_delta: float) -> void:
	if not _is_configured:
		return
	var cell: Vector2i = _map_cell_at_pointer()
	if not _is_in_grid(cell):
		_hover_sprite.visible = false
		if _last_hovered_cell != Vector2i(-1, -1):
			_last_hovered_cell = Vector2i(-1, -1)
			hover_cell_changed.emit(cell)
		return

	var local: Vector2 = tilemap.map_to_local(cell)
	_hover_sprite.visible = true
	if cell != _last_hovered_cell:
		_hover_sprite.position = hover_layer.to_local(tilemap.to_global(local))
		_last_hovered_cell = cell
		hover_cell_changed.emit(cell)

	if _road_drag_active:
		_process_road_drag(cell)
	if _sludge_drag_active:
		_process_sludge_drag(cell)


func _input(event: InputEvent) -> void:
	if not _is_configured:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_V:
		heatmap_toggle_requested.emit()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_configured or not _is_input_allowed():
		return

	if event is InputEventMouseButton and not event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		cancel_drag()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_5:
				(_build_bar.get_node("ParkToggle") as TextureButton).set_pressed(true)
				return
			KEY_6:
				(_build_bar.get_node("SludgeToggle") as TextureButton).set_pressed(true)
				return

	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var grid_pos: Vector2i = _map_cell_at_pointer()
	if not _is_in_grid(grid_pos):
		return
	if current_build_mode == GridCellData.TileType.EMPTY:
		prints("No tool selected — toggle Road or Factory button first.")
		return

	if current_build_mode == GridCellData.TileType.ROAD:
		_road_drag_active = true
		_last_drag_cell = grid_pos
	elif current_build_mode == GridCellData.TileType.SLUDGE:
		_sludge_drag_active = true
		_last_sludge_drag_cell = grid_pos

	_attempt_build_at(grid_pos)


func _attempt_build_at(grid_pos: Vector2i) -> void:
	var existing: int = grid.get_tile_type(grid_pos)
	var result: Dictionary
	if current_build_mode == BULLDOZE:
		result = placement_controller.attempt_bulldoze(grid_pos, _current_money())
	else:
		result = placement_controller.attempt_build(
				current_build_mode, grid_pos, _current_money())
	if not bool(result["ok"]):
		var reason: String = str(result["reason"])
		if reason != "":
			prints(reason)
		return
	money_value_changed.emit(int(result["money"]))
	money_display_refresh_requested.emit()
	build_committed.emit(grid_pos, existing, result)


func _process_road_drag(target: Vector2i) -> void:
	if target == _last_drag_cell:
		return
	var money: int = _current_money()
	var path: Array[Vector2i] = _line_between(_last_drag_cell, target)
	for i in range(1, path.size()):
		var step: Vector2i = path[i]
		var result: Dictionary = placement_controller.attempt_build(
				GridCellData.TileType.ROAD, step, money)
		if bool(result["ok"]):
			money = int(result["money"])
			money_value_changed.emit(money)
			road_connection_refresh_requested.emit(step)
		elif str(result["reason"]) == "Not enough money!":
			break
	_last_drag_cell = target
	money_display_refresh_requested.emit()
	drag_ui_refresh_requested.emit()


func _process_sludge_drag(target: Vector2i) -> void:
	if target == _last_sludge_drag_cell:
		return
	var money: int = _current_money()
	var path: Array[Vector2i] = _line_between(_last_sludge_drag_cell, target)
	for i in range(1, path.size()):
		var step: Vector2i = path[i]
		var result: Dictionary = placement_controller.attempt_build(
				GridCellData.TileType.SLUDGE, step, money)
		if bool(result["ok"]):
			money = int(result["money"])
			money_value_changed.emit(money)
			road_connection_refresh_requested.emit(step)
		elif str(result["reason"]) == "Not enough money!":
			break
	_last_sludge_drag_cell = target
	money_display_refresh_requested.emit()
	drag_ui_refresh_requested.emit()


func _line_between(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var x0: int = a.x
	var y0: int = a.y
	var x1: int = b.x
	var y1: int = b.y
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	while true:
		cells.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
	return cells


func _on_tool_toggled(toggled_on: bool, tile_type: int, button_name: String) -> void:
	if toggled_on:
		current_build_mode = tile_type
		if button_name == "FactoryToggle":
			(_build_bar.get_node(button_name) as TextureButton).texture_normal = FACTORY_TEXTURE
		elif button_name == "BulldozeToggle":
			(_build_bar.get_node(button_name) as TextureButton).texture_normal = BULLDOZE_ACTIVE_TEXTURE
		_unpress_other_toggles(button_name)
		park_factory_heatmap_auto_mode_requested.emit(
				button_name == "FactoryToggle" or button_name == "ParkToggle")
		prints("Build mode: %s" % _mode_name(tile_type))
	else:
		current_build_mode = GridCellData.TileType.EMPTY
		if button_name == "FactoryToggle":
			(_build_bar.get_node(button_name) as TextureButton).texture_normal = FACTORY_TEXTURE
		elif button_name == "BulldozeToggle":
			(_build_bar.get_node(button_name) as TextureButton).texture_normal = BULLDOZE_INACTIVE_TEXTURE
		park_factory_heatmap_auto_mode_requested.emit(false)
		prints("Build mode: OFF")


func _mode_name(tile_type: int) -> String:
	if tile_type == BULLDOZE:
		return "BULLDOZE"
	return GridCellData.TileType.keys()[tile_type]


func _unpress_other_toggles(except_name: String) -> void:
	for child: Node in _build_bar.get_children():
		if child is TextureButton and child.name != except_name \
				and (child as TextureButton).button_pressed:
			(child as TextureButton).set_pressed_no_signal(false)


func _current_money() -> int:
	if not _money_provider.is_valid():
		return 0
	return int(_money_provider.call())


func _is_input_allowed() -> bool:
	if not _input_allowed.is_valid():
		return false
	return bool(_input_allowed.call())


func _is_in_grid(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_size and pos.y >= 0 and pos.y < grid_size
