class_name BuildingPlacement
extends Node
## Handles visual spawning and removal of building sprites on the tilemap.
## Takes a TileMapLayer reference so all isometric math and sprite parenting
## is isolated from the root scene.

## Preloaded building textures, cached once.
const FACTORY: Texture2D = preload("res://assets/factory/FactoryC.png")
const WAREHOUSE: Texture2D = preload("res://assets/warehouse/warehouseBrownA.png")
const HOUSE_A: Texture2D = preload("res://assets/House/houseSmallBlueA.png")
const HOUSE_B: Texture2D = preload("res://assets/House/houseSmallBlueB.png")
const APARTMENT_A: Texture2D = preload("res://assets/Apartment/buildingTallOrangeA.png")
const APARTMENT_B: Texture2D = preload("res://assets/Apartment/buildingTallOrangeB.png")
const GAZEBO: Texture2D = preload("res://assets/Park/gazebo.png")
const SLUDGE_PIPE: Texture2D = preload("res://assets/generated/sludge_pipe.png")

## Reference to the TileMapLayer — set by the root scene after creation.
var tilemap: TileMapLayer

## Reference to the GridManager — lets pipe visual updates query tile types.
var grid: GridManager

## Full-brightness tint for live (border-connected) pipe sprites.
const PIPE_LIVE_MODULATE: Color = Color(1, 1, 1, 1)
## Dimmed tint for disconnected pipe sprites — dead lines read clearly.
const PIPE_DEAD_MODULATE: Color = Color(0.5, 0.5, 0.5, 0.7)

## Live pipe cells from the last PipeNetworkManager refresh (Vector2i → true).
var _live_pipe_cells: Dictionary = {}

## Tracks building Sprite2D nodes keyed by grid position.
var _sprites: Dictionary = {}


## Spawns (or replaces) a building Sprite2D overlay for the given tile type.
## All math assumes a 512×256 isometric diamond tile (Diamond Right layout).
func spawn_building(cell: Vector2i, tile_type: int) -> void:
	# Remove any existing sprite at this cell first.
	if _sprites.has(cell):
		var old: Node = _sprites[cell] as Node
		if is_instance_valid(old):
			old.queue_free()
		_sprites.erase(cell)

	# Pick the building texture for this tile type.
	var tex: Texture2D = _texture_for_type(tile_type)
	if tex == null:
		return

	# Create the sprite, centered.
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

	# Position at diamond centre; offset so the bottom edge sits on the ground plane.
	var diamond_centre: Vector2 = tilemap.map_to_local(cell)
	sprite.position = diamond_centre
	var offset_y: float = 128.0 - (tex_size.y * 0.5 * s)
	sprite.offset = Vector2(0, offset_y)

	tilemap.add_child(sprite)
	_sprites[cell] = sprite

	# New pipe segments inherit the current live/dead tint immediately, so a
	# freshly placed SLUDGE line that isn't border-connected shows dimmed.
	if tile_type == GridCellData.TileType.SLUDGE:
		_tint_pipe(cell)


## Removes the building sprite at the given cell, if one exists.
func remove_building(cell: Vector2i) -> void:
	if _sprites.has(cell):
		var sprite: Node = _sprites[cell] as Node
		if is_instance_valid(sprite):
			sprite.queue_free()
		_sprites.erase(cell)


## Returns true if a building sprite exists at the given cell.
func has_building(cell: Vector2i) -> bool:
	return _sprites.has(cell)


## Refreshes pipe visuals from the network's live-cell set. Live (border-
## connected) SLUDGE segments render at full brightness; disconnected ones are
## dimmed so dead lines are visible at a glance. Called on every network change.
func update_pipe_visuals(live_cells: Array[Vector2i]) -> void:
	_live_pipe_cells.clear()
	for c in live_cells:
		_live_pipe_cells[c] = true
	_apply_pipe_tints()


## Applies the current live/dead tint to every pipe sprite on the board.
func _apply_pipe_tints() -> void:
	if grid == null:
		return
	for cell in _sprites:
		if grid.get_tile_type(cell) == GridCellData.TileType.SLUDGE:
			_tint_pipe(cell)


## Tints a single pipe sprite according to whether its cell is in the live set.
func _tint_pipe(cell: Vector2i) -> void:
	var sprite: Node = _sprites.get(cell)
	if not is_instance_valid(sprite) or not sprite is Sprite2D:
		return
	sprite.modulate = PIPE_LIVE_MODULATE if _live_pipe_cells.has(cell) else PIPE_DEAD_MODULATE


func _texture_for_type(tile_type: int) -> Texture2D:
	match tile_type:
		GridCellData.TileType.INDUSTRIAL:
			return FACTORY
		GridCellData.TileType.WAREHOUSE:
			return WAREHOUSE
		GridCellData.TileType.RESIDENTIAL_LOW:
			return HOUSE_A if randi() % 2 == 0 else HOUSE_B
		GridCellData.TileType.RESIDENTIAL_HIGH:
			return APARTMENT_A if randi() % 2 == 0 else APARTMENT_B
		GridCellData.TileType.PARK:
			return GAZEBO
		GridCellData.TileType.SLUDGE:
			return SLUDGE_PIPE
	return null
