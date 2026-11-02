extends Node
## Small JSON-backed save slot shared by the Main Menu and gameplay UI.

const SAVE_PATH: String = "user://solarchain_save.json"
const SAVE_VERSION: int = 1
const GRID_SIZE: int = 30
const LEGACY_GRID_SIZE: int = 20
const MAX_EXACT_JSON_NUMBER: float = 9007199254740991.0

var last_error: String = ""
var _pending_load_state: Dictionary = {}


func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game(game_state: Dictionary) -> bool:
	last_error = ""
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		last_error = "Could not open the save file for writing."
		return false
	var data: Dictionary = game_state.duplicate(true)
	data["save_version"] = SAVE_VERSION
	file.store_string(JSON.stringify(data, "\t"))
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		last_error = "The save file could not be written (%s)." % error_string(write_error)
		return false
	return true


func load_game() -> Dictionary:
	last_error = ""
	if not has_save_file():
		last_error = "No saved game was found."
		return {}
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		last_error = "Could not open the save file for reading."
		return {}
	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		last_error = "The save file is invalid: %s" % json.get_error_message()
		return {}
	var parsed_data: Variant = json.data
	if not parsed_data is Dictionary:
		last_error = "The save file does not contain a game state."
		return {}
	var game_state: Dictionary = parsed_data as Dictionary
	if not _is_integer_value(game_state.get("save_version", null)) \
			or int(game_state.get("save_version", -1)) != SAVE_VERSION:
		last_error = "This save file uses an unsupported version."
		return {}
	var grid_size_value: Variant = game_state.get("grid_size", null)
	if not _is_integer_value(grid_size_value) \
			or (int(grid_size_value) != GRID_SIZE and int(grid_size_value) != LEGACY_GRID_SIZE):
		last_error = "The save file is missing the city grid."
		return {}
	var validation_error: String = _validate_game_state(game_state)
	if validation_error != "":
		last_error = validation_error
		return {}
	return game_state


func _validate_game_state(game_state: Dictionary) -> String:
	var tiles_value: Variant = game_state.get("tiles", null)
	if not tiles_value is Array:
		return "The save file is missing the city grid."
	var seen_cells: Dictionary = {}
	for tile_value: Variant in tiles_value as Array:
		if not tile_value is Dictionary:
			return "The save file contains an invalid tile entry."
		var tile: Dictionary = tile_value as Dictionary
		var x_value: Variant = tile.get("x", null)
		var y_value: Variant = tile.get("y", null)
		var type_value: Variant = tile.get("type", null)
		var modifier_value: Variant = tile.get("land_value_modifier", 0.0)
		if not _is_integer_value(x_value) or not _is_integer_value(y_value) \
				or not _is_integer_value(type_value) or not _is_number_value(modifier_value):
			return "The save file contains invalid tile data."
		var x: int = int(x_value)
		var y: int = int(y_value)
		var tile_type: int = int(type_value)
		var pos_key: String = "%d:%d" % [x, y]
		if not _is_in_grid(x, y) or tile_type <= GridCellData.TileType.EMPTY \
				or tile_type > GridCellData.TileType.WATER_TOWER_LARGE or seen_cells.has(pos_key):
			return "The save file contains out-of-range or duplicate tiles."
		seen_cells[pos_key] = true

	var supplied_values: Variant = game_state.get("goods_supplied", [])
	if not supplied_values is Array:
		return "The save file contains an invalid goods-supply record."
	for supplied_value: Variant in supplied_values as Array:
		if not supplied_value is Dictionary:
			return "The save file contains an invalid goods-supply record."
		var supplied_record: Dictionary = supplied_value as Dictionary
		if not _valid_position_record(supplied_record) \
				or not supplied_record.get("supplied", null) is bool:
			return "The save file contains an invalid goods-supply record."

	if game_state.has("water_supplied"):
		var water_values: Variant = game_state.get("water_supplied", [])
		if not water_values is Array:
			return "The save file contains an invalid water-supply record."
		for water_value: Variant in water_values as Array:
			if not water_value is Dictionary:
				return "The save file contains an invalid water-supply record."
			var water_record: Dictionary = water_value as Dictionary
			if not _valid_position_record(water_record) \
					or not water_record.get("supplied", null) is bool:
				return "The save file contains an invalid water-supply record."

	for timestamp_key: String in ["tile_claimed_times", "tile_build_times", "factory_strikes"]:
		var timestamp_error: String = _validate_timestamp_entries(
				game_state.get(timestamp_key, []))
		if timestamp_error != "":
			return timestamp_error

	if not game_state.get("tutorial_resolved", null) is bool:
		return "The save file contains invalid tutorial state."
	for integer_key: String in ["money", "goods_stock"]:
		if not _is_integer_value(game_state.get(integer_key, null)):
			return "The save file contains an invalid %s value." % integer_key
	if int(game_state.get("goods_stock", -1)) < 0:
		return "The save file contains an invalid goods stock value."
	var dividend_value: Variant = game_state.get("dividend_percent", null)
	if not _is_number_value(dividend_value) or float(dividend_value) < 0.0 \
				or float(dividend_value) > 100.0:
		return "The save file contains an invalid dividend value."
	if game_state.has("ubi_rate"):
		var ubi_value: Variant = game_state.get("ubi_rate", null)
		if not _is_number_value(ubi_value) or float(ubi_value) < 0.0 \
					or float(ubi_value) > 1.0:
			return "The save file contains an invalid UBI rate."
	if game_state.has("town_level"):
		var town_level_value: Variant = game_state.get("town_level", null)
		if not _is_integer_value(town_level_value) \
				or int(town_level_value) < TownProgressionManager.TownLevel.HAMLET \
				or int(town_level_value) > TownProgressionManager.TownLevel.METROPOLIS:
			return "The save file contains an invalid town level."
	if game_state.has("cumulative_lvt_revenue"):
		var cum_lvt_value: Variant = game_state.get("cumulative_lvt_revenue", null)
		if not _is_integer_value(cum_lvt_value) or int(cum_lvt_value) < 0:
			return "The save file contains an invalid cumulative LVT revenue value."
	if game_state.has("lvt_rate"):
		var lvt_rate_value: Variant = game_state.get("lvt_rate", null)
		if not _is_number_value(lvt_rate_value) \
				or float(lvt_rate_value) < EconomyManager.MIN_LVT_RATE \
				or float(lvt_rate_value) > EconomyManager.MAX_LVT_RATE:
			return "The save file contains an invalid LVT rate."
	if game_state.has("speculator_lots"):
		var spec_lots_value: Variant = game_state.get("speculator_lots", null)
		if not spec_lots_value is Array:
			return "The save file contains invalid speculator lot data."
		for lot_variant: Variant in spec_lots_value as Array:
			if not lot_variant is Dictionary:
				return "The save file contains an invalid speculator lot entry."
			var lot_dict: Dictionary = lot_variant as Dictionary
			if not _valid_position_record(lot_dict):
				return "The save file contains an out-of-bounds speculator lot."
	var timer_error: String = _validate_timer_value(
			game_state.get("assessment_time_left", null), 5.0)
	if timer_error != "":
		return timer_error
	timer_error = _validate_timer_value(game_state.get("supply_time_left", null), 3.0)
	if timer_error != "":
		return timer_error
	return ""


func _validate_timestamp_entries(values: Variant) -> String:
	if not values is Array:
		return "The save file contains invalid timestamp data."
	for entry_value: Variant in values as Array:
		if not entry_value is Dictionary:
			return "The save file contains invalid timestamp data."
		var entry: Dictionary = entry_value as Dictionary
		if not _valid_position_record(entry) \
				or not _is_integer_value(entry.get("time_delta", null)):
			return "The save file contains invalid timestamp data."
		if absf(float(entry["time_delta"])) > MAX_EXACT_JSON_NUMBER:
			return "The save file contains an out-of-range timestamp."
	return ""


func _validate_timer_value(value: Variant, maximum: float) -> String:
	if not _is_number_value(value) or float(value) < -1.0 \
				or float(value) > maximum:
		return "The save file contains invalid timer data."
	return ""


func _valid_position_record(record: Dictionary, allow_sentinel: bool = false) -> bool:
	var x_value: Variant = record.get("x", null)
	var y_value: Variant = record.get("y", null)
	if not _is_integer_value(x_value) or not _is_integer_value(y_value):
		return false
	var x: int = int(x_value)
	var y: int = int(y_value)
	if allow_sentinel and x == -1 and y == -1:
		return true
	return _is_in_grid(x, y)


func _is_in_grid(x: int, y: int) -> bool:
	return x >= 0 and x < GRID_SIZE and y >= 0 and y < GRID_SIZE


func _is_integer_value(value: Variant) -> bool:
	if value is int:
		return absf(float(value)) <= MAX_EXACT_JSON_NUMBER
	return value is float and is_finite(float(value)) \
			and floorf(float(value)) == float(value) \
			and absf(float(value)) <= MAX_EXACT_JSON_NUMBER


func _is_number_value(value: Variant) -> bool:
	if value is int:
		return absf(float(value)) <= MAX_EXACT_JSON_NUMBER
	return value is float and is_finite(float(value)) \
			and absf(float(value)) <= MAX_EXACT_JSON_NUMBER


func request_load_on_game_start(game_state: Dictionary) -> void:
	_pending_load_state = game_state.duplicate(true)


func consume_load_on_game_start() -> Dictionary:
	var requested: Dictionary = _pending_load_state.duplicate(true)
	_pending_load_state.clear()
	return requested


func clear_load_on_game_start() -> void:
	_pending_load_state.clear()
