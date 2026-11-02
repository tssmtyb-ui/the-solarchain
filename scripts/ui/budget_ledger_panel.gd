class_name BudgetLedgerPanel
extends PanelContainer
## Compact popup window displaying the Municipal Budget Ledger across the last
## 10 assessment cycles: Gross LVT Revenue, Maintenance Costs, UBI Payouts,
## and Net Treasury Income, plus a visual income-vs-expenditure bar chart.

const PANEL_WIDTH: float = 520.0
const PANEL_HEIGHT: float = 360.0

var _summary_label: Label
var _history_label: Label
var _chart_container: HBoxContainer
var _latest_history: Array[Dictionary] = []


func _ready() -> void:
	name = "BudgetLedgerPanel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 110
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -PANEL_WIDTH * 0.5
	offset_top = -PANEL_HEIGHT * 0.5
	offset_right = PANEL_WIDTH * 0.5
	offset_bottom = PANEL_HEIGHT * 0.5
	custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	accessibility_name = "Municipal Budget Ledger"
	accessibility_description = "Historical LVT revenue, maintenance costs, UBI payouts, and net income over the last 10 assessment cycles."

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.065, 0.09, 0.97)
	panel_style.border_color = Color(0.95, 0.80, 0.38, 0.95)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 14.0
	panel_style.content_margin_right = 14.0
	panel_style.content_margin_top = 10.0
	panel_style.content_margin_bottom = 10.0
	add_theme_stylebox_override(&"panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.add_theme_constant_override(&"separation", 8)
	add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.name = "LedgerTitle"
	title.text = "Municipal Budget Ledger (Last 10 Cycles)"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override(&"font_size", 18)
	title.add_theme_color_override(&"font_color", Color(0.96, 0.86, 0.50))
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "Close"
	close_btn.tooltip_text = "Close Municipal Budget Ledger"
	close_btn.pressed.connect(_on_close_pressed)
	header.add_child(close_btn)

	_summary_label = Label.new()
	_summary_label.name = "BudgetSummaryLabel"
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.add_theme_font_size_override(&"font_size", 13)
	_summary_label.add_theme_color_override(&"font_color", Color(0.92, 0.95, 0.99))
	vbox.add_child(_summary_label)

	_chart_container = HBoxContainer.new()
	_chart_container.name = "BudgetChartContainer"
	_chart_container.custom_minimum_size = Vector2(0.0, 54.0)
	_chart_container.add_theme_constant_override(&"separation", 6)
	vbox.add_child(_chart_container)

	_history_label = Label.new()
	_history_label.name = "BudgetHistoryLabel"
	_history_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_history_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history_label.add_theme_font_size_override(&"font_size", 12)
	_history_label.add_theme_color_override(&"font_color", Color(0.86, 0.90, 0.95))
	vbox.add_child(_history_label)

	_render_contents()


func render_ledger(
		history: Array[Dictionary],
		current_gross_lvt: int,
		current_maintenance: int,
		current_ubi_payout: int,
		current_net_income: int,
		cumulative_lvt: int = 0) -> void:
	_latest_history.clear()
	for entry: Dictionary in history:
		_latest_history.append(entry.duplicate(true))
	if _summary_label == null:
		return
	_summary_label.text = (
		"LATEST CYCLE — Gross LVT: $%d · Maintenance: -$%d · UBI Payout: -$%d · Net: %s$%d\n"
		+ "Cumulative Gross LVT Collected: $%d"
	) % [
		current_gross_lvt,
		current_maintenance,
		current_ubi_payout,
		"+" if current_net_income >= 0 else "",
		current_net_income,
		cumulative_lvt,
	]
	_render_contents()


func get_rendered_entry_count() -> int:
	return _latest_history.size()


func _render_contents() -> void:
	if _history_label == null or _chart_container == null:
		return
	for child: Node in _chart_container.get_children():
		_chart_container.remove_child(child)
		child.queue_free()

	if _latest_history.is_empty():
		_history_label.text = "No completed assessment cycles recorded yet."
		return

	var max_abs_val: int = 10
	for entry: Dictionary in _latest_history:
		max_abs_val = maxi(max_abs_val, absi(int(entry.get("gross_lvt", 0))))
		max_abs_val = maxi(max_abs_val, absi(int(entry.get("net_income", 0))))

	var lines: Array[String] = [
		"Cycle | Gross LVT | Maint. | UBI Payout | Net Income"
	]
	for entry: Dictionary in _latest_history:
		var cyc: int = int(entry.get("cycle", 0))
		var gross: int = int(entry.get("gross_lvt", 0))
		var maint: int = int(entry.get("maintenance", 0))
		var ubi: int = int(entry.get("ubi_payout", 0))
		var net: int = int(entry.get("net_income", 0))
		var net_prefix: String = "+" if net >= 0 else ""
		lines.append("#%d | $%d | -$%d | -$%d | %s$%d" % [
			cyc, gross, maint, ubi, net_prefix, net
		])

		var bar := ColorRect.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ratio: float = clampf(float(absi(net)) / float(max_abs_val), 0.18, 1.0)
		bar.custom_minimum_size = Vector2(18.0, roundf(48.0 * ratio))
		bar.size_flags_vertical = Control.SIZE_SHRINK_END
		bar.color = Color(0.24, 0.84, 0.44, 0.9) if net >= 0 else Color(0.92, 0.28, 0.28, 0.9)
		bar.tooltip_text = "Cycle #%d: Gross $%d, Maint -$%d, UBI -$%d, Net %s$%d" % [
			cyc, gross, maint, ubi, net_prefix, net
		]
		_chart_container.add_child(bar)

	_history_label.text = "\n".join(lines)


func _on_close_pressed() -> void:
	visible = false
