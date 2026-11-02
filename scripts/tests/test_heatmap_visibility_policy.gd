extends Node


func _instantiate_game() -> Node:
	var game_scene: PackedScene = load("res://node_2d.tscn") as PackedScene
	assert(game_scene != null, "Could not load the game scene.")
	var game: Node = game_scene.instantiate()
	get_tree().root.add_child(game)
	await get_tree().process_frame
	return game


func test_map_money_and_v_share_one_visibility_policy() -> void:
	var game: Node = await _instantiate_game()
	var map_toggle: Button = game.get_node("UI/TopBar/HBoxContainer/MapToggle") as Button
	var money_toggle: Button = game.get_node("UI/TopBar/HBoxContainer/MoneyLabel") as Button
	assert(not bool(game.call("is_heatmap_effectively_visible")), "Heatmap should start hidden.")
	map_toggle.set_pressed(true)
	assert(bool(game.call("is_heatmap_effectively_visible")), "Map activation should show the heatmap.")
	assert(money_toggle.button_pressed, "Money toggle must mirror Map activation.")
	money_toggle.set_pressed(false)
	assert(not bool(game.call("is_heatmap_effectively_visible")), "Money deactivation should hide the heatmap.")
	assert(not map_toggle.button_pressed, "Map toggle must mirror Money deactivation.")
	var key_event: InputEventKey = InputEventKey.new()
	key_event.physical_keycode = KEY_V
	key_event.keycode = KEY_V
	key_event.echo = false
	key_event.pressed = true
	(game.get_node("MapInputController") as MapInputController).call("_input", key_event)
	assert(bool(game.call("is_heatmap_effectively_visible")), "V should show the heatmap from the hidden state.")
	assert(map_toggle.button_pressed and money_toggle.button_pressed, "Both controls must mirror V activation.")
	key_event.pressed = false
	key_event.echo = false
	(game.get_node("MapInputController") as MapInputController).call("_input", key_event)
	key_event.pressed = true
	key_event.echo = false
	(game.get_node("MapInputController") as MapInputController).call("_input", key_event)
	assert(not bool(game.call("is_heatmap_effectively_visible")), "V should hide the heatmap from the visible state.")
	assert(not map_toggle.button_pressed and not money_toggle.button_pressed, "Both controls must mirror V deactivation.")
	game.queue_free()


func test_park_factory_auto_display_and_manual_suppression() -> void:
	var game: Node = await _instantiate_game()
	var map_toggle: Button = game.get_node("UI/TopBar/HBoxContainer/MapToggle") as Button
	var money_toggle: Button = game.get_node("UI/TopBar/HBoxContainer/MoneyLabel") as Button
	var factory_toggle: TextureButton = game.get_node("UI/BuildBar/HBoxContainer/FactoryToggle") as TextureButton
	var park_toggle: TextureButton = game.get_node("UI/BuildBar/HBoxContainer/ParkToggle") as TextureButton

	factory_toggle.set_pressed(true)
	assert(bool(game.call("is_heatmap_effectively_visible")), "Factory mode should auto-show the heatmap.")
	assert(map_toggle.button_pressed and money_toggle.button_pressed, "Both controls must mirror Factory auto-display.")
	game.call("_on_heatmap_toggle_toggled", false)
	assert(not bool(game.call("is_heatmap_effectively_visible")), "Manual hide should suppress Factory auto-display.")
	assert(not map_toggle.button_pressed and not money_toggle.button_pressed, "Both controls must mirror manual suppression.")
	park_toggle.set_pressed(true)
	assert(bool(game.call("is_heatmap_effectively_visible")), "Park mode should clear suppression and show the heatmap.")
	factory_toggle.set_pressed(true)
	assert(bool(game.call("is_heatmap_effectively_visible")), "Switching to Factory should keep auto-display active.")
	game.queue_free()


func test_pause_temporarily_hides_without_clearing_user_preference() -> void:
	var game: Node = await _instantiate_game()
	var policy: HeatmapVisibilityPolicy = game.get("_heatmap_visibility_policy") as HeatmapVisibilityPolicy
	var map_toggle: Button = game.get_node("UI/TopBar/HBoxContainer/MapToggle") as Button
	game.call("_on_heatmap_toggle_toggled", true)
	policy.hidden_by_pause = true
	game.call("_refresh_heatmap_visibility")
	assert(not bool(game.call("is_heatmap_effectively_visible")), "Pause should temporarily hide the heatmap.")
	policy.hidden_by_pause = false
	game.call("_refresh_heatmap_visibility")
	assert(bool(game.call("is_heatmap_effectively_visible")), "Resume should restore the requested heatmap visibility.")
	assert(map_toggle.button_pressed, "Map control should reflect the restored visibility.")
	game.queue_free()


func test_hidden_heatmap_defers_color_refresh_until_shown() -> void:
	var game: Node = await _instantiate_game()
	var heatmap: LandValueHeatmap = game.get_node("LandValueHeatmap") as LandValueHeatmap
	var grid: GridManager = game.get_node("GridManager") as GridManager
	await get_tree().process_frame

	assert(not heatmap.is_heatmap_visible(), "Heatmap should start hidden.")
	assert(bool(heatmap.get("_colors_dirty")), "Hidden heatmap should retain dirty state without calculating colors.")
	assert(not bool(heatmap.get("_color_update_pending")), "Hidden heatmap should not schedule a color pass.")

	grid.set_tile(Vector2i(3, 10), GridCellData.new(GridCellData.TileType.PARK))
	await get_tree().process_frame
	assert(bool(heatmap.get("_colors_dirty")), "Grid changes while hidden should keep the heatmap dirty.")
	assert(not bool(heatmap.get("_color_update_pending")), "Grid changes while hidden should not schedule a color pass.")

	heatmap.set_heatmap_visible(true)
	await get_tree().process_frame
	assert(not bool(heatmap.get("_colors_dirty")), "Showing the heatmap should refresh its colors.")
	assert(not bool(heatmap.get("_color_update_pending")), "Completed heatmap refresh should clear pending state.")
	game.queue_free()


func test_factory_priority_cache_refreshes_after_grid_changes() -> void:
	var game: Node = await _instantiate_game()
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var factory_pos: Vector2i = Vector2i(4, 4)
	var road_pos: Vector2i = Vector2i(4, 3)
	grid.set_tile(road_pos, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(factory_pos, GridCellData.new(GridCellData.TileType.INDUSTRIAL))
	game.call("refresh_road_connections", factory_pos)

	game.call("_ensure_factory_priority_cache")
	var factory_order: Array = game.get("_factory_priority_order") as Array
	assert(factory_order.has(factory_pos), "Connected factory should appear in the cached inspection order.")
	assert(not bool(game.get("_factory_priority_cache_dirty")), "Factory status lookup should leave the cache valid.")

	grid.set_tile(factory_pos, GridCellData.new(GridCellData.TileType.PARK))
	assert(bool(game.get("_factory_priority_cache_dirty")), "Grid changes should invalidate the factory priority cache.")
	game.call("_ensure_factory_priority_cache")
	factory_order = game.get("_factory_priority_order") as Array
	assert(not factory_order.has(factory_pos), "Grid changes should remove non-factory cells from the cached inspection order.")
	game.queue_free()


func test_hover_land_value_cache_invalidates_on_grid_changes() -> void:
	var game: Node = await _instantiate_game()
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var cell: Vector2i = Vector2i(5, 10)
	game.call("_on_heatmap_toggle_toggled", true)
	game.call("_update_land_value_readout", cell)
	var label: Label = game.get_node("UI/LandValueReadoutPanel/LandValueReadoutLabel") as Label
	assert(label.text == "Value: %d/100" % game.get_node("EconomyManager").call("get_land_value", cell),
			"Hover readout should show the current cell value.")
	assert(not bool(game.get("_land_value_readout_dirty")), "Computing the hovered value should mark the cache clean.")

	grid.set_tile(cell, GridCellData.new(GridCellData.TileType.PARK))
	assert(bool(game.get("_land_value_readout_dirty")), "Grid changes should invalidate the hovered value cache.")
	game.call("_update_land_value_readout", cell)
	assert(label.text == "Value: %d/100" % game.get_node("EconomyManager").call("get_land_value", cell),
			"Hover readout should recalculate after a relevant grid change.")
	assert(not bool(game.get("_land_value_readout_dirty")), "Updated hover readout should mark the cache clean again.")
	game.queue_free()
