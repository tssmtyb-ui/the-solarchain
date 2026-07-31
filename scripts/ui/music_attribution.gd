extends Label
## Displays a music attribution notice at the bottom-left of the screen,
## then fades out and hides after 5 seconds.

const FADE_DURATION: float = 1.5  # seconds for the fade-out


func _ready() -> void:
	text = "Music: 'The Jazz Piano' & 'Jazz Comedy' by Benjamin Tissot (Bensound)"
	add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	add_theme_font_size_override("font_size", 14)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

	# Wait 5 seconds, then fade out and hide.
	var fade_tween: Tween = create_tween()
	fade_tween.tween_method(_set_alpha, 1.0, 0.0, FADE_DURATION).set_delay(5.0)
	fade_tween.tween_callback(queue_free)


## Interpolates the label's overall opacity during the fade-out.
func _set_alpha(a: float) -> void:
	modulate = Color(1.0, 1.0, 1.0, a)
