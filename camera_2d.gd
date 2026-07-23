extends Camera2D

@export var speed: float = 600.0
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.05
@export var max_zoom: float = 3.0

func _process(delta: float) -> void:
	var direction := Vector2.ZERO

	# WASD Movement Controls
	if Input.is_key_pressed(KEY_W):
		direction.y -= 1
	if Input.is_key_pressed(KEY_S):
		direction.y += 1
	if Input.is_key_pressed(KEY_A):
		direction.x -= 1
	if Input.is_key_pressed(KEY_D):
		direction.x += 1

	# Move camera position (normalized to prevent fast diagonal movement)
	position += direction.normalized() * speed * delta

func _unhandled_input(event: InputEvent) -> void:
	# Mouse Wheel Zooming
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clamp(zoom + Vector2(zoom_speed, zoom_speed), Vector2(min_zoom, min_zoom), Vector2(max_zoom, max_zoom))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clamp(zoom - Vector2(zoom_speed, zoom_speed), Vector2(min_zoom, min_zoom), Vector2(max_zoom, max_zoom))
