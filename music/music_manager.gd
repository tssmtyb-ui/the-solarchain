class_name MusicManager
extends Node
## Plays the soundtrack as a continuous sequential loop.
## Creates an AudioStreamPlayer child and alternates between MP3 tracks
## so that when one finishes, the next one starts automatically.

const TRACKS: Array[AudioStream] = [
	preload("res://music/bensound-thejazzpiano.mp3"),
	preload("res://music/bensound-jazzcomedy.mp3"),
]

var _player: AudioStreamPlayer
var _current_index: int = 0


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "AudioPlayer"
	_player.volume_db = -6.0
	_player.bus = "Master"
	_player.finished.connect(_on_track_ended)
	add_child(_player)
	_play_track(0)


func _play_track(index: int) -> void:
	_current_index = index
	_player.stream = TRACKS[index]
	_player.volume_db = 0.0
	_player.play()
	prints("Music: playing track", index)


func _on_track_ended() -> void:
	var next: int = (_current_index + 1) % TRACKS.size()
	_play_track(next)
