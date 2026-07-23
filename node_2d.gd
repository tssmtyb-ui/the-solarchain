extends Node2D
## Root scene script for Spekulant — Seed Hub Phase.
##
## Owns the TileMapLayer, GridManager, and EconomyManager and bridges
## the data model to rendering, player input, and simulation.

@onready var _grid: GridManager = $GridManager
@onready var _tilemap: TileMapLayer = $TileMapLayer
@onready var _hover_layer: Node2D = $HoverLayer
@onready var _economy: EconomyManager = _create_economy_manager()


## Maps GridCellData.TileType → { source_id, atlas_coords } for TileSet lookup.
## Keeps the data model decoupled from the rendering layer.
## Each texture is a single 512×256 isometric tile at atlas origin (0,0).
const TILE_TYPE_MAP: Dictionary = {
	GridCellData.TileType.GRASS:      { "source_id": 0,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.DIRT:       { "source_id": 1,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.CONCRETE:   { "source_id": 2,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.ASPHALT:    { "source_id": 3,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.WATER:      { "source_id": 4,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.ROAD:       { "source_id": 5,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.ROAD_CROSS: { "source_id": 6,  "coords": Vector2i(0, 0) },
	GridCellData.TileType.SIDEWALK:   { "source_id": 11, "coords": Vector2i(0, 0) },
	GridCellData.TileType.SEED_HUB:   { "source_id": 2,  "coords": Vector2i(0, 0) }, # concrete ground
	GridCellData.TileType.RESIDENTIAL: { "source_id": 2, "coords": Vector2i(0, 0) }, # concrete placeholder
	GridCellData.TileType.INDUSTRIAL:  { "source_id": 0,  "coords": Vector2i(0, 0) }, # ground: grass blends in; building sprite spawned separately
}

## Grid dimensions for the starting map.
const GRID_SIZE: int = 10

## Preloaded highlight texture for the mouse hover indicator.
const HIGHLIGHT_TEXTURE: Texture2D = preload("res://assets/generated/highlight_diamond_clean.png")

## Tracks the last hovered cell so we can erase the old highlight.
var _last_hovered_cell: Vector2i = Vector2i(-1, -1)

## The Sprite2D used for the mouse-hover highlight indicator.
var _hover_sprite: Sprite2D = Sprite2D.new()

## True once the player has placed their Seed Hub.
var seed_hub_placed: bool = false

## The tile type the player is currently placing (via UI toggle).
## Defaults to EMPTY = no tool selected.
var current_build_mode: int = GridCellData.TileType.EMPTY


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
	road_toggle.toggled.connect(_on_road_toggle_toggled)

	var factory_toggle: TextureButton = $UI/FactoryToggle
	factory_toggle.toggled.connect(_on_factory_toggle_toggled)

	# --- Initialise a clean GRASS map ---
	_init_grass_grid()

	prints("Seed Hub phase ready. Click any grass tile to place the Seed Hub.")


## Fills the grid with uniform GRASS tiles — the player's blank canvas.
func _init_grass_grid() -> void:
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			var cell := Vector2i(x, y)
			_grid.set_tile(cell, GridCellData.new(GridCellData.TileType.GRASS))
			_place_tile(cell, GridCellData.TileType.GRASS)


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
	# Keyboard shortcut: press H to place hub at centre (for testing).
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		var centre := Vector2i(GRID_SIZE / 2.0, GRID_SIZE / 2.0)
		if not seed_hub_placed and _grid.get_tile_type(centre) == GridCellData.TileType.GRASS:
			_try_place_seed_hub(centre)
		return

	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var grid_pos: Vector2i = _tilemap.local_to_map(get_global_mouse_position())

	# Bounds check — ignore clicks outside the starting map.
	if grid_pos.x < 0 or grid_pos.x >= GRID_SIZE or grid_pos.y < 0 or grid_pos.y >= GRID_SIZE:
		return

	if not seed_hub_placed:
		_try_place_seed_hub(grid_pos)
		return

	# --- Seed Hub is placed: use the current build mode ---
	if current_build_mode == GridCellData.TileType.EMPTY:
		prints("No tool selected — toggle Road or Factory button first.")
		return

	# Prevent overwriting the hub or its concrete platform (let's keep it safe).
	var existing: int = _grid.get_tile_type(grid_pos)
	if existing == GridCellData.TileType.SEED_HUB or existing == GridCellData.TileType.CONCRETE:
		prints("Cannot build on the Seed Hub platform.")
		return

	# Double-billing guard: silently skip if the tile is already of the requested type.
	if existing == current_build_mode:
		return

	# "Next to a road" rule + spacing rule for factories.
	if current_build_mode == GridCellData.TileType.INDUSTRIAL:
		var cardinal: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
		var all_8: Array[Vector2i] = [
			Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
			Vector2i(-1,  0),                   Vector2i(1,  0),
			Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1),
		]
		# Rule A: must be adjacent (cardinal) to a road.
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

		# Rule B: cannot be within 1 tile (8-dir) of another factory.
		for off in all_8:
			var adj: Vector2i = Vector2i(grid_pos.x + off.x, grid_pos.y + off.y)
			if not _within_bounds(adj):
				continue
			if _grid.get_tile_type(adj) == GridCellData.TileType.INDUSTRIAL:
				prints("Blocked: Factories cannot be adjacent to each other!")
				return

	# Place the selected tile type.
	_grid.set_tile(grid_pos, GridCellData.new(current_build_mode))
	_place_tile(grid_pos, current_build_mode)
	_spawn_building_sprite(grid_pos, current_build_mode)
	prints("Placed", GridCellData.TileType.keys()[current_build_mode], "at", grid_pos)


## Attempts to place the Seed Hub at the given grid cell.
## Only valid on GRASS tiles.
func _try_place_seed_hub(pos: Vector2i) -> void:
	if _grid.get_tile_type(pos) != GridCellData.TileType.GRASS:
		prints("Seed Hub can only be placed on grass.")
		return

	# Place the Seed Hub.
	_grid.set_tile(pos, GridCellData.new(GridCellData.TileType.SEED_HUB))
	_place_tile(pos, GridCellData.TileType.SEED_HUB)

	# Radiate +100 land value in a 3×3 radius around the hub.
	_radiate_land_value(pos)

	seed_hub_placed = true
	prints("Seed Hub placed at", pos, "— economy bootstrapped.")

	# Start the economy simulation.
	_economy.set_flat_rate(0.15)
	_economy.calculate_all()


## Radiate +100 land value in a 3×3 radius around `center`.
## Converts the 8 adjacent grass tiles to CONCRETE (developed platform)
## and sets their land_value_modifier to 100.0 so the economy has
## something taxable to work with immediately.
func _radiate_land_value(center: Vector2i) -> void:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var neighbor := Vector2i(center.x + dx, center.y + dy)
			# Skip out-of-bounds.
			if neighbor.x < 0 or neighbor.x >= GRID_SIZE or neighbor.y < 0 or neighbor.y >= GRID_SIZE:
				continue
			# Skip the hub tile itself.
			if neighbor == center:
				continue
			# Upgrade the tile to CONCRETE (developed platform) + land value boost.
			var cell_data := GridCellData.new(GridCellData.TileType.CONCRETE, 100.0)
			_grid.set_tile(neighbor, cell_data)
			_place_tile(neighbor, GridCellData.TileType.CONCRETE)


## Called when the Road toggle button is switched on/off.
## ON  → set build mode to ROAD, show Switch01 (active).
## OFF → reset build mode to EMPTY, show Switch02 (inactive).
func _on_road_toggle_toggled(toggled_on: bool) -> void:
	var btn: TextureButton = $UI/RoadToggle
	if toggled_on:
		current_build_mode = GridCellData.TileType.ROAD
		btn.texture_normal = preload("res://Ui/Switch01.png")
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
		prints("Build mode: INDUSTRIAL")
	else:
		current_build_mode = GridCellData.TileType.EMPTY
		btn.texture_normal = preload("res://assets/generated/factory_toggle_icon_frame_0.png")
		prints("Build mode: OFF")


func _on_assessment_completed(total: float, count: int) -> void:
	prints("Assessment: tiles:", count, "revenue: $", snapped(total, 0.01))


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

## Preload warehouse textures for factory building visuals.
const WAREHOUSE_A: Texture2D = preload("res://assets/generated/isometric_warehouse_frame_0.png")
const WAREHOUSE_B: Texture2D = preload("res://assets/generated/isometric_warehouse_v2_frame_0.png")


## Spawns (or replaces) a building Sprite2D for the given tile type at the cell.
## Only supported tile types (INDUSTRIAL) get a visual sprite overlay.
## All math assumes a 512×256 isometric diamond tile.
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
			# Alternate between A (64×64) and B (96×96) for visual variety.
			tex = WAREHOUSE_A if (cell.x + cell.y) % 2 == 0 else WAREHOUSE_B
		_:
			return  # No building sprite for other tile types.

	# Create the sprite, centered on the isometric tile.
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	sprite.name = "Building_%d_%d" % [cell.x, cell.y]
	sprite.z_index = 0
	sprite.y_sort_enabled = true

	# Scale so the building fills about 75% of the 512 px diamond width.
	var tex_size: Vector2 = tex.get_size()
	var target_width: float = 384.0  # 75% of 512
	var s: float = target_width / tex_size.x
	sprite.scale = Vector2(s, s)

	# Position one pixel above the diamond bottom tip for correct y-sort.
	# Diamond bottom = centre_y + tile_h/2 = centre_y + 128
	# We sort at bottom - 1 so the tile in front renders on top.
	var diamond_centre: Vector2 = _tilemap.map_to_local(cell)
	var diamond_bottom_y: float = diamond_centre.y + 128.0
	sprite.position = Vector2(diamond_centre.x, diamond_bottom_y - 1.0)

	# Offset the sprite centre so the scaled texture's bottom edge lands
	# a few pixels past the diamond bottom (padding for shadow/transparency).
	# sprite.position.y = diamond_bottom_y - 1
	# sprite.position.y + offset_y + tex_h/2 * s = diamond_bottom_y + padding
	#     → offset_y = 1 + padding - tex_h/2 * s
	var padding: float = 4.0  # small gap for shadow rows at bottom of sprite
	var offset_y: float = 1.0 + padding - (tex_size.y * 0.5 * s)
	sprite.offset = Vector2(0, offset_y)

	_tilemap.add_child(sprite)
	_building_sprites[cell] = sprite


## Look up the TileSet source/coords for a GridCellData tile type and place it.
func _place_tile(_cell: Vector2i, tile_type: int) -> void:
	var entry: Dictionary = TILE_TYPE_MAP.get(tile_type, {})
	if entry.is_empty():
		push_warning("No TileSet mapping for tile type ", tile_type)
		return
	var source_id: int = entry.source_id
	var atlas_coords: Vector2i = entry.coords
	_tilemap.set_cell(_cell, source_id, atlas_coords)
