class_name CameraControls
extends Camera2D

## Keyboard pan rate in on-screen pixels per second, keeping controls consistent
## at every zoom level. The initial 0.2 zoom is substantially faster than the
## previous fixed 600 world-units-per-second movement.
@export var pan_speed: float = 900.0
@export var fast_pan_multiplier: float = 2.5
@export var pan_acceleration: float = 6000.0
@export var pan_braking: float = 8000.0
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.03
@export var max_zoom: float = 3.0
@export var bounds_margin: Vector2 = Vector2(1024.0, 512.0)

## Keyboard velocity is kept in screen-space so its feel does not change with zoom.
var _pan_velocity: Vector2 = Vector2.ZERO
var _is_dragging: bool = false


func configure_limits_for_tilemap(tilemap: TileMapLayer) -> void:
	if tilemap == null:
		return
	var used_rect: Rect2i = tilemap.get_used_rect()
	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return
	var corners: PackedVector2Array = PackedVector2Array([
		tilemap.map_to_local(Vector2i(used_rect.position.x, used_rect.position.y)),
		tilemap.map_to_local(Vector2i(used_rect.end.x - 1, used_rect.position.y)),
		tilemap.map_to_local(Vector2i(used_rect.position.x, used_rect.end.y - 1)),
		tilemap.map_to_local(Vector2i(used_rect.end.x - 1, used_rect.end.y - 1)),
	])
	var min_x: float = corners[0].x
	var max_x: float = corners[0].x
	var min_y: float = corners[0].y
	var max_y: float = corners[0].y
	for corner: Vector2 in corners:
		min_x = minf(min_x, corner.x)
		max_x = maxf(max_x, corner.x)
		min_y = minf(min_y, corner.y)
		max_y = maxf(max_y, corner.y)
	limit_left = int(floorf(min_x - bounds_margin.x))
	limit_right = int(ceilf(max_x + bounds_margin.x))
	limit_top = int(floorf(min_y - bounds_margin.y))
	limit_bottom = int(ceilf(max_y + bounds_margin.y))
	position = (corners[0] + corners[1] + corners[2] + corners[3]) / 4.0


func _process(delta: float) -> void:
	var drag_active: bool = _is_dragging or Input.is_action_pressed("camera_pan_drag")
	if drag_active:
		_pan_velocity = Vector2.ZERO
		return

	var direction: Vector2 = Input.get_vector(
			"camera_pan_left", "camera_pan_right", "camera_pan_up", "camera_pan_down")
	var speed_multiplier: float = fast_pan_multiplier if Input.is_action_pressed("camera_pan_fast") else 1.0
	var target_velocity: Vector2 = direction * pan_speed * speed_multiplier
	var rate: float = pan_acceleration if direction != Vector2.ZERO else pan_braking
	_pan_velocity = _pan_velocity.move_toward(target_velocity, rate * delta)

	# Camera zoom scales world movement on screen, so divide by zoom to keep
	# keyboard panning at the same apparent speed at all zoom levels.
	var safe_zoom: Vector2 = Vector2(maxf(absf(zoom.x), 0.001), maxf(absf(zoom.y), 0.001))
	global_position += (_pan_velocity / safe_zoom) * delta
	_clamp_to_limits()

func _input(event: InputEvent) -> void:
	# Use _input for drags so the camera keeps following if the pointer crosses
	# a HUD control while the middle mouse button is held.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_is_dragging = event.pressed
		if _is_dragging:
			_pan_velocity = Vector2.ZERO
		return

	if event is InputEventMouseMotion and (_is_dragging or Input.is_action_pressed("camera_pan_drag")):
		var safe_zoom: Vector2 = Vector2(maxf(absf(zoom.x), 0.001), maxf(absf(zoom.y), 0.001))
		# Dragging the map follows the cursor 1:1 in screen-space.
		global_position -= event.relative / safe_zoom
		_clamp_to_limits()


func _clamp_to_limits() -> void:
	if limit_left < limit_right:
		global_position.x = clampf(global_position.x, float(limit_left), float(limit_right))
	if limit_top < limit_bottom:
		global_position.y = clampf(global_position.y, float(limit_top), float(limit_bottom))


func _unhandled_input(event: InputEvent) -> void:
	# Preserve wheel zoom and its existing step/clamp behavior.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clamp(zoom + Vector2(zoom_speed, zoom_speed), Vector2(min_zoom, min_zoom), Vector2(max_zoom, max_zoom))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clamp(zoom - Vector2(zoom_speed, zoom_speed), Vector2(min_zoom, min_zoom), Vector2(max_zoom, max_zoom))
