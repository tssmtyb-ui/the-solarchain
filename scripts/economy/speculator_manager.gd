class_name SpeculatorManager
extends Node
## Corporate Speculator (mini-boss) AI — the brain for a land-buying rival.
## The speculator parks cash in prime empty land and panics out when values
## crash. Isolated from the player economy loop; the root scene drives it via
## `process_speculator_tick()` on its own cadence.
##
## Later phases add the purchase half of the loop (scan for BUY_THRESHOLD).
## This file only owns the AI's state and decisions.

# ---------------------------------------------------------------------------
#   AI behavior thresholds
# ---------------------------------------------------------------------------

## Buys empty land when land value rises above this. Purchase scanning is
## wired by the root scene in a later phase — this is the AI's trigger.
const BUY_THRESHOLD: int = 25

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
