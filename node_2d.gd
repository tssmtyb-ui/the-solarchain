extends Node2D
## Root scene script for Spekulant.
##
## Owns the TileMapLayer, GridManager, and EconomyManager and bridges
## the data model to rendering, player input, and simulation.

@onready var _grid: GridManager = $GridManager
@onready var _tilemap: TileMapLayer = $TileMapLayer
@onready var _hover_layer: Node2D = $HoverLayer
@onready var _economy: EconomyManager = _create_economy_manager()
@onready var _money_label: Label = $UI/TopBar/HBoxContainer/MoneyLabel
@onready var _workers_label: Label = $UI/TopBar/HBoxContainer/WorkersLabel
@onready var _goods_label: Label = $UI/TopBar/HBoxContainer/GoodsLabel
@onready var _dividend_slider: HSlider = $UI/TopBar/HBoxContainer/DividendBox/DividendSlider
@onready var _dividend_label: Label = $UI/TopBar/HBoxContainer/DividendBox/DividendLabel
@onready var _objective_residential: CheckBox = $UI/ObjectiveBox/MarginContainer/VBoxContainer/CheckResidential
@onready var _objective_factory: CheckBox = $UI/ObjectiveBox/MarginContainer/VBoxContainer/CheckFactory
@onready var _objective_road: CheckBox = $UI/ObjectiveBox/MarginContainer/VBoxContainer/CheckRoad
@onready var _bobr_dialogue: PanelContainer = $UI/BobrDialogue
@onready var _quote_label: Label = $UI/BobrDialogue/MarginContainer/HBoxContainer/VBoxContainer/QuoteLabel
@onready var _dismiss_button: Button = $UI/BobrDialogue/MarginContainer/HBoxContainer/VBoxContainer/DismissButton
@onready var _placement: BuildingPlacement = _create_placement_manager()

## Corporate speculator AI — its claimed land is off-limits to the player.
var _speculator: SpeculatorManager

## Placement controller — single owner of the player build pipeline.
var _placement_controller: PlacementController

## Pipe/logistics connectivity graph — the live BFS network for SLUDGE hookups.
var _pipe_network: PipeNetworkManager

## Factory pipe-status hover readout (built programmatically in _ready).
var _factory_status_panel: PanelContainer
var _factory_status_label: Label

## Grid dimensions for the starting map.
const GRID_SIZE: int = 10

## Preloaded highlight texture for the mouse hover indicator.
const HIGHLIGHT_TEXTURE: Texture2D = preload("res://assets/generated/highlight_diamond_clean.png")

## Tracks the last hovered cell so we can erase the old highlight.
var _last_hovered_cell: Vector2i = Vector2i(-1, -1)

## The Sprite2D used for the mouse-hover highlight indicator.
var _hover_sprite: Sprite2D = Sprite2D.new()

## Sentinel value for the bulldoze tool (not a GridCellData tile type).
const BULLDOZE: int = -1

## The tool mode the player is currently using (via UI toggle).
## EMPTY = no tool, BULLDOZE = demolition, otherwise a GridCellData.TileType.
var current_build_mode: int = GridCellData.TileType.EMPTY

## Player's current money balance.
var current_money: int = 1000

## True once the player goes bankrupt (money drops below zero); blocks input.
var is_game_over: bool = false

# ---------------------------------------------------------------------------
#   Supply chain simulation — Step 1: workers, goods & land value
# ---------------------------------------------------------------------------

## Seconds between supply-chain simulation ticks.
const SUPPLY_CHAIN_TICK_INTERVAL: float = 3.0

## Workers contributed to the labour pool per residential tile.
const WORKERS_PER_VILLA: int = 1
const WORKERS_PER_APARTMENT: int = 3

## Workers a factory must draw from the pool to operate.
const WORKERS_PER_FACTORY: int = 2

## Goods each operating factory produces per tick.
const GOODS_PER_FACTORY_TICK: int = 3

## Goods each house consumes per tick (when the pool can afford it).
const GOODS_PER_HOUSE_TICK: int = 1

## Manhattan radius over which a well-supplied house boosts land value.
const GOODS_BOOST_RADIUS: int = 2

## Land-value bonus added per well-supplied house within the boost radius.
const GOODS_LAND_VALUE_BOOST: int = 5

## Total worker capacity contributed by all residential tiles.
var worker_capacity: int = 0

## Workers not yet claimed by factories this tick.
var available_workers: int = 0

## Global goods stockpool — produced by factories, consumed by houses.
var goods_stock: int = 0

## Residential tiles that were well-supplied on the last tick (Vector2i → bool).
var _goods_supplied: Dictionary = {}

## Factories that drew workers and produced goods on the last tick.
var operating_factories: int = 0

# ---------------------------------------------------------------------------
#   Road network validation — Step 2: adjacency checks
# ---------------------------------------------------------------------------

## Cardinal offsets (N, E, S, W) used for road-adjacency checks.
const _CARDINAL_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]

## Road-connection state for every placed house/factory tile (Vector2i → bool).
## A building only participates in the supply chain while its entry is true.
var _road_connected: Dictionary = {}

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

## Bobr's greeting to the new mayor, shown once at launch.
const TUTORIAL_INTRO_QUOTE := "Aha, a new mayor! Do me a favor: build some roads and factories so land values skyrocket. Just don't touch that dividend slider... you want me to get rich, right?"
## Bobr's triumphant taunt right after the land grab.
const TUTORIAL_COMPLETE_QUOTE := "Thanks for the unearned land value boost! I'm letting this prime plot sit empty while your city grows."
## Bobr grudgingly pays the land-value tax once the player resolves the tutorial.
const TUTORIAL_RESOLVE_QUOTE := "Tsk... a land-value tax? Fine. I'll pay it like everyone else — but I'll be watching this plot appreciate, mayor."

## Whether Bobr has grabbed his speculative dirt lot (completion fires once).
var _tutorial_bobr_grabbed: bool = false
## Whether the player raised the LVT slider to end the tutorial.
var _tutorial_resolved: bool = false
## Grid position of Bobr's dirt lot (Vector2i(-1,-1) until claimed).
var _bobr_dirt_lot: Vector2i = Vector2i(-1, -1)

## The Citizen's Dividend live trade-off label (resolved from the scene's TopBar
## via @onready above).

func _ready() -> void:
	assert(_grid != null, "GridManager node missing!")
	assert(_tilemap != null, "TileMapLayer node missing!")

	# Make the Camera2D explicitly current and position it.
	# With 512×256 tile size and 10×10 grid, centre is at roughly (2560, 128).
	$Camera2D.make_current()
	$Camera2D.position = Vector2(2560, 128)
	$Camera2D.zoom = Vector2(0.2, 0.2)

	# Wire up economy signal.
	_economy.assessment_completed.connect(_on_assessment_completed)
	_economy.residential_evolution_triggered.connect(_on_residential_evolution)

	# Corporate speculator AI — its claimed land is off-limits to the player.
	_speculator = SpeculatorManager.new()
	add_child(_speculator)
	_speculator.speculator_bankrupt.connect(_on_speculator_bankrupt)
	_speculator.speculator_panic_sold.connect(_on_speculator_panic_sold)
	_speculator.speculator_claimed_tile.connect(claim_tile_for_speculator)

	# Pipe/logistics network — cached BFS connectivity for SLUDGE hookups.
	# Visual refreshes ride the network_changed signal so pipe sprites always
	# reflect the latest live/dead connectivity.
	_pipe_network = _create_pipe_network_manager()
	_economy.pipe_network = _pipe_network
	_pipe_network.network_changed.connect(_on_pipe_network_changed)

	# Placement controller — single owner of the player build pipeline
	# (cost lookup, placement rules, money deduction, grid and sprite writes).
	_placement_controller = PlacementController.new()
	_placement_controller.name = "PlacementController"
	_placement_controller.grid = _grid
	_placement_controller.tilemap = _tilemap
	_placement_controller.placement = _placement
	_placement_controller.speculator = _speculator
	_placement_controller.pipe_network = _pipe_network
	_placement_controller.grid_size = GRID_SIZE
	add_child(_placement_controller)
	# Demolishing a public park triggers a global industrial strike.
	_placement_controller.park_demolished.connect(_economy.trigger_industrial_strike)

	# Set up the hover-highlight sprite (a yellow diamond outline).
	_hover_sprite.texture = HIGHLIGHT_TEXTURE
	_hover_sprite.centered = true
	_hover_sprite.z_index = 100  # always render on top
	_hover_layer.add_child(_hover_sprite)

	# Connect UI toggle buttons for build modes (all live in the bottom BuildBar dock).
	var road_toggle: TextureButton = $UI/BuildBar/HBoxContainer/RoadToggle
	road_toggle.tooltip_text = "Build Road"
	road_toggle.toggled.connect(_on_road_toggle_toggled)

	var factory_toggle: TextureButton = $UI/BuildBar/HBoxContainer/FactoryToggle
	factory_toggle.tooltip_text = "Build Factory"
	factory_toggle.toggled.connect(_on_factory_toggle_toggled)

	var warehouse_toggle: TextureButton = $UI/BuildBar/HBoxContainer/WarehouseToggle
	warehouse_toggle.tooltip_text = "Build Warehouse"
	warehouse_toggle.toggled.connect(_on_warehouse_toggle_toggled)

	var residential_toggle: TextureButton = $UI/BuildBar/HBoxContainer/ResidentialToggle
	residential_toggle.tooltip_text = "Build Residential"
	residential_toggle.toggled.connect(_on_residential_toggle_toggled)

	var park_toggle: TextureButton = $UI/BuildBar/HBoxContainer/ParkToggle
	park_toggle.tooltip_text = "Build Park"
	park_toggle.toggled.connect(_on_park_toggle_toggled)

	var sludge_toggle: TextureButton = $UI/BuildBar/HBoxContainer/SludgeToggle
	sludge_toggle.tooltip_text = "Build Sludge Line"
	sludge_toggle.toggled.connect(_on_sludge_toggle_toggled)

	var bulldoze_toggle: TextureButton = $UI/BuildBar/HBoxContainer/BulldozeToggle
	bulldoze_toggle.tooltip_text = "Bulldozer (Demolish)"
	bulldoze_toggle.toggled.connect(_on_bulldoze_toggle_toggled)

	# --- Initialise a clean GRASS map with edge highway connections ---
	_init_grass_grid()
	_spawn_edge_highways()

	# Start the economy immediately (timer auto-starts in EconomyManager._ready()).
	_economy.calculate_net_income()

	# Supply-chain simulation (Step 1): its own tick timer, plus a land-value
	# hook into the economy so well-supplied housing raises tax/dividend output.
	_setup_supply_chain()

	# --- Start background music ---
	add_child(MusicManager.new())

	# --- Build programmatic UI overlays (credits + game-over screen) ---
	UIBuilder.new().build_ui($UI, _on_restart_pressed)

	# Toggleable Credits popup — created in code so all content stays fully
	# self-contained in CreditsPanel (see scripts/ui/credits_panel.gd).
	# It self-wires to the Credits button in the TopBar via its relative path.
	var credits_panel := CreditsPanel.new()
	credits_panel.name = "CreditsPanel"
	credits_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	credits_panel.offset_left = -300.0
	credits_panel.offset_right = 300.0
	credits_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	credits_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	$UI.add_child(credits_panel)

	# Citizen's Dividend Policy — the slider + label now live in the scene's TopBar
	# (see node_2d.tscn) and are resolved via @onready refs. Wire the live
	# trade-off behaviour here: refresh on drag AND whenever factory income changes.
	_update_dividend_label(_dividend_slider.value)
	_dividend_slider.value_changed.connect(_on_dividend_changed)
	_dismiss_button.pressed.connect(_on_bobr_dialogue_dismiss)
	_economy.assessment_completed.connect(_on_assessment_refresh_dividend)

	# Hover readout showing a factory's pipe connectivity status (built in code
	# so it needs no scene edits; hidden until the cursor is over a factory).
	_create_factory_status_ui()

	update_money_ui()
	_update_resource_ui()
	_update_objectives()

	prints("World initialised — place roads and factories freely.")

	# Tutorial Step 2: Bobr greets the new mayor on launch.
	_show_bobr_dialogue(TUTORIAL_INTRO_QUOTE)


## Fills the grid with uniform GRASS tiles — the player's blank canvas.
func _init_grass_grid() -> void:
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			var cell := Vector2i(x, y)
			_grid.set_tile(cell, GridCellData.new(GridCellData.TileType.GRASS))
			_placement_controller.place_tile(cell, GridCellData.TileType.GRASS)


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


## Claims a grid position for the corporate speculator: registers it in the
## AI's portfolio and paints a dirt lot so the player can see the land is taken.
func claim_tile_for_speculator(grid_pos: Vector2i) -> void:
	if _speculator.owned_tiles.has(grid_pos):
		return
	_speculator.owned_tiles.append(grid_pos)
	_grid.set_tile(grid_pos, GridCellData.new(GridCellData.TILE_DIRT_LOT))
	_placement_controller.place_tile(grid_pos, GridCellData.TILE_DIRT_LOT)

# ---- Input ----------------------------------------------------------------

## Track mouse position every frame to highlight the hovered cell.
func _process(_delta: float) -> void:
	var mouse_pos: Vector2 = get_global_mouse_position()
	var cell: Vector2i = _tilemap.local_to_map(mouse_pos)

	# Clamp to grid bounds — hide the sprite when outside the map.
	if cell.x < 0 or cell.x >= GRID_SIZE or cell.y < 0 or cell.y >= GRID_SIZE:
		_hover_sprite.visible = false
		_last_hovered_cell = Vector2i(-1, -1)
		_update_factory_status(cell)
		return

	# Position the highlight at the diamond centre of the hovered cell.
	var local: Vector2 = _tilemap.map_to_local(cell)
	_hover_sprite.visible = true
	if cell != _last_hovered_cell:
		_hover_sprite.position = local
		_last_hovered_cell = cell
	# Factory pipe-status readout follows the cursor (checked every frame so it
	# stays live when a build/demolish changes connectivity under the cursor).
	_update_factory_status(cell)


func _unhandled_input(event: InputEvent) -> void:
	if is_game_over:
		return

	# Hotkeys: 5 = Park, 6 = Sludge (activates the matching UI toggle).
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_5:
				$UI/BuildBar/HBoxContainer/ParkToggle.set_pressed(true)
				return
			KEY_6:
				$UI/BuildBar/HBoxContainer/SludgeToggle.set_pressed(true)
				return

	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var grid_pos: Vector2i = _tilemap.local_to_map(get_global_mouse_position())

	if grid_pos.x < 0 or grid_pos.x >= GRID_SIZE or grid_pos.y < 0 or grid_pos.y >= GRID_SIZE:
		return

	if current_build_mode == GridCellData.TileType.EMPTY:
		prints("No tool selected — toggle Road or Factory button first.")
		return

	# Hostile buyout: clicking a speculator-owned DIRT_LOT intercepts the build
	# pipeline — spend HOSTILE_BUYOUT_PREMIUM to seize the land back from the AI.
	if _speculator.owned_tiles.has(grid_pos) or _grid.get_tile_type(grid_pos) == GridCellData.TileType.DIRT_LOT:
		var lot_result: Dictionary = _placement_controller.attempt_hostile_buyout(grid_pos, current_money)
		if not lot_result.ok:
			if lot_result.reason != "":
				prints(lot_result.reason)
			return
		current_money = lot_result.money
		update_money_ui()
		# Release the claimed tile back to a blank GRASS lot.
		_grid.set_tile(grid_pos, GridCellData.new(GridCellData.TileType.GRASS))
		_placement_controller.place_tile(grid_pos, GridCellData.TileType.GRASS)
		_placement.remove_building(grid_pos)
		prints("Hostile buyout of speculator land at", grid_pos)
		return

	# Delegate the whole build pipeline (cost lookup, placement rules, money
	# deduction, grid writes, sprite spawning) to the placement controller.
	# It returns the new balance on success, or { ok: false, reason } with
	# the money untouched on rejection ("" reason = silent no-op).
	var existing: int = _grid.get_tile_type(grid_pos)
	var result: Dictionary
	if current_build_mode == BULLDOZE:
		result = _placement_controller.attempt_bulldoze(grid_pos, current_money)
	else:
		result = _placement_controller.attempt_build(current_build_mode, grid_pos, current_money)

	if not result.ok:
		if result.reason != "":
			prints(result.reason)
		return

	current_money = result.money
	update_money_ui()

	# Step 2: road-network validation — a newly placed/demolished tile can change
	# the connectivity of this cell and its neighbours, so refresh them now.
	refresh_road_connections(grid_pos)
	# Step 3: a build/demolish can change capacity and goods — refresh the readouts.
	_update_resource_ui()
	# Tutorial: recount objectives after any placement or demolition.
	_update_objectives()

	if result.placed_type == GridCellData.TileType.GRASS:
		prints("Demolished", GridCellData.TileType.keys()[existing], "at", grid_pos)
	elif existing == GridCellData.TileType.RESIDENTIAL_LOW and result.placed_type == GridCellData.TileType.RESIDENTIAL_HIGH:
		# Arm the evolution buffer so the fresh upgrade can't be auto-downgraded
		# by a land-value fluctuation on the very next assessment.
		_economy.stamp_evolution_cooldown(grid_pos)
		prints("Upgraded to RESIDENTIAL_HIGH at", grid_pos)
	else:
		prints("Placed", GridCellData.TileType.keys()[result.placed_type], "at", grid_pos)

## Called when the Road toggle button is switched on/off.
## ON  → set build mode to ROAD. OFF → reset build mode to EMPTY.
## The button icon is always the road01.png tile (like the other build icons),
## so no switch-texture swapping happens here anymore.
func _on_road_toggle_toggled(toggled_on: bool) -> void:
	if toggled_on:
		current_build_mode = GridCellData.TileType.ROAD
		_unpress_other_toggles("RoadToggle")
		prints("Build mode: ROAD")
	else:
		current_build_mode = GridCellData.TileType.EMPTY
		prints("Build mode: OFF")

## Called when the Factory toggle button is switched on/off.
## ON  → set build mode to INDUSTRIAL, show warehouse texture (active).
## OFF → reset build mode to EMPTY, restore inactive texture.
func _on_factory_toggle_toggled(toggled_on: bool) -> void:
	var btn: TextureButton = $UI/BuildBar/HBoxContainer/FactoryToggle
	if toggled_on:
		current_build_mode = GridCellData.TileType.INDUSTRIAL
		btn.texture_normal = preload("res://assets/factory/FactoryC.png")
		_unpress_other_toggles("FactoryToggle")
		prints("Build mode: INDUSTRIAL")
	else:
		current_build_mode = GridCellData.TileType.EMPTY
		btn.texture_normal = preload("res://assets/factory/FactoryC.png")
		prints("Build mode: OFF")

## Called when the Warehouse toggle button is switched on/off.
## ON  → set build mode to WAREHOUSE.
## OFF → reset build mode to EMPTY.
func _on_warehouse_toggle_toggled(toggled_on: bool) -> void:
	if toggled_on:
		current_build_mode = GridCellData.TileType.WAREHOUSE
		_unpress_other_toggles("WarehouseToggle")
		prints("Build mode: WAREHOUSE")
	else:
		current_build_mode = GridCellData.TileType.EMPTY
		prints("Build mode: OFF")

## Called when the Residential toggle button is switched on/off.
## ON  → set build mode to RESIDENTIAL_LOW.
## OFF → reset build mode to EMPTY.
func _on_residential_toggle_toggled(toggled_on: bool) -> void:
	if toggled_on:
		current_build_mode = GridCellData.TileType.RESIDENTIAL_LOW
		_unpress_other_toggles("ResidentialToggle")
		prints("Build mode: RESIDENTIAL_LOW")
	else:
		current_build_mode = GridCellData.TileType.EMPTY
		prints("Build mode: OFF")

## Called when the Bulldoze toggle button is switched on/off.
## ON  → set build mode to BULLDOZE, show Switch01 (active).
## OFF → reset build mode to EMPTY, show Switch02 (inactive).
## Unpresses Road and Factory toggles when activated (mutual exclusion).
func _on_bulldoze_toggle_toggled(toggled_on: bool) -> void:
	var btn: TextureButton = $UI/BuildBar/HBoxContainer/BulldozeToggle
	if toggled_on:
		current_build_mode = BULLDOZE
		btn.texture_normal = preload("res://Ui/Switch01.png")
		_unpress_other_toggles("BulldozeToggle")
		prints("Build mode: BULLDOZE")
	else:
		current_build_mode = GridCellData.TileType.EMPTY
		btn.texture_normal = preload("res://Ui/Switch02.png")
		prints("Build mode: OFF")

## Called when the Park toggle button is switched on/off.
## ON  → set build mode to PARK. OFF → reset build mode to EMPTY.
func _on_park_toggle_toggled(toggled_on: bool) -> void:
	if toggled_on:
		current_build_mode = GridCellData.TileType.PARK
		_unpress_other_toggles("ParkToggle")
		prints("Build mode: PARK")
	else:
		current_build_mode = GridCellData.TileType.EMPTY
		prints("Build mode: OFF")

## Called when the Sludge toggle button is switched on/off.
## ON  → set build mode to SLUDGE. OFF → reset build mode to EMPTY.
func _on_sludge_toggle_toggled(toggled_on: bool) -> void:
	if toggled_on:
		current_build_mode = GridCellData.TileType.SLUDGE
		_unpress_other_toggles("SludgeToggle")
		prints("Build mode: SLUDGE")
	else:
		current_build_mode = GridCellData.TileType.EMPTY
		prints("Build mode: OFF")

## Unpresses every other build-mode toggle so only `except_name` stays active.
## The ButtonGroup already handles visual exclusivity; this keeps state in sync
## when modes are switched programmatically (e.g. via hotkeys).
func _unpress_other_toggles(except_name: String) -> void:
	for child in $UI/BuildBar/HBoxContainer.get_children():
		if child is TextureButton and child.name != except_name and child.button_pressed:
			child.set_pressed_no_signal(false)

func _on_assessment_completed(net_income: int) -> void:
	current_money += net_income
	update_money_ui()
	# Drive the corporate speculator AI on the same economic cadence.
	_speculator.process_speculator_tick(_economy)
	_speculator.scan_and_buy_land(_grid, _economy)
	prints("Assessment: net:", net_income)

## Handles speculator bankruptcy: liquidate its entire portfolio back to grass.
func _on_speculator_bankrupt(owned: Array[Vector2i]) -> void:
	for pos in owned:
		_release_speculator_tile(pos)

## Handles a single panic-sold tile: return it to the open market (grass).
func _on_speculator_panic_sold(grid_pos: Vector2i) -> void:
	_release_speculator_tile(grid_pos)

## Removes the DIRT_LOT visual at `grid_pos`, returning the tile to empty
## grass so the player can buy/build it again.
func _release_speculator_tile(grid_pos: Vector2i) -> void:
	_grid.set_tile(grid_pos, GridCellData.new(GridCellData.TileType.GRASS))
	_placement_controller.place_tile(grid_pos, GridCellData.TileType.GRASS)
	_placement.remove_building(grid_pos)

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
	_workers_label.text = "Workers: %d/%d" % [available_workers, worker_capacity]
	_goods_label.text = "Goods: %d" % goods_stock


## Updates the money label to reflect the current balance.
func update_money_ui() -> void:
	_money_label.text = "$%d" % current_money

	# Game over check: bankruptcy freezes the game and shows the game-over screen.
	if current_money < 0 and not is_game_over:
		is_game_over = true
		var timer: Timer = _economy.get_node_or_null("AssessmentTimer")
		if timer:
			timer.stop()
		$UI/GameOverPanel.show()


## Restarts the current scene when the player clicks "Restart Game".
func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()


## Pushes the slider value to the economy and refreshes the trade-off label.
func _on_dividend_changed(value: float) -> void:
	_economy.set_dividend_percent(value)
	_update_dividend_label(value)
	# Tutorial Step 2: raising the land-value tax forces Bobr to pay up.
	if value > 0.0 and _tutorial_bobr_grabbed and not _tutorial_resolved:
		_resolve_tutorial()


## Refreshes the trade-off label after each assessment so the displayed per-tick
## cost stays current as factory income changes between drags.
func _on_assessment_refresh_dividend(_net_income: int) -> void:
	_update_dividend_label(_economy.dividend_percent)


## Renders the live economic trade-off for a given dividend % (0–100).
func _update_dividend_label(value: float) -> void:
	if _dividend_label == null:
		return
	var boost_percent: int = int((_economy.get_factory_boost_multiplier(value) - 1.0) * 100.0)
	if value <= 0.0:
		_dividend_label.text = "Dividend: 0% (No production boost, keeping 100% tax revenue)"
	elif value >= 100.0:
		_dividend_label.text = "Dividend: 100%% (Costs all tax revenue, boosts factory production by +%d%%)" % boost_percent
	else:
		_dividend_label.text = "Dividend: %d%% (Costs $%d/tick, boosts factory production by +%d%%)" % [
			int(value), _economy.get_dividend_cost(value), boost_percent
		]

# ---- Supply chain simulation ------------------------------------------------

## Starts the supply-chain tick timer and wires the goods-supply land-value hook
## into the economy. The hook is additive and non-breaking: it simply raises the
## land value (and thus tax/dividend output) around well-supplied housing.
func _setup_supply_chain() -> void:
	var ticker := Timer.new()
	ticker.name = "SupplyChainTimer"
	ticker.wait_time = SUPPLY_CHAIN_TICK_INTERVAL
	ticker.autostart = true
	ticker.one_shot = false
	ticker.timeout.connect(_on_supply_chain_tick)
	add_child(ticker)

	_economy.goods_supply_bonus_provider = goods_supply_bonus_at


## One simulation tick. Order matters:
##   1) Rebuild total worker capacity from every residential tile.
##   2) Factories draw workers from the pool; staffed factories produce goods.
##   3) Houses consume goods; houses that got fed are flagged so the economy's
##      land value reflects a well-supplied neighbourhood.
func _on_supply_chain_tick() -> void:
	# 1) Rebuild worker capacity from residential tiles.
	worker_capacity = 0
	for pos in _grid.get_all_occupied_positions():
		match _grid.get_tile_type(pos):
			GridCellData.TileType.RESIDENTIAL_LOW:
				worker_capacity += WORKERS_PER_VILLA
			GridCellData.TileType.RESIDENTIAL_HIGH:
				worker_capacity += WORKERS_PER_APARTMENT

	# 2) Factories draw workers; each staffed factory produces goods.
	available_workers = worker_capacity
	operating_factories = 0
	var produced: int = 0
	for pos in _grid.get_all_occupied_positions():
		if _grid.get_tile_type(pos) != GridCellData.TileType.INDUSTRIAL:
			continue
		# Step 2: disconnected factories stay idle — they draw no workers and
		# produce nothing until a road is built next to them.
		if not _road_connected.get(pos, false):
			continue
		if available_workers >= WORKERS_PER_FACTORY:
			available_workers -= WORKERS_PER_FACTORY
			operating_factories += 1
			# Logistics scaling: a factory's goods output is multiplied by its pipe
			# hookup multiplier (+30% hooked / -50% missing). roundi() keeps the
			# bonus/penalty visible at the small base yield (3 goods/tick).
			var pipe_mult: float = _economy.factory_pipe_multiplier(pos)
			produced += roundi(GOODS_PER_FACTORY_TICK * pipe_mult)
	goods_stock += produced

	# 3) Houses consume goods; record which ones were fed this tick.
	_goods_supplied.clear()
	var supplied_houses: int = 0
	for pos in _grid.get_all_occupied_positions():
		var tile_type: int = _grid.get_tile_type(pos)
		if tile_type != GridCellData.TileType.RESIDENTIAL_LOW \
				and tile_type != GridCellData.TileType.RESIDENTIAL_HIGH:
			continue
		# Step 2: disconnected houses consume nothing (and get no supply bonus).
		if not _road_connected.get(pos, false):
			continue
		if goods_stock >= GOODS_PER_HOUSE_TICK:
			goods_stock -= GOODS_PER_HOUSE_TICK
			_goods_supplied[pos] = true
			supplied_houses += 1
		else:
			_goods_supplied[pos] = false

	prints("Supply chain: capacity=%d available=%d factories=%d goods=%d supplied=%d" % [
		worker_capacity, available_workers, operating_factories, goods_stock, supplied_houses])

	# Step 3: keep the TopBar resource readouts in sync with this tick's result.
	_update_resource_ui()


## Land-value bonus a tile receives from well-supplied houses within
## GOODS_BOOST_RADIUS. Consulted by EconomyManager.get_land_value(), so a fed
## neighbourhood raises its tax revenue — and, because factories also price on
## land value, its dividend base too.
func goods_supply_bonus_at(grid_pos: Vector2i) -> int:
	var bonus: int = 0
	for dx in range(-GOODS_BOOST_RADIUS, GOODS_BOOST_RADIUS + 1):
		for dy in range(-GOODS_BOOST_RADIUS, GOODS_BOOST_RADIUS + 1):
			if abs(dx) + abs(dy) > GOODS_BOOST_RADIUS:
				continue
			var adj: Vector2i = Vector2i(grid_pos.x + dx, grid_pos.y + dy)
			if _goods_supplied.get(adj, false):
				bonus += GOODS_LAND_VALUE_BOOST
	return bonus


# ---- Road network validation (Step 2) ---------------------------------------

## Returns true if any of the 4 cardinal neighbours of `pos` is a road tile
## (ROAD or ROAD_CROSS). Out-of-bounds neighbours are treated as not-road.
func is_road_adjacent(pos: Vector2i) -> bool:
	for off in _CARDINAL_OFFSETS:
		var adj: Vector2i = pos + off
		if adj.x < 0 or adj.x >= GRID_SIZE or adj.y < 0 or adj.y >= GRID_SIZE:
			continue
		var tile_type: int = _grid.get_tile_type(adj)
		if tile_type == GridCellData.TileType.ROAD or tile_type == GridCellData.TileType.ROAD_CROSS:
			return true
	return false


## Recomputes the road-connection state for a single tile. House/factory tiles
## get a fresh is_road_adjacent() result; anything else is pruned from the map
## so stale entries can't linger after a demolish.
func _update_road_connection(pos: Vector2i) -> void:
	var tile_type: int = _grid.get_tile_type(pos)
	var is_building: bool = (
		tile_type == GridCellData.TileType.RESIDENTIAL_LOW
		or tile_type == GridCellData.TileType.RESIDENTIAL_HIGH
		or tile_type == GridCellData.TileType.INDUSTRIAL
	)
	if not is_building:
		_road_connected.erase(pos)
		return
	_road_connected[pos] = is_road_adjacent(pos)


## Re-checks road connections for `center` and all four cardinal neighbours.
## Covers both a newly placed road (its adjacent buildings) and a newly placed
## building (its own tile). Call after any build or demolish.
func refresh_road_connections(center: Vector2i) -> void:
	_update_road_connection(center)
	for off in _CARDINAL_OFFSETS:
		_update_road_connection(center + off)


# ---- Tutorial objective tracking (Step 1) ----------------------------------

## Recomputes the tutorial objective counts straight from the current grid and
## refreshes the ObjectiveBox checklist. Idempotent — safe to call after any
## build, bulldoze, or residential evolution.
func _update_objectives() -> void:
	_obj_residential = 0
	_obj_factory = 0
	var total_buildings: int = 0
	var connected_buildings: int = 0
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
		else:
			continue
		total_buildings += 1
		if is_road_adjacent(pos):
			connected_buildings += 1

	# Road objective: the targets are met AND every house/factory sits on a road.
	_obj_road_connected = (
		_obj_residential >= OBJECTIVE_RESIDENTIAL_TARGET
		and _obj_factory >= OBJECTIVE_FACTORY_TARGET
		and total_buildings > 0
		and connected_buildings == total_buildings
	)
	_refresh_objective_ui()

	# Tutorial Step 2: fire Bobr's land grab the moment the checklist completes.
	if _all_objectives_met() and not _tutorial_bobr_grabbed:
		_bobr_land_grab()


## Writes the current objective state into the ObjectiveBox checklist nodes.
func _refresh_objective_ui() -> void:
	var res_done: bool = _obj_residential >= OBJECTIVE_RESIDENTIAL_TARGET
	var fac_done: bool = _obj_factory >= OBJECTIVE_FACTORY_TARGET
	_objective_residential.button_pressed = res_done
	_objective_factory.button_pressed = fac_done
	_objective_road.button_pressed = _obj_road_connected
	_objective_residential.text = "Build %d Residential zones (%d/%d)" % [
		OBJECTIVE_RESIDENTIAL_TARGET, _obj_residential, OBJECTIVE_RESIDENTIAL_TARGET]
	_objective_factory.text = "Build %d Factory (%d/%d)" % [
		OBJECTIVE_FACTORY_TARGET, _obj_factory, OBJECTIVE_FACTORY_TARGET]
	_objective_road.text = "Connect them with a Road (%s)" % (
		"Connected" if _obj_road_connected else "Pending")


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


## Completion event: Bobr buys/locks a random empty tile next to the player's
## city as a dirt lot, then taunts the mayor. The plot is deliberately NOT added
## to the AI's portfolio — it stays untaxed and unsellable ("locked") until the
## player resolves the land-value tax (see _resolve_tutorial()).
func _bobr_land_grab() -> void:
	var pos: Vector2i = _find_city_adjacent_empty_tile()
	_tutorial_bobr_grabbed = true
	if pos == Vector2i(-1, -1):
		_show_bobr_dialogue(TUTORIAL_COMPLETE_QUOTE)
		return
	_bobr_dirt_lot = pos
	_grid.set_tile(pos, GridCellData.new(GridCellData.TILE_DIRT_LOT))
	_placement_controller.place_tile(pos, GridCellData.TILE_DIRT_LOT)
	_show_bobr_dialogue(TUTORIAL_COMPLETE_QUOTE)
	prints("Bobr claims dirt lot at", pos)


## Returns a random GRASS tile adjacent to a house/factory (the "city"), or
## Vector2i(-1,-1) when no such spot exists.
func _find_city_adjacent_empty_tile() -> Vector2i:
	var candidates: Array[Vector2i] = []
	for pos in _grid.get_all_occupied_positions():
		if _grid.get_tile_type(pos) != GridCellData.TileType.GRASS:
			continue
		if _speculator.owned_tiles.has(pos):
			continue
		if _is_adjacent_to_city(pos):
			candidates.append(pos)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates.pick_random()


## True if any 8-directional neighbour of `pos` is a house or factory.
func _is_adjacent_to_city(pos: Vector2i) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var adj: Vector2i = pos + Vector2i(dx, dy)
			if adj.x < 0 or adj.x >= GRID_SIZE or adj.y < 0 or adj.y >= GRID_SIZE:
				continue
			var tile_type: int = _grid.get_tile_type(adj)
			if tile_type == GridCellData.TileType.RESIDENTIAL_LOW \
					or tile_type == GridCellData.TileType.RESIDENTIAL_HIGH \
					or tile_type == GridCellData.TileType.INDUSTRIAL:
				return true
	return false


## LVT resolution: the player raised the dividend slider above 0%, so Bobr's
## speculative plot now enters the AI's taxable portfolio. Ends the tutorial.
func _resolve_tutorial() -> void:
	_tutorial_resolved = true
	if _bobr_dirt_lot != Vector2i(-1, -1) \
			and not _speculator.owned_tiles.has(_bobr_dirt_lot):
		_speculator.owned_tiles.append(_bobr_dirt_lot)
	_show_bobr_dialogue(TUTORIAL_RESOLVE_QUOTE)
	prints("Bobr pays the land-value tax on his plot at", _bobr_dirt_lot)


# ---- Pipe network visuals + factory status readout --------------------------

## Refreshes pipe sprite tints whenever the logistics network changes (a pipe or
## factory is placed/removed). Live border-connected segments render normally;
## disconnected ones are dimmed via BuildingPlacement.
func _on_pipe_network_changed() -> void:
	_placement.update_pipe_visuals(_pipe_network.get_live_pipe_cells())


## Builds the hover readout that shows a factory's pipe connectivity status.
## Shown while the cursor is over an INDUSTRIAL tile; hidden otherwise.
func _create_factory_status_ui() -> void:
	var panel := PanelContainer.new()
	panel.name = "FactoryStatusPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.13, 0.85)
	style.border_color = Color(0.87, 0.73, 0.35, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override(&"panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never block clicks
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 16.0
	panel.offset_top = -150.0   # sit above the bottom BuildBar dock
	panel.offset_right = 420.0
	panel.offset_bottom = -94.0
	panel.visible = false
	$UI.add_child(panel)
	_factory_status_panel = panel

	var label := Label.new()
	label.name = "FactoryStatusLabel"
	label.add_theme_font_size_override(&"font_size", 16)
	label.add_theme_color_override(&"font_color", Color(0.9, 0.9, 0.9))
	panel.add_child(label)
	_factory_status_label = label


## Shows/hides the factory pipe-status readout for the currently hovered cell.
func _update_factory_status(cell: Vector2i) -> void:
	if _factory_status_panel == null:
		return
	var in_bounds: bool = (
		cell.x >= 0 and cell.x < GRID_SIZE and cell.y >= 0 and cell.y < GRID_SIZE
	)
	var is_factory: bool = in_bounds \
			and _grid.get_tile_type(cell) == GridCellData.TileType.INDUSTRIAL
	_factory_status_panel.visible = is_factory
	if is_factory:
		var status: String = _economy.factory_pipe_status(cell)
		if _factory_status_label.text != status:
			_factory_status_label.text = status


# ---- Bootstrap helper -------------------------------------------------------

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
