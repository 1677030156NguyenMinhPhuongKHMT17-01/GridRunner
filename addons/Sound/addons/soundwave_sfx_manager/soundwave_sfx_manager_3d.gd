@icon("res://addons/soundwave_sfx_manager/soundwave3d.png")
extends Node3D
class_name  SoundwaveSfx3D

@export var sfx: Dictionary[String, AudioStream]

func play_sfx(sfx_name, max_distance = 0.0, max_polyphony = 1, panning_strengh = 1.0):
    if sfx[sfx_name]:
        var audio_player = AudioStreamPlayer3D.new()
        add_child(audio_player)
        # configure new audio player
        audio_player.bus = "sfx"
        audio_player.max_distance = max_distance
        audio_player.max_polyphony = max_polyphony
        audio_player.panning_strength = panning_strengh
        # play 
        audio_player.stream = sfx[sfx_name]
        audio_player.play()
        audio_player.finished.connect(audio_player.queue_free)