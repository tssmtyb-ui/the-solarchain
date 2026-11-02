class_name HeatmapVisibilityPolicy
extends RefCounted
## Pure visibility-state policy shared by UI input handlers and unit tests.

var manual_visible: bool = false
var park_factory_auto_enabled: bool = false
var park_factory_suppressed: bool = false
var hidden_by_pause: bool = false


func set_manual_visible(show_heatmap: bool) -> void:
	if show_heatmap:
		manual_visible = true
		park_factory_suppressed = false
	else:
		manual_visible = false
		park_factory_suppressed = park_factory_auto_enabled


func set_park_factory_auto_enabled(is_enabled: bool) -> void:
	park_factory_auto_enabled = is_enabled
	park_factory_suppressed = false


func toggle_manual_visibility() -> void:
	set_manual_visible(not is_effectively_visible())


func is_effectively_visible() -> bool:
	var requested_visible: bool = (manual_visible or park_factory_auto_enabled) \
			and not park_factory_suppressed
	return requested_visible and not hidden_by_pause
