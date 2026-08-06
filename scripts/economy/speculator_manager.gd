class_name SpeculatorManager
extends Node
## Corporate Speculator (mini-boss) AI — the brain for a land-buying rival.
## The speculator parks cash in prime empty land and panics out when values
## crash. Isolated from the player economy loop; the root scene drives it via
## `process_speculator_tick()` on its own cadence.
##
## The root scene drives it via `scan_and_buy_land()` (purchase half) and
## `process_speculator_tick()` (LVT + panic/bankruptcy) on its own cadence.
## This file owns the AI's state and decisions.

# ---------------------------------------------------------------------------
#   AI behavior thresholds
# ---------------------------------------------------------------------------

## Buys empty land when land value rises above this.
const BUY_THRESHOLD: int = 25

## Monetary cost the speculator pays to claim a prime tile.
const CLAIM_COST: int = 100

## Sells land back whenever a held tile's land value crashes below this.
const PANIC_SELL_THRESHOLD: int = 15

# ---------------------------------------------------------------------------
#   State
# ---------------------------------------------------------------------------

## The speculator's own treasury. LVT on owned tiles is deducted here every
## tick — an economic crash can wipe it out (bankruptcy), echoing the player's
## own fragility.
var speculator_cash: int = 500

## Land currently held by this speculator.
var owned_tiles: Array[Vector2i] = []

# ---------------------------------------------------------------------------
#   Signals
# ---------------------------------------------------------------------------

## Emitted when speculator_cash drops below zero. `owned_tiles` is a snapshot
## of the entire portfolio at the moment of collapse.
signal speculator_bankrupt(owned_tiles: Array[Vector2i])

## Emitted when a single held tile is panic-sold back to the open market.
signal speculator_panic_sold(grid_pos: Vector2i)

## Emitted when the speculator pays CLAIM_COST to claim a prime GRASS tile.
## The root scene paints the DIRT_LOT marker on the map in response.
signal speculator_claimed_tile(grid_pos: Vector2i)

# ---------------------------------------------------------------------------
#   Logic
# ---------------------------------------------------------------------------

## Runs one AI tick: pays LVT on every held tile, then either collapses
## (bankruptcy: signal + full liquidation) or panic-sells individual tiles
## whose land value crashed below the hold threshold.
func process_speculator_tick(economy_manager_ref: EconomyManager) -> void:
	# Speculators pay the same LVT the player pays — one assessment per tile.
	for pos in owned_tiles:
		speculator_cash -= economy_manager_ref.get_land_value(pos)

	# Bankruptcy: out of money, the portfolio liquidates entirely.
	if speculator_cash < 0:
		var snapshot: Array[Vector2i] = []
		for pos in owned_tiles:
			snapshot.append(pos)
		speculator_bankrupt.emit(snapshot)
		owned_tiles.clear()
		return

	# Panic selling: dump any holding whose value crashed below the threshold.
	# Iterate a copy so we can erase from the live array.
	for pos in owned_tiles.duplicate():
		if economy_manager_ref.get_land_value(pos) < PANIC_SELL_THRESHOLD:
			owned_tiles.erase(pos)
			speculator_panic_sold.emit(pos)


## Scans the grid for empty GRASS land above BUY_THRESHOLD and claims the single
## highest-value tile it can afford (CLAIM_COST). Emits speculator_claimed_tile
## on success so the root scene can paint the DIRT_LOT marker.
func scan_and_buy_land(grid_manager_ref: GridManager, economy_manager_ref: EconomyManager) -> void:
	var best_pos: Vector2i = Vector2i(-1, -1)
	var best_value: int = 0

	for pos in grid_manager_ref.get_all_occupied_positions():
		if grid_manager_ref.get_tile_type(pos) != GridCellData.TileType.GRASS:
			continue
		var value: int = economy_manager_ref.get_land_value(pos)
		if value > BUY_THRESHOLD and value > best_value:
			best_value = value
			best_pos = pos

	# Claim the best prime tile if we found one and can afford it.
	if best_pos != Vector2i(-1, -1) and speculator_cash >= CLAIM_COST:
		speculator_cash -= CLAIM_COST
		owned_tiles.append(best_pos)
		speculator_claimed_tile.emit(best_pos)


## Hostile buyout: the player seizes `pos` from the AI. Removes it from the
## portfolio and pays the speculator the flat buyout premium (BUYOUT_GAIN) in
## cash. Returns true if the tile was actually held and released.
func force_sell_tile(pos: Vector2i) -> void:
	if owned_tiles.has(pos):
		owned_tiles.erase(pos)
		speculator_cash += 500
