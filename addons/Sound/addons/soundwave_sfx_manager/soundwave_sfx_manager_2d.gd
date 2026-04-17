@icon("res://addons/soundwave_sfx_manager/soundwave2d.png")
extends Node2D
class_name  SoundwaveSfx2D


@export var sfx: Dictionary[String, AudioStream]

func play_sfx(sfx_name):
    if sfx[sfx_name]:
        var audio_player = AudioStreamPlayer2D.new()
        add_child(audio_player)
        # configure new audio palyer
        audio_player.bus = "sfx"
        # play
        audio_player.stream = sfx[sfx_name]
        audio_player.play()
        audio_player.finished.connect(audio_player.queue_free)