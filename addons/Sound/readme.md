
# Soundwave Godot music plugins

![hackatime](https://hackatime.hackclub.com/api/v1/badge/U0A5GJ8JP5F/Orosemo/sound-wave)

[Demo](https://github.com/Orosemo/soundwave-demo)
[SFX](https://github.com/Orosemo/soundwave-sfx)

## Table of content

- [Soundwave Music Manager](#soundwave-music-manager)
- [Demo](#demo)

---

## IMPORTANT for the plugin to work properlz a `music` audio bus needs to be created in the editor.

## Soundwave Music Manager

The Soundwave Music Manager is an helpful godot plugin that adds a autoload music manager that is able to play global background music from predefined playlists.

### Usage

1. Install and activate the plugin ([learn how](https://docs.godotengine.org/en/stable/tutorials/plugins/editor/installing_plugins.html)).
2. Create your background music playlists as `AudioStreamPlaylist`s in a new folder e.g. `res://playlists/`.
3. Open the music manager scene in `res://addons/soundwave_music_manager/soundwave_music_manager.tscn` and add the previosly created playlists with an fitting string key in the playlist dict and configure the fade durating, fade type and play on load playlist to your liking.
4. You can now  change the playlist by running `soundwaveMusicManager.play_playlist("<playlist>")`.

## Demo

The demo for this plugin is can be found [here](https://github.com/Orosemo/soundwave-demo). Check the readme for more informations
