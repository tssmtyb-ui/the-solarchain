extends Node
## Plays the soundtrack as a continuous sequential loop.
## Creates an AudioStreamPlayer child and alternates between MP3 tracks
## so that when one finishes, the next one starts automatically.

const TRACK_PATHS: PackedStringArray = [
	"res://music/bensound-thejazzpiano.mp3",
	"res://music/bensound-jazzcomedy.mp3",
]
const SETTINGS_PATH: String = "user://solarchain_settings.cfg"
const MUSIC_VOLUME_DB: float = -6.0
const MUTED_VOLUME_DB: float = -80.0

var _player: AudioStreamPlayer
var _current_index: int = 0
var _muted: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var config: ConfigFile = ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		_muted = bool(config.get_value("audio", "music_muted", false))
	_player = AudioStreamPlayer.new()
	_player.name = "AudioPlayer"
	_player.volume_db = MUSIC_VOLUME_DB
	_player.bus = "Master"
	_player.finished.connect(_on_track_ended)
	add_child(_player)
	_play_track(0)


func _play_track(index: int) -> void:
	_current_index = index
	if DisplayServer.get_name() == "headless":
		return
	var stream: AudioStream = load(TRACK_PATHS[index]) as AudioStream
	if stream == null:
		push_error("MusicManager: could not load track %s." % TRACK_PATHS[index])
		return
	_player.stream = stream
	_player.play()
	_apply_mute_state()
	prints("Music: playing track", index)


func is_muted() -> bool:
	return _muted


func set_muted(muted: bool) -> void:
	_muted = muted
	_apply_mute_state()
	var config: ConfigFile = ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("audio", "music_muted", _muted)
	var save_error: Error = config.save(SETTINGS_PATH)
	if save_error != OK:
		push_warning("MusicManager: could not save audio settings (%s)." % error_string(save_error))


func toggle_muted() -> bool:
	set_muted(not _muted)
	return _muted


func _apply_mute_state() -> void:
	if _player == null:
		return
	_player.volume_db = MUTED_VOLUME_DB if _muted else MUSIC_VOLUME_DB


func _on_track_ended() -> void:
	var next: int = (_current_index + 1) % TRACK_PATHS.size()
	_play_track(next)
