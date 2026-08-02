class_name GridCellData
## Lightweight data object stored per grid cell.
## Holds the tile type and its land-value modifier (used later for LVT simulation).

## All tile types available in the game. Add new entries as new systems appear.
enum TileType {
	EMPTY,
	GRASS,
	DIRT,
	CONCRETE,
	ASPHALT,
	WATER,
	ROAD,
	ROAD_CROSS,
	SIDEWALK,
	SIDEWALK_CORNER,
	RESIDENTIAL_LOW,
	RESIDENTIAL_HIGH,
	INDUSTRIAL,
	WAREHOUSE,
	SEED_HUB,
	PARK,
	SLUDGE,
}

var tile_type: int = TileType.EMPTY
var land_value_modifier: float = 0.0


func _init(p_tile_type: int = TileType.EMPTY, p_land_value_modifier: float = 0.0) -> void:
	tile_type = p_tile_type
	land_value_modifier = p_land_value_modifier


## Returns true if this tile is considered empty / unbuilt.
func is_empty() -> bool:
	return tile_type == TileType.EMPTY
