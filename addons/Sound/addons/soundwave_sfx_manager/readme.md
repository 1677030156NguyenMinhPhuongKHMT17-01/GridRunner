
# Soundwave Godot music plugin

![hackatime](https://hackatime.hackclub.com/api/v1/badge/U0A5GJ8JP5F/Orosemo/sound-wave)

[Demo](https://github.com/Orosemo/soundwave-demo)
[Music](https://github.com/Orosemo/soundwave-music)

## Table of content

- [Soundwave SFX Manager](#soundwave-sfx-manager)
- [Demo](#demo)

---

## IMPORTANT for the plugin to work properlz a `sfx` audio bus needs to be created in the editor.

## Soundwave SFX Manager

The Soundwave SFX Manager is an helpful godot plugin that adds two new Nodes: `SoundwaveSfx2D` and `SoundwaveSfx3D` which are nodes used to play sounds from a predefined list. It is able to handle overlapping sounds which make it capable of handling multiple different sfx at the same time.

### Usage

1. Install and activate the plugin ([learn how](https://docs.godotengine.org/en/stable/tutorials/plugins/editor/installing_plugins.html)).
2. Add the `SoundwaveSfx2D` or `SoundwaveSfx3D` (depending on the scene type (2d or 3d)) node to your scene.
3. Configure the nodes `sfx` property and add your sfx with fitting keys.
4. Play sounds by calling the `play_sfx("<your sfx key>")` on the `SoundwaveSfx` node.

## Demo

The demo for this plugin is can be found [here](https://github.com/Orosemo/soundwave-demo). Check the readme for more informations
