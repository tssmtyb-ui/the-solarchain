extends Node2D
## Root scene script for Spekulant.
##
## Owns the TileMapLayer, GridManager, and EconomyManager and bridges
## the data model to rendering, player input, and simulation.

@onready var _grid: GridManager = $GridManager
@onready var _tilemap: TileMapLayer = $TileMapLayer
@onready var _hover_layer: Node2D = $HoverLayer
@onready var _land_value_heatmap: LandValueHeatmap = $LandValueHeatmap
@onready var _land_value_legend: LandValueHeatmapLegend = $UI/LandValueHeatmapLegend
@onready var _economy: EconomyManager = _create_economy_manager()
@onready var _money_label: Button = $UI/TopBar/HBoxContainer/MoneyLabel
@onready var _map_toggle: Button = $UI/TopBar/HBoxContainer/MapToggle
var _pause_toggle: Button
@onready var _workers_label: Label = $UI/TopBar/HBoxContainer/WorkersLabel
@onready var _goods_label: Label = $UI/TopBar/HBoxContainer/GoodsLabel
@onready var _factories_label: Label = $UI/TopBar/HBoxContainer/FactoriesLabel
@onready var _economy_flow_button: Button = $UI/TopBar/HBoxContainer/EconomyFlowButton
@onready var _objective_header: Button = $UI/ObjectiveBox/MarginContainer/VBoxContainer/Title
@onready var _objective_completion_summary: Label = $UI/ObjectiveBox/MarginContainer/VBoxContainer/CompletionSummary
@onready var _dividend_slider: HSlider = $UI/TopBar/HBoxContainer/DividendBox/DividendSlider
@onready var _dividend_label: Label = $UI/TopBar/HBoxContainer/DividendBox/DividendLabel
@onready var _objective_residential: CheckBox = $UI/ObjectiveBox/MarginContainer/VBoxContainer/CheckResidential
@onready var _objective_factory: CheckBox = $UI/ObjectiveBox/MarginContainer/VBoxContainer/CheckFactory
@onready var _objective_road: CheckBox = $UI/ObjectiveBox/MarginContainer/VBoxContainer/CheckRoad
@onready var _objective_sludge: CheckBox = $UI/ObjectiveBox/MarginContainer/VBoxContainer/CheckSludgeLine
@onready var _bobr_dialogue: PanelContainer = $UI/BobrDialogue
@onready var _quote_label: Label = $UI/BobrDialogue/MarginContainer/HBoxContainer/VBoxContainer/QuoteLabel
@onready var _dismiss_button: Button = $UI/BobrDialogue/MarginContainer/HBoxContainer/VBoxContainer/DismissButton
@onready var _placement: BuildingPlacement = _create_placement_manager()

## Placement controller — single owner of the player build pipeline.
var _placement_controller: PlacementController
var _map_input_controller: MapInputController


## Pipe/logistics connectivity graph — the live BFS network for SLUDGE hookups.
var _pipe_network: PipeNetworkManager
## Cached cardinal road adjacency shared by placement, supply, and objectives.
var _road_connectivity: RoadConnectivityManager

## Farm field assignment rules, shared with the supply-chain simulator.
var _farm_system: FarmSystem = FarmSystem.new()
var _supply_chain: SupplyChainSimulator
var _residential_evolution: ResidentialEvolutionManager
var _town_progression: TownProgressionManager
var _speculator_manager: SpeculatorManager

## Screen-space readouts for factory logistics and the hovered land-value cell.
var _factory_status_panel: FactoryStatusReadout
var _land_value_readout_panel: HeatmapReadout
var _economy_flow_panel: EconomyFlowReadout
var _budget_ledger_panel: BudgetLedgerPanel
var _budget_ledger_button: Button
var _town_level_box: VBoxContainer
var _town_level_label: Label
var _town_level_progress: ProgressBar
var _economy_hud_presenter: EconomyHudPresenter = EconomyHudPresenter.new()
var _objective_panel_presenter: ObjectivePanelPresenter = ObjectivePanelPresenter.new()

## Shared state policy for Map/Money/V and Park/Factory heatmap visibility.
var _heatmap_visibility_policy: HeatmapVisibilityPolicy = HeatmapVisibilityPolicy.new()

## Reusable pause/settings interface and its Credits popup.
var _settings_menu: SettingsMenu
var _credits_panel: CreditsPanel
var _pause_badge: PanelContainer
var _map_boundary_fog: MapBoundaryFog
var simulation_paused: bool = false

## Grid dimensions for the starting map.
const GRID_SIZE: int = 30
const DEFAULT_WATER_TILES: Array[Vector2i] = [
	Vector2i(22, 22), Vector2i(23, 22), Vector2i(24, 22),
	Vector2i(22, 23), Vector2i(23, 23), Vector2i(24, 23),
	Vector2i(23, 24), Vector2i(24, 24), Vector2i(25, 24),
]

## True while rebuilding state after loading to avoid an extra simulated supply tick.
var _is_load_rebuild: bool = false

var _factory_priority_cache_dirty: bool = true
var _factory_priority_order: Array[Vector2i] = []
var _factory_priority_index: Dictionary = {}
var _hover_refresh_pending: bool = false
var _land_value_readout_dirty: bool = true
var _cached_land_value_cell: Vector2i = Vector2i(-1, -1)
var _cached_land_value_text: String = ""
var _cached_pollution_risk: bool = false

## Player's current money balance.
var current_money: int = 1000

## True once the player goes bankrupt (money drops below zero); blocks input.
var is_game_over: bool = false

# ---------------------------------------------------------------------------
#   Supply-chain simulation component and compatibility accessors
# ---------------------------------------------------------------------------

const SupplyChainScript = preload("res://scripts/simulation/supply_chain_simulator.gd")
const SUPPLY_CHAIN_TICK_INTERVAL: float = SupplyChainScript.TICK_INTERVAL
const WORKERS_PER_VILLA: int = SupplyChainScript.WORKERS_PER_VILLA
const WORKERS_PER_APARTMENT: int = SupplyChainScript.WORKERS_PER_APARTMENT
const WORKERS_PER_FACTORY: int = SupplyChainScript.WORKERS_PER_FACTORY
const GOODS_PER_FACTORY_TICK: int = SupplyChainScript.GOODS_PER_FACTORY_TICK
const GOODS_PER_HOUSE_TICK: int = SupplyChainScript.GOODS_PER_HOUSE_TICK
const GOODS_LAND_VALUE_BOOST: int = SupplyChainScript.GOODS_LAND_VALUE_BOOST

var worker_capacity: int:
	get:
		return _supply_chain.worker_capacity if _supply_chain != null else 0
var available_workers: int:
	get:
		return _supply_chain.available_workers if _supply_chain != null else 0
var goods_stock: int:
	get:
		return _supply_chain.goods_stock if _supply_chain != null else 0
	set(value):
		if _supply_chain != null:
			_supply_chain.goods_stock = value
var operating_factories: int:
	get:
		return _supply_chain.operating_factories if _supply_chain != null else 0
var goods_produced_last_tick: int:
	get:
		return _supply_chain.goods_produced_last_tick if _supply_chain != null else 0
var goods_consumed_last_tick: int:
	get:
		return _supply_chain.goods_consumed_last_tick if _supply_chain != null else 0
var homes_supplied_last_tick: int:
	get:
		return _supply_chain.homes_supplied_last_tick if _supply_chain != null else 0
var road_connected_homes_last_tick: int:
	get:
		return _supply_chain.road_connected_homes_last_tick if _supply_chain != null else 0
var total_homes_last_tick: int:
	get:
		return _supply_chain.total_homes_last_tick if _supply_chain != null else 0
var operating_farmhouses: int:
	get:
		return _supply_chain.operating_farmhouses if _supply_chain != null else 0
var active_farm_fields_last_tick: int:
	get:
		return _supply_chain.active_farm_fields_last_tick if _supply_chain != null else 0
var farm_goods_produced_last_tick: int:
	get:
		return _supply_chain.farm_goods_produced_last_tick if _supply_chain != null else 0
## Tutorial objective completion is a persistent milestone; city conditions may change later.
var _foundations_complete: bool = false
var _objectives_collapsed: bool = false
var _tutorial_milestone_announced: bool = false

# ---------------------------------------------------------------------------
#   Tutorial objectives — Step 1: checklist tracking
# ---------------------------------------------------------------------------

## Residential zones required to complete the first tutorial objective.
const OBJECTIVE_RESIDENTIAL_TARGET: int = 2
## Factories required to complete the second tutorial objective.
const OBJECTIVE_FACTORY_TARGET: int = 1

## Live residential-zone count on the grid (any density).
var _obj_residential: int = 0
## Live factory count on the grid.
var _obj_factory: int = 0
## True once every placed house/factory sits adjacent to a road.
var _obj_road_connected: bool = false
## True once every placed factory is connected to the map edge by live sludge.
var _obj_factories_hooked_up: bool = false

## Greeting to the new mayor, shown once at launch.
const TUTORIAL_INTRO_QUOTE := "Aha, a new mayor! Build roads, residences, and factories so your city thrives, then tune the Citizen's Dividend slider."
## Milestone message once city foundations are complete.
const TUTORIAL_COMPLETE_QUOTE := "City foundations complete! Now set a Citizen's Dividend above 0% to complete the tutorial. After that, your city is yours to grow."
## Message once the player resolves the tutorial.
const TUTORIAL_RESOLVE_QUOTE := "Citizen's Dividend active! Your city's surplus now flows back to residents."

## Whether the player raised the LVT slider to end the tutorial.
var _tutorial_resolved: bool = false


func _setup_settings_menu() -> void:
	var settings_scene: PackedScene = load("res://scenes/ui/settings_menu.tscn") as PackedScene
	if settings_scene == null:
		push_error("Settings menu scene could not be loaded.")
		return
	_settings_menu = settings_scene.instantiate() as SettingsMenu
	_settings_menu.name = "SettingsMenu"
	_settings_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_settings_menu.pause_requested.connect(_on_pause_requested)
	_settings_menu.resume_requested.connect(_on_resume_requested)
	_settings_menu.save_requested.connect(_on_save_requested)
	_settings_menu.load_requested.connect(_on_load_requested)
	_settings_menu.main_menu_requested.connect(_on_main_menu_requested)
	$UI.add_child(_settings_menu)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	assert(_grid != null, "GridManager node missing!")
	assert(_tilemap != null, "TileMapLayer node missing!")
	var restored_state: Dictionary = {}
	var save_manager: Node = get_node_or_null("/root/GameSave")
	if save_manager != null:
		var pending_state: Variant = save_manager.call("consume_load_on_game_start")
		if pending_state is Dictionary:
			restored_state = pending_state as Dictionary

	# Wire up economy signal.
	_economy.assessment_completed.connect(_on_assessment_completed)
	_economy.residential_evolution_triggered.connect(_on_residential_evolution)
	_land_value_heatmap.configure(_grid, _economy, _tilemap, GRID_SIZE)
	_grid.grid_changed.connect(_on_grid_state_changed)
	_map_toggle.accessibility_name = "Land value map"
	_map_toggle.accessibility_description = "Show or hide the live land-value heatmap. Press V to toggle."
	_map_toggle.toggle_mode = true
	_map_toggle.set_pressed_no_signal(false)
	_map_toggle.tooltip_text = "Toggle land-value heatmap (V)"
	_map_toggle.toggled.connect(_on_heatmap_toggle_toggled)
	_money_label.toggle_mode = true
	_money_label.set_pressed_no_signal(false)
	_money_label.accessibility_name = "Money balance and land-value map toggle"
	_money_label.accessibility_description = "Current city funds. Activate to show or hide the live land-value heatmap."
	_money_label.tooltip_text = "Current money. Click to toggle the land-value heatmap (V)."
	_money_label.toggled.connect(_on_money_label_toggled)
	_ensure_pause_toggle_ui()
	_create_pause_badge_ui()

	# Pipe/logistics network — cached BFS connectivity for SLUDGE hookups.
	# Visual refreshes ride the network_changed signal so pipe sprites always
	# reflect the latest live/dead connectivity.
	_pipe_network = _create_pipe_network_manager()
	_economy.pipe_network = _pipe_network
	_pipe_network.network_changed.connect(_on_pipe_network_changed)
	_pipe_network.capacity_updated.connect(_on_pipe_capacity_updated)

	# Road-connectivity service — the shared source of adjacency and eligibility.
	_road_connectivity = RoadConnectivityManager.new()
	_road_connectivity.name = "RoadConnectivityManager"
	add_child(_road_connectivity)
	_road_connectivity.configure(_grid, GRID_SIZE)

	# Placement controller — single owner of the player build pipeline
	# (cost lookup, placement rules, money deduction, grid and sprite writes).
	_placement_controller = PlacementController.new()
	_placement_controller.name = "PlacementController"
	_placement_controller.grid = _grid
	_placement_controller.tilemap = _tilemap
	_placement_controller.placement = _placement
	_placement_controller.pipe_network = _pipe_network
	_placement_controller.road_connectivity = _road_connectivity
	_placement_controller.grid_size = GRID_SIZE
	add_child(_placement_controller)
	# Demolishing a public park strikes the nearest factory for three minutes.
	_placement_controller.park_demolished.connect(_on_park_demolished)

	_map_input_controller = MapInputController.new()
	_map_input_controller.name = "MapInputController"
	_map_input_controller.configure(
			_grid,
			_tilemap,
			_hover_layer,
			$UI/BuildBar/HBoxContainer,
			_placement_controller,
			_placement,
			GRID_SIZE,
			Callable(self, "_get_current_money"),
			Callable(self, "_is_map_input_allowed"))
	_map_input_controller.hover_cell_changed.connect(_on_hover_cell_changed)
	_map_input_controller.money_value_changed.connect(_on_map_input_money_changed)
	_map_input_controller.money_display_refresh_requested.connect(update_money_ui)
	_map_input_controller.build_committed.connect(_on_map_build_committed)
	_map_input_controller.road_connection_refresh_requested.connect(refresh_road_connections)
	_map_input_controller.drag_ui_refresh_requested.connect(_on_map_drag_ui_refresh_requested)
	_map_input_controller.park_factory_heatmap_auto_mode_requested.connect(
			_set_park_factory_heatmap_auto_mode)
	_map_input_controller.heatmap_toggle_requested.connect(_on_v_heatmap_toggled)
	add_child(_map_input_controller)

	# Build the default canvas; loaded state is applied after the simulation and UI are ready.
	_init_grass_grid()
	_spawn_water_tiles()
	_spawn_edge_highways()

	# Keep the startup framing centered on the populated isometric map and
	# configure camera movement boundaries across the expanded grid.
	$Camera2D.make_current()
	$Camera2D.zoom = Vector2(0.16, 0.16)
	if $Camera2D.has_method("configure_limits_for_tilemap"):
		$Camera2D.call("configure_limits_for_tilemap", _tilemap)
	_setup_map_boundary_fog()

	_economy_hud_presenter.configure(
			_workers_label, _goods_label, _factories_label, _dividend_label)
	_setup_town_progression_and_budget_ledger()

	# Start the economy immediately (timer auto-starts in EconomyManager._ready()).
	if restored_state.is_empty():
		_economy.calculate_net_income()

	# Supply-chain simulation (Step 1): owns its timer and allocation state; the
	# economy reads the simulator's supplied-home tax bonus through its callback.
	_setup_supply_chain()
	# Populate workforce and goods telemetry immediately instead of showing a blank HUD for the first three seconds.
	_on_supply_chain_tick()

	# Settings and pause controls share the reusable settings panel.
	_setup_settings_menu()

	# --- Build programmatic UI overlays (credits + game-over screen) ---
	UIBuilder.new().build_ui($UI, _on_restart_pressed)

	# The Credits popup is shared with the pause/settings panel and still
	# self-wires to the TopBar Credits button.
	_credits_panel = CreditsPanel.new()
	_credits_panel.name = "CreditsPanel"
	_credits_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_credits_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_credits_panel.offset_left = -300.0
	_credits_panel.offset_top = -220.0
	_credits_panel.offset_right = 300.0
	_credits_panel.offset_bottom = 220.0
	_credits_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_credits_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	$UI.add_child(_credits_panel)
	_settings_menu.configure(true, _credits_panel)
	if get_tree().paused:
		_settings_menu.open_menu()
	else:
		_settings_menu.close_menu()

	# Citizen's Dividend Policy — the slider + label now live in the scene's TopBar
	# (see node_2d.tscn) and are resolved via @onready refs. Wire the live
	# trade-off behaviour here: refresh on drag AND whenever factory income changes.
	_update_dividend_label(_dividend_slider.value)
	_dividend_slider.value_changed.connect(_on_dividend_changed)
	_economy_flow_button.tooltip_text = "Open workforce, factory, and goods-flow details"
	_economy_flow_button.pressed.connect(_on_economy_flow_pressed)
	_objective_panel_presenter.configure(
			$UI/ObjectiveBox,
			_objective_header,
			_objective_completion_summary,
			_objective_residential,
			_objective_factory,
			_objective_road,
			_objective_sludge)
	_objective_header.pressed.connect(_on_objective_header_pressed)
	_objective_sludge.tooltip_text = "Optional objective: connect this factory to a live sludge network reaching the map edge for a 30% production bonus. It is not required to complete the foundations milestone."
	_dismiss_button.pressed.connect(_on_bobr_dialogue_dismiss)
	_economy.assessment_completed.connect(_on_assessment_refresh_dividend)
	_refresh_town_progression_and_budget_ui()

	# Hover readouts are screen-space panels and never intercept map input.
	_create_land_value_readout_ui()
	_create_factory_status_ui()
	_create_economy_flow_ui()
	_economy_hud_presenter.set_economy_flow_panel(_economy_flow_panel)
	$UI/ObjectiveBox.resized.connect(_on_objective_box_resized)
	$UI/ObjectiveBox.visibility_changed.connect(_on_objective_box_resized)
	_objective_panel_presenter.set_related_panels(
			_factory_status_panel, _economy_flow_panel)
	_on_objective_box_resized()

	update_money_ui()
	_update_resource_ui()
	_update_objectives()

	if not restored_state.is_empty():
		if not _apply_saved_state(restored_state):
			push_warning("Saved city was invalid; started a new city instead.")
			_economy.calculate_net_income()
			_update_objectives()
			_show_bobr_dialogue(TUTORIAL_INTRO_QUOTE)
	else:
		_show_bobr_dialogue(TUTORIAL_INTRO_QUOTE)

	prints("World initialised — place roads and factories freely.")


## Fills the grid with uniform GRASS tiles — the player's blank canvas.
func _init_grass_grid() -> void:
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			var cell := Vector2i(x, y)
			_grid.set_tile(cell, GridCellData.new(GridCellData.TileType.GRASS))
			_placement_controller.place_tile(cell, GridCellData.TileType.GRASS)


## Places initial water tiles on the expanded map using the water ground tile.
func _spawn_water_tiles() -> void:
	for water_pos: Vector2i in DEFAULT_WATER_TILES:
		if _is_in_grid(water_pos):
			_grid.set_tile(water_pos, GridCellData.new(GridCellData.TileType.WATER))
			_placement_controller.place_tile(water_pos, GridCellData.TileType.WATER)


## Places ROAD tiles at the east and west edges of the grid as highway connections.
## West gateway: (0, GRID_SIZE / 2)    East gateway: (GRID_SIZE - 1, GRID_SIZE / 2)
## These are written to both the grid data model and the TileMapLayer.
func _spawn_edge_highways() -> void:
	var mid_y: int = int(GRID_SIZE * 0.5)

	var west_cell := Vector2i(0, mid_y)
	_grid.set_tile(west_cell, GridCellData.new(GridCellData.TileType.ROAD))
	_placement_controller.place_tile(west_cell, GridCellData.TileType.ROAD)

	var east_cell := Vector2i(GRID_SIZE - 1, mid_y)
	_grid.set_tile(east_cell, GridCellData.new(GridCellData.TileType.ROAD))
	_placement_controller.place_tile(east_cell, GridCellData.TileType.ROAD)

	prints("Edge highways placed at", west_cell, "and", east_cell)


func _on_park_demolished(park_pos: Vector2i) -> void:
	_economy.trigger_industrial_strike(park_pos)
	_factory_priority_cache_dirty = true
	_request_hover_status_refresh()


func _get_current_money() -> int:
	return current_money


func _is_map_input_allowed() -> bool:
	return not is_game_over


func _on_hover_cell_changed(cell: Vector2i) -> void:
	_update_factory_status(cell)
	_update_land_value_readout(cell)


func _on_map_input_money_changed(new_money: int) -> void:
	current_money = new_money


func _on_map_build_committed(
		grid_pos: Vector2i, existing_type: int, result: Dictionary) -> void:
	var placed_type: int = int(result["placed_type"])
	refresh_road_connections(grid_pos)
	_update_resource_ui()
	_update_objectives()
	if placed_type == GridCellData.TileType.GRASS \
			or (placed_type == GridCellData.TileType.WATER and existing_type != GridCellData.TileType.WATER):
		prints("Demolished", GridCellData.TileType.keys()[existing_type], "at", grid_pos)
	elif existing_type == GridCellData.TileType.RESIDENTIAL_LOW \
			and placed_type == GridCellData.TileType.RESIDENTIAL_HIGH:
		# Protect the upgraded residence from an immediate land-value downgrade.
		_economy.stamp_evolution_cooldown(grid_pos)
		prints("Upgraded to RESIDENTIAL_HIGH at", grid_pos)
	else:
		prints("Placed", GridCellData.TileType.keys()[placed_type], "at", grid_pos)


func _on_map_drag_ui_refresh_requested() -> void:
	_update_resource_ui()
	_update_objectives()


# ---- Input & Simulation Pause (Active-Building Mode) -----------------------

func _unhandled_input(event: InputEvent) -> void:
	if is_game_over or get_tree().paused:
		return
	if _settings_menu != null and _settings_menu.visible:
		return
	if _credits_panel != null and _credits_panel.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE:
			toggle_simulation_pause()
			get_viewport().set_input_as_handled()


func is_simulation_paused() -> bool:
	return simulation_paused


func toggle_simulation_pause() -> void:
	set_simulation_paused(not simulation_paused)


func set_simulation_paused(paused: bool) -> void:
	if is_game_over and paused:
		return
	simulation_paused = paused
	if _economy != null:
		_economy.set_paused(paused)
	if _supply_chain != null:
		_supply_chain.set_paused(paused)
	_refresh_pause_ui()


func _on_pause_toggle_toggled(toggled_on: bool) -> void:
	set_simulation_paused(toggled_on)


func _ensure_pause_toggle_ui() -> void:
	var top_bar_row: HBoxContainer = get_node_or_null("UI/TopBar/HBoxContainer") as HBoxContainer
	if top_bar_row == null:
		return
	_pause_toggle = top_bar_row.get_node_or_null("PauseToggle") as Button
	if _pause_toggle == null:
		_pause_toggle = Button.new()
		_pause_toggle.name = "PauseToggle"
		_pause_toggle.custom_minimum_size = Vector2(76, 40)
		_pause_toggle.text = "Pause"
		top_bar_row.add_child(_pause_toggle)
		var credits_btn: Node = top_bar_row.get_node_or_null("CreditsButton")
		if credits_btn != null:
			top_bar_row.move_child(_pause_toggle, credits_btn.get_index())
	_pause_toggle.toggle_mode = true
	_pause_toggle.focus_mode = Control.FOCUS_NONE
	_pause_toggle.set_pressed_no_signal(false)
	_pause_toggle.accessibility_name = "Simulation pause toggle"
	_pause_toggle.tooltip_text = "Pause simulation time (Spacebar) — build and inspect freely while paused"
	if not _pause_toggle.toggled.is_connected(_on_pause_toggle_toggled):
		_pause_toggle.toggled.connect(_on_pause_toggle_toggled)


func _setup_map_boundary_fog() -> void:
	if _map_boundary_fog == null or not is_instance_valid(_map_boundary_fog):
		_map_boundary_fog = MapBoundaryFog.new()
		_map_boundary_fog.name = "MapBoundaryFog"
		add_child(_map_boundary_fog)
	_map_boundary_fog.configure(_tilemap, GRID_SIZE, $Camera2D as Camera2D)


func _setup_town_progression_and_budget_ledger() -> void:
	if _town_progression == null or not is_instance_valid(_town_progression):
		_town_progression = TownProgressionManager.new()
		_town_progression.name = "TownProgressionManager"
		add_child(_town_progression)
	if not _town_progression.town_level_changed.is_connected(_on_town_level_changed):
		_town_progression.town_level_changed.connect(_on_town_level_changed)

	var top_bar_row: HBoxContainer = get_node_or_null("UI/TopBar/HBoxContainer") as HBoxContainer
	if top_bar_row != null:
		_town_level_box = top_bar_row.get_node_or_null("TownLevelBox") as VBoxContainer
		if _town_level_box == null:
			_town_level_box = VBoxContainer.new()
			_town_level_box.name = "TownLevelBox"
			_town_level_box.custom_minimum_size = Vector2(168, 0)
			_town_level_box.alignment = BoxContainer.ALIGNMENT_CENTER
			_town_level_box.add_theme_constant_override(&"separation", 2)

			_town_level_label = Label.new()
			_town_level_label.name = "TownLevelLabel"
			_town_level_label.text = "Tier 1: Hamlet"
			_town_level_label.add_theme_font_size_override(&"font_size", 11)
			_town_level_label.add_theme_color_override(&"font_color", Color(0.96, 0.86, 0.50))
			_town_level_box.add_child(_town_level_label)

			_town_level_progress = ProgressBar.new()
			_town_level_progress.name = "TownLevelProgress"
			_town_level_progress.min_value = 0.0
			_town_level_progress.max_value = 100.0
			_town_level_progress.value = 0.0
			_town_level_progress.show_percentage = false
			_town_level_progress.custom_minimum_size = Vector2(160, 10)
			_town_level_box.add_child(_town_level_progress)

			top_bar_row.add_child(_town_level_box)
			if _money_label != null:
				top_bar_row.move_child(_town_level_box, _money_label.get_index() + 1)
		else:
			_town_level_label = _town_level_box.get_node_or_null("TownLevelLabel") as Label
			_town_level_progress = _town_level_box.get_node_or_null("TownLevelProgress") as ProgressBar

		_budget_ledger_button = top_bar_row.get_node_or_null("BudgetLedgerButton") as Button
		if _budget_ledger_button == null:
			_budget_ledger_button = Button.new()
			_budget_ledger_button.name = "BudgetLedgerButton"
			_budget_ledger_button.custom_minimum_size = Vector2(74, 40)
			_budget_ledger_button.text = "Budget"
			_budget_ledger_button.tooltip_text = "Open Municipal Budget Ledger (Last 10 Assessment Cycles)"
			_budget_ledger_button.pressed.connect(_on_budget_ledger_pressed)
			top_bar_row.add_child(_budget_ledger_button)
			if _economy_flow_button != null:
				top_bar_row.move_child(_budget_ledger_button, _economy_flow_button.get_index() + 1)

	if _budget_ledger_panel == null or not is_instance_valid(_budget_ledger_panel):
		_budget_ledger_panel = BudgetLedgerPanel.new()
		$UI.add_child(_budget_ledger_panel)

	_economy_hud_presenter.set_town_level_controls(_town_level_label, _town_level_progress)
	_economy_hud_presenter.set_budget_ledger_panel(_budget_ledger_panel)
	_setup_speculator_manager()


func _setup_speculator_manager() -> void:
	if _speculator_manager == null or not is_instance_valid(_speculator_manager):
		_speculator_manager = SpeculatorManager.new()
		_speculator_manager.name = "SpeculatorManager"
		add_child(_speculator_manager)
	_speculator_manager.configure(
			_grid,
			_economy,
			_town_progression,
			_road_connectivity,
			_placement_controller,
			_placement,
			GRID_SIZE)
	if _placement_controller != null:
		_placement_controller.speculator_manager = _speculator_manager
	if _economy != null:
		_economy.speculator_lvt_provider = _speculator_manager.calculate_total_speculator_lvt
	if _land_value_heatmap != null:
		_land_value_heatmap.set_speculator_manager(_speculator_manager)
	if not _speculator_manager.lots_changed.is_connected(_on_speculator_lots_changed):
		_speculator_manager.lots_changed.connect(_on_speculator_lots_changed)


func _on_speculator_lots_changed() -> void:
	_land_value_readout_dirty = true
	_request_hover_status_refresh()


func _on_budget_ledger_pressed() -> void:
	if _budget_ledger_panel == null:
		return
	_budget_ledger_panel.visible = not _budget_ledger_panel.visible
	if _budget_ledger_panel.visible:
		_refresh_town_progression_and_budget_ui()


func _on_town_level_changed(new_level: int, level_name: String) -> void:
	if _economy != null and _town_progression != null:
		_economy.town_level_lvt_multiplier = _town_progression.get_lvt_efficiency_multiplier()
	prints("Town Level advanced to Tier %d: %s" % [new_level, level_name])


func _refresh_town_progression_and_budget_ui() -> void:
	if _town_progression == null or _economy == null or _grid == null:
		return
	var population: int = 0
	var apartment_count: int = 0
	for pos: Vector2i in _grid.get_all_occupied_positions():
		var t: int = _grid.get_tile_type(pos)
		if t == GridCellData.TileType.RESIDENTIAL_LOW:
			population += SupplyChainSimulator.WORKERS_PER_VILLA
		elif t == GridCellData.TileType.RESIDENTIAL_HIGH:
			population += SupplyChainSimulator.WORKERS_PER_APARTMENT
			apartment_count += 1
	if _supply_chain != null:
		population = maxi(population, _supply_chain.worker_capacity)

	var gross_lvt: int = maxi(_economy.last_lvt_revenue, _economy.cumulative_lvt_revenue)
	_town_progression.evaluate_progression(population, gross_lvt, apartment_count)
	_economy.town_level_lvt_multiplier = _town_progression.get_lvt_efficiency_multiplier()

	if _map_input_controller != null:
		_map_input_controller.apply_town_progression_locks(_town_progression)
	if _dividend_slider != null:
		var ubi_unlocked: bool = _town_progression.is_ubi_unlocked()
		_dividend_slider.editable = ubi_unlocked
		_dividend_slider.tooltip_text = (
			"Adjust Citizen's Dividend / UBI payout percentage"
			if ubi_unlocked
			else "Citizen's Dividend / UBI Slider — Locked (Requires Town Level: 15 Population & $1,000 Gross LVT)"
		)

	var report: Dictionary = _town_progression.get_progress_report(
			population, gross_lvt, apartment_count)
	_economy_hud_presenter.render_town_level(report)
	_economy_hud_presenter.render_budget_ledger(
			_economy.get_budget_history(),
			_economy.last_lvt_revenue,
			_economy.last_maintenance_cost,
			_economy.last_ubi_payout,
			_economy.get_retained_treasury_revenue(),
			_economy.cumulative_lvt_revenue)


func _create_pause_badge_ui() -> void:
	_pause_badge = PanelContainer.new()
	_pause_badge.name = "PauseBadge"
	_pause_badge.visible = false
	_pause_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_badge.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_pause_badge.offset_left = -150.0
	_pause_badge.offset_top = 80.0
	_pause_badge.offset_right = 150.0
	_pause_badge.offset_bottom = 114.0
	_pause_badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.18, 0.11, 0.04, 0.94)
	badge_style.border_color = Color(0.98, 0.78, 0.25, 0.95)
	badge_style.set_border_width_all(2)
	badge_style.set_corner_radius_all(8)
	badge_style.content_margin_left = 14.0
	badge_style.content_margin_right = 14.0
	badge_style.content_margin_top = 4.0
	badge_style.content_margin_bottom = 4.0
	_pause_badge.add_theme_stylebox_override(&"panel", badge_style)
	var badge_label := Label.new()
	badge_label.name = "PauseBadgeLabel"
	badge_label.text = "PAUSED — Active Building Mode"
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_label.add_theme_font_size_override(&"font_size", 15)
	badge_label.add_theme_color_override(&"font_color", Color(0.99, 0.85, 0.35))
	_pause_badge.add_child(badge_label)
	$UI.add_child(_pause_badge)


func _refresh_pause_ui() -> void:
	if _pause_toggle != null:
		_pause_toggle.set_pressed_no_signal(simulation_paused)
		_pause_toggle.text = "PAUSED" if simulation_paused else "Pause"
		_pause_toggle.modulate = (
			Color(1.0, 0.85, 0.35, 1.0)
			if simulation_paused
			else Color(1.0, 1.0, 1.0, 1.0)
		)
		_pause_toggle.tooltip_text = (
			"Simulation is PAUSED (Spacebar to resume) — active building enabled"
			if simulation_paused
			else "Pause simulation time (Spacebar) — build and inspect freely while paused"
		)
	if _pause_badge != null:
		_pause_badge.visible = simulation_paused




## Grid changes invalidate a visible hover value and factory inspection status.
func _on_grid_state_changed() -> void:
	_land_value_readout_dirty = true
	_factory_priority_cache_dirty = true
	_request_hover_status_refresh()


func _request_hover_status_refresh() -> void:
	if _hover_refresh_pending:
		return
	_hover_refresh_pending = true
	call_deferred("_refresh_hover_status")


func _refresh_hover_status() -> void:
	_hover_refresh_pending = false
	if not is_node_ready():
		return
	var cell: Vector2i = _tilemap.local_to_map(get_global_mouse_position())
	if _map_input_controller == null or cell != _map_input_controller.get_hovered_cell():
		return
	_update_factory_status(cell)
	_update_land_value_readout(cell)


func _set_heatmap_visible(show_heatmap: bool) -> void:
	_heatmap_visibility_policy.set_manual_visible(show_heatmap)
	_refresh_heatmap_visibility()


func _on_v_heatmap_toggled() -> void:
	if is_game_over:
		return
	_heatmap_visibility_policy.toggle_manual_visibility()
	_refresh_heatmap_visibility()


func _on_heatmap_toggle_toggled(toggled_on: bool) -> void:
	_set_heatmap_visible(toggled_on)


func _on_money_label_toggled(toggled_on: bool) -> void:
	_set_heatmap_visible(toggled_on)


## Park/Factory tools reveal land value while active, preserving the player's
## previous preference when another tool is selected.
func _set_park_factory_heatmap_auto_mode(is_enabled: bool) -> void:
	_heatmap_visibility_policy.set_park_factory_auto_enabled(is_enabled)
	_refresh_heatmap_visibility()


func is_heatmap_effectively_visible() -> bool:
	return _is_heatmap_effectively_visible()


func _is_heatmap_effectively_visible() -> bool:
	return _heatmap_visibility_policy.is_effectively_visible()


func _refresh_heatmap_visibility() -> void:
	var displayed: bool = _is_heatmap_effectively_visible()
	_map_toggle.set_pressed_no_signal(displayed)
	_money_label.set_pressed_no_signal(displayed)
	_map_toggle.tooltip_text = "Hide land-value heatmap (V)" if displayed \
			else "Show land-value heatmap (V)"
	_map_toggle.accessibility_description = "Land value map is %s. Press V to %s it." % [
		"visible" if displayed else "hidden", "hide" if displayed else "show"
	]
	_money_label.tooltip_text = "Current money: $%d. Click to hide the land-value heatmap (V)." % current_money \
			if displayed else "Current money: $%d. Click to show the land-value heatmap (V)." % current_money
	_money_label.accessibility_description = "Current city funds: $%d. The land-value heatmap is %s. Activate to %s it." % [
		current_money, "visible" if displayed else "hidden", "hide" if displayed else "show"
	]
	_land_value_heatmap.set_heatmap_visible(displayed)
	_land_value_legend.set_heatmap_visible(displayed)
	if not displayed:
		_set_land_value_readout_visible(false)
	else:
		_update_land_value_readout(_tilemap.local_to_map(get_global_mouse_position()))


func _on_assessment_completed(net_income: int) -> void:
	if _is_load_rebuild:
		return
	current_money += net_income
	_refresh_town_progression_and_budget_ui()
	if _speculator_manager != null and _speculator_manager.is_active():
		_speculator_manager.process_assessment_cycle()
	update_money_ui()
	# Strike expiries can change the order shown by a hovered factory.
	_factory_priority_cache_dirty = true
	_request_hover_status_refresh()
	prints("Assessment: net:", net_income)


## Handles automatic density evolution (villa <-> apartment) driven by land value.
## The EconomyManager emits this when a residential tile crosses a threshold.
func _on_residential_evolution(grid_pos: Vector2i, new_tile_type: int) -> void:
	# Update the data model and ground tile, then swap the building sprite.
	# spawn_building() already queue_frees any existing sprite at this cell.
	_grid.set_tile(grid_pos, GridCellData.new(new_tile_type))
	_placement_controller.place_tile(grid_pos, new_tile_type)
	_placement.spawn_building(grid_pos, new_tile_type)
	# Keep road-connection state in sync for the evolved tile (still a house).
	refresh_road_connections(grid_pos)
	_update_resource_ui()
	_update_objectives()
	prints("Evolved tile at", grid_pos, "->", GridCellData.TileType.keys()[new_tile_type])


## Refreshes the workforce and goods readouts in the TopBar from the live
## supply-chain state. Matches the MoneyLabel styling for a unified HUD.
func _update_resource_ui() -> void:
	var snapshot: Dictionary = _supply_chain.get_resource_hud_snapshot()
	_economy_hud_presenter.render_resources(
			int(snapshot["worker_capacity"]),
			int(snapshot["employed_workers"]),
			int(snapshot["available_workers"]),
			int(snapshot["goods_stock"]),
			int(snapshot["goods_produced_last_tick"]),
			int(snapshot["goods_consumed_last_tick"]),
			int(snapshot["supplied_homes"]),
			int(snapshot["residences"]),
			int(snapshot["staffed_factory_count"]),
			int(snapshot["factory_count"]),
			int(snapshot["operating_farmhouses"]),
			int(snapshot["farmhouse_count"]),
			int(snapshot["active_farm_fields_last_tick"]),
			int(snapshot["farmland_count"]),
			int(snapshot["farm_goods_produced_last_tick"]),
			WORKERS_PER_FACTORY,
			SUPPLY_CHAIN_TICK_INTERVAL,
			GOODS_LAND_VALUE_BOOST,
			FarmSystem.FARMLAND_RADIUS,
			int(snapshot["road_connected_homes_last_tick"]),
			int(snapshot.get("water_delivered_last_tick", 0)),
			int(snapshot.get("water_capacity_last_tick", 0)),
			int(snapshot.get("water_demand_last_tick", 0)))
	_refresh_town_progression_and_budget_ui()


## Updates the money label to reflect the current balance.
func update_money_ui() -> void:
	_money_label.text = "$%d" % current_money
	if is_node_ready():
		_refresh_heatmap_visibility()
		if _is_heatmap_effectively_visible():
			_update_land_value_readout(_tilemap.local_to_map(get_global_mouse_position()))

	# Game over check: bankruptcy freezes the game and shows the game-over screen.
	if current_money < 0 and not is_game_over:
		is_game_over = true
		var timer: Timer = _economy.get_node_or_null("AssessmentTimer")
		if timer:
			timer.stop()
		$UI/GameOverPanel.show()


## Restarts the current scene when the player clicks "Restart Game".
func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_node("/root/GameSave").call("clear_load_on_game_start")
	get_tree().reload_current_scene()


## Pushes the slider value to the economy and refreshes the trade-off label.
func _on_dividend_changed(value: float) -> void:
	_economy.set_ubi_rate(value / 100.0)
	_land_value_readout_dirty = true
	_update_dividend_label(_economy.dividend_percent)
	_update_resource_ui()
	_request_hover_status_refresh()
	if _land_value_heatmap != null and _land_value_heatmap.visible:
		_land_value_heatmap.queue_redraw()
	if value > 0.0 and _foundations_complete and not _tutorial_resolved:
		_resolve_tutorial()


## Refreshes the trade-off label after each assessment so the displayed per-tick
## cost stays current as factory income changes between drags.
func _on_assessment_refresh_dividend(_net_income: int) -> void:
	_update_dividend_label(_economy.dividend_percent)


## Renders the live economic trade-off for a given dividend % (0–100).
func _update_dividend_label(value: float) -> void:
	var boost_percent: int = int((_economy.get_factory_boost_multiplier(value) - 1.0) * 100.0)
	_economy_hud_presenter.render_dividend(
			value, _economy.get_dividend_cost(value), boost_percent)

# ---- Supply chain simulation ------------------------------------------------

## Pauses the game simulation while leaving the settings overlay responsive.
func _on_pause_requested() -> void:
	if is_game_over:
		return
	if _map_input_controller != null:
		_map_input_controller.cancel_drag()
	_heatmap_visibility_policy.hidden_by_pause = _is_heatmap_effectively_visible()
	_refresh_heatmap_visibility()
	if _factory_status_panel != null:
		_factory_status_panel.hide()
	get_tree().paused = true
	_settings_menu.open_menu()


func _on_resume_requested() -> void:
	_settings_menu.close_menu()
	get_tree().paused = false
	_heatmap_visibility_policy.hidden_by_pause = false
	_refresh_heatmap_visibility()


func _on_main_menu_requested() -> void:
	_settings_menu.close_menu()
	get_tree().paused = false
	var error: Error = get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	if error != OK:
		push_error("Could not return to Main Menu (%s)." % error_string(error))


func _on_save_requested() -> void:
	var save_manager: Node = get_node_or_null("/root/GameSave")
	if save_manager == null:
		_settings_menu.set_status("Save/load is unavailable.")
		return
	var save_result: bool = bool(save_manager.call("save_game", _capture_game_state()))
	if save_result:
		_settings_menu.set_status("City saved successfully.")
		_settings_menu.refresh_save_load_state()
	else:
		_settings_menu.set_status(str(save_manager.get("last_error")))


## Requests a saved state from the autoload, then loads it into this live session.
func _on_load_requested() -> void:
	var save_manager: Node = get_node_or_null("/root/GameSave")
	if save_manager == null:
		_settings_menu.set_status("Save/load is unavailable.")
		return
	var loaded_state: Variant = save_manager.call("load_game")
	if not loaded_state is Dictionary or (loaded_state as Dictionary).is_empty():
		_settings_menu.set_status(str(save_manager.get("last_error")))
		return
	if not _apply_saved_state(loaded_state as Dictionary):
		_settings_menu.set_status("The save data is incompatible with this city.")
		return
	_settings_menu.set_status("Saved city loaded successfully.")


func _capture_game_state() -> Dictionary:
	var tiles: Array[Dictionary] = []
	for pos: Vector2i in _grid.get_all_occupied_positions():
		var data: GridCellData = _grid.get_tile(pos)
		if data == null:
			continue
		tiles.append({
			"x": pos.x,
			"y": pos.y,
			"type": data.tile_type,
			"land_value_modifier": data.land_value_modifier
		})
	var claimed_times: Array[Dictionary] = _timestamp_entries_to_data(_economy.tile_claimed_times)
	var build_times: Array[Dictionary] = _timestamp_entries_to_data(_economy.tile_build_times)
	var strikes: Array[Dictionary] = _timestamp_entries_to_data(_economy.factory_strike_until_msec)
	var state: Dictionary = {
		"grid_size": GRID_SIZE,
		"tiles": tiles,
		"money": current_money,
		"goods_stock": goods_stock,
		"foundations_complete": _foundations_complete,
		"objectives_collapsed": _objectives_collapsed,
		"tutorial_milestone_announced": _tutorial_milestone_announced,
		"dividend_percent": _economy.dividend_percent,
		"ubi_rate": _economy.ubi_rate,
		"lvt_rate": _economy.get_lvt_rate(),
		"town_level": _town_progression.get_town_level() if _town_progression != null else TownProgressionManager.TownLevel.HAMLET,
		"cumulative_lvt_revenue": _economy.cumulative_lvt_revenue,
		"speculator_lots": _speculator_manager.serialize_lots() if _speculator_manager != null else [],
		"tutorial_resolved": _tutorial_resolved,
		"tile_claimed_times": claimed_times,
		"tile_build_times": build_times,
		"factory_strikes": strikes,
		"goods_supplied": _goods_supplied_entries_to_data(),
		"water_supplied": _supply_chain.serialize_water_supplied(),
		"assessment_time_left": _timer_time_left(_economy.get_node_or_null("AssessmentTimer") as Timer),
		"supply_time_left": _timer_time_left(_supply_chain.get_supply_chain_timer())
	}
	return state


func _apply_saved_state(state: Dictionary) -> bool:
	var saved_grid_size: int = int(state.get("grid_size", -1))
	if saved_grid_size != GRID_SIZE and saved_grid_size != 20:
		return false
	var tile_values: Variant = state.get("tiles", null)
	if not tile_values is Array:
		return false
	var tile_records: Array = tile_values as Array
	var seen_cells: Dictionary = {}
	for record_value: Variant in tile_records:
		if not record_value is Dictionary:
			return false
		var record: Dictionary = record_value as Dictionary
		var pos: Vector2i = Vector2i(int(record.get("x", -1)), int(record.get("y", -1)))
		var tile_type: int = int(record.get("type", -1))
		if not _is_in_grid(pos) or tile_type <= GridCellData.TileType.EMPTY \
				or tile_type > GridCellData.TileType.WATER_TOWER_LARGE or seen_cells.has(pos):
			return false
		seen_cells[pos] = true
	var supplied_values: Variant = state.get("goods_supplied", [])
	if not supplied_values is Array:
		return false
	if not _validate_timestamp_entries(state.get("tile_claimed_times", [])) \
			or not _validate_timestamp_entries(state.get("tile_build_times", [])) \
			or not _validate_timestamp_entries(state.get("factory_strikes", [])):
		return false
	for supplied_value: Variant in supplied_values as Array:
		if not supplied_value is Dictionary:
			return false
		var supplied_record: Dictionary = supplied_value as Dictionary
		var supplied_pos: Vector2i = Vector2i(
				int(supplied_record.get("x", -1)), int(supplied_record.get("y", -1)))
		if not _is_in_grid(supplied_pos):
			return false
	if not _validate_timer_value(
			state.get("assessment_time_left", -1.0), _economy.assessment_interval) \
			or not _validate_timer_value(
				state.get("supply_time_left", -1.0), SUPPLY_CHAIN_TICK_INTERVAL):
		return false

	# Clear derived visuals and grid state before rebuilding every saved tile.
	_placement.clear_buildings()
	_tilemap.clear()
	_grid.clear_all()
	_economy.tile_claimed_times.clear()
	_economy.tile_build_times.clear()
	_economy.factory_strike_until_msec.clear()
	_road_connectivity.clear_cache()
	_supply_chain.clear_supplied_goods()
	_supply_chain.clear_supplied_water()
	if _residential_evolution != null:
		_residential_evolution.clear_state()
	_is_load_rebuild = true
	_pipe_network.mark_dirty()
	current_money = int(state.get("money", 1000))
	goods_stock = maxi(0, int(state.get("goods_stock", 0)))
	_foundations_complete = bool(state.get("foundations_complete", false))
	_objectives_collapsed = bool(state.get("objectives_collapsed", _foundations_complete))
	_tutorial_milestone_announced = bool(state.get("tutorial_milestone_announced", _foundations_complete))
	if state.has("ubi_rate"):
		_economy.set_ubi_rate(float(state.get("ubi_rate", 0.0)))
	else:
		_economy.set_dividend_percent(float(state.get("dividend_percent", 0.0)))
	_dividend_slider.set_value_no_signal(_economy.dividend_percent)
	_economy.set_lvt_rate(float(state.get("lvt_rate", 1.0)))
	_economy.cumulative_lvt_revenue = maxi(0, int(state.get("cumulative_lvt_revenue", 0)))
	_economy.clear_budget_history()
	if _town_progression != null:
		_town_progression.set_town_level(
				int(state.get("town_level", TownProgressionManager.TownLevel.HAMLET)),
				false)
		_economy.town_level_lvt_multiplier = _town_progression.get_lvt_efficiency_multiplier()
	if _speculator_manager != null:
		_speculator_manager.restore_lots(state.get("speculator_lots", []))
	_tutorial_resolved = bool(state.get("tutorial_resolved", false))
	_foundations_complete = _foundations_complete or _tutorial_resolved
	_tutorial_milestone_announced = _tutorial_milestone_announced or _foundations_complete
	_objectives_collapsed = _objectives_collapsed or _foundations_complete

	for record_value: Variant in tile_records:
		var record: Dictionary = record_value as Dictionary
		var pos: Vector2i = Vector2i(int(record["x"]), int(record["y"]))
		var tile_type: int = int(record["type"])
		var modifier: float = float(record.get("land_value_modifier", 0.0))
		_grid.set_tile(pos, GridCellData.new(tile_type, modifier))
		_placement_controller.place_tile(pos, tile_type)
		if tile_type != GridCellData.TileType.GRASS \
				and tile_type != GridCellData.TileType.ROAD \
				and tile_type != GridCellData.TileType.ROAD_CROSS:
			_placement.spawn_building(pos, tile_type)
		_refresh_road_neighbors_for_cell(pos)

	_restore_timestamp_entries(_economy.tile_claimed_times, state.get("tile_claimed_times", []))
	_restore_timestamp_entries(_economy.tile_build_times, state.get("tile_build_times", []))
	_restore_timestamp_entries(_economy.factory_strike_until_msec, state.get("factory_strikes", []))
	_restore_goods_supplied(state.get("goods_supplied", []))
	if state.has("water_supplied"):
		_supply_chain.restore_water_supplied(state.get("water_supplied", []))
	_economy.prune_factory_strikes()

	_pipe_network.mark_dirty()
	_pipe_network.get_live_pipe_cells()
	_rebuild_derived_city_state()
	_is_load_rebuild = false
	_on_pipe_network_changed()
	_update_resource_ui()
	_set_timer_time_left(_economy.get_node_or_null("AssessmentTimer") as Timer, state.get("assessment_time_left", -1.0))
	_set_timer_time_left(
			_supply_chain.get_supply_chain_timer(), state.get("supply_time_left", -1.0))
	return true


func _rebuild_derived_city_state() -> void:
	for pos: Vector2i in _grid.get_all_occupied_positions():
		refresh_road_connections(pos)
	_on_supply_chain_tick()
	_economy.calculate_net_income(false)
	_update_dividend_label(_economy.dividend_percent)
	_update_objectives()
	if _foundations_complete:
		if _tutorial_resolved:
			_show_bobr_dialogue(TUTORIAL_RESOLVE_QUOTE)
		else:
			_show_bobr_dialogue(TUTORIAL_COMPLETE_QUOTE)
	else:
		_bobr_dialogue.hide()
	update_money_ui()
	_update_resource_ui()


func _refresh_road_neighbors_for_cell(pos: Vector2i) -> void:
	_placement_controller.refresh_road_neighbors(pos)


func _goods_supplied_entries_to_data() -> Array[Dictionary]:
	return _supply_chain.serialize_goods_supplied()


func _restore_goods_supplied(values: Variant) -> void:
	_supply_chain.restore_goods_supplied(values)


func _timestamp_entries_to_data(timestamps: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var now: int = Time.get_ticks_msec()
	for key: Variant in timestamps:
		if not key is Vector2i:
			continue
		var pos: Vector2i = key as Vector2i
		var elapsed_or_remaining: int = int(timestamps[key]) - now
		entries.append({
			"x": pos.x,
			"y": pos.y,
			"time_delta": elapsed_or_remaining
		})
	return entries


func _validate_timer_value(value: Variant, maximum: float) -> bool:
	if not value is float and not value is int:
		return false
	return float(value) >= -1.0 and float(value) <= maximum


func _validate_timestamp_entries(values: Variant) -> bool:
	if not values is Array:
		return false
	for entry_value: Variant in values as Array:
		if not entry_value is Dictionary:
			return false
		var entry: Dictionary = entry_value as Dictionary
		var pos: Vector2i = Vector2i(int(entry.get("x", -1)), int(entry.get("y", -1)))
		var delta_value: Variant = entry.get("time_delta", null)
		var valid_delta: bool = delta_value is int
		if delta_value is float:
			var delta_number: float = float(delta_value)
			valid_delta = is_finite(delta_number) and floorf(delta_number) == delta_number
		if not _is_in_grid(pos) or not valid_delta:
			return false
	return true


func _restore_timestamp_entries(destination: Dictionary, values: Variant) -> void:
	if not values is Array:
		return
	var now: int = Time.get_ticks_msec()
	for entry_value: Variant in values as Array:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value as Dictionary
		var pos: Vector2i = Vector2i(int(entry.get("x", -1)), int(entry.get("y", -1)))
		if not _is_in_grid(pos):
			continue
		destination[pos] = now + int(entry.get("time_delta", 0))


func _is_in_grid(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < GRID_SIZE and pos.y >= 0 and pos.y < GRID_SIZE


func _timer_time_left(timer: Timer) -> float:
	return timer.time_left if timer != null else -1.0


func _set_timer_time_left(timer: Timer, time_left: Variant) -> void:
	if timer == null:
		return
	var restored_time: float = float(time_left)
	if restored_time > 0.0:
		timer.start(minf(restored_time, timer.wait_time))


## Configures the supply-chain simulation, starts its timer, and exposes the
## established residential goods tax callback and dual-trigger evolution
## evaluator to EconomyManager.
func _setup_supply_chain() -> void:
	_supply_chain = SupplyChainScript.new() as SupplyChainSimulator
	_supply_chain.name = "SupplyChainSimulator"
	_supply_chain.configure(
			_grid, _road_connectivity, _economy, _pipe_network, _farm_system, GRID_SIZE)
	_supply_chain.is_load_rebuild_provider = func() -> bool: return _is_load_rebuild
	_supply_chain.tick_started.connect(_on_supply_chain_tick_started)
	_supply_chain.tick_completed.connect(_on_supply_chain_tick_completed)
	add_child(_supply_chain)
	_supply_chain.start_timer()
	_economy.residential_goods_tax_bonus_provider = residential_goods_tax_bonus_at
	_economy.factory_water_multiplier_provider = _supply_chain.get_factory_water_multiplier
	_economy.factory_water_status_provider = _factory_water_status_at

	_residential_evolution = ResidentialEvolutionManager.new()
	_residential_evolution.name = "ResidentialEvolutionManager"
	_residential_evolution.configure(
			_grid, _economy, _road_connectivity, _supply_chain)
	add_child(_residential_evolution)
	_economy.residential_evolution_evaluator = _residential_evolution.evaluate_assessment_cycle

## Compatibility entry point used for initial population and load rebuilds.
## The component emits lifecycle signals so the root can refresh its UI and hover.
func _on_supply_chain_tick() -> void:
	_supply_chain.run_tick()


## Direct tax bonus for a residence supplied with goods on the latest supply tick.
func residential_goods_tax_bonus_at(grid_pos: Vector2i) -> int:
	return _supply_chain.residential_goods_tax_bonus_at(grid_pos)


func _on_supply_chain_tick_started() -> void:
	# Factory inspection eligibility and worker priority change with each staffing pass.
	_factory_priority_cache_dirty = true


func _on_supply_chain_tick_completed() -> void:
	_land_value_readout_dirty = true
	_update_resource_ui()
	_request_hover_status_refresh()


# ---- Road connectivity service bridge --------------------------------------

## Notifies dependent UI caches after the connectivity service observes a grid change.
func refresh_road_connections(center: Vector2i) -> void:
	_road_connectivity.refresh_around(center)
	_factory_priority_cache_dirty = true
	_request_hover_status_refresh()


# ---- Tutorial objective tracking (Step 1) ----------------------------------

## Recomputes the tutorial objective counts straight from the current grid and
## refreshes the ObjectiveBox checklist. Idempotent — safe to call after any
## build, bulldoze, or residential evolution.
func _update_objectives() -> void:
	_obj_residential = 0
	_obj_factory = 0
	var total_buildings: int = 0
	var connected_buildings: int = 0
	var hooked_factories: int = 0
	for pos in _grid.get_all_occupied_positions():
		var tile_type: int = _grid.get_tile_type(pos)
		var is_residential: bool = (
			tile_type == GridCellData.TileType.RESIDENTIAL_LOW
			or tile_type == GridCellData.TileType.RESIDENTIAL_HIGH
		)
		if is_residential:
			_obj_residential += 1
		elif tile_type == GridCellData.TileType.INDUSTRIAL:
			_obj_factory += 1
			if _pipe_network.is_factory_hooked_up(pos):
				hooked_factories += 1
		else:
			continue
		total_buildings += 1
		if _road_connectivity.is_road_connected(pos):
			connected_buildings += 1

	# Road objective: the targets are met AND every house/factory sits on a road.
	_obj_road_connected = (
		_obj_residential >= OBJECTIVE_RESIDENTIAL_TARGET
		and _obj_factory >= OBJECTIVE_FACTORY_TARGET
		and total_buildings > 0
		and connected_buildings == total_buildings
	)
	_obj_factories_hooked_up = _obj_factory > 0 and hooked_factories == _obj_factory
	_refresh_objective_ui()

	# Record the foundations milestone once; later demolition does not revoke it.
	if _all_objectives_met() and not _foundations_complete and not _is_load_rebuild:
		_foundations_complete = true
		_objectives_collapsed = true
		_tutorial_milestone_announced = true
		_refresh_objective_ui()
		_show_bobr_dialogue(TUTORIAL_COMPLETE_QUOTE)


## Delegates rendering of objective state and panel layout to its presenter.
func _refresh_objective_ui() -> void:
	_objective_panel_presenter.render(
			_obj_residential,
			_obj_factory,
			_obj_road_connected,
			_obj_factories_hooked_up,
			_foundations_complete,
			_objectives_collapsed,
			_tutorial_resolved,
			OBJECTIVE_RESIDENTIAL_TARGET,
			OBJECTIVE_FACTORY_TARGET)


func _on_objective_header_pressed() -> void:
	_objectives_collapsed = not _objectives_collapsed
	_refresh_objective_ui()


func _on_objective_box_resized() -> void:
	_objective_panel_presenter.update_related_layout()


func _on_economy_flow_pressed() -> void:
	if _economy_flow_panel == null:
		return
	_economy_flow_panel.visible = not _economy_flow_panel.visible
	if _economy_flow_panel.visible:
		_economy_flow_panel.z_index = 100
		_economy_flow_panel.call("update_layout")
	_economy_flow_button.text = "Flow"
	_economy_flow_button.tooltip_text = "Close economic flow details" if _economy_flow_panel.visible \
			else "Open workforce, factory, and goods-flow details"


# ---- Tutorial event triggers (Step 2) --------------------------------------

## Opens Bobr's speech bubble with `quote`. The dialogue starts hidden and is
## closed via the Dismiss button.
func _show_bobr_dialogue(quote: String) -> void:
	if _quote_label == null:
		return
	_quote_label.text = quote
	_bobr_dialogue.show()


## Closes Bobr's speech bubble when the player clicks Dismiss.
func _on_bobr_dialogue_dismiss() -> void:
	_bobr_dialogue.hide()


## True once every tutorial checklist item is complete.
func _all_objectives_met() -> bool:
	return (
		_obj_residential >= OBJECTIVE_RESIDENTIAL_TARGET
		and _obj_factory >= OBJECTIVE_FACTORY_TARGET
		and _obj_road_connected
	)


## Ends the tutorial once the player raises the dividend slider above 0%.
func _resolve_tutorial() -> void:
	_tutorial_resolved = true
	_refresh_objective_ui()
	_show_bobr_dialogue(TUTORIAL_RESOLVE_QUOTE)


# ---- Pipe network visuals + factory status readout --------------------------

## Refreshes pipe sprite tints whenever the logistics network changes (a pipe or
## factory is placed/removed). Live border-connected segments render normally;
## disconnected ones are dimmed via BuildingPlacement.
func _on_pipe_network_changed() -> void:
	if _is_load_rebuild:
		return
	_placement.update_pipe_visuals(
			_pipe_network.get_live_pipe_cells(),
			_pipe_network.get_bottleneck_pipe_cells())
	_request_hover_status_refresh()


## Refreshes pipe warning tints and factory status after a supply tick reallocates flow.
func _on_pipe_capacity_updated() -> void:
	if _is_load_rebuild:
		return
	_placement.update_pipe_capacity_visuals(_pipe_network.get_bottleneck_pipe_cells())
	_request_hover_status_refresh()


## Builds the hover readout that shows a factory's pipe connectivity status.
## Shown while the cursor is over an INDUSTRIAL tile; hidden otherwise.
func _create_factory_status_ui() -> void:
	_factory_status_panel = FactoryStatusReadout.new()
	_factory_status_panel.name = "FactoryStatusPanel"
	_factory_status_panel.visible = false
	$UI.add_child(_factory_status_panel)
	_factory_status_panel.set_objective_panel_height(
			$UI/ObjectiveBox.offset_bottom - $UI/ObjectiveBox.offset_top)


func _create_economy_flow_ui() -> void:
	_economy_flow_panel = EconomyFlowReadout.new()
	_economy_flow_panel.name = "EconomyFlowReadout"
	$UI.add_child(_economy_flow_panel)
	_economy_flow_panel.z_index = 100


## Shows/hides the factory or residential inspection readout for the hovered cell.
func _update_factory_status(cell: Vector2i) -> void:
	if _factory_status_panel == null:
		return
	var tile_type: int = _grid.get_tile_type(cell) if _is_in_grid(cell) else GridCellData.TileType.EMPTY
	var is_factory: bool = tile_type == GridCellData.TileType.INDUSTRIAL
	var is_residential: bool = (
		tile_type == GridCellData.TileType.RESIDENTIAL_LOW
		or tile_type == GridCellData.TileType.RESIDENTIAL_HIGH
		or tile_type == GridCellData.TileType.ABANDONED
	)
	var is_water_tower: bool = (
		tile_type == GridCellData.TileType.WATER_TOWER_SMALL
		or tile_type == GridCellData.TileType.WATER_TOWER_LARGE
	)
	var is_speculator_lot: bool = (
		_speculator_manager != null
		and _is_in_grid(cell)
		and _speculator_manager.is_speculator_owned(cell)
	)
	var show_panel: bool = is_factory or is_residential or is_water_tower or is_speculator_lot
	if _factory_status_panel.visible != show_panel:
		_factory_status_panel.visible = show_panel
	if is_factory:
		_factory_status_panel.set_status_text(_factory_inspection_text(cell))
	elif is_residential:
		_factory_status_panel.set_status_text(_residential_inspection_text(cell))
	elif is_water_tower:
		_factory_status_panel.set_status_text(_water_tower_inspection_text(cell))
	elif is_speculator_lot:
		_factory_status_panel.set_status_text(_speculator_manager.get_lot_inspection_text(cell))


func _factory_water_status_at(factory_pos: Vector2i) -> String:
	if _supply_chain == null or _road_connectivity == null:
		return ""
	if not _road_connectivity.is_road_connected(factory_pos):
		return "WATER: Disconnected from road network — output reduced by 50%"
	var stats: Dictionary = _supply_chain.get_network_water_stats_for_cell(factory_pos)
	var supplied: bool = _supply_chain.is_water_supplied(factory_pos)
	var header: String = (
		"WATER: Active road-network supply — 100% efficiency"
		if supplied
		else "WATER: Unsupplied — output reduced by 50%"
	)
	var flow: String = "Road water pool: %d/%d capacity · demand %d" % [
		int(stats["delivered"]), int(stats["capacity"]), int(stats["demand"])
	]
	if bool(stats["bottleneck"]):
		flow += " — SHORTAGE"
	return header + "\n" + flow


func _water_tower_inspection_text(tower_pos: Vector2i) -> String:
	var tile_type: int = _grid.get_tile_type(tower_pos)
	var tier_label: String = (
		"Tier 1 Small Water Tower (+30 Capacity)"
		if tile_type == GridCellData.TileType.WATER_TOWER_SMALL
		else "Tier 2 Large Water Tower (+80 Capacity)"
	)
	if not _road_connectivity.is_road_connected(tower_pos):
		return "WATER INFRASTRUCTURE: %s\nSTATUS: Offline — needs cardinal road connection" % tier_label
	var stats: Dictionary = _supply_chain.get_network_water_stats_for_cell(tower_pos)
	var status: String = "STATUS: Active on road network #%d" % _road_connectivity.get_building_network_id(tower_pos)
	var flow: String = "Network water pool: %d/%d capacity · demand %d" % [
		int(stats["delivered"]), int(stats["capacity"]), int(stats["demand"])
	]
	if bool(stats["bottleneck"]):
		flow += " — SHORTAGE"
	return "WATER INFRASTRUCTURE: %s\n%s\n%s" % [tier_label, status, flow]


func _residential_inspection_text(cell: Vector2i) -> String:
	if _residential_evolution == null:
		return ""
	return _residential_evolution.get_inspection_text(cell)


func _ensure_factory_priority_cache() -> void:
	if not _factory_priority_cache_dirty:
		return
	_factory_priority_order.clear()
	_factory_priority_index.clear()
	for grid_pos: Vector2i in _grid.get_all_occupied_positions():
		if _grid.get_tile_type(grid_pos) == GridCellData.TileType.INDUSTRIAL \
				and _road_connectivity.is_road_connected(grid_pos) \
				and not _economy.is_factory_on_strike(grid_pos):
			_factory_priority_index[grid_pos] = _factory_priority_order.size()
			_factory_priority_order.append(grid_pos)
	_factory_priority_cache_dirty = false


func _factory_inspection_text(factory_pos: Vector2i) -> String:
	var status_line: String = "STATUS: Operating"
	var output: int = _supply_chain.get_factory_delivered_goods(factory_pos)
	_ensure_factory_priority_cache()
	var worker_priority: int = int(_factory_priority_index.get(factory_pos, -1))
	var workers_before_this: int = maxi(
			0, worker_capacity - maxi(worker_priority, 0) * WORKERS_PER_FACTORY)
	if not _road_connectivity.is_road_connected(factory_pos):
		status_line = "STATUS: Offline — needs a road connection"
	elif _economy.is_factory_on_strike(factory_pos):
		status_line = "STATUS: On strike — production paused"
	elif not _economy.staffed_factories.has(factory_pos):
		var missing_workers: int = maxi(0, WORKERS_PER_FACTORY - workers_before_this)
		status_line = "STATUS: Idle — needs %d more workers (%d available before this factory)" % [
			missing_workers, workers_before_this]
		if missing_workers > 0:
			status_line += "\nAdd residences to grow workforce."
	else:
		status_line = "STATUS: Operating — %d workers assigned · %d goods per %s-second cycle" % [
			WORKERS_PER_FACTORY, output, str(SUPPLY_CHAIN_TICK_INTERVAL)]
	return status_line + "\n" + _economy.factory_pipe_status(factory_pos)


# ---- Bootstrap helper -------------------------------------------------------

## Creates a compact fixed-screen readout for the hovered heatmap cell.
func _create_land_value_readout_ui() -> void:
	_land_value_readout_panel = HeatmapReadout.new()
	_land_value_readout_panel.name = "LandValueReadoutPanel"
	_land_value_readout_panel.visible = false
	$UI.add_child(_land_value_readout_panel)


## Shows the hovered cell's land value and a pollution warning when applicable.
func _update_land_value_readout(cell: Vector2i) -> void:
	if _land_value_readout_panel == null:
		return
	if not _is_heatmap_effectively_visible() or not _is_in_grid(cell):
		_land_value_readout_dirty = true
		_cached_land_value_cell = Vector2i(-1, -1)
		_set_land_value_readout_visible(false)
		return
	_set_land_value_readout_visible(true)
	if cell == _cached_land_value_cell and not _land_value_readout_dirty:
		return
	_cached_land_value_text = "%d/100" % _economy.get_land_value(cell)
	_cached_pollution_risk = _economy.is_within_pollution_risk(cell)
	var is_spec_lot: bool = (
		_speculator_manager != null
		and _speculator_manager.is_speculator_owned(cell)
	)
	_cached_land_value_cell = cell
	_land_value_readout_dirty = false
	_land_value_readout_panel.show_cell(_cached_land_value_text, _cached_pollution_risk, is_spec_lot)


func _set_land_value_readout_visible(show_readout: bool) -> void:
	if not show_readout and _land_value_readout_panel != null:
		_land_value_readout_panel.invalidate_cell()
	if _land_value_readout_panel != null \
			and _land_value_readout_panel.visible != show_readout:
		_land_value_readout_panel.visible = show_readout


## Creates and adds the EconomyManager as a child, then returns it.
func _create_economy_manager() -> EconomyManager:
	var em := EconomyManager.new()
	em.name = "EconomyManager"
	em.grid = _grid
	em.grid_size = GRID_SIZE
	em.assessment_interval = 5.0
	add_child(em)
	move_child(em, 0)
	return em


## Creates and adds the BuildingPlacement manager, wiring its tilemap reference.
func _create_placement_manager() -> BuildingPlacement:
	var bp := BuildingPlacement.new()
	bp.name = "BuildingPlacement"
	bp.tilemap = _tilemap
	bp.grid = _grid
	add_child(bp)
	return bp


## Creates and adds the PipeNetworkManager, returning it for injection into the
## economy (hookup multipliers) and placement controller (cache invalidation).
func _create_pipe_network_manager() -> PipeNetworkManager:
	var pn := PipeNetworkManager.new()
	pn.name = "PipeNetworkManager"
	pn.grid = _grid
	pn.grid_size = GRID_SIZE
	add_child(pn)
	return pn

## All ground-tile writes are delegated to _placement_controller.place_tile(),
## which owns the TileSet mapping (see placement_controller.gd TILE_TYPE_MAP).
