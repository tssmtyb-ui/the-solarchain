extends Node2D
## Root scene script for Spekulant.
##
## Owns the TileMapLayer, GridManager, and EconomyManager and bridges
## the data model to rendering, player input, and simulation.

@onready var _grid: GridManager = $GridManager
@onready var _tilemap: TileMapLayer = $TileMapLayer
@onready var _hover_layer: Node2D = $HoverLayer
@onready var _economy: EconomyManager = _create_economy_manager()
@onready var _money_label: Label = $UI/MoneyLabel
@onready var _placement: BuildingPlacement = _create_placement_manager()

## Corporate speculator AI — its claimed land is off-limits to the player.
var _speculator: SpeculatorManager


## Maps GridCellData.TileType → { source_id, atlas_coords } for TileSet lookup.
## Keeps the data model decoupled from the rendering layer.
## Each texture is a single 512×256 isometric tile at atlas origin (0,0).
const TILE_TYPE_MAP: Dictionary = {
	GridCellData.TileType.GRASS:      { "source_id": 0,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.DIRT:       { "source_id": 1,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.ASPHALT:    { "source_id": 3,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.WATER:      { "source_id": 4,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.ROAD:       { "source_id": 5,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.ROAD_CROSS: { "source_id": 6,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.SIDEWALK:   { "source_id": 11, "coords": Vector2i(0, 0) },
	GridCellData.TileType.RESIDENTIAL_LOW: { "source_id": 0, "coords": Vector2i(0, 0) }, # ground: grass; building sprite spawned separately
	GridCellData.TileType.RESIDENTIAL_HIGH: { "source_id": 0, "coords": Vector2i(0, 0) }, # ground: grass; building sprite spawned separately
	GridCellData.TileType.INDUSTRIAL:  { "source_id": 0,  "coords": Vector2i(0, 0) }, # ground: grass blends in; building sprite spawned separately
	GridCellData.TileType.WAREHOUSE:  { "source_id": 0,  "coords": Vector2i(0, 0) }, # ground: grass blends in; building sprite spawned separately
	GridCellData.TileType.PARK:       { "source_id": 0,  "coords": Vector2i(0, 0) }, # ground: grass; gazebo spawned separately
	GridCellData.TileType.SLUDGE:     { "source_id": 0,  "coords": Vector2i(0, 0) }, # ground: grass; pipe spawned separately
	GridCellData.TileType.DIRT_LOT:   { "source_id": 1,  "coords": Vector2i(0, 0) }, # dirt lot — speculator-owned land
}

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

## Build costs deducted from current_money when placing tiles.
const ROAD_COST: int = 10
const FACTORY_COST: int = 100
const WAREHOUSE_COST: int = 60
const RESIDENTIAL_COST: int = 50
const UPGRADE_COST: int = 150
const PARK_COST: int = 50
const SLUDGE_COST: int = 10

## Per-cycle tile economics (applied in _on_assessment_completed).
const ROAD_UPKEEP: int = 1

## Land Value Tax constants.
## A tile's economic value is determined by its Manhattan distance to the
## nearest edge highway (outside world connection). Values drop by LVT_DROP_OFF
## per tile of distance away from the highway, never below MIN_LAND_VALUE.
const MAX_LAND_VALUE: int = 50
const LVT_DROP_OFF: int = 3
const MIN_LAND_VALUE: int = 5

## Maximum land value a low-density villa can afford before being priced out.
## Villas on land worth more than this provide 0 workers and 0 tax income.
const MAX_VILLA_LAND_VALUE: int = 30

## Worker radius constants for the factory labour dependency loop.
## Factories scan for nearby housing within this Manhattan distance.
const WORKER_RADIUS: int = 3
## Workers required for a factory to operate at full efficiency.
const REQUIRED_WORKERS: int = 2

## Edge highway cells that are protected from bulldozing.
const EDGE_HIGHWAY_CELLS: Array[Vector2i] = [
	Vector2i(0, int(GRID_SIZE * 0.5)),
	Vector2i(GRID_SIZE - 1, int(GRID_SIZE * 0.5)),
]

## The tool mode the player is currently using (via UI toggle).
## EMPTY = no tool, BULLDOZE = demolition, otherwise a GridCellData.TileType.
var current_build_mode: int = GridCellData.TileType.EMPTY

## Player's current money balance.
var current_money: int = 1000

## True once the player goes bankrupt (money drops below zero); blocks input.
var is_game_over: bool = false


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

	# Set up the hover-highlight sprite (a yellow diamond outline).
	_hover_sprite.texture = HIGHLIGHT_TEXTURE
	_hover_sprite.centered = true
	_hover_sprite.z_index = 100  # always render on top
	_hover_layer.add_child(_hover_sprite)

	# Connect UI toggle buttons for build modes.
	var road_toggle: TextureButton = $UI/RoadToggle
	road_toggle.tooltip_text = "Build Road"
	road_toggle.toggled.connect(_on_road_toggle_toggled)

	var factory_toggle: TextureButton = $UI/FactoryToggle
	factory_toggle.tooltip_text = "Build Factory"
	factory_toggle.toggled.connect(_on_factory_toggle_toggled)

	var warehouse_toggle: TextureButton = $UI/WarehouseToggle
	warehouse_toggle.tooltip_text = "Build Warehouse"
	warehouse_toggle.toggled.connect(_on_warehouse_toggle_toggled)

	var residential_toggle: TextureButton = $UI/ResidentialToggle
	residential_toggle.tooltip_text = "Build Residential"
	residential_toggle.toggled.connect(_on_residential_toggle_toggled)

	var park_toggle: TextureButton = $UI/ParkToggle
	park_toggle.tooltip_text = "Build Park"
	park_toggle.toggled.connect(_on_park_toggle_toggled)

	var sludge_toggle: TextureButton = $UI/SludgeToggle
	sludge_toggle.tooltip_text = "Build Sludge Line"
	sludge_toggle.toggled.connect(_on_sludge_toggle_toggled)

	var bulldoze_toggle: TextureButton = $UI/BulldozeToggle
	bulldoze_toggle.tooltip_text = "Bulldozer (Demolish)"
	bulldoze_toggle.toggled.connect(_on_bulldoze_toggle_toggled)

	# --- Initialise a clean GRASS map with edge highway connections ---
	_init_grass_grid()
	_spawn_edge_highways()

	# Start the economy immediately (timer auto-starts in EconomyManager._ready()).
	_economy.calculate_net_income()

	# --- Start background music ---
	add_child(MusicManager.new())

	# --- Build programmatic UI overlays (credits + game-over screen) ---
	UIBuilder.new().build_ui($UI, _on_restart_pressed)

	update_money_ui()

	prints("World initialised — place roads and factories freely.")


## Fills the grid with uniform GRASS tiles — the player's blank canvas.
func _init_grass_grid() -> void:
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			var cell := Vector2i(x, y)
			_grid.set_tile(cell, GridCellData.new(GridCellData.TileType.GRASS))
			_place_tile(cell, GridCellData.TileType.GRASS)


## Places ROAD tiles at the east and west edges of the grid as highway connections.
## West gateway: (0, GRID_SIZE / 2)    East gateway: (GRID_SIZE - 1, GRID_SIZE / 2)
## These are written to both the grid data model and the TileMapLayer.
func _spawn_edge_highways() -> void:
	var mid_y: int = int(GRID_SIZE * 0.5)

	var west_cell := Vector2i(0, mid_y)
	_grid.set_tile(west_cell, GridCellData.new(GridCellData.TileType.ROAD))
	_place_tile(west_cell, GridCellData.TileType.ROAD)

	var east_cell := Vector2i(GRID_SIZE - 1, mid_y)
	_grid.set_tile(east_cell, GridCellData.new(GridCellData.TileType.ROAD))
	_place_tile(east_cell, GridCellData.TileType.ROAD)

	prints("Edge highways placed at", west_cell, "and", east_cell)


## Returns true if `pos` lies within the GRID_SIZE × GRID_SIZE map bounds.
func _within_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < GRID_SIZE and pos.y >= 0 and pos.y < GRID_SIZE


## Claims a grid position for the corporate speculator: registers it in the
## AI's portfolio and paints a dirt lot so the player can see the land is taken.
func claim_tile_for_speculator(grid_pos: Vector2i) -> void:
	if _speculator.owned_tiles.has(grid_pos):
		return
	_speculator.owned_tiles.append(grid_pos)
	_grid.set_tile(grid_pos, GridCellData.new(GridCellData.TILE_DIRT_LOT))
	_place_tile(grid_pos, GridCellData.TILE_DIRT_LOT)


# ---- Input ----------------------------------------------------------------

## Track mouse position every frame to highlight the hovered cell.
func _process(_delta: float) -> void:
	var mouse_pos: Vector2 = get_global_mouse_position()
	var cell: Vector2i = _tilemap.local_to_map(mouse_pos)

	# Clamp to grid bounds — hide the sprite when outside the map.
	if cell.x < 0 or cell.x >= GRID_SIZE or cell.y < 0 or cell.y >= GRID_SIZE:
		_hover_sprite.visible = false
		_last_hovered_cell = Vector2i(-1, -1)
		return

	# Position the highlight at the diamond centre of the hovered cell.
	var local: Vector2 = _tilemap.map_to_local(cell)
	_hover_sprite.visible = true
	if cell != _last_hovered_cell:
		_hover_sprite.position = local
		_last_hovered_cell = cell


func _unhandled_input(event: InputEvent) -> void:
	if is_game_over:
		return

	# Hotkeys: 5 = Park, 6 = Sludge (activates the matching UI toggle).
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_5:
				$UI/ParkToggle.set_pressed(true)
				return
			KEY_6:
				$UI/SludgeToggle.set_pressed(true)
				return

	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var grid_pos: Vector2i = _tilemap.local_to_map(get_global_mouse_position())

	if grid_pos.x < 0 or grid_pos.x >= GRID_SIZE or grid_pos.y < 0 or grid_pos.y >= GRID_SIZE:
		return

	if current_build_mode == GridCellData.TileType.EMPTY:
		prints("No tool selected — toggle Road or Factory button first.")
		return

	var existing: int = _grid.get_tile_type(grid_pos)
	if existing == current_build_mode and current_build_mode != GridCellData.TileType.RESIDENTIAL_LOW:
		return

	# Speculator-owned land is off-limits — block any placement (or bulldoze).
	if _speculator.owned_tiles.has(grid_pos):
		prints("Blocked:", grid_pos, "is owned by the speculator!")
		return

	if current_build_mode == GridCellData.TileType.ROAD or current_build_mode == GridCellData.TileType.ROAD_CROSS:
		if current_money < ROAD_COST:
			prints("Not enough money!")
			return
		current_money -= ROAD_COST
		update_money_ui()
		_grid.set_tile(grid_pos, GridCellData.new(current_build_mode))
		_place_tile(grid_pos, current_build_mode)
		prints("Placed", GridCellData.TileType.keys()[current_build_mode], "at", grid_pos)
		return

	if current_build_mode == GridCellData.TileType.INDUSTRIAL:
		var cardinal: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
		var found_road := false
		for off in cardinal:
			var adj: Vector2i = Vector2i(grid_pos.x + off.x, grid_pos.y + off.y)
			if not _within_bounds(adj):
				continue
			var adj_type: int = _grid.get_tile_type(adj)
			if adj_type == GridCellData.TileType.ROAD or adj_type == GridCellData.TileType.ROAD_CROSS:
				found_road = true
				break
		if not found_road:
			prints("Blocked: Factories must be built next to a road!")
			return
		if current_money < FACTORY_COST:
			prints("Not enough money!")
			return
		current_money -= FACTORY_COST
		update_money_ui()
		_grid.set_tile(grid_pos, GridCellData.new(current_build_mode))
		_place_tile(grid_pos, current_build_mode)
		_placement.spawn_building(grid_pos, current_build_mode)
		prints("Placed", GridCellData.TileType.keys()[current_build_mode], "at", grid_pos)
		return

	if current_build_mode == GridCellData.TileType.WAREHOUSE:
		var cardinal: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
		var found_road := false
		for off in cardinal:
			var adj: Vector2i = Vector2i(grid_pos.x + off.x, grid_pos.y + off.y)
			if not _within_bounds(adj):
				continue
			var adj_type: int = _grid.get_tile_type(adj)
			if adj_type == GridCellData.TileType.ROAD or adj_type == GridCellData.TileType.ROAD_CROSS:
				found_road = true
				break
		if not found_road:
			prints("Blocked: Warehouses must be built next to a road!")
			return
		if current_money < WAREHOUSE_COST:
			prints("Not enough money!")
			return
		current_money -= WAREHOUSE_COST
		update_money_ui()
		_grid.set_tile(grid_pos, GridCellData.new(current_build_mode))
		_place_tile(grid_pos, current_build_mode)
		_placement.spawn_building(grid_pos, current_build_mode)
		prints("Placed", GridCellData.TileType.keys()[current_build_mode], "at", grid_pos)
		return

	if current_build_mode == GridCellData.TileType.PARK:
		if current_money < PARK_COST:
			prints("Not enough money!")
			return
		current_money -= PARK_COST
		update_money_ui()
		_grid.set_tile(grid_pos, GridCellData.new(current_build_mode))
		_place_tile(grid_pos, current_build_mode)
		_placement.spawn_building(grid_pos, current_build_mode)
		prints("Placed", GridCellData.TileType.keys()[current_build_mode], "at", grid_pos)
		return

	if current_build_mode == GridCellData.TileType.SLUDGE:
		if current_money < SLUDGE_COST:
			prints("Not enough money!")
			return
		current_money -= SLUDGE_COST
		update_money_ui()
		_grid.set_tile(grid_pos, GridCellData.new(current_build_mode))
		_place_tile(grid_pos, current_build_mode)
		_placement.spawn_building(grid_pos, current_build_mode)
		prints("Placed", GridCellData.TileType.keys()[current_build_mode], "at", grid_pos)
		return

	if current_build_mode == GridCellData.TileType.RESIDENTIAL_LOW:
		# Upgrade: clicking on an existing house upgrades it to an apartment.
		if existing == GridCellData.TileType.RESIDENTIAL_LOW:
			if current_money < UPGRADE_COST:
				prints("Not enough money for upgrade!")
				return
			current_money -= UPGRADE_COST
			update_money_ui()
			_grid.set_tile(grid_pos, GridCellData.new(GridCellData.TileType.RESIDENTIAL_HIGH))
			_place_tile(grid_pos, GridCellData.TileType.RESIDENTIAL_HIGH)
			_placement.spawn_building(grid_pos, GridCellData.TileType.RESIDENTIAL_HIGH)
			prints("Upgraded to RESIDENTIAL_HIGH at", grid_pos)
			return

		# Normal house placement on any non-residential tile.
		if current_money < RESIDENTIAL_COST:
			prints("Not enough money!")
			return
		current_money -= RESIDENTIAL_COST
		update_money_ui()
		_grid.set_tile(grid_pos, GridCellData.new(current_build_mode))
		_place_tile(grid_pos, current_build_mode)
		_placement.spawn_building(grid_pos, current_build_mode)
		prints("Placed", GridCellData.TileType.keys()[current_build_mode], "at", grid_pos)
		return

	# --- Bulldoze: demolish player-built tiles back to grass ---
	if current_build_mode == BULLDOZE:
		if EDGE_HIGHWAY_CELLS.has(grid_pos):
			prints("Cannot demolish edge highway connection.")
			return

		if existing == GridCellData.TileType.ROAD \
		   or existing == GridCellData.TileType.ROAD_CROSS \
		   or existing == GridCellData.TileType.INDUSTRIAL \
		   or existing == GridCellData.TileType.WAREHOUSE \
		   or existing == GridCellData.TileType.RESIDENTIAL_LOW \
		   or existing == GridCellData.TileType.RESIDENTIAL_HIGH \
		   or existing == GridCellData.TileType.PARK \
		   or existing == GridCellData.TileType.SLUDGE:
			# Destroy any building sprite attached to this tile.
			_placement.remove_building(grid_pos)

			# Reset the tile to grass in data model + tilemap.
			_grid.set_tile(grid_pos, GridCellData.new(GridCellData.TileType.GRASS))
			_place_tile(grid_pos, GridCellData.TileType.GRASS)
			prints("Demolished", GridCellData.TileType.keys()[existing], "at", grid_pos)
		else:
			prints("Nothing to demolish at", grid_pos)
		return

	_grid.set_tile(grid_pos, GridCellData.new(current_build_mode))
	_place_tile(grid_pos, current_build_mode)
	prints("Placed", GridCellData.TileType.keys()[current_build_mode], "at", grid_pos)

## Called when the Road toggle button is switched on/off.
## ON  → set build mode to ROAD, show Switch01 (active).
## OFF → reset build mode to EMPTY, show Switch02 (inactive).
func _on_road_toggle_toggled(toggled_on: bool) -> void:
	var btn: TextureButton = $UI/RoadToggle
	if toggled_on:
		current_build_mode = GridCellData.TileType.ROAD
		btn.texture_normal = preload("res://Ui/Switch01.png")
		_unpress_other_toggles("RoadToggle")
		prints("Build mode: ROAD")
	else:
		current_build_mode = GridCellData.TileType.EMPTY
		btn.texture_normal = preload("res://Ui/Switch02.png")
		prints("Build mode: OFF")


## Called when the Factory toggle button is switched on/off.
## ON  → set build mode to INDUSTRIAL, show warehouse texture (active).
## OFF → reset build mode to EMPTY, restore inactive texture.
func _on_factory_toggle_toggled(toggled_on: bool) -> void:
	var btn: TextureButton = $UI/FactoryToggle
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
	var btn: TextureButton = $UI/BulldozeToggle
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
	for child in $UI.get_children():
		if child is TextureButton and child.name != except_name and child.button_pressed:
			child.set_pressed_no_signal(false)


## Returns the Land Value of a grid position based on Manhattan distance to the
## nearest edge highway (outside-world connection).
##
## Tiles closer to the highway fetch a higher value; remote land drops toward
## MIN_LAND_VALUE. The formula: MAX_LAND_VALUE - (shortest_distance * LVT_DROP_OFF),
## clamped to never go below MIN_LAND_VALUE.
func get_land_value(grid_pos: Vector2i) -> int:
	var mid_y: int = int(GRID_SIZE * 0.5)

	var west := Vector2i(0, mid_y)
	var east := Vector2i(GRID_SIZE - 1, mid_y)

	var dist_west: int = abs(grid_pos.x - west.x) + abs(grid_pos.y - west.y)
	var dist_east: int = abs(grid_pos.x - east.x) + abs(grid_pos.y - east.y)
	var shortest: int = mini(dist_west, dist_east)

	var raw: int = MAX_LAND_VALUE - (shortest * LVT_DROP_OFF)
	return clampi(raw, MIN_LAND_VALUE, MAX_LAND_VALUE)


## Scans within WORKER_RADIUS of a factory position and counts nearby workers.
## RESIDENTIAL_LOW tiles contribute 1 worker, RESIDENTIAL_HIGH tiles contribute 3.
## Uses Manhattan distance (abs(dx) + abs(dy) <= WORKER_RADIUS) for the scan.
func _get_local_workers(factory_pos: Vector2i) -> int:
	var count: int = 0
	for dx in range(-WORKER_RADIUS, WORKER_RADIUS + 1):
		for dy in range(-WORKER_RADIUS, WORKER_RADIUS + 1):
			if abs(dx) + abs(dy) > WORKER_RADIUS:
				continue
			var pos: Vector2i = Vector2i(factory_pos.x + dx, factory_pos.y + dy)
			if pos.x < 0 or pos.x >= GRID_SIZE or pos.y < 0 or pos.y >= GRID_SIZE:
				continue
			var tile_type: int = _grid.get_tile_type(pos)
			if tile_type == GridCellData.TileType.RESIDENTIAL_LOW:
				# Villa is priced out if land value exceeds the threshold.
				if get_land_value(pos) > MAX_VILLA_LAND_VALUE:
					prints("Villa at", pos, "abandoned! Land value too high.")
				else:
					count += 1
			elif tile_type == GridCellData.TileType.RESIDENTIAL_HIGH:
				count += 3
	return count


func _on_assessment_completed(net_income: int) -> void:
	current_money += net_income
	update_money_ui()
	# Drive the corporate speculator AI on the same economic cadence.
	_speculator.process_speculator_tick(_economy)
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
	_place_tile(grid_pos, GridCellData.TileType.GRASS)
	_placement.remove_building(grid_pos)


## Handles automatic density evolution (villa <-> apartment) driven by land value.
## The EconomyManager emits this when a residential tile crosses a threshold.
func _on_residential_evolution(grid_pos: Vector2i, new_tile_type: int) -> void:
	# Update the data model and ground tile, then swap the building sprite.
	# spawn_building() already queue_frees any existing sprite at this cell.
	_grid.set_tile(grid_pos, GridCellData.new(new_tile_type))
	_place_tile(grid_pos, new_tile_type)
	_placement.spawn_building(grid_pos, new_tile_type)
	prints("Evolved tile at", grid_pos, "->", GridCellData.TileType.keys()[new_tile_type])


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
	add_child(bp)
	return bp

## Look up the TileSet source/coords for a GridCellData tile type and place it.
func _place_tile(_cell: Vector2i, tile_type: int) -> void:
	var entry: Dictionary = TILE_TYPE_MAP.get(tile_type, {})
	if entry.is_empty():
		push_warning("No TileSet mapping for tile type ", tile_type)
		return
	var source_id: int = entry.source_id
	var atlas_coords: Vector2i = entry.coords
	_tilemap.set_cell(_cell, source_id, atlas_coords)
