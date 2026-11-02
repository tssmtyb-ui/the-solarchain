extends Node


func test_hover_readout_shows_only_value_and_applicable_pollution_warning() -> void:
	var readout: HeatmapReadout = HeatmapReadout.new()
	add_child(readout)
	await get_tree().process_frame
	readout.visible = true
	readout.show_cell("42/100", false)
	var label: Label = readout.get_node("LandValueReadoutLabel") as Label
	assert(label.text == "Value: 42/100", "Readout should show only the hovered cell's value when safe.")
	readout.show_cell("42/100", true)
	assert(label.text == "Value: 42/100 · Pollution risk", "Readout should add a concise pollution warning when applicable.")
	assert(not label.text.contains("Cell ("), "Readout should not include cell coordinates.")
	assert(not label.text.contains("Factory pollution risk: no"), "Readout should not show a negative pollution message.")
	assert(readout.custom_minimum_size.y <= HeatmapReadout.MAX_VISIBLE_HEIGHT, "Readout should remain compact.")
	readout.queue_free()
