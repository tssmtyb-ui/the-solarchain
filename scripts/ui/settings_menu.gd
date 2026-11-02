class_name SettingsMenu
extends Control
## Shared settings panel used by the Main Menu and in-game pause menu.

signal pause_requested
signal resume_requested
signal save_requested
signal load_requested
signal main_menu_requested
signal menu_closed

const MUSIC_SETTINGS_PATH: String = "user://solarchain_settings.cfg"

@onready var _title_label: Label = $CenterContainer/Panel/Margin/VBox/TitleLabel
@onready var _resume_button: Button = $CenterContainer/Panel/Margin/VBox/ResumeButton
@onready var _save_button: Button = $CenterContainer/Panel/Margin/VBox/SaveGameButton
@onready var _load_button: Button = $CenterContainer/Panel/Margin/VBox/LoadGameButton
@onready var _music_button: Button = $CenterContainer/Panel/Margin/VBox/MusicButton
@onready var _credits_button: Button = $CenterContainer/Panel/Margin/VBox/CreditsButton
@onready var _back_button: Button = $CenterContainer/Panel/Margin/VBox/BackButton
@onready var _main_menu_button: Button = $CenterContainer/Panel/Margin/VBox/MainMenuButton
@onready var _status_label: Label = $CenterContainer/Panel/Margin/VBox/StatusLabel

var _in_game: bool = false
var _credits_panel: CreditsPanel
var _credits_from_settings: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_resume_button.pressed.connect(_on_resume_pressed)
	_save_button.pressed.connect(_on_save_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	_music_button.pressed.connect(_on_music_pressed)
	_credits_button.pressed.connect(_on_credits_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_apply_context()


func configure(in_game: bool, credits_panel: CreditsPanel) -> void:
	_in_game = in_game
	_credits_panel = credits_panel
	if _credits_panel != null \
			and not _credits_panel.closed.is_connected(on_credits_closed):
		_credits_panel.closed.connect(on_credits_closed)
	if is_node_ready():
		_apply_context()


func open_menu() -> void:
	refresh_save_load_state()
	_status_label.text = ""
	show()
	if _in_game:
		_resume_button.grab_focus()
	else:
		_back_button.grab_focus()


func close_menu() -> void:
	if not visible:
		return
	hide()
	menu_closed.emit()


func set_status(message: String) -> void:
	_status_label.text = message


func _apply_context() -> void:
	_title_label.text = "Paused" if _in_game else "Settings"
	_resume_button.visible = _in_game
	_save_button.visible = _in_game
	_load_button.visible = true
	_back_button.visible = not _in_game
	_main_menu_button.visible = _in_game
	_refresh_music_label()
	refresh_save_load_state()


func refresh_save_load_state() -> void:
	var save_manager: Node = get_node_or_null("/root/GameSave")
	_load_button.disabled = save_manager == null \
			or not bool(save_manager.call("has_save_file"))


func _refresh_music_label() -> void:
	var music_manager: Node = get_node_or_null("/root/MusicManager")
	var muted: bool = false
	if music_manager != null:
		muted = bool(music_manager.call("is_muted"))
	else:
		var config: ConfigFile = ConfigFile.new()
		if config.load(MUSIC_SETTINGS_PATH) == OK:
			muted = bool(config.get_value("audio", "music_muted", false))
	_music_button.disabled = false
	_music_button.text = "Unmute Music" if muted else "Mute Music"


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_save_pressed() -> void:
	save_requested.emit()


func _on_load_pressed() -> void:
	load_requested.emit()


func _on_music_pressed() -> void:
	var music_manager: Node = get_node_or_null("/root/MusicManager")
	if music_manager == null:
		return
	music_manager.call("toggle_muted")
	_refresh_music_label()


func _on_credits_pressed() -> void:
	if _credits_panel != null and is_instance_valid(_credits_panel):
		_credits_from_settings = true
		hide()
		_credits_panel.open()


func _on_back_pressed() -> void:
	close_menu()


func on_credits_closed() -> void:
	if not _credits_from_settings:
		return
	_credits_from_settings = false
	show()
	_credits_button.grab_focus()


func _on_main_menu_pressed() -> void:
	main_menu_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _credits_panel != null and is_instance_valid(_credits_panel) \
			and _credits_panel.visible and event.is_action_pressed("ui_cancel") \
			and not event.is_echo():
		_credits_panel.close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and event.is_echo():
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if _in_game:
		if visible:
			if _credits_panel != null and is_instance_valid(_credits_panel) \
					and _credits_panel.visible:
				_credits_panel.close()
			else:
				resume_requested.emit()
		else:
			pause_requested.emit()
	elif visible:
		if _credits_panel != null and is_instance_valid(_credits_panel) \
				and _credits_panel.visible:
			_credits_panel.close()
		else:
			close_menu()
	get_viewport().set_input_as_handled()
