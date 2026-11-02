extends Node


func _instantiate_game() -> Node:
	var game_scene: PackedScene = load("res://node_2d.tscn") as PackedScene
	assert(game_scene != null, "Could not load the gameplay scene.")
	var game: Node = game_scene.instantiate()
	get_tree().root.add_child(game)
	await get_tree().process_frame
	return game


func test_game_scene_wires_dedicated_map_input_controller() -> void:
	var game: Node = await _instantiate_game()
	var controller: MapInputController = game.get_node("MapInputController") as MapInputController
	assert(controller != null, "Gameplay scene should own a MapInputController.")
	assert(controller.placement_controller == game.get_node("PlacementController"),
			"Input controller must delegate placement to PlacementController.")
	assert(controller.get_hovered_cell() == Vector2i(-1, -1),
			"Hover controller should start without a hovered grid cell.")
	assert(controller.rasterize_line(Vector2i(2, 2), Vector2i(6, 2)) == [
		Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2),
	], "Horizontal drag rasterization should include each intermediate cell.")
	assert(controller.rasterize_line(Vector2i(1, 1), Vector2i(4, 4)) == [
		Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 4),
	], "Diagonal drag rasterization should remain gap-free.")
	game.queue_free()
	await get_tree().process_frame


func test_tool_selection_mutual_exclusion_and_heatmap_auto_mode() -> void:
	var game: Node = await _instantiate_game()
	var controller: MapInputController = game.get_node("MapInputController") as MapInputController
	var build_bar: HBoxContainer = game.get_node("UI/BuildBar/HBoxContainer") as HBoxContainer
	var factory_toggle: TextureButton = build_bar.get_node("FactoryToggle") as TextureButton
	var road_toggle: TextureButton = build_bar.get_node("RoadToggle") as TextureButton
	var park_toggle: TextureButton = build_bar.get_node("ParkToggle") as TextureButton

	factory_toggle.set_pressed(true)
	assert(controller.current_build_mode == GridCellData.TileType.INDUSTRIAL,
			"Selecting Factory should update the active tool.")
	assert(bool(game.call("is_heatmap_effectively_visible")),
			"Factory selection should retain automatic heatmap behavior.")
	road_toggle.set_pressed(true)
	assert(controller.current_build_mode == GridCellData.TileType.ROAD,
			"Selecting Road should replace the active tool.")
	assert(not factory_toggle.button_pressed and road_toggle.button_pressed,
			"Tool buttons should remain mutually exclusive.")
	assert(not bool(game.call("is_heatmap_effectively_visible")),
			"Selecting Road should disable the Factory/Park heatmap auto mode.")
	park_toggle.set_pressed(true)
	assert(controller.current_build_mode == GridCellData.TileType.PARK,
			"Selecting Park should update the active tool.")
	assert(bool(game.call("is_heatmap_effectively_visible")),
			"Park selection should show the heatmap.")
	game.queue_free()
	await get_tree().process_frame


func test_controller_delegates_road_drag_build_and_bulldoze() -> void:
	var game: Node = await _instantiate_game()
	var controller: MapInputController = game.get_node("MapInputController") as MapInputController
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var start: Vector2i = Vector2i(4, 6)
	var end: Vector2i = Vector2i(7, 6)
	var initial_money: int = int(game.get("current_money"))

	controller.current_build_mode = GridCellData.TileType.ROAD
	controller.call("_attempt_build_at", start)
	controller.set("_road_drag_active", true)
	controller.set("_last_drag_cell", start)
	controller.call("_process_road_drag", end)
	for x: int in range(start.x, end.x + 1):
		assert(grid.get_tile_type(Vector2i(x, start.y)) == GridCellData.TileType.ROAD,
				"Road drag should fill every crossed cell.")
	assert(int(game.get("current_money")) == initial_money - 40,
			"The start cell and three drag cells should each charge the road cost.")

	controller.current_build_mode = MapInputController.BULLDOZE
	controller.call("_attempt_build_at", Vector2i(5, 6))
	assert(grid.get_tile_type(Vector2i(5, 6)) == GridCellData.TileType.GRASS,
			"Bulldoze should delegate demolition and restore grass.")
	assert(int(game.get("current_money")) == initial_money - 40,
			"Bulldozing should not charge or refund money.")
	game.queue_free()
	await get_tree().process_frame


func test_sludge_drag_uses_gap_free_line_and_charges_per_tile() -> void:
	var game: Node = await _instantiate_game()
	var controller: MapInputController = game.get_node("MapInputController") as MapInputController
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var start: Vector2i = Vector2i(4, 8)
	var finish: Vector2i = Vector2i(7, 8)
	var initial_money: int = int(game.get("current_money"))

	controller.current_build_mode = GridCellData.TileType.SLUDGE
	controller.call("_attempt_build_at", start)
	controller.set("_sludge_drag_active", true)
	controller.set("_last_sludge_drag_cell", start)
	controller.call("_process_sludge_drag", finish)
	for x: int in range(start.x, finish.x + 1):
		assert(grid.get_tile_type(Vector2i(x, start.y)) == GridCellData.TileType.SLUDGE,
				"Sludge drag should fill every crossed cell.")
	assert(int(game.get("current_money")) == initial_money - 40,
			"The start cell and three drag cells should each charge the sludge cost.")
	game.queue_free()
	await get_tree().process_frame


func test_ground_tiles_allow_unrestricted_player_building() -> void:
	var game: Node = await _instantiate_game()
	var controller: MapInputController = game.get_node("MapInputController") as MapInputController
	var placement_controller: PlacementController = game.get_node("PlacementController") as PlacementController
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var camera: Camera2D = game.get_node("Camera2D") as Camera2D
	assert(int(game.get("GRID_SIZE")) == 30, "Expanded map should use a 30x30 grid.")
	assert(camera.limit_left < camera.limit_right and camera.limit_top < camera.limit_bottom,
			"Camera limits should be configured for the expanded map.")

	var position: Vector2i = Vector2i(8, 8)
	var initial_money: int = int(game.get("current_money"))
	grid.set_tile(position, GridCellData.new(GridCellData.TileType.DIRT))

	controller.current_build_mode = GridCellData.TileType.ROAD
	controller.call("_attempt_build_at", position)
	assert(grid.get_tile_type(position) == GridCellData.TileType.ROAD,
			"Player should be able to build freely on ground tiles without speculator restrictions.")
	assert(int(game.get("current_money")) == initial_money - 10,
			"Building on ground tiles should charge only the standard building cost.")

	# Verify water tiles cannot be built upon or demolished.
	var water_pos: Vector2i = Vector2i(22, 22)
	assert(grid.get_tile_type(water_pos) == GridCellData.TileType.WATER,
			"Expanded map should include distinct WATER ground tiles.")
	var water_build: Dictionary = placement_controller.attempt_build(
			GridCellData.TileType.ROAD, water_pos, int(game.get("current_money")))
	assert(not bool(water_build["ok"]) and str(water_build["reason"]).contains("water"),
			"Standard buildings must be rejected on water tiles.")
	assert(grid.get_tile_type(water_pos) == GridCellData.TileType.WATER,
			"Rejected placement must leave the water tile intact.")
	game.queue_free()
	await get_tree().process_frame


func test_water_tower_placement_rules_and_bulldoze_restoration() -> void:
	var game: Node = await _instantiate_game()
	var controller: MapInputController = game.get_node("MapInputController") as MapInputController
	var placement_controller: PlacementController = game.get_node("PlacementController") as PlacementController
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var build_bar: HBoxContainer = game.get_node("UI/BuildBar/HBoxContainer") as HBoxContainer

	var small_toggle: TextureButton = build_bar.get_node("WaterTowerSmallToggle") as TextureButton
	var large_toggle: TextureButton = build_bar.get_node("WaterTowerLargeToggle") as TextureButton
	assert(small_toggle != null and large_toggle != null,
			"BuildBar should expose Small and Large Water Tower buttons.")
	small_toggle.set_pressed(true)
	assert(controller.current_build_mode == GridCellData.TileType.WATER_TOWER_SMALL,
			"Small Water Tower button should select WATER_TOWER_SMALL mode.")
	large_toggle.set_pressed(true)
	assert(controller.current_build_mode == GridCellData.TileType.WATER_TOWER_LARGE,
			"Large Water Tower button should select WATER_TOWER_LARGE mode.")

	# 1) Reject inland placement away from water (even with a road).
	grid.set_tile(Vector2i(5, 4), GridCellData.new(GridCellData.TileType.ROAD))
	var inland_res: Dictionary = placement_controller.attempt_build(
			GridCellData.TileType.WATER_TOWER_SMALL, Vector2i(5, 5), 1000)
	assert(not bool(inland_res["ok"]) and str(inland_res["reason"]).contains("water"),
			"Water Tower away from water must be rejected.")

	# 2) Reject placement on water without an adjacent road.
	var water_cell: Vector2i = Vector2i(22, 22)
	var no_road_res: Dictionary = placement_controller.attempt_build(
			GridCellData.TileType.WATER_TOWER_SMALL, water_cell, 1000)
	assert(not bool(no_road_res["ok"]) and str(no_road_res["reason"]).contains("road"),
			"Water Tower on water without an adjacent road must be rejected.")

	# 3) Place road adjacent to water_cell (22, 21) -> build Small Water Tower ($200) on water_cell.
	grid.set_tile(Vector2i(22, 21), GridCellData.new(GridCellData.TileType.ROAD))
	var on_water_res: Dictionary = placement_controller.attempt_build(
			GridCellData.TileType.WATER_TOWER_SMALL, water_cell, 1000)
	assert(bool(on_water_res["ok"]) and int(on_water_res["money"]) == 800,
			"Small Water Tower on water adjacent to a road should succeed and cost $200.")
	assert(grid.get_tile_type(water_cell) == GridCellData.TileType.WATER_TOWER_SMALL,
			"Grid should record WATER_TOWER_SMALL at the water cell.")

	# 4) Place Large Water Tower ($500) on shoreline land (21, 22) adjacent to water (22, 22) and road (21, 21).
	grid.set_tile(Vector2i(21, 21), GridCellData.new(GridCellData.TileType.ROAD))
	var shoreline_cell: Vector2i = Vector2i(21, 22)
	var on_shore_res: Dictionary = placement_controller.attempt_build(
			GridCellData.TileType.WATER_TOWER_LARGE, shoreline_cell, 800)
	assert(bool(on_shore_res["ok"]) and int(on_shore_res["money"]) == 300,
			"Large Water Tower on shoreline land adjacent to water and road should succeed and cost $500.")
	assert(grid.get_tile_type(shoreline_cell) == GridCellData.TileType.WATER_TOWER_LARGE,
			"Grid should record WATER_TOWER_LARGE at the shoreline cell.")

	# 5) Bulldozing the tower on water restores WATER; bulldozing shoreline tower restores GRASS.
	var demo_water: Dictionary = placement_controller.attempt_bulldoze(water_cell, 300)
	assert(bool(demo_water["ok"]) and grid.get_tile_type(water_cell) == GridCellData.TileType.WATER,
			"Bulldozing a Water Tower placed on water must restore the WATER tile.")
	var demo_shore: Dictionary = placement_controller.attempt_bulldoze(shoreline_cell, 300)
	assert(bool(demo_shore["ok"]) and grid.get_tile_type(shoreline_cell) == GridCellData.TileType.GRASS,
			"Bulldozing a Water Tower placed on shoreline land must restore GRASS.")

	game.queue_free()
	await get_tree().process_frame


func test_pause_toggle_spacebar_and_active_building_while_paused() -> void:
	var game: Node = await _instantiate_game()
	var controller: MapInputController = game.get_node("MapInputController") as MapInputController
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var economy: EconomyManager = game.get_node("EconomyManager") as EconomyManager
	var simulator: SupplyChainSimulator = game.get_node("SupplyChainSimulator") as SupplyChainSimulator
	var pause_toggle: Button = game.get_node("UI/TopBar/HBoxContainer/PauseToggle") as Button
	var pause_badge: Control = game.get_node("UI/PauseBadge") as Control

	assert(pause_toggle != null and pause_badge != null,
			"HUD should include PauseToggle button and PauseBadge indicator.")
	assert(not bool(game.call("is_simulation_paused")) and not pause_badge.visible,
			"Simulation should start unpaused.")

	# Toggle pause via Spacebar shortcut.
	var space_event: InputEventKey = InputEventKey.new()
	space_event.keycode = KEY_SPACE
	space_event.physical_keycode = KEY_SPACE
	space_event.pressed = true
	space_event.echo = false
	game.call("_unhandled_input", space_event)

	assert(bool(game.call("is_simulation_paused")),
			"Spacebar should pause the simulation.")
	assert(pause_toggle.button_pressed and pause_toggle.text == "PAUSED" and pause_badge.visible,
			"HUD should highlight the pause button and display the PAUSED badge.")
	assert(simulator.get_supply_chain_timer().paused and (economy.get_node("AssessmentTimer") as Timer).paused,
			"SupplyChainTimer and AssessmentTimer must be paused while simulation is paused.")

	# Active building and bulldozing must work 100% while paused.
	var build_cell: Vector2i = Vector2i(10, 10)
	var money_before: int = int(game.get("current_money"))
	controller.current_build_mode = GridCellData.TileType.ROAD
	controller.call("_attempt_build_at", build_cell)
	assert(grid.get_tile_type(build_cell) == GridCellData.TileType.ROAD,
			"Player must be able to place tiles while simulation is paused.")
	assert(int(game.get("current_money")) == money_before - 10,
			"Building while paused should deduct cost immediately.")

	controller.current_build_mode = MapInputController.BULLDOZE
	controller.call("_attempt_build_at", build_cell)
	assert(grid.get_tile_type(build_cell) == GridCellData.TileType.GRASS,
			"Player must be able to bulldoze tiles while simulation is paused.")

	# Unpause via PauseToggle button.
	pause_toggle.set_pressed(false)
	assert(not bool(game.call("is_simulation_paused")) and not pause_badge.visible,
			"Unpausing via PauseToggle should resume the simulation and hide the badge.")
	assert(not simulator.get_supply_chain_timer().paused and not (economy.get_node("AssessmentTimer") as Timer).paused,
			"Timers must resume when unpaused.")

	game.queue_free()
	await get_tree().process_frame


func test_map_boundary_fog_obscures_outer_void_and_preserves_edge_tiles() -> void:
	var game: Node = await _instantiate_game()
	var fog: MapBoundaryFog = game.get_node("MapBoundaryFog") as MapBoundaryFog
	var tilemap: TileMapLayer = game.get_node("TileMapLayer") as TileMapLayer
	var camera: Camera2D = game.get_node("Camera2D") as Camera2D
	var controller: MapInputController = game.get_node("MapInputController") as MapInputController
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var grid_size: int = int(game.get("GRID_SIZE"))

	assert(fog != null and fog.is_configured(),
			"Gameplay scene should instantiate and configure MapBoundaryFog.")
	assert(fog.get_fog_polygon() != null and fog.get_shader_material() != null,
			"MapBoundaryFog should own a Polygon2D with a ShaderMaterial.")
	assert(fog.z_index < 100,
			"MapBoundaryFog must render below HoverLayer (z_index = 100) and UI.")

	# Every corner and edge cell inside [0, grid_size - 1] must have 0.0 fog opacity.
	var interior_and_edge_cells: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(0, grid_size - 1),
		Vector2i(grid_size - 1, 0),
		Vector2i(grid_size - 1, grid_size - 1),
		Vector2i(0, int(grid_size * 0.5)),
		Vector2i(grid_size - 1, int(grid_size * 0.5)),
		Vector2i(int(grid_size * 0.5), int(grid_size * 0.5)),
	]
	for cell: Vector2i in interior_and_edge_cells:
		assert(is_zero_approx(fog.get_fog_opacity_at_cell(cell)),
				"Playable cell %s must have 0.0 boundary fog opacity." % [cell])

	# Outside the grid perimeter, fog opacity must ramp smoothly from > 0.0 to 1.0.
	var near_outside_opacity: float = fog.get_fog_opacity_at_cell(Vector2i(-2, 10), 1.5)
	var deep_outside_opacity: float = fog.get_fog_opacity_at_cell(Vector2i(-8, 10), 1.5)
	assert(near_outside_opacity > 0.05 and near_outside_opacity < 0.95,
			"Cells within the outer mist band should have partial animated fog opacity.")
	assert(is_equal_approx(deep_outside_opacity, 1.0),
			"Deep void cells beyond fade_tiles must be 100% obscured (opacity 1.0).")

	# Animated mist should evolve subtly over time within the transition band.
	var sample_t0: float = fog.get_fog_opacity_at_cell(Vector2i(-2, 12), 0.0)
	var sample_t1: float = fog.get_fog_opacity_at_cell(Vector2i(-2, 12), 3.5)
	assert(not is_equal_approx(sample_t0, sample_t1),
			"Mist transition band should animate over time via wind_velocity.")

	# Edge tiles must remain 100% interactive for building placement and hover inspection.
	var edge_build_cell: Vector2i = Vector2i(0, 5)
	controller.current_build_mode = GridCellData.TileType.ROAD
	controller.call("_attempt_build_at", edge_build_cell)
	assert(grid.get_tile_type(edge_build_cell) == GridCellData.TileType.ROAD,
			"Edge tiles must remain 100% buildable with MapBoundaryFog active.")

	# Dynamic scaling when reconfigured with a different grid_size.
	var rect_30: Rect2 = fog.get_coverage_rect()
	fog.configure(tilemap, 40, camera)
	assert(fog.grid_size == 40, "MapBoundaryFog should update its grid_size when reconfigured.")
	assert(fog.get_coverage_rect().size.x > rect_30.size.x,
			"Coverage polygon should expand when configured for a larger grid_size.")
	assert(is_zero_approx(fog.get_fog_opacity_at_cell(Vector2i(39, 39))),
			"Expanded edge cell (39, 39) should have 0.0 fog opacity after scaling.")
	assert(is_equal_approx(fog.get_fog_opacity_at_cell(Vector2i(48, 39)), 1.0),
			"Cells outside the expanded 40x40 perimeter should fade to 1.0.")

	game.queue_free()
	await get_tree().process_frame

