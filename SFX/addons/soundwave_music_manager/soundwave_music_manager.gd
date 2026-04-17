@icon("res://addons/soundwave_music_manager/soundwaveMusic.png")
extends AudioStreamPlayer2D


@export_category("playlists")
@export var playlists: Dictionary[String, AudioStreamPlaylist]
@export var play_on_load: AudioStreamPlaylist
@export var fade_duration: float = 0.5
@export_enum("EASE_IN", "EASE_OUT", "EASE_IN_OUT", "EASE_OUT_IN") var fade_mode: int

var current_playlist: AudioStreamPlaylist

func fade_in():
	var tween = get_tree().create_tween()
	tween.set_ease(fade_mode)
	tween.tween_property(self , "volume_linear", 1.0, fade_duration,)
	tween.tween_callback(tween.kill)

func fade_out():
	var tween = get_tree().create_tween()
	tween.set_ease(fade_mode)
	tween.tween_property(self , "volume_linear", 0, fade_duration)
	tween.tween_callback(change_playlist)

func change_playlist():
	stream = current_playlist
	play()
	fade_in()

func play_playlist(playlist_name):
	if playlists[playlist_name]:
		current_playlist = playlists[playlist_name]
		fade_out()

func _ready():
	if play_on_load:
		current_playlist = play_on_load
		change_playlist()
		
