extends Control
## Main Menu entry point for starting, configuring, or quitting the game.

@onready var _settings_menu: SettingsMenu = $SettingsMenu
@onready var _start_button: Button = $CenterContainer/MenuPanel/Margin/VBox/StartGameButton
@onready var _settings_button: Button = $CenterContainer/MenuPanel/Margin/VBox/SettingsButton
@onready var _quit_button: Button = $CenterContainer/MenuPanel/Margin/VBox/QuitButton

var _credits_panel: CreditsPanel
var _save_manager: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_save_manager = get_node_or_null("/root/GameSave")
	if _save_manager == null:
		push_error("Main Menu: GameSave autoload is missing.")
	_start_button.pressed.connect(_on_start_game_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_settings_menu.load_requested.connect(_on_load_requested)
	_settings_menu.menu_closed.connect(_on_settings_menu_closed)

	_credits_panel = CreditsPanel.new()
	_credits_panel.name = "CreditsPanel"
	_credits_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_credits_panel.set_anchors_preset(Control.PRESET_CENTER)
	_credits_panel.offset_left = -300.0
	_credits_panel.offset_top = -220.0
	_credits_panel.offset_right = 300.0
	_credits_panel.offset_bottom = 220.0
	_credits_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_credits_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_credits_panel.z_index = 50
	_credits_panel.closed.connect(_on_credits_closed)
	add_child(_credits_panel)
	_settings_menu.configure(false, _credits_panel)


func _on_start_game_pressed() -> void:
	if _save_manager != null:
		_save_manager.call("clear_load_on_game_start")
	_change_to_game()


func _on_settings_pressed() -> void:
	$CenterContainer.hide()
	_settings_menu.open_menu()


func _on_settings_menu_closed() -> void:
	$CenterContainer.show()
	_settings_button.grab_focus()


func _on_credits_closed() -> void:
	_settings_menu.on_credits_closed()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _change_to_game() -> void:
	var error: Error = get_tree().change_scene_to_file("res://node_2d.tscn")
	if error != OK:
		push_error("Main Menu: could not open the game scene (%s)." % error_string(error))


func _on_load_requested() -> void:
	if _save_manager == null:
		_settings_menu.set_status("Save/load is unavailable.")
		return
	var loaded_state: Variant = _save_manager.call("load_game")
	if not loaded_state is Dictionary or (loaded_state as Dictionary).is_empty():
		_settings_menu.set_status(str(_save_manager.get("last_error")))
		return
	_save_manager.call("request_load_on_game_start", loaded_state as Dictionary)
	_settings_menu.set_status("Loading saved city...")
	_change_to_game()


func open_saved_game() -> void:
	_on_load_requested()
