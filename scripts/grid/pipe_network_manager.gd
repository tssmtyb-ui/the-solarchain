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

## 4-connectivity offsets — matches the Manhattan math used by the economy
## (WORKER_RADIUS, POLLUTION_RADIUS, _count_magnets_in_radius).
const CARDINAL: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
]

## The GridManager data model.
var grid: GridManager

## Grid dimensions — mirrors the root scene's GRID_SIZE.
var grid_size: int = 10

## True when _live_pipe_cells is stale and must be recomputed on the next query.
var _dirty: bool = true

## Cached set of live pipe cells (Vector2i → true) reachable from a supply source.
var _live_pipe_cells: Dictionary = {}


## Marks the cached network as stale. Call whenever a SLUDGE or INDUSTRIAL tile
## is placed or removed so the next hookup query recomputes connectivity.
func mark_dirty() -> void:
	_dirty = true


## Returns true if `factory_pos` has a live pipe in any cardinal neighbour —
## i.e. the factory is hooked into the logistics network.
func is_factory_hooked_up(factory_pos: Vector2i) -> bool:
	_ensure_fresh()
	for off in CARDINAL:
		var adj: Vector2i = Vector2i(factory_pos.x + off.x, factory_pos.y + off.y)
		if _live_pipe_cells.has(adj):
			return true
	return false


## Returns the set of live pipe cells (recomputes if stale). Useful for debug
## overlays / visual tinting of connected vs. dead pipes.
func get_live_pipe_cells() -> Array[Vector2i]:
	_ensure_fresh()
	var cells: Array[Vector2i] = []
	for k in _live_pipe_cells:
		cells.append(k as Vector2i)
	return cells


## Rebuilds the reachable-pipe set if the cache is dirty: BFS flood-fill seeded
## from every supply source (SLUDGE cell touching the map border).
func _ensure_fresh() -> void:
	if not _dirty:
		return
	_live_pipe_cells.clear()
	var queue: Array[Vector2i] = []
	for x in range(grid_size):
		for y in range(grid_size):
			var pos := Vector2i(x, y)
			if _is_supply_source(pos) and _is_pipe(pos) and not _live_pipe_cells.has(pos):
				_live_pipe_cells[pos] = true
				queue.append(pos)
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for off in CARDINAL:
			var nxt: Vector2i = Vector2i(cur.x + off.x, cur.y + off.y)
			if _is_pipe(nxt) and not _live_pipe_cells.has(nxt):
				_live_pipe_cells[nxt] = true
				queue.append(nxt)
	_dirty = false


## True if the cell sits on the map border — a potential supply exit point.
func _is_supply_source(pos: Vector2i) -> bool:
	return pos.x == 0 or pos.x == grid_size - 1 or pos.y == 0 or pos.y == grid_size - 1


## True if the cell holds a pipe tile and lies within grid bounds.
func _is_pipe(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= grid_size or pos.y < 0 or pos.y >= grid_size:
		return false
	return grid.get_tile_type(pos) == PIPE_TILE
