extends Control
## Main Menu - Giao diện mở đầu game

const SPACESHIP_SCENE = preload("res://scenes/spaceship.tscn")
const VOLUME_PERCENT_MIN = 1.0
const VOLUME_PERCENT_MAX = 100.0
const OPENING_CRAWL_DURATION = 10.0
const OPENING_CRAWL_TITLE = "EPISODE I\nNEON GRID BREACH"
const OPENING_CRAWL_TEXT_TEMPLATE = """Thiên hà Helix đang chìm trong tín hiệu nhiễu.
Neon Grid đã chiếm các tuyến đua lượng tử và biến chúng
thành hành lang kiểm soát vận tốc.

Bạn là ARIA VEIL — phi công thử nghiệm cuối cùng của
đội GridRunner, người từng mất cả phi đội trong sự cố
Core Singularity.

Sau khi hoàn tất tinh chỉnh phi thuyền,
bạn nhận lệnh đột phá qua từng stage để mở khóa
hệ thống dẫn đường thiên hà.

Chuyến xuất kích này không chỉ là một cuộc đua.
Đây là cơ hội duy nhất để giành lại tự do điều hướng."""
const MENU_SOUNDTRACK_PATH = "res://audio/Smart_Systems.mp3"

# Animation
var title_phase: float = 0.0
var button_hover_scale: float = 1.0
var stars_phase: float = 0.0
var preview_spin_speed: float = 0.6
var preview_ship: Node3D
var opening_crawl_active: bool = false
var opening_crawl_timer: float = 0.0
var opening_crawl_scene_queued: bool = false
var opening_crawl_start_y: float = 0.0
var opening_crawl_end_y: float = -1000.0

# References
@onready var title_label = $VBoxContainer/TitleLabel
@onready var subtitle_label = $VBoxContainer/SubtitleLabel
@onready var start_button = $VBoxContainer/ButtonContainer/StartButton
@onready var customize_button = $VBoxContainer/ButtonContainer/CustomizeButton
@onready var settings_button = $VBoxContainer/ButtonContainer/SettingsButton
@onready var quit_button = $VBoxContainer/ButtonContainer/QuitButton
@onready var settings_panel = $SettingsPanel
@onready var customizer_panel = $CustomizerPanel
@onready var version_label = $VersionLabel
@onready var stars_container = $StarsContainer
@onready var opening_crawl_overlay = $OpeningCrawlOverlay
@onready var crawl_title_label = $OpeningCrawlOverlay/CrawlTitle
@onready var crawl_body_label = $OpeningCrawlOverlay/CrawlBody
@onready var crawl_hint_label = $OpeningCrawlOverlay/CrawlHint

# Settings panel references
@onready var preset_option = $SettingsPanel/VBoxContainer/PresetOption
@onready var grip_mode_option = $SettingsPanel/VBoxContainer/GripModeOption
@onready var sensitivity_slider = $SettingsPanel/VBoxContainer/SensitivitySlider
@onready var sensitivity_value = $SettingsPanel/VBoxContainer/SensitivityValue
@onready var master_volume_slider = $SettingsPanel/VBoxContainer/MasterVolumeSlider
@onready var master_volume_value = $SettingsPanel/VBoxContainer/MasterVolumeValue
@onready var music_volume_slider = $SettingsPanel/VBoxContainer/MusicVolumeSlider
@onready var music_volume_value = $SettingsPanel/VBoxContainer/MusicVolumeValue
@onready var sfx_volume_slider = $SettingsPanel/VBoxContainer/SfxVolumeSlider
@onready var sfx_volume_value = $SettingsPanel/VBoxContainer/SfxVolumeValue
@onready var back_button = $SettingsPanel/VBoxContainer/BackButton

# Customizer references
@onready var preview_root = $CustomizerPanel/VBoxContainer/PreviewContainer/ShipPreviewViewport/PreviewRoot
@onready var body_prev_button = $CustomizerPanel/VBoxContainer/PartRows/BodyRow/BodyPrevButton
@onready var body_next_button = $CustomizerPanel/VBoxContainer/PartRows/BodyRow/BodyNextButton
@onready var wing_prev_button = $CustomizerPanel/VBoxContainer/PartRows/WingRow/WingPrevButton
@onready var wing_next_button = $CustomizerPanel/VBoxContainer/PartRows/WingRow/WingNextButton
@onready var tail_prev_button = $CustomizerPanel/VBoxContainer/PartRows/TailRow/TailPrevButton
@onready var tail_next_button = $CustomizerPanel/VBoxContainer/PartRows/TailRow/TailNextButton
@onready var engine_prev_button = $CustomizerPanel/VBoxContainer/PartRows/EngineRow/EnginePrevButton
@onready var engine_next_button = $CustomizerPanel/VBoxContainer/PartRows/EngineRow/EngineNextButton
@onready var body_value_label = $CustomizerPanel/VBoxContainer/PartRows/BodyRow/BodyValueLabel
@onready var wing_value_label = $CustomizerPanel/VBoxContainer/PartRows/WingRow/WingValueLabel
@onready var tail_value_label = $CustomizerPanel/VBoxContainer/PartRows/TailRow/TailValueLabel
@onready var engine_value_label = $CustomizerPanel/VBoxContainer/PartRows/EngineRow/EngineValueLabel
@onready var summary_label = $CustomizerPanel/VBoxContainer/SummaryLabel
@onready var start_from_customizer_button = $CustomizerPanel/VBoxContainer/ActionRow/StartFromCustomizerButton
@onready var customizer_back_button = $CustomizerPanel/VBoxContainer/ActionRow/CustomizerBackButton

# Current settings
var current_preset: int = 0
var current_grip_mode: int = 0
var current_sensitivity: float = 2.0
var current_master_volume: float = 100.0
var current_music_volume: float = 70.0
var current_sfx_volume: float = 85.0
var menu_music_player: AudioStreamPlayer


func _ready():
	# Hide settings panel initially
	settings_panel.visible = false
	customizer_panel.visible = false
	customize_button.visible = false
	customize_button.disabled = true
	if opening_crawl_overlay:
		opening_crawl_overlay.visible = false
		opening_crawl_overlay.modulate.a = 1.0
	if crawl_title_label:
		crawl_title_label.text = OPENING_CRAWL_TITLE
	if crawl_body_label:
		crawl_body_label.text = OPENING_CRAWL_TEXT_TEMPLATE
	
	# Connect button signals
	start_button.pressed.connect(_on_start_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	back_button.pressed.connect(_on_back_pressed)
	start_from_customizer_button.pressed.connect(_on_start_from_customizer_pressed)
	customizer_back_button.pressed.connect(_on_customizer_back_pressed)
	
	# Connect settings signals
	preset_option.item_selected.connect(_on_preset_selected)
	grip_mode_option.item_selected.connect(_on_grip_mode_selected)
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	music_volume_slider.value_changed.connect(_on_music_volume_changed)
	sfx_volume_slider.value_changed.connect(_on_sfx_volume_changed)

	# Connect customizer signals
	body_prev_button.pressed.connect(func(): _cycle_preview_ship_part("body", -1))
	body_next_button.pressed.connect(func(): _cycle_preview_ship_part("body", 1))
	wing_prev_button.pressed.connect(func(): _cycle_preview_ship_part("wings", -1))
	wing_next_button.pressed.connect(func(): _cycle_preview_ship_part("wings", 1))
	tail_prev_button.pressed.connect(func(): _cycle_preview_ship_part("tail", -1))
	tail_next_button.pressed.connect(func(): _cycle_preview_ship_part("tail", 1))
	engine_prev_button.pressed.connect(func(): _cycle_preview_ship_part("engine", -1))
	engine_next_button.pressed.connect(func(): _cycle_preview_ship_part("engine", 1))
	
	# Setup preset options
	preset_option.clear()
	preset_option.add_item("Default")
	preset_option.add_item("Sensitive")
	preset_option.add_item("Smooth")
	preset_option.add_item("Beginner")
	grip_mode_option.clear()
	grip_mode_option.add_item("Cầm ngang")
	grip_mode_option.add_item("Cầm dọc")
	
	# Load saved settings
	load_settings()
	setup_menu_music()
	apply_white_text_theme(self)
	
	# Create animated stars background
	create_stars()
	
	# Button hover effects
	setup_button_effects()
	setup_ship_preview()


func _process(delta):
	if opening_crawl_active:
		update_opening_crawl(delta)
		return
	
	# Animate title glow
	title_phase += delta * 2.0
	if title_label:
		var glow = 0.7 + 0.3 * sin(title_phase)
		title_label.modulate = Color(glow, glow, glow, 1.0)
	
	# Animate subtitle
	if subtitle_label:
		var sub_glow = 0.5 + 0.5 * sin(title_phase * 1.5)
		subtitle_label.modulate = Color(sub_glow, sub_glow, sub_glow, 1.0)
	
	# Animate stars
	animate_stars(delta)

	# Rotate ship preview while customizer is open
	if customizer_panel.visible and preview_ship and is_instance_valid(preview_ship):
		preview_ship.rotate_y(delta * preview_spin_speed)


func create_stars():
	"""Tạo các ngôi sao nền động"""
	if not stars_container:
		return
	
	for i in range(50):
		var star = ColorRect.new()
		star.size = Vector2(randf_range(2, 5), randf_range(2, 5))
		star.position = Vector2(
			randf_range(0, get_viewport().size.x),
			randf_range(0, get_viewport().size.y)
		)
		star.color = Color(1, 1, 1, randf_range(0.3, 0.8))
		star.set_meta("twinkle_speed", randf_range(1.0, 4.0))
		star.set_meta("twinkle_phase", randf_range(0, TAU))
		stars_container.add_child(star)


func animate_stars(delta):
	"""Animate twinkling stars"""
	if not stars_container:
		return
	
	for star in stars_container.get_children():
		if star.has_meta("twinkle_phase"):
			var phase = star.get_meta("twinkle_phase")
			var speed = star.get_meta("twinkle_speed")
			phase += delta * speed
			star.set_meta("twinkle_phase", phase)
			
			var alpha = 0.3 + 0.5 * abs(sin(phase))
			star.color.a = alpha


func setup_button_effects():
	"""Setup hover effects for buttons"""
	for button in [
		start_button, customize_button, settings_button, quit_button, back_button,
		body_prev_button, body_next_button, wing_prev_button, wing_next_button,
		tail_prev_button, tail_next_button, engine_prev_button, engine_next_button,
		start_from_customizer_button, customizer_back_button
	]:
		if button:
			button.mouse_entered.connect(func(): _on_button_hover(button, true))
			button.mouse_exited.connect(func(): _on_button_hover(button, false))


func apply_white_text_theme(node: Node):
	if node is Label:
		(node as Label).add_theme_color_override("font_color", Color.WHITE)
	elif node is Button:
		var button = node as Button
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_color_override("font_pressed_color", Color.WHITE)
		button.add_theme_color_override("font_focus_color", Color.WHITE)
	elif node is OptionButton:
		var option = node as OptionButton
		option.add_theme_color_override("font_color", Color.WHITE)
	for child in node.get_children():
		apply_white_text_theme(child)


func _on_button_hover(button: Button, hovering: bool):
	"""Handle button hover animation"""
	if hovering:
		var tween = create_tween()
		tween.tween_property(button, "scale", Vector2(1.05, 1.05), 0.1)
	else:
		var tween = create_tween()
		tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.1)


func setup_ship_preview():
	"""Instantiate ship preview used by the pre-game customization panel."""
	if not preview_root:
		return
	if preview_ship and is_instance_valid(preview_ship):
		preview_ship.queue_free()
	
	preview_ship = SPACESHIP_SCENE.instantiate()
	preview_ship.name = "PreviewShip"
	preview_ship.set("preview_mode", true)
	preview_root.add_child(preview_ship)
	preview_ship.position = Vector3(0, -0.15, 0)
	preview_ship.rotation_degrees = Vector3(8, 180, 0)
	preview_ship.scale = Vector3.ONE * 1.3
	
	if preview_ship.has_method("set_preview_mode"):
		preview_ship.set_preview_mode(true)
	
	refresh_ship_customizer_labels()


func _cycle_preview_ship_part(part: String, step: int):
	if not preview_ship or not is_instance_valid(preview_ship):
		return
	if not preview_ship.has_method("cycle_ship_part"):
		return
	preview_ship.cycle_ship_part(part, step)
	refresh_ship_customizer_labels()


func _cycle_preview_ship_color(part: String, step: int):
	if not preview_ship or not is_instance_valid(preview_ship):
		return
	if not preview_ship.has_method("cycle_ship_color"):
		return
	preview_ship.cycle_ship_color(part, step)
	refresh_ship_customizer_labels()


func refresh_ship_customizer_labels():
	if not preview_ship or not is_instance_valid(preview_ship):
		return
	if preview_ship.has_method("get_ship_part_variant_label"):
		var body_text = str(preview_ship.get_ship_part_variant_label("body"))
		var wing_text = str(preview_ship.get_ship_part_variant_label("wings"))
		var tail_text = str(preview_ship.get_ship_part_variant_label("tail"))
		var engine_text = str(preview_ship.get_ship_part_variant_label("engine"))
		
		if preview_ship.has_method("get_ship_part_color_label"):
			body_text += " • " + str(preview_ship.get_ship_part_color_label("body"))
			wing_text += " • " + str(preview_ship.get_ship_part_color_label("wings"))
			tail_text += " • " + str(preview_ship.get_ship_part_color_label("tail"))
			engine_text += " • " + str(preview_ship.get_ship_part_color_label("engine"))
		
		body_value_label.text = body_text
		wing_value_label.text = wing_text
		tail_value_label.text = tail_text
		engine_value_label.text = engine_text
	if preview_ship.has_method("get_ship_customization_summary"):
		summary_label.text = str(preview_ship.get_ship_customization_summary())


func _on_start_pressed():
	"""Start flow step 1: mở customizer sau khi bấm Start."""
	if settings_panel.visible:
		settings_panel.visible = false
	if not preview_ship or not is_instance_valid(preview_ship):
		setup_ship_preview()
	
	refresh_ship_customizer_labels()
	customizer_panel.visible = true
	customizer_panel.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(customizer_panel, "modulate:a", 1.0, 0.2)


func _on_start_from_customizer_pressed():
	"""Start flow step 2: xác nhận tàu và vào game."""
	# Save settings before starting
	save_settings()
	
	customizer_panel.visible = false
	settings_panel.visible = false
	
	# Force windowed mode before switching scene to avoid swapchain resize failures on some Vulkan drivers.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	start_opening_crawl()


func _change_to_main_scene():
	var err = get_tree().change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		opening_crawl_scene_queued = false
		opening_crawl_active = false
		if opening_crawl_overlay:
			opening_crawl_overlay.visible = false
			opening_crawl_overlay.modulate.a = 1.0
		customizer_panel.visible = true
		push_error("Failed to load main scene (error code: %d)" % err)


func start_opening_crawl():
	if opening_crawl_scene_queued:
		return
	if not opening_crawl_overlay or not crawl_body_label:
		call_deferred("_change_to_main_scene")
		return
	
	var crawl_text = OPENING_CRAWL_TEXT_TEMPLATE
	if preview_ship and is_instance_valid(preview_ship) and preview_ship.has_method("get_ship_customization_summary"):
		crawl_text += "\n\nProfile tàu: " + str(preview_ship.get_ship_customization_summary())
	
	if crawl_title_label:
		crawl_title_label.text = OPENING_CRAWL_TITLE
		crawl_title_label.modulate.a = 1.0
	if crawl_body_label:
		crawl_body_label.text = crawl_text
		crawl_body_label.scale = Vector2.ONE
		crawl_body_label.pivot_offset = crawl_body_label.size * 0.5
	
	var viewport_size = get_viewport().get_visible_rect().size
	opening_crawl_start_y = viewport_size.y + 40.0
	opening_crawl_end_y = -max(760.0, viewport_size.y * 0.95)
	crawl_body_label.position.y = opening_crawl_start_y
	crawl_body_label.modulate.a = 1.0
	
	if crawl_hint_label:
		crawl_hint_label.text = "SPACE / ENTER để bỏ qua"
	
	opening_crawl_timer = 0.0
	opening_crawl_active = true
	opening_crawl_overlay.visible = true
	opening_crawl_overlay.modulate.a = 1.0


func update_opening_crawl(delta: float):
	if not opening_crawl_active:
		return
	opening_crawl_timer += delta
	
	var progress = clamp(opening_crawl_timer / OPENING_CRAWL_DURATION, 0.0, 1.0)
	var eased = progress * progress
	if crawl_body_label:
		crawl_body_label.position.y = lerp(opening_crawl_start_y, opening_crawl_end_y, eased)
		var body_scale = lerp(1.0, 0.62, progress)
		crawl_body_label.scale = Vector2(body_scale, body_scale)
		var body_alpha = clamp(1.0 - max(0.0, (progress - 0.82) / 0.18), 0.0, 1.0)
		crawl_body_label.modulate.a = body_alpha
	
	if crawl_title_label:
		var title_alpha = clamp(1.0 - max(0.0, (progress - 0.55) / 0.35), 0.0, 1.0)
		crawl_title_label.modulate.a = title_alpha
	
	if progress >= 1.0:
		finish_opening_crawl_and_start_game()


func finish_opening_crawl_and_start_game():
	if opening_crawl_scene_queued:
		return
	opening_crawl_scene_queued = true
	opening_crawl_active = false
	if opening_crawl_overlay:
		var tween = create_tween()
		tween.tween_property(opening_crawl_overlay, "modulate:a", 0.0, 0.35)
		tween.tween_callback(func():
			opening_crawl_overlay.visible = false
			call_deferred("_change_to_main_scene")
		)
	else:
		call_deferred("_change_to_main_scene")


func _on_customize_pressed():
	"""Backward-compatible handler: route to Start flow."""
	_on_start_pressed()


func _on_customizer_back_pressed():
	"""Close ship customization panel."""
	var tween = create_tween()
	tween.tween_property(customizer_panel, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func(): customizer_panel.visible = false)


func _on_settings_pressed():
	"""Open settings panel"""
	if customizer_panel.visible:
		customizer_panel.visible = false
	
	settings_panel.visible = true
	
	# Animate panel appearance
	settings_panel.modulate.a = 0
	var tween = create_tween()
	tween.tween_property(settings_panel, "modulate:a", 1.0, 0.2)


func _on_quit_pressed():
	"""Quit the game"""
	get_tree().quit()


func _on_back_pressed():
	"""Close settings panel"""
	var tween = create_tween()
	tween.tween_property(settings_panel, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func(): settings_panel.visible = false)


func _on_preset_selected(index: int):
	"""Handle preset selection"""
	current_preset = index
	
	# Update sensitivity based on preset
	match index:
		0:  # Default
			sensitivity_slider.value = 2.0
		1:  # Sensitive
			sensitivity_slider.value = 3.0
		2:  # Smooth
			sensitivity_slider.value = 1.8
		3:  # Beginner
			sensitivity_slider.value = 1.5


func _on_sensitivity_changed(value: float):
	"""Handle sensitivity slider change"""
	current_sensitivity = value
	if sensitivity_value:
		sensitivity_value.text = "%.1f" % value
	save_settings()


func _on_grip_mode_selected(index: int):
	current_grip_mode = clampi(index, 0, 1)
	save_settings()


func _on_master_volume_changed(value: float):
	current_master_volume = clamp(value, VOLUME_PERCENT_MIN, VOLUME_PERCENT_MAX)
	if master_volume_value:
		master_volume_value.text = "%d%%" % int(round(current_master_volume))
	apply_runtime_audio_settings()
	save_settings()


func _on_music_volume_changed(value: float):
	current_music_volume = clamp(value, VOLUME_PERCENT_MIN, VOLUME_PERCENT_MAX)
	if music_volume_value:
		music_volume_value.text = "%d%%" % int(round(current_music_volume))
	apply_runtime_audio_settings()
	save_settings()


func _on_sfx_volume_changed(value: float):
	current_sfx_volume = clamp(value, VOLUME_PERCENT_MIN, VOLUME_PERCENT_MAX)
	if sfx_volume_value:
		sfx_volume_value.text = "%d%%" % int(round(current_sfx_volume))
	apply_runtime_audio_settings()
	save_settings()


func volume_percent_to_db(percent: float) -> float:
	var normalized = clamp(percent, VOLUME_PERCENT_MIN, VOLUME_PERCENT_MAX) / 100.0
	return linear_to_db(normalized)


func legacy_db_to_percent(db_value: float) -> float:
	var normalized_linear = db_to_linear(clamp(db_value, -40.0, 6.0))
	return clamp(round(normalized_linear * 100.0), VOLUME_PERCENT_MIN, VOLUME_PERCENT_MAX)


func apply_runtime_audio_settings():
	var master_idx = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, volume_percent_to_db(current_master_volume))
	update_menu_music_volume()


func load_mp3_stream(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	var music_data = FileAccess.get_file_as_bytes(path)
	if music_data.is_empty():
		return null
	var stream = AudioStreamMP3.new()
	stream.data = music_data
	stream.loop = true
	return stream


func setup_menu_music():
	if menu_music_player and is_instance_valid(menu_music_player):
		return
	menu_music_player = AudioStreamPlayer.new()
	menu_music_player.name = "MenuMusic"
	menu_music_player.bus = "Master"
	add_child(menu_music_player)
	
	var stream = load_mp3_stream(MENU_SOUNDTRACK_PATH)
	if stream:
		menu_music_player.stream = stream
		update_menu_music_volume()
		menu_music_player.play()
	else:
		push_warning("Menu soundtrack not found: " + MENU_SOUNDTRACK_PATH)


func update_menu_music_volume():
	if not menu_music_player:
		return
	menu_music_player.volume_db = volume_percent_to_db(current_music_volume)


func save_settings():
	"""Save settings to config file"""
	var config = ConfigFile.new()
	config.set_value("controls", "preset", current_preset)
	config.set_value("controls", "grip_mode", current_grip_mode)
	config.set_value("controls", "sensitivity", current_sensitivity)
	config.set_value("audio", "master_percent", current_master_volume)
	config.set_value("audio", "music_percent", current_music_volume)
	config.set_value("audio", "sfx_percent", current_sfx_volume)
	config.save("user://menu_settings.cfg")


func load_settings():
	"""Load settings from config file"""
	var config = ConfigFile.new()
	if config.load("user://menu_settings.cfg") == OK:
		current_preset = int(config.get_value("controls", "preset", 0))
		current_grip_mode = clampi(int(config.get_value("controls", "grip_mode", 0)), 0, 1)
		current_sensitivity = float(config.get_value("controls", "sensitivity", 2.0))
		if config.has_section_key("audio", "master_percent"):
			current_master_volume = float(config.get_value("audio", "master_percent", 100.0))
		else:
			current_master_volume = legacy_db_to_percent(float(config.get_value("audio", "master_db", 0.0)))
		if config.has_section_key("audio", "music_percent"):
			current_music_volume = float(config.get_value("audio", "music_percent", 70.0))
		else:
			current_music_volume = legacy_db_to_percent(float(config.get_value("audio", "music_db", -8.0)))
		if config.has_section_key("audio", "sfx_percent"):
			current_sfx_volume = float(config.get_value("audio", "sfx_percent", 85.0))
		else:
			current_sfx_volume = legacy_db_to_percent(float(config.get_value("audio", "sfx_db", -4.0)))
	
	current_master_volume = clamp(current_master_volume, VOLUME_PERCENT_MIN, VOLUME_PERCENT_MAX)
	current_music_volume = clamp(current_music_volume, VOLUME_PERCENT_MIN, VOLUME_PERCENT_MAX)
	current_sfx_volume = clamp(current_sfx_volume, VOLUME_PERCENT_MIN, VOLUME_PERCENT_MAX)
	
	if preset_option:
		preset_option.selected = current_preset
	if grip_mode_option:
		grip_mode_option.selected = current_grip_mode
	if sensitivity_slider:
		sensitivity_slider.value = current_sensitivity
	if sensitivity_value:
		sensitivity_value.text = "%.1f" % current_sensitivity
	if master_volume_slider:
		master_volume_slider.value = current_master_volume
	if master_volume_value:
		master_volume_value.text = "%d%%" % int(round(current_master_volume))
	if music_volume_slider:
		music_volume_slider.value = current_music_volume
	if music_volume_value:
		music_volume_value.text = "%d%%" % int(round(current_music_volume))
	if sfx_volume_slider:
		sfx_volume_slider.value = current_sfx_volume
	if sfx_volume_value:
		sfx_volume_value.text = "%d%%" % int(round(current_sfx_volume))
	
	apply_runtime_audio_settings()


func _input(event):
	if opening_crawl_active:
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
			finish_opening_crawl_and_start_game()
			return
		if event is InputEventKey and event.pressed and not event.is_echo():
			match event.keycode:
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE:
					finish_opening_crawl_and_start_game()
					return
		return
	
	if event.is_action_pressed("ui_cancel"):
		if customizer_panel.visible:
			_on_customizer_back_pressed()
		elif settings_panel.visible:
			_on_back_pressed()
		return
	
	if customizer_panel.visible and event is InputEventKey and event.pressed and not event.is_echo():
		var color_step = -1 if event.shift_pressed else 1
		match event.keycode:
			KEY_5:
				_cycle_preview_ship_color("body", color_step)
			KEY_6:
				_cycle_preview_ship_color("wings", color_step)
			KEY_7:
				_cycle_preview_ship_color("tail", color_step)
			KEY_8:
				_cycle_preview_ship_color("engine", color_step)
