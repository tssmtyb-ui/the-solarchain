extends Node


func test_economy_hud_presenter_preserves_resource_text_and_accessibility() -> void:
	var workers_label: Label = Label.new()
	var goods_label: Label = Label.new()
	var factories_label: Label = Label.new()
	var dividend_label: Label = Label.new()
	var presenter: EconomyHudPresenter = EconomyHudPresenter.new()
	presenter.configure(workers_label, goods_label, factories_label, dividend_label)

	presenter.render_resources(8, 5, 3, 12, 4, 2, 3, 6, 2, 3, 1, 2, 4, 7, 4, 2, 3.0, 5, 3, 5)

	assert(workers_label.text == "Workers 8 · E 5 · A 3")
	assert(goods_label.text == "Goods 12 · +4/-2 · Homes 3/6")
	assert(factories_label.text == "Factories 2/3 · Farms 1/2")
	assert(workers_label.accessibility_name == "Workforce")
	assert(workers_label.tooltip_text == "Housing provides 8 workers total. 5 are assigned to operating factories and 3 remain available. Each factory needs 2 workers.")
	assert(workers_label.accessibility_description == workers_label.tooltip_text)
	assert(goods_label.accessibility_name == "Goods and home delivery")
	assert(goods_label.tooltip_text == "Goods in stock: 12. Each supply cycle (3.0 seconds): +4 produced, -2 consumed. 3 of 6 homes received goods.")
	assert(goods_label.accessibility_description == goods_label.tooltip_text)
	assert(factories_label.accessibility_name == "Factories operating")
	assert(factories_label.tooltip_text == "2/3 factories operating; each needs a road and 2 workers. Farms: 1/2 Farmhouses operating with 4 active of 7 fields (+4 goods/tick). Farmhouses need one worker plus a road; fields must be within radius 3. Sludge improves factory output.")
	workers_label.free()
	goods_label.free()
	factories_label.free()
	dividend_label.free()


func test_economy_hud_presenter_preserves_dividend_text_at_boundaries_and_midpoint() -> void:
	var presenter: EconomyHudPresenter = EconomyHudPresenter.new()
	var workers_label: Label = Label.new()
	var goods_label: Label = Label.new()
	var factories_label: Label = Label.new()
	var dividend_label: Label = Label.new()
	presenter.configure(workers_label, goods_label, factories_label, dividend_label)

	presenter.render_dividend(0.0, 0, 0)
	assert(dividend_label.text == "Dividend: 0% (No production boost, keeping 100% tax revenue)")
	presenter.render_dividend(25.0, 45, 12)
	assert(dividend_label.text == "Dividend: 25% (Costs $45/tick, boosts factory production by +12%)")
	presenter.render_dividend(100.0, 0, 50)
	assert(dividend_label.text == "Dividend: 100% (Costs all tax revenue, boosts factory production by +50%)")
	workers_label.free()
	goods_label.free()
	factories_label.free()
	dividend_label.free()


func test_objective_panel_presenter_preserves_text_visibility_and_layout() -> void:
	var box: Control = Control.new()
	var header: Button = Button.new()
	var summary: Label = Label.new()
	var residential: CheckBox = CheckBox.new()
	var factory: CheckBox = CheckBox.new()
	var road: CheckBox = CheckBox.new()
	var sludge: CheckBox = CheckBox.new()
	var presenter: ObjectivePanelPresenter = ObjectivePanelPresenter.new()
	presenter.configure(box, header, summary, residential, factory, road, sludge)

	presenter.render(1, 1, false, true, false, false, false, 2, 1)
	assert(residential.text == "Build 2 Residential zones (1/2)")
	assert(factory.text == "Build 1 Factory (1/1)")
	assert(road.text == "Connect them with a Road (Pending)")
	assert(sludge.text == "Optional: sludge to map edge (+30% output)")
	assert(not residential.button_pressed and factory.button_pressed and not road.button_pressed)
	assert(sludge.button_pressed)
	assert(header.text == "Objectives  ▾")
	assert(not summary.visible and residential.visible and factory.visible and road.visible and sludge.visible)
	assert(is_equal_approx(box.offset_bottom, 340.0))
	assert(is_equal_approx(box.custom_minimum_size.y, 340.0))
	assert(is_equal_approx(box.size.y, 340.0))

	presenter.render(2, 1, true, true, true, true, false, 2, 1)
	assert(header.text == "City Foundations  ✓  ▸")
	assert(road.text == "Connect them with a Road (Connected)")
	assert(residential.button_pressed and factory.button_pressed and road.button_pressed)
	assert(summary.text == "Foundations complete!\nNext: set Dividend above 0% to resolve Bobr's challenge.")
	assert(summary.visible and not residential.visible and not factory.visible and not road.visible and not sludge.visible)
	assert(is_equal_approx(box.offset_bottom, 252.0))

	presenter.render(2, 1, true, true, true, true, true, 2, 1)
	assert(summary.text == "Foundations complete · tutorial resolved.\nYour city is yours to grow.")
	assert(is_equal_approx(box.offset_bottom, 232.0))
	box.free()
	header.free()
	summary.free()
	residential.free()
	factory.free()
	road.free()
	sludge.free()


func test_game_scene_delegates_resource_dividend_and_objective_presentation() -> void:
	var game_scene: PackedScene = load("res://node_2d.tscn") as PackedScene
	assert(game_scene != null, "Could not load the gameplay scene.")
	var game: Node = game_scene.instantiate()
	get_tree().root.add_child(game)
	await get_tree().process_frame

	game.call("_update_resource_ui")
	var workers_label: Label = game.get_node("UI/TopBar/HBoxContainer/WorkersLabel") as Label
	var goods_label: Label = game.get_node("UI/TopBar/HBoxContainer/GoodsLabel") as Label
	var factories_label: Label = game.get_node("UI/TopBar/HBoxContainer/FactoriesLabel") as Label
	assert(workers_label.text == "Workers 0 · E 0 · A 0")
	assert(goods_label.text == "Goods 0 · +0/-0 · Homes 0/0")
	assert(factories_label.text == "Factories 0/0 · Farms 0/0")

	game.call("_update_dividend_label", 0.0)
	var dividend_label: Label = game.get_node("UI/TopBar/HBoxContainer/DividendBox/DividendLabel") as Label
	assert(dividend_label.text == "Dividend: 0% (No production boost, keeping 100% tax revenue)")

	var objective_header: Button = game.get_node("UI/ObjectiveBox/MarginContainer/VBoxContainer/Title") as Button
	assert(objective_header.text == "Objectives  ▾")
	game.queue_free()
	await get_tree().process_frame
