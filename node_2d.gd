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

## Background-music tracks played in a continuous sequential loop.
const MUSIC_TRACKS: Array[AudioStream] = [
	preload("res://music/bensound-thejazzpiano.mp3"),
	preload("res://music/bensound-jazzcomedy.mp3"),
]

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

	var bulldoze_toggle: TextureButton = $UI/BulldozeToggle
	bulldoze_toggle.tooltip_text = "Bulldozer (Demolish)"
	bulldoze_toggle.toggled.connect(_on_bulldoze_toggle_toggled)

	# --- Initialise a clean GRASS map with edge highway connections ---
	_init_grass_grid()
	_spawn_edge_highways()

	# Start the economy immediately (timer auto-starts in EconomyManager._ready()).
	_economy.set_flat_rate(0.15)
	_economy.calculate_all()

	# --- Start background music (sequential looping playlist) ---
	_setup_music()

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
		_spawn_building_sprite(grid_pos, current_build_mode)
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
		_spawn_building_sprite(grid_pos, current_build_mode)
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
			_spawn_building_sprite(grid_pos, GridCellData.TileType.RESIDENTIAL_HIGH)
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
		_spawn_building_sprite(grid_pos, current_build_mode)
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
		   or existing == GridCellData.TileType.RESIDENTIAL_HIGH:
			# Destroy any building sprite attached to this tile.
			if _building_sprites.has(grid_pos):
				var sprite: Node = _building_sprites[grid_pos] as Node
				if is_instance_valid(sprite):
					sprite.queue_free()
				_building_sprites.erase(grid_pos)

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
		$UI/BulldozeToggle.set_pressed_no_signal(false)
		$UI/FactoryToggle.set_pressed_no_signal(false)
		$UI/WarehouseToggle.set_pressed_no_signal(false)
		$UI/ResidentialToggle.set_pressed_no_signal(false)
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
		btn.texture_normal = preload("res://assets/generated/factory_toggle_icon_2_frame_0.png")
		$UI/RoadToggle.set_pressed_no_signal(false)
		$UI/WarehouseToggle.set_pressed_no_signal(false)
		$UI/ResidentialToggle.set_pressed_no_signal(false)
		$UI/BulldozeToggle.set_pressed_no_signal(false)
		prints("Build mode: INDUSTRIAL")
	else:
		current_build_mode = GridCellData.TileType.EMPTY
		btn.texture_normal = preload("res://assets/generated/factory_toggle_icon_frame_0.png")
		prints("Build mode: OFF")


## Called when the Warehouse toggle button is switched on/off.
## ON  → set build mode to WAREHOUSE.
## OFF → reset build mode to EMPTY.
func _on_warehouse_toggle_toggled(toggled_on: bool) -> void:
	if toggled_on:
		current_build_mode = GridCellData.TileType.WAREHOUSE
		$UI/RoadToggle.set_pressed_no_signal(false)
		$UI/FactoryToggle.set_pressed_no_signal(false)
		$UI/ResidentialToggle.set_pressed_no_signal(false)
		$UI/BulldozeToggle.set_pressed_no_signal(false)
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
		$UI/RoadToggle.set_pressed_no_signal(false)
		$UI/FactoryToggle.set_pressed_no_signal(false)
		$UI/WarehouseToggle.set_pressed_no_signal(false)
		$UI/BulldozeToggle.set_pressed_no_signal(false)
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
		$UI/RoadToggle.set_pressed_no_signal(false)
		$UI/FactoryToggle.set_pressed_no_signal(false)
		$UI/WarehouseToggle.set_pressed_no_signal(false)
		$UI/ResidentialToggle.set_pressed_no_signal(false)
		prints("Build mode: BULLDOZE")
	else:
		current_build_mode = GridCellData.TileType.EMPTY
		btn.texture_normal = preload("res://Ui/Switch02.png")
		prints("Build mode: OFF")


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


func _on_assessment_completed(total: float, count: int) -> void:
	# Count placed tile types from the grid data model.
	var road_count: int = 0
	var income: int = 0

	for pos in _grid.get_all_occupied_positions():
		var t: int = _grid.get_tile_type(pos)
		if t == GridCellData.TileType.ROAD or t == GridCellData.TileType.ROAD_CROSS:
			road_count += 1
		elif t == GridCellData.TileType.INDUSTRIAL:
			# Factories need workers to generate income.
			if _get_local_workers(pos) >= REQUIRED_WORKERS:
				income += get_land_value(pos)
			else:
				prints("Factory at", pos, "is idle! Not enough workers.")
		elif t == GridCellData.TileType.WAREHOUSE:
			income += get_land_value(pos)
		elif t == GridCellData.TileType.RESIDENTIAL_LOW:
			var lv: int = get_land_value(pos)
			if lv <= MAX_VILLA_LAND_VALUE:
				income += lv
			else:
				prints("RESIDENTIAL_LOW at", pos, "pays $0 — land value too high.")
		elif t == GridCellData.TileType.RESIDENTIAL_HIGH:
			# High-density captures double the land value.
			income += get_land_value(pos) * 2

	var upkeep: int = road_count * ROAD_UPKEEP
	var net: int = income - upkeep

	current_money += net
	update_money_ui()
	prints("Assessment: tiles:", count, "revenue: $", snapped(total, 0.01),
		" roads:", road_count, " income:+$", income, " upkeep:-$", upkeep, " net:", net)


## Updates the money label to reflect the current balance.
func update_money_ui() -> void:
	_money_label.text = "$%d" % current_money


# ---- Bootstrap helper -------------------------------------------------------

## Creates and adds the EconomyManager as a child, then returns it.
func _create_economy_manager() -> EconomyManager:
	var em := EconomyManager.new()
	em.name = "EconomyManager"
	em.flat_rate = 0.15
	em.assessment_interval = 5.0
	add_child(em)
	move_child(em, 0)
	return em


## Tracks building Sprite2D nodes keyed by grid position.
## Allows cleanup when a tile is replaced with a different type.
var _building_sprites: Dictionary = {}

## Preload the factory building texture (used for INDUSTRIAL tiles).
const FACTORY: Texture2D = preload("res://assets/factory/FactoryC.png")

## Preload the warehouse building texture (used for WAREHOUSE tiles).
const WAREHOUSE: Texture2D = preload("res://assets/warehouse/warehouseBrownA.png")

## Preload the house building textures (randomly picked for RESIDENTIAL_LOW tiles).
const HOUSE_A: Texture2D = preload("res://assets/House/houseSmallBlueA.png")
const HOUSE_B: Texture2D = preload("res://assets/House/houseSmallBlueB.png")

## Preload the apartment building textures (randomly picked for RESIDENTIAL_HIGH tiles).
const APARTMENT_A: Texture2D = preload("res://assets/Apartment/buildingTallOrangeA.png")
const APARTMENT_B: Texture2D = preload("res://assets/Apartment/buildingTallOrangeB.png")


## Spawns (or replaces) a building Sprite2D overlay for the given tile type.
##
## All math assumes a 512×256 isometric diamond tile (Diamond Right layout).
## The building's visual base (texture bottom edge) is pinned to the diamond
## bottom tip (ground plane) so the structure rests on the tile surface.
## Y-sort happens at diamond_centre.y so tiles in front
## (south, higher Y) render on top of the building's lower portion.
func _spawn_building_sprite(cell: Vector2i, tile_type: int) -> void:
	# Remove any existing sprite at this cell first.
	if _building_sprites.has(cell):
		var old: Node = _building_sprites[cell] as Node
		if is_instance_valid(old):
			old.queue_free()
		_building_sprites.erase(cell)

	# Pick the building texture for this tile type.
	var tex: Texture2D
	match tile_type:
		GridCellData.TileType.INDUSTRIAL:
			tex = FACTORY
		GridCellData.TileType.WAREHOUSE:
			tex = WAREHOUSE
		GridCellData.TileType.RESIDENTIAL_LOW:
			tex = HOUSE_A if randi() % 2 == 0 else HOUSE_B
		GridCellData.TileType.RESIDENTIAL_HIGH:
			tex = APARTMENT_A if randi() % 2 == 0 else APARTMENT_B
		_:
			return  # No building sprite for other tile types.

	# Create the sprite, centered (so position = centre of the sprite rect).
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	sprite.name = "Building_%d_%d" % [cell.x, cell.y]
	sprite.z_index = 0
	sprite.y_sort_enabled = true

	# Scale so the building fills ~75 % of the 512 px diamond width.
	var tex_size: Vector2 = tex.get_size()
	var target_width: float = 384.0
	var s: float = target_width / tex_size.x
	sprite.scale = Vector2(s, s)

	# Position at diamond centre so y-sort aligns with the tile's vertical midpoint.
	# Tiles in front (south, higher Y) sort after us and render on top.
	var diamond_centre: Vector2 = _tilemap.map_to_local(cell)
	sprite.position = diamond_centre

	# Offset the sprite centre so the scaled texture's bottom edge sits exactly
	# at the diamond bottom tip (ground plane), 128 px below diamond_centre.y.
	# With centered = true:
	#   centre_y + offset_y + tex_h/2 * s = diamond_centre.y + 128
	#   → offset_y = 128 - tex_h/2 * s
	var offset_y: float = 128.0 - (tex_size.y * 0.5 * s)
	sprite.offset = Vector2(0, offset_y)

	_tilemap.add_child(sprite)
	_building_sprites[cell] = sprite


## Background-music state.
var _music_player: AudioStreamPlayer
var _music_index: int = 0


## Sets up an AudioStreamPlayer child for background music and starts playback.
## Tracks play sequentially in a never-ending loop via the finished signal.
func _setup_music() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.volume_db = -6.0
	_music_player.bus = "Master"
	_music_player.finished.connect(_on_music_track_ended)
	add_child(_music_player)
	_play_music_track(0)


func _play_music_track(index: int) -> void:
	_music_index = index
	_music_player.stream = MUSIC_TRACKS[index]
	_music_player.volume_db = 0.0
	_music_player.play()
	prints("MusicManager: playing track", index)


func _on_music_track_ended() -> void:
	var next: int = (_music_index + 1) % MUSIC_TRACKS.size()
	_play_music_track(next)


## Look up the TileSet source/coords for a GridCellData tile type and place it.
func _place_tile(_cell: Vector2i, tile_type: int) -> void:
	var entry: Dictionary = TILE_TYPE_MAP.get(tile_type, {})
	if entry.is_empty():
		push_warning("No TileSet mapping for tile type ", tile_type)
		return
	var source_id: int = entry.source_id
	var atlas_coords: Vector2i = entry.coords
	_tilemap.set_cell(_cell, source_id, atlas_coords)
