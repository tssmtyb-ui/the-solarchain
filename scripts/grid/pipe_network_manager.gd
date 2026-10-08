class_name PipeNetworkManager
extends Node
## Owns the pipe/logistics connectivity graph for SLUDGE tiles.
##
## Computes the set of "live" pipe cells — SLUDGE tiles reachable (4-connectivity)
## from any supply source (a pipe touching the map border) — via a cached BFS
## flood-fill. The cache is invalidated by mark_dirty() whenever the grid's
## SLUDGE/INDUSTRIAL layout changes, so is_factory_hooked_up() stays cheap.
##
## Injected dependencies (set by the root scene before use):
##   grid      (GridManager)  — tile reads
##   grid_size (int)          — bounds for the border/supply check

## The tile type that constitutes a pipe segment.
const PIPE_TILE: int = GridCellData.TileType.SLUDGE

## Maximum transported goods per pipe cell per supply-chain tick (3 seconds).
## Four goods per cell is roughly 1.33 goods per second.
const PIPE_CAPACITY_PER_CELL_PER_TICK: int = 4

## 4-connectivity offsets — consistent with other grid-neighbour checks.
const CARDINAL: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
]

## The GridManager data model.
var grid: GridManager

## Grid dimensions — mirrors the root scene's GRID_SIZE.
var grid_size: int = 10

## True when cached live pipe components must be recomputed.
var _dirty: bool = true

## Cached set of live pipe cells (Vector2i → true) reachable from a supply source.
var _live_pipe_cells: Dictionary = {}

## Live pipe cell -> component ID. IDs are assigned in grid-scan order.
var _component_by_cell: Dictionary = {}

## Component ID -> {cells, capacity, demand, delivered}.
var _components: Dictionary = {}


## Emitted when pipe topology changes so the root can refresh pipe visuals.
signal network_changed

## Emitted after flow has been allocated for a supply tick.
signal capacity_updated


## Marks cached topology stale. Called when a pipe or factory is placed/removed.
func mark_dirty() -> void:
	_dirty = true
	network_changed.emit()


## Returns the live network ID adjacent to a factory, or -1 if it is unhooked.
## If a factory touches multiple networks, CARDINAL order deterministically picks
## the first one; the factory does not merge those networks.
func get_factory_network_id(factory_pos: Vector2i) -> int:
	_ensure_fresh()
	for off in CARDINAL:
		var adjacent: Vector2i = factory_pos + off
		if _component_by_cell.has(adjacent):
			return int(_component_by_cell[adjacent])
	return -1


## True if the factory touches a live pipe network reaching the map edge.
func is_factory_hooked_up(factory_pos: Vector2i) -> bool:
	return get_factory_network_id(factory_pos) >= 0


## Capacity for a cached network, or 0 if the ID is no longer present.
func get_network_capacity(component_id: int) -> int:
	_ensure_fresh()
	if not _components.has(component_id):
		return 0
	var stats: Dictionary = _components[component_id]
	return int(stats["capacity"])


## Resets actual demand/delivery counters before the next supply-chain tick.
func reset_capacity_usage() -> void:
	_ensure_fresh()
	for component_id: int in _components.keys():
		var stats: Dictionary = _components[component_id]
		stats["demand"] = 0
		stats["delivered"] = 0
		_components[component_id] = stats


## Adds one factory's requested and delivered output to its live network totals.
func record_network_flow(component_id: int, demand: int, delivered: int) -> void:
	_ensure_fresh()
	if not _components.has(component_id):
		return
	var stats: Dictionary = _components[component_id]
	stats["demand"] = int(stats["demand"]) + demand
	stats["delivered"] = int(stats["delivered"]) + delivered
	_components[component_id] = stats


## Announces that demand/delivery totals are ready for visuals and UI queries.
func finish_capacity_tick() -> void:
	capacity_updated.emit()


## Capacity telemetry for the network touching a factory.
func get_factory_network_stats(factory_pos: Vector2i) -> Dictionary:
	var component_id: int = get_factory_network_id(factory_pos)
	if component_id < 0 or not _components.has(component_id):
		return {"capacity": 0, "demand": 0, "delivered": 0, "bottleneck": false}
	var stats: Dictionary = _components[component_id]
	stats["bottleneck"] = int(stats["demand"]) > 0 \
			and int(stats["demand"]) >= int(stats["capacity"])
	return stats


## Returns live pipe cells for networks currently at or above 100% utilization.
func get_bottleneck_pipe_cells() -> Array[Vector2i]:
	_ensure_fresh()
	var cells: Array[Vector2i] = []
	for component_id: int in _components.keys():
		var stats: Dictionary = _components[component_id]
		var demand: int = int(stats["demand"])
		var capacity: int = int(stats["capacity"])
		if demand <= 0 or demand < capacity:
			continue
		var component_cells: Array[Vector2i] = stats["cells"]
		cells.append_array(component_cells)
	return cells


## Returns every live pipe cell, recomputing the cached component graph if stale.
func get_live_pipe_cells() -> Array[Vector2i]:
	_ensure_fresh()
	var cells: Array[Vector2i] = []
	for key: Variant in _live_pipe_cells:
		cells.append(key as Vector2i)
	return cells


## Rebuilds cached live components with one BFS per border-connected component.
func _ensure_fresh() -> void:
	if not _dirty:
		return
	_live_pipe_cells.clear()
	_component_by_cell.clear()
	_components.clear()
	var next_component_id: int = 0
	for x in range(grid_size):
		for y in range(grid_size):
			var start_cell: Vector2i = Vector2i(x, y)
			if not _is_supply_source(start_cell) or not _is_pipe(start_cell) \
					or _component_by_cell.has(start_cell):
				continue
			var component_cells: Array[Vector2i] = []
			var queue: Array[Vector2i] = [start_cell]
			var queue_index: int = 0
			_component_by_cell[start_cell] = next_component_id
			_live_pipe_cells[start_cell] = true
			while queue_index < queue.size():
				var current: Vector2i = queue[queue_index]
				queue_index += 1
				component_cells.append(current)
				for offset: Vector2i in CARDINAL:
					var neighbor: Vector2i = current + offset
					if not _is_pipe(neighbor) or _component_by_cell.has(neighbor):
						continue
					_component_by_cell[neighbor] = next_component_id
					_live_pipe_cells[neighbor] = true
					queue.append(neighbor)
			_components[next_component_id] = {
				"cells": component_cells,
				"capacity": component_cells.size() * PIPE_CAPACITY_PER_CELL_PER_TICK,
				"demand": 0,
				"delivered": 0
			}
			next_component_id += 1
	_dirty = false


## True if the cell sits on the map border — a potential supply exit point.
func _is_supply_source(pos: Vector2i) -> bool:
	return pos.x == 0 or pos.x == grid_size - 1 or pos.y == 0 or pos.y == grid_size - 1


## True if the cell holds a pipe tile and lies within grid bounds.
func _is_pipe(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= grid_size or pos.y < 0 or pos.y >= grid_size:
		return false
	return grid.get_tile_type(pos) == PIPE_TILE
