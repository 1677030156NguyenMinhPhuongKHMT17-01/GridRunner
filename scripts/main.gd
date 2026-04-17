extends Node3D
## Main Game Controller with Enhanced Features

const YAFSM = preload("res://addons/imjp94.yafsm/YAFSM.gd")
const TRACKING_WHEEL_WIDGET_SCRIPT = preload("res://scripts/tracking_wheel_widget.gd")

# UDP Socket để nhận dữ liệu từ Python tracker
var udp_server: PacketPeerUDP
const UDP_PORT = 5555

# Python tracker process
var tracker_pid: int = -1
var tracker_running: bool = false
const TRACKER_STOP_FLAG_PATH = "user://tracker_stop.flag"
const TRACKER_STOP_WAIT_TIMEOUT_MS = 1200
const TRACKER_STOP_POLL_INTERVAL_MS = 60
var tracker_stop_flag_abs_path: String = ""

# Game state
var score: int = 0
var high_score: int = 0
var speed_multiplier: float = 1.0
var collision_slowdown: float = 0.0
const COLLISION_RECOVERY_RATE = 0.65
var game_over: bool = false
var paused: bool = false
var spawn_timer: float = 0.0
var difficulty_timer: float = 0.0
const SPAWN_INTERVAL_BASE = 0.8
var current_spawn_interval: float = SPAWN_INTERVAL_BASE
const MAX_OBSTACLES = 20

# Camera shake
var shake_intensity: float = 0.0
var shake_decay: float = 5.0
var original_camera_pos: Vector3

# Debug mode
var debug_mode: bool = false

# Calibration mode
var calibration_mode: bool = false
var calibration_progress: int = 0
const CALIBRATION_SAMPLE_TARGET = 120

# Connection status
var last_data_time: float = 0.0
var connection_timeout: float = 2.0

# Near-miss warning
var warning_intensity: float = 0.0
const WARNING_DISTANCE = 5.0  # Khoảng cách để cảnh báo

# Combo system
var combo_count: int = 0
var combo_timer: float = 0.0
const COMBO_TIMEOUT = 2.0

# Campaign race
var race_intro_active: bool = true
var race_intro_timer: float = 0.0
var race_started: bool = false
var race_finished: bool = false
var player_race_distance: float = 0.0
var race_target_distance: float = 1500.0
var current_campaign_level: int = 0
var campaign_transition_pending: bool = false
var campaign_completed: bool = false
var stage_clear_waiting: bool = false
var pending_next_level_index: int = -1
var rival_ships: Array = []
const LANE_POSITIONS = [-6.0, -3.0, 0.0, 3.0, 6.0]
const CAMPAIGN_LEVELS = [
	{
		"title": "Signal Breach",
		"goal_distance": 1000.0,
		"rival_count": 3,
		"rival_speed_min": 17.0,
		"rival_speed_max": 20.5,
		"spawn_interval": 0.9,
		"support_interval": 5.2,
		"segment_duration": 6.4,
		"story": [
			"Mở đầu chiến dịch: bạn vượt qua lớp phòng thủ đầu tiên của Neon Grid.",
			"Đừng va chạm trực diện, giữ nhịp tăng tốc ổn định.",
			"Về nhất để mở khóa tầng mạng tiếp theo."
		]
	},
	{
		"title": "Pulse Corridor",
		"goal_distance": 1250.0,
		"rival_count": 4,
		"rival_speed_min": 18.5,
		"rival_speed_max": 22.2,
		"spawn_interval": 0.8,
		"support_interval": 4.7,
		"segment_duration": 5.9,
		"story": [
			"Hành lang xung nhịp đã kích hoạt, tốc độ thay đổi liên tục.",
			"Đối thủ bắt đầu block lane và tăng tốc bất ngờ.",
			"Gom vật phẩm đúng lúc để giữ lợi thế."
		]
	},
	{
		"title": "Quantum Lattice",
		"goal_distance": 1450.0,
		"rival_count": 4,
		"rival_speed_min": 20.0,
		"rival_speed_max": 24.5,
		"spawn_interval": 0.72,
		"support_interval": 4.2,
		"segment_duration": 5.4,
		"story": [
			"Mạng lưới lượng tử xuất hiện, đường đua dày đặc hơn.",
			"Rival sẽ đổi lane liên tục như người chơi thật.",
			"Giữ bình tĩnh và canh boost khi có khoảng trống."
		]
	},
	{
		"title": "Core Singularity",
		"goal_distance": 1650.0,
		"rival_count": 5,
		"rival_speed_min": 21.5,
		"rival_speed_max": 26.5,
		"spawn_interval": 0.64,
		"support_interval": 3.9,
		"segment_duration": 5.0,
		"story": [
			"Chặng cuối: lõi Singularity mở toàn bộ bẫy vận tốc.",
			"Không còn đường an toàn tuyệt đối - chỉ có kỹ năng lái.",
			"Vượt qua chặng này để kết thúc chiến dịch."
		]
	}
]
const CAMPAIGN_ENDING_LINES = [
	"Bạn đã phá vỡ phong tỏa của Neon Grid.",
	"Đội GridRunner giành lại tuyến đua liên thiên hà.",
	"Chiến dịch hoàn tất: toàn bộ hệ thống đã được giải phóng."
]

# ============================================================
# TRACK/CURVE SYSTEM - Hệ thống đường cong
# ============================================================
enum TrackSegment { STRAIGHT, CURVE_LEFT, CURVE_RIGHT }

var current_segment: int = TrackSegment.STRAIGHT
var segment_timer: float = 0.0
var segment_duration: float = 6.0  # Thời gian mỗi đoạn đường
var next_segment: int = TrackSegment.STRAIGHT

# Track rotation - góc xoay hiện tại của đường
var track_rotation: float = 0.0  # Degrees
var target_track_rotation: float = 0.0
var track_rotation_speed: float = 2.0  # Tốc độ xoay

# Visual offset khi rẽ
var track_offset: Vector3 = Vector3.ZERO
var target_track_offset: Vector3 = Vector3.ZERO

# Curve intensity
const CURVE_ANGLE = 46.0  # Độ nghiêng khi rẽ (bank)
const CURVE_OFFSET = 8.4  # Offset ngang khi rẽ
const CURVE_LATERAL_SPEED = 10.8  # Tốc độ trôi ngang khi vào cua
const SHIP_CURVE_INFLUENCE = 0.95  # Mức ảnh hưởng của cua lên tàu
const GRID_CURVE_INFLUENCE = 0.72  # Mức ảnh hưởng của cua lên grid line
const CURVE_TRANSITION_RATIO = 0.32  # Phần trăm cuối segment dùng để blend sang segment kế
const CURVE_DEPTH_STRENGTH = 1.45  # Độ "bẻ" theo chiều sâu để cảm giác cua rõ hơn
const CURVE_BANK_VERTICAL_PUSH = 0.03  # Độ nghiêng mặt đường theo bề ngang
var track_wave_phase: float = 0.0
var track_wave_amount: float = 0.0
var track_curve_intensity: float = 0.0

# Obstacle spawn layout
const OBSTACLE_LANE_CHOICES = [-7.2, -4.8, -2.4, 0.0, 2.4, 4.8, 7.2]
const OBSTACLE_Y_CHOICES = [-2.4, -1.2, 0.0, 1.2, 2.4]
const OBSTACLE_SPAWN_FRONT_Z = -124.0
var last_obstacle_spawn_pos: Vector3 = Vector3(999.0, 999.0, -999.0)

# Rival visualization/collision tuning
const RIVAL_VISUAL_Z_BASE = -4.5
const RIVAL_VISUAL_DISTANCE_SCALE = 0.09
const RIVAL_VISUAL_Z_MIN = -26.0
const RIVAL_VISUAL_Z_MAX = 14.0
const RANK_DISTANCE_EPSILON = 0.5
const RIVAL_COLLISION_COOLDOWN = 0.28
const RIVAL_COLLISION_PUSH_BASE = 0.9
var rival_collision_cooldown: float = 0.0

# Camera (pilot/chase feel)
const CAMERA_FOLLOW_RESPONSE = 6.5
const CAMERA_LOOK_RESPONSE = 8.0
const CAMERA_BASE_FOV = 84.0
const CAMERA_BOOST_FOV = 13.0

# Audio
var audio_engine: AudioStreamPlayer
var audio_boost: AudioStreamPlayer
var audio_warning: AudioStreamPlayer
var audio_score: AudioStreamPlayer
var audio_explosion: AudioStreamPlayer
var audio_music: AudioStreamPlayer
var master_volume_percent: float = 100.0
var music_volume_percent: float = 70.0
var sfx_volume_percent: float = 85.0
var score_sound_cooldown: float = 0.0
var warning_sound_cooldown: float = 0.0
var music_playback: AudioStreamGeneratorPlayback
var music_phase_a: float = 0.0
var music_phase_b: float = 0.0
var music_phase_c: float = 0.0
var music_progress: float = 0.0
var music_chord_index: int = 0
var using_custom_soundtrack: bool = false
const CUSTOM_SOUNDTRACK_PATH = "res://audio/Breis_-_Mega_Man_X4_Intro_Stage_X.mp3"
const AUDIO_PERCENT_MIN = 1.0
const AUDIO_PERCENT_MAX = 100.0
const MUSIC_SAMPLE_RATE = 44100.0
const MUSIC_CHORD_DURATION = 3.0
const MUSIC_CHORDS = [
	[110.0, 138.59, 164.81],  # Am
	[98.0, 123.47, 146.83],   # G
	[87.31, 110.0, 130.81],   # F
	[92.5, 116.54, 138.59],   # G# / transition
]

# Hand tracking data
const HAND_PACKET_TEMPLATE: Dictionary = {
	"found": false,
	"mid_x": 0.5,
	"mid_y": 0.5,
	"angle": 0.0,
	"distance": 0.5,
	"hands": 0
}
const TRACKER_PACKET_WARNING_INTERVAL_MS = 1500
var hand_data: Dictionary = HAND_PACKET_TEMPLATE.duplicate()
var _last_tracker_packet_warning_ms: int = -TRACKER_PACKET_WARNING_INTERVAL_MS

enum ControlMode { HAND_TRACKING, KEYBOARD_MOUSE, HYBRID }
var control_mode: int = ControlMode.HYBRID
var _esc_was_pressed: bool = false
var _restart_was_pressed: bool = false
var _menu_was_pressed: bool = false
var _toggle_control_was_pressed: bool = false
var _continue_was_pressed: bool = false

# References
@onready var camera = $Camera3D
@onready var score_label = $UI/ScoreLabel
@onready var speed_label = $UI/SpeedLabel
@onready var status_label = $UI/StatusLabel
@onready var game_over_label = $UI/GameOverLabel
@onready var restart_label = $UI/RestartLabel
@onready var high_score_label = $UI/HighScoreLabel
@onready var race_label = $UI/RaceLabel
@onready var story_label = $UI/StoryLabel
@onready var control_help_label = $UI/ControlHelpLabel
@onready var instruction_label = $UI/InstructionLabel
@onready var calibration_label = $UI/CalibrationLabel
@onready var combo_label = $UI/ComboLabel
@onready var warning_overlay = $UI/WarningOverlay
@onready var pause_menu = $UI/PauseMenu
@onready var pause_label = $UI/PauseMenu/PauseLabel
var player_tag_label: Label3D

var spaceship: Node3D
var grid_floor: Node3D
var obstacles: Array = []
var obstacle_pool: Array = []
var support_items: Array = []
var support_item_pool: Array = []
var support_item_spawn_timer: float = 0.0
var support_item_interval: float = 4.8
const SUPPORT_ITEM_POOL_SIZE = 12
var runtime_profiler: Panel
var tracking_monitor_panel: Panel
var tracking_monitor_info_label: Label
var tracking_wheel_widget: Control
var game_state_stack
const OBSTACLE_POOL_SIZE = 30

var speed_boost_timer: float = 0.0
var shield_timer: float = 0.0
var rival_slow_timer: float = 0.0
var drift_active: bool = false
var drift_charge: float = 0.0
const DRIFT_CHARGE_MAX = 1.0
const DRIFT_CHARGE_GAIN_RATE = 0.42
const DRIFT_CHARGE_DECAY_RATE = 0.22
const DRIFT_SPEED_PENALTY = 0.92
var gesture_boost_cooldown: float = 0.0
var gesture_item_cooldown: float = 0.0
var last_ship_gesture: int = -1
var support_inventory: Array = []
const SUPPORT_INVENTORY_MAX = 3

# Preload scenes
var spaceship_scene = preload("res://scenes/spaceship.tscn")
var obstacle_scene = preload("res://scenes/obstacle.tscn")
var support_item_scene = preload("res://scenes/support_item.tscn")


func _ready():
	ensure_input_actions()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	if pause_menu:
		pause_menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	original_camera_pos = camera.position
	camera.fov = CAMERA_BASE_FOV
	# Fix camera near clip plane to prevent mesh clipping
	camera.near = 0.15

	start_hand_tracker()
	setup_udp()
	setup_game()
	setup_runtime_profiler()
	setup_tracking_monitor_ui()
	load_audio_settings()
	setup_audio()
	create_grid()
	create_background_stars()
	load_high_score()
	current_segment = pick_next_segment(TrackSegment.STRAIGHT)
	next_segment = pick_next_segment(current_segment)
	game_state_stack = YAFSM.StackPlayer.new()
	game_state_stack.name = "GameStateStack"
	add_child(game_state_stack)
	set_game_state("intro")
	if race_label:
		race_label.text = get_race_hud_text(0.0)


func ensure_input_actions():
	"""Đảm bảo luôn có bộ action cho keyboard/mouse control."""
	_ensure_key_action("move_left", [KEY_A, KEY_LEFT])
	_ensure_key_action("move_right", [KEY_D, KEY_RIGHT])
	_ensure_key_action("move_up", [KEY_W, KEY_UP])
	_ensure_key_action("move_down", [KEY_S, KEY_DOWN])
	_ensure_key_action("kb_boost", [KEY_SHIFT])
	_ensure_key_action("kb_brake", [KEY_CTRL])
	_ensure_key_action("toggle_control_mode", [KEY_TAB])
	_ensure_mouse_action("mouse_steer", MOUSE_BUTTON_LEFT)


func _ensure_key_action(action_name: String, keys: Array):
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	
	for key in keys:
		var exists = false
		for existing in InputMap.action_get_events(action_name):
			if existing is InputEventKey and existing.physical_keycode == int(key):
				exists = true
				break
		if exists:
			continue
		var event = InputEventKey.new()
		event.physical_keycode = int(key)
		event.keycode = int(key)
		InputMap.action_add_event(action_name, event)


func _ensure_mouse_action(action_name: String, mouse_button: int):
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	
	for existing in InputMap.action_get_events(action_name):
		if existing is InputEventMouseButton and existing.button_index == mouse_button:
			return
	
	var event = InputEventMouseButton.new()
	event.button_index = mouse_button
	InputMap.action_add_event(action_name, event)


func start_hand_tracker():
	"""Khởi động Python hand tracker (v2 - optimized) tự động."""
	tracker_pid = -1
	tracker_running = false
	print("Starting Hand Tracker v2 (CPU-optimized 60 FPS profile)...")
	
	# Use the main tracker with all optimizations
	var script_to_use = ProjectSettings.globalize_path("res://hand_tracker_server.py")
	
	if not FileAccess.file_exists("res://hand_tracker_server.py"):
		print("Error: hand_tracker_server.py not found!")
		return
	
	tracker_stop_flag_abs_path = ProjectSettings.globalize_path(TRACKER_STOP_FLAG_PATH)
	_remove_tracker_stop_flag_if_present()
	
	print("Using script: ", script_to_use)
	
	# Run Python script in background with CPU low-latency profile
	var args = [
		script_to_use,
		"--headless",
		"--fps", "60",
		"--target-fps", "60",
		"--scale", "0.6",
		"--model-complexity", "0",
		"--stop-file", tracker_stop_flag_abs_path
	]
	tracker_pid = OS.create_process("python", args)
	
	if tracker_pid > 0:
		tracker_running = true
		print("✓ Hand Tracker started with PID: ", tracker_pid)
	else:
		print("✗ Failed to start Hand Tracker")
		print("  Please run manually: python hand_tracker_server.py --headless --fps 60 --target-fps 60 --scale 0.6 --model-complexity 0")


func setup_udp():
	udp_server = PacketPeerUDP.new()
	var err = udp_server.bind(UDP_PORT)
	if err != OK:
		print("Failed to bind UDP port ", UDP_PORT)
	else:
		print("UDP Server listening on port ", UDP_PORT)


func setup_game():
	# Create spaceship
	spaceship = spaceship_scene.instantiate()
	add_child(spaceship)
	spaceship.position = Vector3.ZERO
	setup_player_marker()
	prewarm_obstacle_pool(OBSTACLE_POOL_SIZE)
	prewarm_support_item_pool(SUPPORT_ITEM_POOL_SIZE)
	apply_campaign_level(0, true)


func setup_player_marker():
	if not spaceship or not is_instance_valid(spaceship):
		return
	if player_tag_label and is_instance_valid(player_tag_label):
		player_tag_label.queue_free()
	player_tag_label = Label3D.new()
	player_tag_label.name = "PlayerMarker"
	player_tag_label.text = "PLAYER"
	player_tag_label.modulate = Color(0.92, 1.0, 1.0, 1.0)
	player_tag_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	player_tag_label.no_depth_test = true
	player_tag_label.pixel_size = 0.0042
	player_tag_label.position = Vector3(0.0, 1.4, 0.0)
	spaceship.add_child(player_tag_label)


func get_campaign_level_data(index: int = -1) -> Dictionary:
	var safe_index = current_campaign_level if index < 0 else index
	safe_index = clampi(safe_index, 0, CAMPAIGN_LEVELS.size() - 1)
	return CAMPAIGN_LEVELS[safe_index]


func get_total_racer_count() -> int:
	return max(1, rival_ships.size() + 1)


func get_player_rank() -> int:
	var rank = 1
	for rival_data in rival_ships:
		if float(rival_data.get("distance", 0.0)) > player_race_distance + RANK_DISTANCE_EPSILON:
			rank += 1
	return clampi(rank, 1, get_total_racer_count())


func get_stage_objective_text(target_distance_override: float = -1.0) -> String:
	var target_distance = race_target_distance if target_distance_override < 0.0 else target_distance_override
	return "Thắng: #1 khi chạm %.0fm | Thua: đối thủ chạm mốc trước." % target_distance


func get_race_hud_text(best_rival_distance: float) -> String:
	var progress = clamp(player_race_distance / max(race_target_distance, 1.0), 0.0, 1.0)
	var lead = player_race_distance - best_rival_distance
	var lead_text = "%.0fm" % [lead]
	if lead > 0.0:
		lead_text = "+" + lead_text
	var player_rank = get_player_rank()
	var total_racers = get_total_racer_count()
	var remaining = max(0.0, race_target_distance - player_race_distance)
	return "STAGE %d/%d | Hạng %d/%d | %.0f%% | Còn %.0fm | Lead %s\nMốc %.0fm | Thắng: #1 về đích trước đối thủ" % [
		current_campaign_level + 1,
		CAMPAIGN_LEVELS.size(),
		player_rank,
		total_racers,
		progress * 100.0,
		remaining,
		lead_text,
		race_target_distance
	]


func get_inventory_text() -> String:
	if support_inventory.is_empty():
		return "-"
	var text = ""
	for i in range(support_inventory.size()):
		if i > 0:
			text += ", "
		text += str(support_inventory[i])
	return text


func build_campaign_intro_lines() -> Array:
	var level_data = get_campaign_level_data()
	var lines: Array = []
	var stage_title = "STAGE %d/%d - %s" % [
		current_campaign_level + 1,
		CAMPAIGN_LEVELS.size(),
		str(level_data.get("title", "Campaign"))
	]
	
	if campaign_transition_pending:
		lines.append("Stage clear! Đang mở khóa " + stage_title)
	else:
		lines.append("Campaign briefing: " + stage_title)
	
	var story_lines = level_data.get("story", [])
	if story_lines is Array:
		for line in story_lines:
			lines.append(str(line))
	
	lines.append("Mục tiêu %dm | Đối thủ %d" % [int(race_target_distance), rival_ships.size()])
	lines.append(get_stage_objective_text())
	return lines


func clear_active_world_entities():
	for obs in obstacles.duplicate():
		release_obstacle(obs)
	obstacles.clear()
	
	for item in support_items.duplicate():
		release_support_item(item)
	support_items.clear()


func apply_campaign_level(level_index: int, reset_score: bool = false):
	current_campaign_level = clampi(level_index, 0, CAMPAIGN_LEVELS.size() - 1)
	if reset_score or current_campaign_level == 0:
		campaign_transition_pending = false
	
	var level_data = get_campaign_level_data()
	race_target_distance = float(level_data.get("goal_distance", 1500.0))
	segment_duration = float(level_data.get("segment_duration", 6.0))
	current_spawn_interval = float(level_data.get("spawn_interval", SPAWN_INTERVAL_BASE))
	support_item_interval = float(level_data.get("support_interval", 4.8))
	
	clear_active_world_entities()
	
	if reset_score:
		score = 0
	
	game_over = false
	paused = false
	get_tree().paused = false
	if pause_menu:
		pause_menu.visible = false
	
	spawn_timer = 0.0
	difficulty_timer = 0.0
	support_item_spawn_timer = 0.0
	shake_intensity = 0.0
	warning_intensity = 0.0
	collision_slowdown = 0.0
	combo_count = 0
	combo_timer = 0.0
	speed_boost_timer = 0.0
	shield_timer = 0.0
	rival_slow_timer = 0.0
	drift_active = false
	drift_charge = 0.0
	gesture_boost_cooldown = 0.0
	gesture_item_cooldown = 0.0
	last_ship_gesture = -1
	support_inventory.clear()
	rival_collision_cooldown = 0.0
	score_sound_cooldown = 0.0
	warning_sound_cooldown = 0.0
	
	current_segment = pick_next_segment(TrackSegment.STRAIGHT)
	next_segment = pick_next_segment(current_segment)
	segment_timer = 0.0
	track_rotation = 0.0
	target_track_rotation = 0.0
	track_offset = Vector3.ZERO
	target_track_offset = Vector3.ZERO
	track_wave_phase = 0.0
	track_wave_amount = 0.0
	track_curve_intensity = 0.0
	last_obstacle_spawn_pos = Vector3(999.0, 999.0, -999.0)
	
	if grid_floor:
		grid_floor.rotation_degrees.y = 0.0
		grid_floor.rotation_degrees.z = 0.0
		grid_floor.position.x = 0.0
		grid_floor.position.y = 0.0
	if camera:
		camera.rotation_degrees.z = 0.0
		camera.rotation_degrees.y = 0.0
		if original_camera_pos != Vector3.ZERO:
			camera.position = original_camera_pos
		camera.fov = CAMERA_BASE_FOV
	
	if spaceship:
		spaceship.reset()
		if spaceship.has_method("resume_particles"):
			spaceship.resume_particles()
	
	setup_rival_ships(level_data)
	
	race_intro_active = true
	race_intro_timer = 0.0
	race_started = false
	race_finished = false
	player_race_distance = 0.0
	campaign_completed = false
	stage_clear_waiting = false
	pending_next_level_index = -1
	_continue_was_pressed = false
	
	if game_over_label:
		game_over_label.text = ""
	if restart_label:
		restart_label.text = ""
	if score_label:
		score_label.visible = true
	if speed_label:
		speed_label.visible = true
	if status_label:
		status_label.visible = true
	if race_label:
		race_label.visible = true
	if high_score_label:
		high_score_label.visible = true
	if control_help_label:
		control_help_label.visible = true
	if story_label:
		story_label.visible = true
		story_label.text = ""
	if race_label:
		race_label.text = get_race_hud_text(0.0)
	if combo_label:
		combo_label.visible = false
	if warning_overlay:
		warning_overlay.modulate.a = 0.0
	
	set_game_state("intro")


func advance_campaign_level():
	var next_level = current_campaign_level + 1
	if next_level >= CAMPAIGN_LEVELS.size():
		handle_campaign_victory()
		return
	
	var stage_bonus = 180 + current_campaign_level * 70
	add_score(stage_bonus)
	stage_clear_waiting = true
	pending_next_level_index = next_level
	race_finished = true
	game_over = true
	campaign_completed = false
	set_game_state("game_over")
	game_over_label.text = "STAGE CLEAR!"
	restart_label.text = "ENTER - Continue | R - Retry Campaign | M - Main Menu"
	if story_label:
		var next_level_data = get_campaign_level_data(next_level)
		story_label.visible = true
		var next_goal = float(next_level_data.get("goal_distance", race_target_distance))
		story_label.text = "Bạn đã hoàn thành STAGE %d (+%d điểm).\nNhấn ENTER để tiếp tục tới STAGE %d - %s.\n%s" % [
			current_campaign_level + 1,
			stage_bonus,
			next_level + 1,
			str(next_level_data.get("title", "Campaign")),
			get_stage_objective_text(next_goal)
		]


func continue_to_next_stage():
	if not stage_clear_waiting:
		return
	if pending_next_level_index < 0:
		return
	stage_clear_waiting = false
	campaign_transition_pending = true
	apply_campaign_level(pending_next_level_index, false)


func handle_campaign_victory():
	race_finished = true
	game_over = true
	campaign_completed = true
	stage_clear_waiting = false
	pending_next_level_index = -1
	set_game_state("game_over")
	game_over_label.text = "CAMPAIGN COMPLETE"
	restart_label.text = "R - Replay Campaign | M - Main Menu"
	if story_label:
		var ending_text = ""
		for i in range(CAMPAIGN_ENDING_LINES.size()):
			if i > 0:
				ending_text += "\n"
			ending_text += str(CAMPAIGN_ENDING_LINES[i])
		story_label.visible = true
		story_label.text = ending_text


func handle_campaign_defeat(best_rival_distance: float):
	race_finished = true
	game_over = true
	campaign_completed = false
	stage_clear_waiting = false
	pending_next_level_index = -1
	set_game_state("game_over")
	game_over_label.text = "DEFEAT"
	restart_label.text = "R - Retry Campaign | M - Main Menu"
	if story_label:
		var deficit = max(0.0, best_rival_distance - player_race_distance)
		var player_rank = get_player_rank()
		story_label.visible = true
		story_label.text = "Bạn về hạng %d/%d, bị bỏ lại %.0fm ở STAGE %d.\n%s" % [
			player_rank,
			get_total_racer_count(),
			deficit,
			current_campaign_level + 1,
			get_stage_objective_text()
		]


func setup_runtime_profiler():
	"""Attach GDProfiler in debug builds for quick frame-time checks."""
	if not OS.is_debug_build():
		return
	
	var profiler_script := load("res://addons/gd_profiler/profiler/movable_profiler.gd")
	if profiler_script == null:
		return
	
	runtime_profiler = Panel.new()
	runtime_profiler.name = "RuntimeProfiler"
	runtime_profiler.set_script(profiler_script)
	runtime_profiler.size = Vector2(260, 50)
	runtime_profiler.position = Vector2(20, 140)
	runtime_profiler.set_anchors_preset(Control.PRESET_TOP_LEFT)
	
	if has_node("UI"):
		$UI.add_child(runtime_profiler)


func setup_tracking_monitor_ui():
	if not has_node("UI"):
		return
	
	tracking_monitor_panel = Panel.new()
	tracking_monitor_panel.name = "TrackingMonitorPanel"
	tracking_monitor_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tracking_monitor_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tracking_monitor_panel.offset_left = 20.0
	tracking_monitor_panel.offset_top = -262.0
	tracking_monitor_panel.offset_right = 360.0
	tracking_monitor_panel.offset_bottom = -20.0
	$UI.add_child(tracking_monitor_panel)
	
	var container = VBoxContainer.new()
	container.name = "Container"
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.anchor_right = 1.0
	container.anchor_bottom = 1.0
	container.offset_left = 10.0
	container.offset_top = 8.0
	container.offset_right = -10.0
	container.offset_bottom = -8.0
	tracking_monitor_panel.add_child(container)
	
	var title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "TRACKING MONITOR"
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color(0.78, 0.95, 1.0))
	container.add_child(title_label)
	
	tracking_wheel_widget = Control.new()
	tracking_wheel_widget.name = "WheelWidget"
	tracking_wheel_widget.custom_minimum_size = Vector2(0.0, 128.0)
	tracking_wheel_widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tracking_wheel_widget.size_flags_vertical = Control.SIZE_FILL
	tracking_wheel_widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tracking_wheel_widget.set_script(TRACKING_WHEEL_WIDGET_SCRIPT)
	container.add_child(tracking_wheel_widget)
	
	tracking_monitor_info_label = Label.new()
	tracking_monitor_info_label.name = "InfoLabel"
	tracking_monitor_info_label.text = "Status: waiting tracker..."
	tracking_monitor_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tracking_monitor_info_label.add_theme_font_size_override("font_size", 12)
	tracking_monitor_info_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.62))
	tracking_monitor_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(tracking_monitor_info_label)


func get_tracking_status_label(tracker_connected: bool, tracker_found: bool) -> String:
	if tracker_connected and tracker_found:
		return "LOCKED"
	if tracker_connected:
		return "SEARCHING"
	if tracker_running:
		return "CONNECTING"
	return "OFFLINE"


func get_gesture_name(gesture: int) -> String:
	match gesture:
		HandControlMapper.GestureType.NONE:
			return "Gesture: NONE"
		HandControlMapper.GestureType.MOVE:
			return "Gesture: MOVE"
		HandControlMapper.GestureType.TILT:
			return "Gesture: TILT"
		HandControlMapper.GestureType.BOOST:
			return "Gesture: BOOST"
		HandControlMapper.GestureType.BRAKE:
			return "Gesture: BRAKE"
		HandControlMapper.GestureType.HANDS_UP:
			return "Gesture: HANDS UP"
		HandControlMapper.GestureType.HANDS_DOWN:
			return "Gesture: HANDS DOWN"
		HandControlMapper.GestureType.HANDS_LEFT:
			return "Gesture: HANDS LEFT"
		HandControlMapper.GestureType.HANDS_RIGHT:
			return "Gesture: HANDS RIGHT"
		HandControlMapper.GestureType.DRIFT:
			return "Gesture: DRIFT"
		HandControlMapper.GestureType.ITEM_USE:
			return "Gesture: ITEM USE"
		HandControlMapper.GestureType.ITEM_NEXT:
			return "Gesture: ITEM NEXT"
	return "Gesture: -"


func update_tracking_monitor():
	if not is_instance_valid(tracking_monitor_info_label):
		return
	
	var tracker_connected = is_tracker_connected()
	var tracker_found = bool(hand_data.get("found", false))
	var hands = int(hand_data.get("hands", 0))
	var angle_deg = rad_to_deg(float(hand_data.get("angle", 0.0)))
	var depth = float(hand_data.get("distance", 0.5))
	var mid_x = float(hand_data.get("mid_x", 0.5))
	var mid_y = float(hand_data.get("mid_y", 0.5))
	
	if is_instance_valid(tracking_wheel_widget) and tracking_wheel_widget.has_method("set_tracking_state"):
		tracking_wheel_widget.call("set_tracking_state", hand_data, tracker_connected)
	
	var control_snapshot: Dictionary = {}
	if spaceship and spaceship.has_method("get_tracking_control_snapshot"):
		control_snapshot = spaceship.get_tracking_control_snapshot()
	
	var steering = float(control_snapshot.get("steering", 0.0))
	var throttle = float(control_snapshot.get("throttle", 0.0))
	var brake = float(control_snapshot.get("brake", 0.0))
	var gesture = int(control_snapshot.get("gesture", HandControlMapper.GestureType.NONE))
	var status_line = get_tracking_status_label(tracker_connected, tracker_found)
	
	tracking_monitor_info_label.text = "Status: %s | Hands: %d | Mode: %s\nAngle: %+0.1f° | Depth: %.2f | mid:(%.2f, %.2f)\nSteer: %+0.2f | Thr: %.2f | Brk: %.2f | %s" % [
		status_line,
		hands,
		get_control_mode_name(),
		angle_deg,
		depth,
		mid_x,
		mid_y,
		steering,
		throttle,
		brake,
		get_gesture_name(gesture),
	]
	
	var info_color = Color(1.0, 0.55, 0.55)
	if tracker_connected and tracker_found:
		info_color = Color(0.82, 1.0, 0.88)
	elif tracker_connected:
		info_color = Color(1.0, 0.92, 0.6)
	tracking_monitor_info_label.add_theme_color_override("font_color", info_color)


func set_game_state(state_name: String):
	"""Track high-level flow using YAFSM StackPlayer."""
	if game_state_stack == null:
		return
	if game_state_stack.current == state_name:
		return
	if game_state_stack.current != null:
		game_state_stack.pop()
	game_state_stack.push(state_name)


func prewarm_obstacle_pool(count: int):
	"""Pre-instantiate obstacles to avoid runtime hitch when spawning."""
	for _i in range(count):
		var obs = obstacle_scene.instantiate()
		add_child(obs)
		if obs.has_method("deactivate_for_pool"):
			obs.deactivate_for_pool()
		else:
			obs.visible = false
			obs.position = Vector3(0, -1000, 0)
		obstacle_pool.append(obs)


func acquire_obstacle() -> Node3D:
	if obstacle_pool.is_empty():
		var obs = obstacle_scene.instantiate()
		add_child(obs)
		return obs
	return obstacle_pool.pop_back()


func release_obstacle(obs: Node3D):
	if not is_instance_valid(obs):
		return
	
	obstacles.erase(obs)
	if obs.has_method("deactivate_for_pool"):
		obs.deactivate_for_pool()
	else:
		obs.visible = false
		obs.position = Vector3(0, -1000, 0)
	
	obstacle_pool.append(obs)


func prewarm_support_item_pool(count: int):
	for _i in range(count):
		var item = support_item_scene.instantiate()
		add_child(item)
		if item.has_method("deactivate_for_pool"):
			item.deactivate_for_pool()
		else:
			item.visible = false
			item.position = Vector3(0, -1000, 0)
		support_item_pool.append(item)


func acquire_support_item() -> Node3D:
	if support_item_pool.is_empty():
		var item = support_item_scene.instantiate()
		add_child(item)
		return item
	return support_item_pool.pop_back()


func release_support_item(item: Node3D):
	if not is_instance_valid(item):
		return
	
	support_items.erase(item)
	if item.has_method("deactivate_for_pool"):
		item.deactivate_for_pool()
	else:
		item.visible = false
		item.position = Vector3(0, -1000, 0)
	support_item_pool.append(item)


func setup_rival_ships(level_data: Dictionary = {}):
	for existing_data in rival_ships:
		var existing_node = existing_data.get("node")
		if is_instance_valid(existing_node):
			existing_node.queue_free()
	rival_ships.clear()
	
	var rival_count = int(level_data.get("rival_count", 3))
	var speed_min = float(level_data.get("rival_speed_min", 18.0))
	var speed_max = float(level_data.get("rival_speed_max", 23.0))
	var personalities = ["balanced", "aggressive", "defender", "trickster", "sprinter"]
	var lanes: Array = LANE_POSITIONS.duplicate()
	lanes.shuffle()
	
	for i in range(rival_count):
		var rival = spaceship_scene.instantiate()
		rival.set("preview_mode", true)
		add_child(rival)
		if rival.has_method("set_preview_mode"):
			rival.set_preview_mode(true)
		
		# Đa dạng hóa hình dáng/màu rival mà không ghi đè config của người chơi.
		if rival.has_method("apply_all_ship_part_variants"):
			rival.set("body_variant_index", i % 3)
			rival.set("wing_variant_index", (i + 1) % 3)
			rival.set("tail_variant_index", (i + 2) % 3)
			rival.set("engine_variant_index", (i + 1) % 3)
			rival.apply_all_ship_part_variants()
		if rival.has_method("apply_ship_colors"):
			rival.set("body_color_index", (i + 1) % 7)
			rival.set("wing_color_index", (i + 2) % 7)
			rival.set("tail_color_index", (i + 3) % 7)
			rival.set("engine_color_index", (i + 4) % 7)
			rival.apply_ship_colors()
		
		var lane = float(lanes[i % lanes.size()])
		rival.position = Vector3(lane, 0.0, -8.0)
		rival.scale = Vector3.ONE * 0.88
		
		var personality = personalities[i % personalities.size()]
		var aggression = randf_range(0.45, 0.82)
		match personality:
			"aggressive":
				aggression = randf_range(0.78, 1.0)
			"defender":
				aggression = randf_range(0.55, 0.76)
			"trickster":
				aggression = randf_range(0.62, 0.9)
			"sprinter":
				aggression = randf_range(0.68, 0.92)
		
		rival_ships.append({
			"node": rival,
			"distance": 0.0,
			"base_speed": randf_range(speed_min, speed_max),
			"current_speed": 0.0,
			"lane": lane,
			"target_lane": lane,
			"phase": randf_range(0.0, TAU),
			"phase_speed": randf_range(1.2, 2.0),
			"decision_timer": randf_range(0.3, 1.1),
			"boost_timer": randf_range(0.0, 0.6),
			"brake_timer": 0.0,
			"personality": personality,
			"aggression": aggression,
			"lane_change_speed": randf_range(2.6, 4.8),
			"consistency": randf_range(0.45, 0.92),
			"collision_cooldown": 0.0
		})


func get_obstacle_lane_penalty(lane_x: float) -> float:
	var penalty = 0.0
	for obs in obstacles:
		if not is_instance_valid(obs):
			continue
		if obs.position.z < -55.0 or obs.position.z > -2.0:
			continue
		var lateral = abs(obs.position.x - lane_x)
		if lateral < 1.2:
			penalty += 2.4
		elif lateral < 2.2:
			penalty += 0.9
	return penalty


func get_lane_crowding_penalty(lane_x: float, exclude_node) -> float:
	var crowding = 0.0
	for rival_data in rival_ships:
		var other_node = rival_data.get("node")
		if not is_instance_valid(other_node):
			continue
		if other_node == exclude_node:
			continue
		var x_gap = abs(other_node.position.x - lane_x)
		crowding += max(0.0, 1.4 - x_gap) * 0.8
	return crowding


func choose_rival_target_lane(rival_data: Dictionary, player_lane: float) -> float:
	var best_lane = float(rival_data.get("lane", 0.0))
	var best_score = -INF
	var personality = str(rival_data.get("personality", "balanced"))
	var aggression = float(rival_data.get("aggression", 0.6))
	var rival_distance = float(rival_data.get("distance", 0.0))
	var gap_to_player = player_race_distance - rival_distance
	var phase = float(rival_data.get("phase", 0.0))
	var rival_node = rival_data.get("node")
	
	for lane in LANE_POSITIONS:
		var lane_x = float(lane)
		var lane_gap = abs(lane_x - player_lane)
		var lane_score = randf_range(-0.35, 0.35)
		
		if gap_to_player > 20.0:
			lane_score += 2.4 - lane_gap * 0.55
		elif gap_to_player < -16.0:
			lane_score += 1.1 + lane_gap * 0.14
		else:
			lane_score += 1.4 - lane_gap * 0.28
		
		match personality:
			"aggressive":
				lane_score += (2.2 - lane_gap * 0.6) * aggression
			"defender":
				if gap_to_player < 0.0:
					lane_score += 1.6 - lane_gap * 0.5
				else:
					lane_score += 0.5 - abs(lane_x) * 0.08
			"trickster":
				lane_score += sin(phase * 2.1 + lane_x) * 0.9
			"sprinter":
				lane_score += 1.2 - abs(lane_x) * 0.16
			_:
				lane_score += 0.6 - abs(lane_x) * 0.08
		
		lane_score -= get_obstacle_lane_penalty(lane_x) * (1.0 + aggression * 0.6)
		lane_score -= get_lane_crowding_penalty(lane_x, rival_node)
		
		if lane_score > best_score:
			best_score = lane_score
			best_lane = lane_x
	
	return best_lane


func create_grid():
	# Segmented technical-grid track để tạo cảm giác đường cong thật hơn.
	grid_floor = Node3D.new()
	grid_floor.name = "GridFloor"
	add_child(grid_floor)
	
	var road_width = 18.0
	var grid_width = 16.4
	var segment_len = 8.0
	var segment_start = -128
	var segment_end = 24
	
	var road_material = StandardMaterial3D.new()
	road_material.albedo_color = Color(0.03, 0.04, 0.08)
	road_material.roughness = 0.78
	road_material.metallic = 0.22
	
	var data_lane_material = StandardMaterial3D.new()
	data_lane_material.albedo_color = Color(0.02, 0.12, 0.2, 0.55)
	data_lane_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	data_lane_material.emission_enabled = true
	data_lane_material.emission = Color(0.0, 0.55, 0.95)
	data_lane_material.emission_energy_multiplier = 0.35
	data_lane_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	var line_material = StandardMaterial3D.new()
	line_material.albedo_color = Color(0.1, 0.75, 1.0)
	line_material.emission_enabled = true
	line_material.emission = Color(0.1, 0.75, 1.0)
	line_material.emission_energy_multiplier = 1.45
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	var lane_material = StandardMaterial3D.new()
	lane_material.albedo_color = Color(0.95, 0.98, 1.0)
	lane_material.emission_enabled = true
	lane_material.emission = Color(0.8, 0.95, 1.0)
	lane_material.emission_energy_multiplier = 0.9
	
	var rail_material = StandardMaterial3D.new()
	rail_material.albedo_color = Color(0.1, 0.5, 0.95)
	rail_material.emission_enabled = true
	rail_material.emission = Color(0.1, 0.65, 1.0)
	rail_material.emission_energy_multiplier = 1.25
	
	# Road + inner lane + rails dưới dạng segment cuộn để dễ "uốn" theo curve theo chiều sâu.
	for z in range(segment_start, segment_end + 1, int(segment_len)):
		var road_mesh = BoxMesh.new()
		road_mesh.size = Vector3(road_width, 0.12, segment_len + 0.12)
		var road_seg = MeshInstance3D.new()
		road_seg.mesh = road_mesh
		road_seg.material_override = road_material
		road_seg.position = Vector3(0, -6.2, z)
		road_seg.set_meta("scrolling", true)
		road_seg.set_meta("scroll_reset_z", float(segment_start))
		road_seg.set_meta("base_x", 0.0)
		road_seg.set_meta("curve_factor", 1.15)
		grid_floor.add_child(road_seg)
		
		var data_mesh = BoxMesh.new()
		data_mesh.size = Vector3(grid_width, 0.025, segment_len + 0.08)
		var data_seg = MeshInstance3D.new()
		data_seg.mesh = data_mesh
		data_seg.material_override = data_lane_material
		data_seg.position = Vector3(0, -6.06, z)
		data_seg.set_meta("scrolling", true)
		data_seg.set_meta("scroll_reset_z", float(segment_start))
		data_seg.set_meta("base_x", 0.0)
		data_seg.set_meta("curve_factor", 1.25)
		grid_floor.add_child(data_seg)
		
		for rail_x in [-9.1, 9.1]:
			var rail_mesh = BoxMesh.new()
			rail_mesh.size = Vector3(0.15, 0.42, segment_len + 0.1)
			var rail_seg = MeshInstance3D.new()
			rail_seg.mesh = rail_mesh
			rail_seg.material_override = rail_material
			rail_seg.position = Vector3(rail_x, -5.86, z)
			rail_seg.set_meta("scrolling", true)
			rail_seg.set_meta("scroll_reset_z", float(segment_start))
			rail_seg.set_meta("base_x", rail_x)
			rail_seg.set_meta("curve_factor", 1.55)
			grid_floor.add_child(rail_seg)
	
	# Longitudinal grid lines theo segment (để curvature nhìn rõ hơn thay vì line thẳng kéo dài).
	for x in range(-8, 9):
		var base_x = float(x) * 0.95
		for z in range(segment_start, segment_end + 1, int(segment_len)):
			var mesh = BoxMesh.new()
			mesh.size = Vector3(0.04, 0.02, segment_len - 0.3)
			var line = MeshInstance3D.new()
			line.mesh = mesh
			line.material_override = line_material
			line.position = Vector3(base_x, -6.01, z)
			line.set_meta("scrolling", true)
			line.set_meta("scroll_reset_z", float(segment_start))
			line.set_meta("base_x", base_x)
			line.set_meta("curve_factor", 1.35)
			grid_floor.add_child(line)
	
	# Horizontal scan lines
	for z in range(segment_start, segment_end + 1, 4):
		var mesh = BoxMesh.new()
		mesh.size = Vector3(grid_width, 0.02, 0.05)
		var line = MeshInstance3D.new()
		line.mesh = mesh
		line.material_override = line_material
		line.position = Vector3(0, -6.0, z)
		line.set_meta("scrolling", true)
		line.set_meta("scroll_reset_z", float(segment_start))
		line.set_meta("base_x", 0.0)
		line.set_meta("curve_factor", 1.5)
		grid_floor.add_child(line)
	
	# Diagonal links for technical network feel
	for z in range(segment_start, segment_end + 1, 12):
		for side in [-1, 1]:
			var link_mesh = BoxMesh.new()
			link_mesh.size = Vector3(2.8, 0.02, 0.04)
			var link = MeshInstance3D.new()
			link.mesh = link_mesh
			link.material_override = line_material
			link.position = Vector3(4.2 * side, -5.99, z + 0.8 * side)
			link.rotation_degrees = Vector3(0, 28.0 * side, 0)
			link.set_meta("scrolling", true)
			link.set_meta("scroll_reset_z", float(segment_start))
			link.set_meta("base_x", 4.2 * side)
			link.set_meta("curve_factor", 1.45)
			grid_floor.add_child(link)
	
	# Junction nodes
	for z in range(segment_start, segment_end + 1, 12):
		for lane_x in [-6.4, -3.2, 0.0, 3.2, 6.4]:
			var node_mesh = SphereMesh.new()
			node_mesh.radius = 0.06
			node_mesh.height = 0.12
			var junction = MeshInstance3D.new()
			junction.mesh = node_mesh
			junction.material_override = line_material
			junction.position = Vector3(lane_x, -5.98, z)
			junction.set_meta("scrolling", true)
			junction.set_meta("scroll_reset_z", float(segment_start))
			junction.set_meta("base_x", lane_x)
			junction.set_meta("curve_factor", 1.45)
			grid_floor.add_child(junction)
	
	# Lane markers
	for z in range(segment_start, segment_end + 1, 10):
		for lane_x in [-3.2, 0.0, 3.2]:
			var marker_mesh = BoxMesh.new()
			marker_mesh.size = Vector3(0.2, 0.03, 2.6)
			var marker = MeshInstance3D.new()
			marker.mesh = marker_mesh
			marker.material_override = lane_material
			marker.position = Vector3(lane_x, -5.97, z)
			marker.set_meta("scrolling", true)
			marker.set_meta("scroll_reset_z", float(segment_start))
			marker.set_meta("base_x", lane_x)
			marker.set_meta("curve_factor", 1.32)
			grid_floor.add_child(marker)


func volume_percent_to_db(percent: float) -> float:
	var normalized = clamp(percent, AUDIO_PERCENT_MIN, AUDIO_PERCENT_MAX) / 100.0
	return linear_to_db(normalized)


func legacy_db_to_percent(db_value: float) -> float:
	var normalized_linear = db_to_linear(clamp(db_value, -40.0, 6.0))
	return clamp(round(normalized_linear * 100.0), AUDIO_PERCENT_MIN, AUDIO_PERCENT_MAX)


func load_audio_settings():
	var config = ConfigFile.new()
	if config.load("user://menu_settings.cfg") == OK:
		if config.has_section_key("audio", "master_percent"):
			master_volume_percent = float(config.get_value("audio", "master_percent", 100.0))
		else:
			master_volume_percent = legacy_db_to_percent(float(config.get_value("audio", "master_db", 0.0)))
		if config.has_section_key("audio", "music_percent"):
			music_volume_percent = float(config.get_value("audio", "music_percent", 70.0))
		else:
			music_volume_percent = legacy_db_to_percent(float(config.get_value("audio", "music_db", -8.0)))
		if config.has_section_key("audio", "sfx_percent"):
			sfx_volume_percent = float(config.get_value("audio", "sfx_percent", 85.0))
		else:
			sfx_volume_percent = legacy_db_to_percent(float(config.get_value("audio", "sfx_db", -4.0)))
	
	master_volume_percent = clamp(master_volume_percent, AUDIO_PERCENT_MIN, AUDIO_PERCENT_MAX)
	music_volume_percent = clamp(music_volume_percent, AUDIO_PERCENT_MIN, AUDIO_PERCENT_MAX)
	sfx_volume_percent = clamp(sfx_volume_percent, AUDIO_PERCENT_MIN, AUDIO_PERCENT_MAX)
	
	var master_idx = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, volume_percent_to_db(master_volume_percent))


func setup_audio():
	"""Thiết lập các audio players"""
	# Engine sound (looping)
	audio_engine = AudioStreamPlayer.new()
	audio_engine.name = "AudioEngine"
	audio_engine.bus = "Master"
	add_child(audio_engine)
	
	# Boost sound
	audio_boost = AudioStreamPlayer.new()
	audio_boost.name = "AudioBoost"
	audio_boost.bus = "Master"
	add_child(audio_boost)
	
	# Warning beep
	audio_warning = AudioStreamPlayer.new()
	audio_warning.name = "AudioWarning"
	audio_warning.bus = "Master"
	add_child(audio_warning)
	
	# Score sound
	audio_score = AudioStreamPlayer.new()
	audio_score.name = "AudioScore"
	audio_score.bus = "Master"
	add_child(audio_score)
	
	# Explosion sound
	audio_explosion = AudioStreamPlayer.new()
	audio_explosion.name = "AudioExplosion"
	audio_explosion.bus = "Master"
	add_child(audio_explosion)

	# Soundtrack (procedural)
	audio_music = AudioStreamPlayer.new()
	audio_music.name = "AudioMusic"
	audio_music.bus = "Master"
	add_child(audio_music)
	setup_soundtrack()
	apply_audio_volume_levels()
	
	# Generate simple audio streams
	generate_audio_streams()


func apply_audio_volume_levels():
	var sfx_db = volume_percent_to_db(sfx_volume_percent)
	var music_db = volume_percent_to_db(music_volume_percent)
	if audio_engine:
		audio_engine.volume_db = sfx_db + 1.0
	if audio_boost:
		audio_boost.volume_db = sfx_db + 3.0
	if audio_warning:
		audio_warning.volume_db = sfx_db + 1.0
	if audio_score:
		audio_score.volume_db = sfx_db + 2.0
	if audio_explosion:
		audio_explosion.volume_db = sfx_db + 4.0
	if audio_music:
		audio_music.volume_db = music_db


func load_custom_soundtrack_stream() -> AudioStream:
	if not FileAccess.file_exists(CUSTOM_SOUNDTRACK_PATH):
		return null
	var music_data = FileAccess.get_file_as_bytes(CUSTOM_SOUNDTRACK_PATH)
	if music_data.is_empty():
		return null
	var stream = AudioStreamMP3.new()
	stream.data = music_data
	stream.loop = true
	return stream


func setup_soundtrack():
	if not audio_music or not audio_music.is_inside_tree():
		using_custom_soundtrack = false
		music_playback = null
		return
	var custom_stream = load_custom_soundtrack_stream()
	if custom_stream:
		using_custom_soundtrack = true
		audio_music.stream = custom_stream
		if not audio_music.playing:
			audio_music.play()
		audio_music.stream_paused = false
		music_playback = null
		return
	
	using_custom_soundtrack = false
	var stream = AudioStreamGenerator.new()
	stream.mix_rate = MUSIC_SAMPLE_RATE
	stream.buffer_length = 0.6
	audio_music.stream = stream
	if not audio_music.playing:
		audio_music.play()
	audio_music.stream_paused = false
	music_playback = audio_music.get_stream_playback() as AudioStreamGeneratorPlayback
	music_progress = 0.0
	music_chord_index = 0


func update_soundtrack(delta: float):
	if paused:
		return
	if not audio_music:
		music_playback = null
		return
	if not audio_music.is_inside_tree():
		music_playback = null
		return
	if not audio_music.playing:
		audio_music.play()
	if using_custom_soundtrack:
		return
	if music_playback == null:
		music_playback = audio_music.get_stream_playback() as AudioStreamGeneratorPlayback
	if music_playback == null:
		return
	
	music_progress += delta
	if music_progress >= MUSIC_CHORD_DURATION:
		music_progress -= MUSIC_CHORD_DURATION
		music_chord_index = (music_chord_index + 1) % MUSIC_CHORDS.size()
	
	var chord = MUSIC_CHORDS[music_chord_index]
	var frames = music_playback.get_frames_available()
	for _i in range(frames):
		music_phase_a = wrapf(music_phase_a + TAU * chord[0] / MUSIC_SAMPLE_RATE, 0.0, TAU)
		music_phase_b = wrapf(music_phase_b + TAU * chord[1] / MUSIC_SAMPLE_RATE, 0.0, TAU)
		music_phase_c = wrapf(music_phase_c + TAU * chord[2] / MUSIC_SAMPLE_RATE, 0.0, TAU)
		
		var ambient = sin(music_phase_a * 0.5) * 0.08
		var mix_signal = sin(music_phase_a) * 0.18 + sin(music_phase_b) * 0.14 + sin(music_phase_c) * 0.1 + ambient
		var sample = clamp(mix_signal, -0.68, 0.68)
		music_playback.push_frame(Vector2(sample, sample))


func create_tone_wav(freq: float, duration: float, amplitude: float = 0.45, use_decay: bool = true) -> AudioStreamWAV:
	var sample_rate = 22050
	var sample_count = int(max(1.0, duration * sample_rate))
	var data = PackedByteArray()
	data.resize(sample_count * 2)  # 16-bit mono
	
	for i in range(sample_count):
		var t = float(i) / float(sample_rate)
		var sample = sin(TAU * freq * t)
		var envelope = 1.0
		if use_decay:
			var fade_in = min(1.0, float(i) / 220.0)
			var fade_out = min(1.0, float(sample_count - i - 1) / 220.0)
			envelope = min(fade_in, fade_out)
		var pcm = int(clamp(sample * amplitude * envelope, -1.0, 1.0) * 32767.0)
		data[i * 2] = pcm & 0xFF
		data[i * 2 + 1] = (pcm >> 8) & 0xFF
	
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = data
	return wav


func generate_audio_streams():
	"""Tạo các SFX procedural để đảm bảo game luôn có âm thanh cơ bản."""
	if audio_engine:
		var engine_wav = create_tone_wav(92.0, 0.8, 0.42, false)
		engine_wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		engine_wav.loop_begin = 0
		engine_wav.loop_end = int(engine_wav.data.size() / 2)
		audio_engine.stream = engine_wav
		audio_engine.play()
	
	if audio_boost:
		audio_boost.stream = create_tone_wav(430.0, 0.18, 0.8, true)
	if audio_warning:
		audio_warning.stream = create_tone_wav(250.0, 0.14, 0.66, true)
	if audio_score:
		audio_score.stream = create_tone_wav(760.0, 0.11, 0.7, true)
	if audio_explosion:
		audio_explosion.stream = create_tone_wav(120.0, 0.26, 1.0, true)


func create_background_stars():
	"""Tạo background hoàn thiện hơn: stars + nebula + planets."""
	var stars_container = Node3D.new()
	stars_container.name = "BackgroundStars"
	add_child(stars_container)
	
	var star_material = StandardMaterial3D.new()
	star_material.albedo_color = Color(1, 1, 1)
	star_material.emission_enabled = true
	star_material.emission = Color(1, 1, 1)
	star_material.emission_energy_multiplier = 2.0
	star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	# Tạo nhiều ngôi sao ở xa
	for i in range(200):
		var star = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = randf_range(0.05, 0.2)
		sphere.height = sphere.radius * 2
		star.mesh = sphere
		
		# Random color cho stars
		var star_mat = star_material.duplicate()
		var colors = [
			Color(1, 1, 1),     # White
			Color(0.8, 0.9, 1), # Blue-white
			Color(1, 0.9, 0.8), # Yellow-white
			Color(0, 1, 1),     # Cyan
			Color(1, 0, 1),     # Magenta
		]
		star_mat.emission = colors[randi() % colors.size()]
		star_mat.emission_energy_multiplier = randf_range(1.0, 3.0)
		star.material_override = star_mat
		
		# Vị trí xa camera
		star.position = Vector3(
			randf_range(-50, 50),
			randf_range(-30, 30),
			randf_range(-150, -50)
		)
		star.set_meta("twinkle_phase", randf_range(0, TAU))
		star.set_meta("twinkle_speed", randf_range(1.0, 4.0))
		
		stars_container.add_child(star)
	
	# Nebula clouds
	for _i in range(6):
		var cloud = MeshInstance3D.new()
		var cloud_mesh = SphereMesh.new()
		cloud_mesh.radius = randf_range(8.0, 18.0)
		cloud_mesh.height = cloud_mesh.radius * 2.0
		cloud.mesh = cloud_mesh
		
		var cloud_mat = StandardMaterial3D.new()
		cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cloud_mat.albedo_color = Color(randf_range(0.1, 0.4), randf_range(0.2, 0.5), randf_range(0.5, 0.9), 0.14)
		cloud_mat.emission_enabled = true
		cloud_mat.emission = cloud_mat.albedo_color
		cloud_mat.emission_energy_multiplier = 0.65
		cloud.material_override = cloud_mat
		
		cloud.position = Vector3(
			randf_range(-80, 80),
			randf_range(-35, 35),
			randf_range(-260, -140)
		)
		cloud.scale = Vector3(1.6, 0.7, 1.2)
		cloud.set_meta("drift_speed", randf_range(0.25, 0.6))
		stars_container.add_child(cloud)
	
	# Large far planets
	for _i in range(3):
		var planet = MeshInstance3D.new()
		var planet_mesh = SphereMesh.new()
		planet_mesh.radius = randf_range(2.2, 4.8)
		planet_mesh.height = planet_mesh.radius * 2.0
		planet.mesh = planet_mesh
		
		var planet_mat = StandardMaterial3D.new()
		planet_mat.albedo_color = Color(randf_range(0.2, 0.8), randf_range(0.2, 0.8), randf_range(0.3, 0.9))
		planet_mat.emission_enabled = true
		planet_mat.emission = planet_mat.albedo_color * 0.35
		planet_mat.emission_energy_multiplier = 0.8
		planet.material_override = planet_mat
		
		planet.position = Vector3(
			randf_range(-70, 70),
			randf_range(-20, 25),
			randf_range(-230, -120)
		)
		planet.set_meta("drift_speed", randf_range(0.08, 0.2))
		stars_container.add_child(planet)


func _process(delta):
	process_global_shortcuts()
	update_soundtrack(delta)
	receive_hand_data()
	update_ui()
	update_warning_effect(delta)
	update_combo(delta)
	update_stars(delta)
	collision_slowdown = max(0.0, collision_slowdown - COLLISION_RECOVERY_RATE * delta)
	score_sound_cooldown = max(0.0, score_sound_cooldown - delta)
	warning_sound_cooldown = max(0.0, warning_sound_cooldown - delta)
	
	# Pause check
	if paused:
		return
	
	# Calibration mode
	if calibration_mode:
		process_calibration()
		return
	
	if race_intro_active:
		process_race_intro(delta)
		return
	
	if not game_over:
		update_status_effects(delta)
		update_track_segment(delta)
		update_spaceship(delta)
		update_grid(delta)
		spawn_obstacles(delta)
		spawn_support_items(delta)
		update_obstacles(delta)
		update_support_items(delta)
		check_collisions()
		check_support_item_pickups()
		update_rivals(delta)
		resolve_rival_collisions(delta)
		update_race_progress(delta)
		update_camera(delta)
		update_camera_shake(delta)
		update_difficulty(delta)
	
	# Debug visualization
	if debug_mode:
		draw_debug()


func process_global_shortcuts():
	"""Polling global để ESC/R/M luôn hoạt động kể cả khi paused."""
	var esc_pressed = Input.is_physical_key_pressed(KEY_ESCAPE)
	if esc_pressed and not _esc_was_pressed:
		if game_over:
			return_to_menu()
		else:
			toggle_pause()
	_esc_was_pressed = esc_pressed
	
	var restart_pressed = Input.is_action_pressed("restart")
	if restart_pressed and not _restart_was_pressed and (game_over or paused):
		restart_game()
	_restart_was_pressed = restart_pressed
	
	var continue_pressed = Input.is_action_pressed("ui_accept") or Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER)
	if continue_pressed and not _continue_was_pressed and game_over and stage_clear_waiting:
		continue_to_next_stage()
	_continue_was_pressed = continue_pressed
	
	var menu_pressed = Input.is_physical_key_pressed(KEY_M)
	if menu_pressed and not _menu_was_pressed and (paused or game_over):
		return_to_menu()
	_menu_was_pressed = menu_pressed
	
	var mode_toggle_pressed = Input.is_action_pressed("toggle_control_mode")
	if mode_toggle_pressed and not _toggle_control_was_pressed:
		cycle_control_mode()
	_toggle_control_was_pressed = mode_toggle_pressed


func cycle_control_mode():
	control_mode = (control_mode + 1) % 3
	match control_mode:
		ControlMode.HAND_TRACKING:
			print("Control mode: HAND TRACKING")
		ControlMode.KEYBOARD_MOUSE:
			print("Control mode: KEYBOARD + MOUSE")
		ControlMode.HYBRID:
			print("Control mode: HYBRID")


func get_control_mode_name() -> String:
	match control_mode:
		ControlMode.HAND_TRACKING:
			return "HAND"
		ControlMode.KEYBOARD_MOUSE:
			return "KB/MOUSE"
		ControlMode.HYBRID:
			return "HYBRID"
	return "UNKNOWN"


func build_keyboard_mouse_control_data() -> Dictionary:
	var input_x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var input_y = Input.get_action_strength("move_up") - Input.get_action_strength("move_down")
	
	var viewport_size = get_viewport().get_visible_rect().size
	if viewport_size.x > 0.0 and viewport_size.y > 0.0:
		var mouse_pos = get_viewport().get_mouse_position()
		var mouse_x = clamp((mouse_pos.x / viewport_size.x) * 2.0 - 1.0, -1.0, 1.0)
		var mouse_y = clamp((mouse_pos.y / viewport_size.y) * 2.0 - 1.0, -1.0, 1.0)
		var mouse_weight = 1.0 if Input.is_action_pressed("mouse_steer") else 0.45
		input_x = lerp(input_x, mouse_x, mouse_weight)
		input_y = lerp(input_y, -mouse_y, mouse_weight)
	
	input_x = clamp(input_x, -1.0, 1.0)
	input_y = clamp(input_y, -1.0, 1.0)
	
	var boosting = Input.is_action_pressed("kb_boost")
	var braking = Input.is_action_pressed("kb_brake")
	var distance = 0.5
	if boosting and not braking:
		distance = 0.7
	elif braking and not boosting:
		distance = 0.3
	
	return {
		"found": true,
		"mid_x": clamp(0.5 + input_x * 0.35, 0.0, 1.0),
		"mid_y": clamp(0.5 - input_y * 0.35, 0.0, 1.0),
		"angle": input_x * deg_to_rad(24.0),
		"distance": distance,
		"hands": 2
	}


func get_active_control_data() -> Dictionary:
	var manual_data = build_keyboard_mouse_control_data()
	var tracker_ok = is_tracker_connected()
	var tracker_data = hand_data.duplicate()
	
	if not tracker_ok:
		tracker_data["found"] = false
	
	match control_mode:
		ControlMode.HAND_TRACKING:
			return tracker_data
		ControlMode.KEYBOARD_MOUSE:
			return manual_data
		ControlMode.HYBRID:
			if tracker_data.get("found", false):
				return tracker_data
			return manual_data
	
	return manual_data


func _warn_tracker_packet_issue(message: String):
	var now_ms = Time.get_ticks_msec()
	if now_ms - _last_tracker_packet_warning_ms < TRACKER_PACKET_WARNING_INTERVAL_MS:
		return
	_last_tracker_packet_warning_ms = now_ms
	print("Tracker packet warning: ", message)


func _normalize_hand_packet(packet_data: Variant) -> Dictionary:
	if not (packet_data is Dictionary):
		return {}
	
	var packet: Dictionary = packet_data
	for key in HAND_PACKET_TEMPLATE.keys():
		if not packet.has(key):
			return {}
	
	if typeof(packet["found"]) != TYPE_BOOL:
		return {}
	
	var hands_type = typeof(packet["hands"])
	if hands_type != TYPE_INT and hands_type != TYPE_FLOAT:
		return {}
	
	var normalized: Dictionary = HAND_PACKET_TEMPLATE.duplicate()
	normalized["found"] = bool(packet["found"])
	normalized["hands"] = clampi(int(packet["hands"]), 0, 2)
	
	var numeric_ranges: Dictionary = {
		"mid_x": Vector2(0.0, 1.0),
		"mid_y": Vector2(0.0, 1.0),
		"angle": Vector2(-PI, PI),
		"distance": Vector2(0.0, 1.0),
	}
	for key in numeric_ranges.keys():
		var raw_value = packet[key]
		var value_type = typeof(raw_value)
		if value_type != TYPE_INT and value_type != TYPE_FLOAT:
			return {}
		var bounds: Vector2 = numeric_ranges[key]
		normalized[key] = clamp(float(raw_value), bounds.x, bounds.y)
	
	if normalized["hands"] < 2:
		normalized["found"] = false
	
	return normalized


func receive_hand_data():
	var received = false
	while udp_server.get_available_packet_count() > 0:
		var packet = udp_server.get_packet()
		var json_string = packet.get_string_from_utf8()
		var json = JSON.new()
		var parse_err = json.parse(json_string)
		if parse_err != OK:
			_warn_tracker_packet_issue("Invalid JSON packet from tracker")
			continue
		
		var normalized_packet = _normalize_hand_packet(json.data)
		if normalized_packet.is_empty():
			_warn_tracker_packet_issue("Packet schema mismatch from tracker")
			continue
		
		hand_data = normalized_packet
		received = true
	
	if received:
		last_data_time = Time.get_ticks_msec() / 1000.0


func is_tracker_connected() -> bool:
	"""Kiểm tra xem tracker có đang gửi dữ liệu không"""
	var current_time = Time.get_ticks_msec() / 1000.0
	return (current_time - last_data_time) < connection_timeout


func update_ui():
	update_tracking_monitor()
	
	if paused:
		if instruction_label:
			instruction_label.visible = false
		return
	
	# Score with combo indicator
	if combo_count > 1:
		score_label.text = "Score: %d (x%.1f)" % [score, 1.0 + combo_count * 0.1]
	else:
		score_label.text = "Score: %d" % score
	
	# Speed + drift meter
	var drift_percent = int(round(clamp(drift_charge, 0.0, 1.0) * 100.0))
	speed_label.text = "Speed: %.1fx | Drift %d%% | %s" % [speed_multiplier, drift_percent, get_track_segment_name()]
	speed_label.add_theme_color_override("font_color", Color.WHITE)
	
	high_score_label.text = "Best: %d" % high_score
	if tracker_running and tracker_pid > 0 and not OS.is_process_running(tracker_pid):
		tracker_running = false
	
	var tracker_found = hand_data.get("found", false)
	var tracker_connected = is_tracker_connected()
	var using_manual = control_mode == ControlMode.KEYBOARD_MOUSE or (control_mode == ControlMode.HYBRID and not tracker_found)
	var inventory_text = get_inventory_text()
	
	if using_manual:
		status_label.text = "⌨🖱 Control: %s | Item: %s (Tab để đổi mode)" % [get_control_mode_name(), inventory_text]
		instruction_label.visible = false
	elif tracker_found:
		status_label.text = "✋✋ Control: HAND TRACKING | Item: %s" % inventory_text
		instruction_label.visible = false
	else:
		if tracker_connected:
			status_label.text = "⚠ Show both hands (Mode: %s) | Item: %s" % [get_control_mode_name(), inventory_text]
		elif tracker_running:
			status_label.text = "⏳ Connecting tracker... (Mode: %s) | Item: %s" % [get_control_mode_name(), inventory_text]
		else:
			status_label.text = "⚠ Tracker offline - install deps: pip install -r requirements.txt (Mode: %s) | Item: %s" % [get_control_mode_name(), inventory_text]
		instruction_label.visible = true
	
	status_label.add_theme_color_override("font_color", Color.WHITE)


func update_spaceship(delta):
	if not spaceship:
		return
	
	var data: Dictionary = get_active_control_data()
	
	if spaceship.has_method("update_from_hand_data"):
		spaceship.update_from_hand_data(data, delta)
	else:
		# Backward compatibility
		if data.get("found", false):
			spaceship.update_from_hands(
				data.get("mid_x", 0.5),
				data.get("mid_y", 0.5),
				data.get("angle", 0.0),
				data.get("distance", 0.5),
				delta
			)
	
	var ship_gesture = -1
	if spaceship.has_method("get_current_gesture"):
		ship_gesture = int(spaceship.get_current_gesture())
	else:
		ship_gesture = int(spaceship.get("current_gesture"))
	process_runtime_gestures(ship_gesture, delta)
	
	var boosted_speed = spaceship.speed_boost
	if speed_boost_timer > 0.0:
		boosted_speed += 0.35
	if drift_active:
		boosted_speed *= DRIFT_SPEED_PENALTY
	speed_multiplier = max(0.35, boosted_speed - collision_slowdown)
	if audio_engine and audio_engine.stream:
		if not audio_engine.playing:
			audio_engine.play()
		audio_engine.pitch_scale = lerp(audio_engine.pitch_scale, 0.82 + speed_multiplier * 0.28, clamp(delta * 5.0, 0.0, 1.0))
	apply_curve_pull_to_spaceship(delta)


func process_runtime_gestures(gesture: int, delta: float):
	var ship_speed_boost = 1.0
	if spaceship:
		ship_speed_boost = float(spaceship.speed_boost)
	var is_drift_gesture = gesture == HandControlMapper.GestureType.DRIFT and ship_speed_boost >= 1.0
	if is_drift_gesture:
		drift_active = true
		drift_charge = min(DRIFT_CHARGE_MAX, drift_charge + DRIFT_CHARGE_GAIN_RATE * delta)
	else:
		drift_active = false
	
	var rising_edge = gesture != last_ship_gesture
	if rising_edge:
		match gesture:
			HandControlMapper.GestureType.BOOST:
				trigger_gesture_boost()
			HandControlMapper.GestureType.ITEM_USE:
				trigger_gesture_item_use()
			HandControlMapper.GestureType.ITEM_NEXT:
				cycle_inventory_item()
	
	last_ship_gesture = gesture


func trigger_gesture_boost():
	if gesture_boost_cooldown > 0.0:
		return
	
	var boost_time = 0.0
	if drift_charge > 0.15:
		boost_time = lerp(0.8, 2.4, clamp(drift_charge, 0.0, 1.0))
		drift_charge = 0.0
	elif support_inventory.has("boost"):
		boost_time = 2.0
		support_inventory.erase("boost")
	
	if boost_time <= 0.0:
		return
	
	speed_boost_timer = max(speed_boost_timer, boost_time)
	gesture_boost_cooldown = 0.55
	if audio_boost and audio_boost.stream:
		audio_boost.play()


func trigger_gesture_item_use():
	if gesture_item_cooldown > 0.0:
		return
	if support_inventory.is_empty():
		return
	
	var item_type = str(support_inventory[0])
	support_inventory.remove_at(0)
	apply_support_item_effect_type(item_type)
	gesture_item_cooldown = 0.45


func cycle_inventory_item():
	if support_inventory.size() <= 1:
		return
	var first_item = support_inventory.pop_at(0)
	support_inventory.append(first_item)


func update_status_effects(delta):
	if speed_boost_timer > 0.0:
		speed_boost_timer = max(0.0, speed_boost_timer - delta)
	if shield_timer > 0.0:
		shield_timer = max(0.0, shield_timer - delta)
	if rival_slow_timer > 0.0:
		rival_slow_timer = max(0.0, rival_slow_timer - delta)
	if gesture_boost_cooldown > 0.0:
		gesture_boost_cooldown = max(0.0, gesture_boost_cooldown - delta)
	if gesture_item_cooldown > 0.0:
		gesture_item_cooldown = max(0.0, gesture_item_cooldown - delta)
	if not drift_active:
		drift_charge = max(0.0, drift_charge - DRIFT_CHARGE_DECAY_RATE * delta)
	if rival_collision_cooldown > 0.0:
		rival_collision_cooldown = max(0.0, rival_collision_cooldown - delta)


func process_race_intro(delta):
	race_intro_timer += delta
	if story_label:
		story_label.visible = true
	
	var intro_lines = build_campaign_intro_lines()
	var line_duration = 2.3
	var line_index = clampi(int(floor(race_intro_timer / line_duration)), 0, intro_lines.size() - 1)
	if story_label:
		story_label.text = intro_lines[line_index]
	
	var intro_total_duration = max(5.2, float(intro_lines.size()) * line_duration + 0.6)
	if race_intro_timer >= intro_total_duration:
		race_intro_active = false
		race_started = true
		campaign_transition_pending = false
		if story_label:
			story_label.visible = false
		set_game_state("playing")


func is_spawn_location_clear(candidate_pos: Vector3, x_gap: float, y_gap: float, z_gap: float) -> bool:
	for obs in obstacles:
		if not is_instance_valid(obs):
			continue
		if abs(obs.position.z - candidate_pos.z) < z_gap and abs(obs.position.x - candidate_pos.x) < x_gap and abs(obs.position.y - candidate_pos.y) < y_gap:
			return false
	
	for item in support_items:
		if not is_instance_valid(item):
			continue
		if abs(item.position.z - candidate_pos.z) < z_gap and abs(item.position.x - candidate_pos.x) < x_gap and abs(item.position.y - candidate_pos.y) < y_gap:
			return false
	
	return true


func get_obstacle_spawn_position() -> Vector3:
	var stage_progress = float(current_campaign_level) / max(1.0, float(CAMPAIGN_LEVELS.size() - 1))
	var clear_x_gap = lerp(2.0, 1.45, stage_progress)
	var clear_y_gap = lerp(1.25, 0.95, stage_progress)
	var clear_z_gap = lerp(18.0, 13.2, stage_progress)
	var curve_bias = track_curve_intensity * 0.2
	var best_score = -INF
	var best_spawn = Vector3(
		clamp(randf_range(-7.2, 7.2) + track_offset.x * 0.16, -8.4, 8.4),
		randf_range(-2.2, 2.2),
		OBSTACLE_SPAWN_FRONT_Z + randf_range(-5.0, 3.0)
	)
	
	for lane_x_raw in OBSTACLE_LANE_CHOICES:
		for lane_y_raw in OBSTACLE_Y_CHOICES:
			var spawn_x = clamp(float(lane_x_raw) + randf_range(-0.42, 0.42) + track_offset.x * 0.16, -8.6, 8.6)
			var spawn_y = clamp(float(lane_y_raw) + randf_range(-0.26, 0.26), -3.4, 3.4)
			var spawn_pos = Vector3(spawn_x, spawn_y, OBSTACLE_SPAWN_FRONT_Z + randf_range(-4.0, 4.0))
			
			# Tránh "spawn chết" ngay đúng corridor của người chơi.
			if spaceship and abs(spawn_pos.x - spaceship.position.x) < 0.95 and abs(spawn_pos.y - spaceship.position.y) < 0.65 and randf() < 0.88:
				continue
			if not is_spawn_location_clear(spawn_pos, clear_x_gap, clear_y_gap, clear_z_gap):
				continue
			
			var candidate_score = 0.0
			if spaceship:
				var x_gap = abs(spawn_pos.x - spaceship.position.x)
				var y_gap = abs(spawn_pos.y - spaceship.position.y)
				if x_gap < 1.1 and y_gap < 0.8:
					candidate_score -= 4.0
				else:
					candidate_score += min(x_gap, 6.0) * 0.24 + min(y_gap, 3.0) * 0.14
			
			# Giảm lặp lane/y liên tiếp để obstacle "đọc" được hơn.
			if last_obstacle_spawn_pos.x < 900.0:
				candidate_score -= max(0.0, 2.2 - abs(spawn_pos.x - last_obstacle_spawn_pos.x)) * 0.8
				candidate_score -= max(0.0, 1.15 - abs(spawn_pos.y - last_obstacle_spawn_pos.y)) * 0.35
			
			# Tăng nhẹ bias theo hướng cua để bố cục track hợp mắt hơn.
			candidate_score += spawn_pos.x * curve_bias
			candidate_score += (1.0 - abs(spawn_pos.x) / 8.6) * 0.18
			candidate_score += randf_range(-0.16, 0.16) * (0.6 + stage_progress * 0.7)
			
			if candidate_score > best_score:
				best_score = candidate_score
				best_spawn = spawn_pos
	
	last_obstacle_spawn_pos = best_spawn
	return best_spawn


func get_support_item_spawn_position() -> Vector3:
	var lane_choices = [-6.0, -3.0, 0.0, 3.0, 6.0]
	var y_choices = [-2.4, -1.2, 0.0, 1.2, 2.4]
	
	for _attempt in range(20):
		var lane_x = lane_choices[randi() % lane_choices.size()]
		if spaceship and randf() < 0.6:
			lane_x = clamp(spaceship.position.x + randf_range(-2.6, 2.6), -6.2, 6.2)
		
		var spawn_x = clamp(lane_x + randf_range(-0.45, 0.45) + track_offset.x * 0.18, -7.0, 7.0)
		var spawn_y = y_choices[randi() % y_choices.size()] + randf_range(-0.3, 0.3)
		var spawn_pos = Vector3(spawn_x, clamp(spawn_y, -3.0, 3.0), -132.0 + randf_range(-5.0, 5.0))
		
		if not is_spawn_location_clear(spawn_pos, 2.4, 1.4, 22.0):
			continue
		return spawn_pos
	
	return Vector3(clamp(randf_range(-5.8, 5.8), -6.2, 6.2), randf_range(-2.2, 2.2), -130.0)


func spawn_support_items(delta):
	support_item_spawn_timer += delta
	if support_item_spawn_timer < support_item_interval:
		return
	if support_items.size() >= 4:
		return
	
	support_item_spawn_timer = 0.0
	var item = acquire_support_item()
	var spawn_pos = get_support_item_spawn_position()
	if item.has_method("activate_for_pool"):
		item.activate_for_pool(spawn_pos)
	else:
		item.position = spawn_pos
		item.visible = true
	support_items.append(item)


func update_support_items(delta):
	var lateral_velocity = get_curve_lateral_velocity()
	for item in support_items:
		if is_instance_valid(item) and item.has_method("update_movement"):
			item.update_movement(speed_multiplier, delta, lateral_velocity)


func check_support_item_pickups():
	if not spaceship:
		return
	
	for item in support_items.duplicate():
		if not is_instance_valid(item):
			support_items.erase(item)
			continue
		
		if item.position.z > 12.0:
			release_support_item(item)
			continue
		
		var pickup_radius = 1.1
		if item.has_method("get_pickup_radius"):
			pickup_radius = float(item.get_pickup_radius())
		
		if spaceship.position.distance_to(item.position) <= pickup_radius:
			collect_support_item(item)
			release_support_item(item)


func apply_support_item_effect(item: Node3D):
	var item_type = "boost"
	if item.has_method("get_item_type_name"):
		item_type = str(item.get_item_type_name())
	apply_support_item_effect_type(item_type)
	if spaceship:
		spawn_collision_effect(spaceship.position + Vector3(0, 0, -0.6))


func collect_support_item(item: Node3D):
	var item_type = "boost"
	if item.has_method("get_item_type_name"):
		item_type = str(item.get_item_type_name())
	
	if support_inventory.size() >= SUPPORT_INVENTORY_MAX:
		support_inventory.remove_at(0)
	support_inventory.append(item_type)
	
	if item_type == "boost" or item_type == "shield":
		if audio_boost and audio_boost.stream:
			audio_boost.play()
	elif audio_warning and audio_warning.stream:
		audio_warning.play()
	
	if spaceship:
		spawn_collision_effect(spaceship.position + Vector3(0, 0, -0.6))


func apply_support_item_effect_type(item_type: String):
	match item_type:
		"boost":
			speed_boost_timer = max(speed_boost_timer, 4.5)
		"shield":
			shield_timer = max(shield_timer, 6.0)
		"rival_slow":
			rival_slow_timer = max(rival_slow_timer, 5.5)
		"jammer":
			rival_slow_timer = max(rival_slow_timer, 4.0)
			shake_intensity = max(shake_intensity, 0.22)
	
	if item_type == "boost" or item_type == "shield":
		if audio_boost and audio_boost.stream:
			audio_boost.play()
	elif audio_warning and audio_warning.stream:
		audio_warning.play()


func update_rivals(delta):
	if rival_ships.is_empty():
		return
	
	var player_lane = 0.0
	if spaceship:
		player_lane = spaceship.position.x
	
	for i in range(rival_ships.size()):
		var rival_data = rival_ships[i]
		var rival_node = rival_data["node"]
		if not is_instance_valid(rival_node):
			continue
		
		var phase = float(rival_data.get("phase", 0.0)) + delta * float(rival_data.get("phase_speed", 1.6))
		rival_data["phase"] = phase
		
		var decision_timer = float(rival_data.get("decision_timer", 0.0)) - delta
		if decision_timer <= 0.0:
			var target_lane = choose_rival_target_lane(rival_data, player_lane)
			rival_data["target_lane"] = target_lane
			var personality = str(rival_data.get("personality", "balanced"))
			match personality:
				"aggressive":
					decision_timer = randf_range(0.4, 0.9)
				"trickster":
					decision_timer = randf_range(0.35, 0.8)
				"sprinter":
					decision_timer = randf_range(0.5, 1.0)
				_:
					decision_timer = randf_range(0.6, 1.2)
			
			var gap_to_player = player_race_distance - float(rival_data.get("distance", 0.0))
			var aggression = float(rival_data.get("aggression", 0.6))
			if gap_to_player > 16.0 and randf() < aggression:
				rival_data["boost_timer"] = max(float(rival_data.get("boost_timer", 0.0)), randf_range(0.45, 1.25))
			if get_obstacle_lane_penalty(float(target_lane)) > 1.7 and randf() < 0.65:
				rival_data["brake_timer"] = max(float(rival_data.get("brake_timer", 0.0)), randf_range(0.2, 0.55))
		
		rival_data["decision_timer"] = decision_timer
		
		var boost_timer = max(0.0, float(rival_data.get("boost_timer", 0.0)) - delta)
		var brake_timer = max(0.0, float(rival_data.get("brake_timer", 0.0)) - delta)
		rival_data["boost_timer"] = boost_timer
		rival_data["brake_timer"] = brake_timer
		
		var gap_to_player_now = player_race_distance - float(rival_data.get("distance", 0.0))
		var wave_speed = sin(phase * 1.7 + float(i) * 0.8) * 1.25
		var catchup_speed = clamp(gap_to_player_now * 0.05, -1.8, 3.0)
		var aggression_speed = (float(rival_data.get("aggression", 0.6)) - 0.5) * 2.0
		var speed = float(rival_data.get("base_speed", 20.0)) + wave_speed + catchup_speed + aggression_speed
		
		if boost_timer > 0.0:
			speed += 4.2
		if brake_timer > 0.0:
			speed -= 3.4
		if str(rival_data.get("personality", "")) == "sprinter":
			speed += 0.8
		
		var slow_factor = 0.65 if rival_slow_timer > 0.0 else 1.0
		speed = clamp(speed * slow_factor, 12.0, 33.0)
		rival_data["current_speed"] = speed
		rival_data["distance"] = float(rival_data.get("distance", 0.0)) + speed * delta
		
		var lane = float(rival_data.get("lane", 0.0))
		var target_lane_now = float(rival_data.get("target_lane", lane))
		var lane_change_speed = float(rival_data.get("lane_change_speed", 3.4))
		lane = move_toward(lane, target_lane_now, delta * lane_change_speed * 2.3)
		rival_data["lane"] = lane
		
		var consistency = float(rival_data.get("consistency", 0.7))
		var weave = sin(phase * 2.0 + float(i) * 1.1) * (1.0 - consistency) * 1.2
		var target_x = lane + weave + track_offset.x * 0.34
		rival_node.position.x = lerp(rival_node.position.x, target_x, delta * (3.8 + lane_change_speed * 0.25))
		# Clamp X to valid track bounds to prevent drift outside lanes
		rival_node.position.x = clamp(rival_node.position.x, -8.2, 8.2)
		rival_node.position.y = sin(phase * 1.75 + float(i) * 0.7) * 0.2
		
		var relative_distance = (float(rival_data.get("distance", 0.0)) - player_race_distance) * RIVAL_VISUAL_DISTANCE_SCALE
		var player_z = spaceship.position.z if spaceship else 0.0
		rival_node.position.z = clamp(player_z + RIVAL_VISUAL_Z_BASE - relative_distance, RIVAL_VISUAL_Z_MIN, RIVAL_VISUAL_Z_MAX)
		var bank_target = clamp((target_x - rival_node.position.x) * -8.0 + -sin(phase) * 5.0, -18.0, 18.0)
		rival_node.rotation_degrees.z = lerp(rival_node.rotation_degrees.z, bank_target, delta * 4.5)
		rival_ships[i] = rival_data


func resolve_rival_collisions(delta: float):
	if rival_ships.is_empty():
		return
	
	const PLAYER_HALF_X = 0.4
	const PLAYER_HALF_Y = 0.15
	const PLAYER_HALF_Z = 0.8
	const RIVAL_HALF_X = 0.42
	const RIVAL_HALF_Y = 0.16
	const RIVAL_HALF_Z = 0.82
	
	for i in range(rival_ships.size()):
		var rival_data = rival_ships[i]
		rival_data["collision_cooldown"] = max(0.0, float(rival_data.get("collision_cooldown", 0.0)) - delta)
		rival_ships[i] = rival_data
	
	if spaceship and rival_collision_cooldown <= 0.0:
		for i in range(rival_ships.size()):
			var rival_data = rival_ships[i]
			var rival_node = rival_data.get("node")
			if not is_instance_valid(rival_node):
				continue
			if float(rival_data.get("collision_cooldown", 0.0)) > 0.0:
				continue
			
			var dx = spaceship.position.x - rival_node.position.x
			var dy = spaceship.position.y - rival_node.position.y
			var dz = spaceship.position.z - rival_node.position.z
			var overlap_x = (PLAYER_HALF_X + RIVAL_HALF_X) - abs(dx)
			var overlap_y = (PLAYER_HALF_Y + RIVAL_HALF_Y) - abs(dy)
			var overlap_z = (PLAYER_HALF_Z + RIVAL_HALF_Z) - abs(dz)
			if overlap_x <= 0.0 or overlap_y <= 0.0 or overlap_z <= 0.0:
				continue
			
			var push_dir = sign(dx)
			if is_zero_approx(push_dir):
				push_dir = -1.0 if rival_node.position.x > spaceship.position.x else 1.0
			var push_amount = clamp(RIVAL_COLLISION_PUSH_BASE + overlap_x * 0.45, 0.35, 1.35)
			spaceship.position.x = clamp(spaceship.position.x + push_dir * push_amount, -9.0, 9.0)
			rival_node.position.x = clamp(rival_node.position.x - push_dir * push_amount * 0.65, -9.0, 9.0)
			
			rival_data["lane"] = rival_node.position.x
			rival_data["target_lane"] = rival_node.position.x
			
			var distance_penalty = 3.5 + max(0.0, speed_multiplier - 1.0) * 2.0
			if shield_timer > 0.0:
				distance_penalty *= 0.4
			player_race_distance = max(0.0, player_race_distance - distance_penalty)
			rival_data["distance"] = max(0.0, float(rival_data.get("distance", 0.0)) - 1.6)
			
			var slowdown_penalty = 0.18 + max(0.0, speed_multiplier - 1.0) * 0.45
			if shield_timer > 0.0:
				slowdown_penalty *= 0.45
			collision_slowdown = clamp(collision_slowdown + slowdown_penalty, 0.0, 2.8)
			shake_intensity = max(shake_intensity, 0.16 + slowdown_penalty * 0.12)
			rival_collision_cooldown = RIVAL_COLLISION_COOLDOWN
			rival_data["collision_cooldown"] = RIVAL_COLLISION_COOLDOWN * 0.75
			
			if audio_explosion and audio_explosion.stream:
				audio_explosion.play()
			spawn_collision_effect(spaceship.position + Vector3(push_dir * 0.45, 0.0, -0.45))
			
			rival_ships[i] = rival_data
			break
	
	for i in range(rival_ships.size()):
		var first_data = rival_ships[i]
		var first_node = first_data.get("node")
		if not is_instance_valid(first_node):
			continue
		for j in range(i + 1, rival_ships.size()):
			var second_data = rival_ships[j]
			var second_node = second_data.get("node")
			if not is_instance_valid(second_node):
				continue
			if float(first_data.get("collision_cooldown", 0.0)) > 0.0 or float(second_data.get("collision_cooldown", 0.0)) > 0.0:
				continue
			
			var pair_dx = first_node.position.x - second_node.position.x
			var pair_dz = first_node.position.z - second_node.position.z
			var pair_overlap_x = (RIVAL_HALF_X * 2.0) - abs(pair_dx)
			var pair_overlap_z = (RIVAL_HALF_Z * 1.2) - abs(pair_dz)
			if pair_overlap_x <= 0.0 or pair_overlap_z <= 0.0:
				continue
			
			var pair_push_dir = sign(pair_dx)
			if is_zero_approx(pair_push_dir):
				pair_push_dir = 1.0 if randf() < 0.5 else -1.0
			var separation = clamp(0.25 + pair_overlap_x * 0.35, 0.2, 0.9)
			first_node.position.x = clamp(first_node.position.x + pair_push_dir * separation, -9.0, 9.0)
			second_node.position.x = clamp(second_node.position.x - pair_push_dir * separation, -9.0, 9.0)
			
			first_data["lane"] = first_node.position.x
			first_data["target_lane"] = first_node.position.x
			second_data["lane"] = second_node.position.x
			second_data["target_lane"] = second_node.position.x
			
			if float(first_data.get("distance", 0.0)) >= float(second_data.get("distance", 0.0)):
				second_data["distance"] = max(0.0, float(second_data.get("distance", 0.0)) - 1.0 - pair_overlap_z * 0.5)
			else:
				first_data["distance"] = max(0.0, float(first_data.get("distance", 0.0)) - 1.0 - pair_overlap_z * 0.5)
			
			first_data["collision_cooldown"] = 0.18
			second_data["collision_cooldown"] = 0.18
			rival_ships[i] = first_data
			rival_ships[j] = second_data


func update_race_progress(delta):
	if not race_started or race_finished:
		return
	
	player_race_distance += speed_multiplier * delta * 22.0
	var best_rival_distance = 0.0
	for rival_data in rival_ships:
		best_rival_distance = max(best_rival_distance, float(rival_data.get("distance", 0.0)))
	
	if race_label:
		race_label.text = get_race_hud_text(best_rival_distance)
	
	var player_finished = player_race_distance >= race_target_distance
	var rival_finished = best_rival_distance >= race_target_distance
	if player_finished or rival_finished:
		var player_rank = get_player_rank()
		var player_won = player_finished and player_rank == 1
		if player_won:
			if current_campaign_level < CAMPAIGN_LEVELS.size() - 1:
				advance_campaign_level()
			else:
				handle_campaign_victory()
		else:
			handle_campaign_defeat(best_rival_distance)


func apply_curve_pull_to_spaceship(delta):
	"""Khi vào cua, tàu sẽ bị kéo ngang để gameplay không còn chạy thẳng tuyệt đối."""
	if not spaceship:
		return
	
	var lateral_velocity = get_curve_lateral_velocity()
	if abs(lateral_velocity) < 0.001:
		return
	
	spaceship.position.x += lateral_velocity * delta * SHIP_CURVE_INFLUENCE
	spaceship.position.x = clamp(spaceship.position.x, -9.0, 9.0)


func update_grid(delta):
	if grid_floor:
		var scroll_speed = 34.0 * delta * speed_multiplier
		for child in grid_floor.get_children():
			if child.has_meta("scrolling"):
				child.position.z += scroll_speed
				var reset_z = float(child.get_meta("scroll_reset_z", -110.0))
				if child.position.z > 24.0:
					child.position.z = reset_z
				
				if not child.has_meta("base_x"):
					child.set_meta("base_x", child.position.x)
				if not child.has_meta("base_y"):
					child.set_meta("base_y", child.position.y)
				var base_x = float(child.get_meta("base_x"))
				var base_y = float(child.get_meta("base_y"))
				var curve_factor = float(child.get_meta("curve_factor", 1.0))
				var depth = clamp((-child.position.z + 20.0) / 170.0, 0.0, 1.0)
				var depth_curve = pow(depth, 1.22) * (0.35 + curve_factor * CURVE_DEPTH_STRENGTH * GRID_CURVE_INFLUENCE)
				var curve_shift = track_offset.x * depth_curve
				var wave_shift = sin(track_wave_phase + child.position.z * 0.065 + base_x * 0.2) * track_wave_amount * 0.58 * depth
				var bank_y = -base_x * deg_to_rad(track_rotation) * CURVE_BANK_VERTICAL_PUSH * (0.25 + depth * 1.12)
				child.position.x = base_x + curve_shift + wave_shift
				child.position.y = base_y + bank_y + sin(track_wave_phase * 0.7 + child.position.z * 0.04) * track_wave_amount * 0.08 * depth
		
		var wave = sin(track_wave_phase) * track_wave_amount
		grid_floor.position.x = lerp(grid_floor.position.x, track_offset.x * 0.34, delta * 3.5)
		grid_floor.position.y = lerp(grid_floor.position.y, wave * 0.28, delta * 2.7)
		grid_floor.rotation_degrees.y = lerp(grid_floor.rotation_degrees.y, track_rotation * 0.68, delta * 3.2)
		grid_floor.rotation_degrees.z = lerp(grid_floor.rotation_degrees.z, -track_rotation * 0.32, delta * 3.0)


func get_segment_curve_direction(segment: int) -> float:
	match segment:
		TrackSegment.CURVE_LEFT:
			return -1.0
		TrackSegment.CURVE_RIGHT:
			return 1.0
		_:
			return 0.0


func update_track_segment(delta):
	"""Cập nhật đoạn đường và xử lý rẽ"""
	segment_timer += delta * speed_multiplier
	
	# Kiểm tra chuyển đoạn
	if segment_timer >= segment_duration:
		segment_timer = fmod(segment_timer, max(segment_duration, 0.001))
		var completed_segment = current_segment
		current_segment = next_segment
		next_segment = pick_next_segment(current_segment)
		
		# Bonus điểm khi hoàn thành đoạn cong
		if completed_segment != TrackSegment.STRAIGHT:
			add_score(15)  # Bonus cho việc qua khúc cua
	
	# Blend giữa segment hiện tại và segment kế tiếp để tạo cảm giác cua liên tục.
	var progress = clamp(segment_timer / max(segment_duration, 0.001), 0.0, 1.0)
	var current_curve = get_segment_curve_direction(current_segment)
	var next_curve = get_segment_curve_direction(next_segment)
	var transition_start = 1.0 - CURVE_TRANSITION_RATIO
	var transition_t = 0.0
	if progress > transition_start:
		transition_t = (progress - transition_start) / CURVE_TRANSITION_RATIO
	transition_t = ease_in_out(clamp(transition_t, 0.0, 1.0))
	
	var blended_curve = lerp(current_curve, next_curve, transition_t)
	target_track_rotation = blended_curve * CURVE_ANGLE
	target_track_offset = Vector3(blended_curve * CURVE_OFFSET, 0.0, 0.0)
	
	# Smooth transition
	track_curve_intensity = lerp(track_curve_intensity, blended_curve, delta * track_rotation_speed * 1.35)
	track_rotation = lerp(track_rotation, target_track_rotation, delta * track_rotation_speed * 1.18)
	track_offset = track_offset.lerp(target_track_offset, delta * track_rotation_speed * 1.12)
	track_wave_phase += delta * speed_multiplier * (0.82 + abs(track_curve_intensity) * 0.58)
	var target_wave = lerp(0.16, 0.58, abs(track_curve_intensity))
	track_wave_amount = lerp(track_wave_amount, target_wave, delta * 2.6)


func ease_in_out(t: float) -> float:
	"""Smooth easing function"""
	if t < 0.5:
		return 2 * t * t
	else:
		return 1 - pow(-2 * t + 2, 2) / 2


func get_track_segment_name() -> String:
	"""Lấy tên đoạn đường hiện tại"""
	match current_segment:
		TrackSegment.STRAIGHT:
			return "STRAIGHT"
		TrackSegment.CURVE_LEFT:
			return "← CURVE LEFT"
		TrackSegment.CURVE_RIGHT:
			return "CURVE RIGHT →"
	return ""


func pick_next_segment(previous_segment: int) -> int:
	"""Sinh đoạn đường tiếp theo với xác suất ưu tiên đoạn cong."""
	var rand = randf()
	
	# Nếu vừa đi thẳng, ưu tiên vào cua ngay.
	if previous_segment == TrackSegment.STRAIGHT:
		return TrackSegment.CURVE_LEFT if rand < 0.55 else TrackSegment.CURVE_RIGHT
	
	# Nếu đang cua, hiếm khi trả về đoạn thẳng để nhịp cua liên tục hơn.
	if rand < 0.08:
		return TrackSegment.STRAIGHT
	if previous_segment == TrackSegment.CURVE_LEFT:
		return TrackSegment.CURVE_RIGHT if rand < 0.82 else TrackSegment.CURVE_LEFT
	return TrackSegment.CURVE_LEFT if rand < 0.82 else TrackSegment.CURVE_RIGHT


func get_curve_lateral_velocity() -> float:
	"""Tốc độ trôi ngang dựa theo góc cua hiện tại."""
	return track_curve_intensity * CURVE_LATERAL_SPEED


func spawn_obstacles(delta):
	spawn_timer += delta
	if spawn_timer > current_spawn_interval and obstacles.size() < MAX_OBSTACLES:
		spawn_timer = 0
		var obs = acquire_obstacle()
		var spawn_pos = get_obstacle_spawn_position()
		if obs.has_method("activate_for_pool"):
			obs.activate_for_pool(spawn_pos)
		else:
			obs.position = spawn_pos
			obs.visible = true
		
		obstacles.append(obs)


func update_difficulty(delta):
	difficulty_timer += delta
	# Increase difficulty every 10 seconds
	if difficulty_timer > 10.0:
		difficulty_timer = 0.0
		current_spawn_interval = max(0.3, current_spawn_interval - 0.05)


func update_obstacles(delta):
	var lateral_velocity = get_curve_lateral_velocity()
	for obs in obstacles:
		if is_instance_valid(obs):
			obs.update_movement(speed_multiplier, delta, lateral_velocity)


func check_collisions():
	var closest_distance = 999.0
	
	# Spaceship collision size (phải khớp với debug draw)
	const SHIP_HALF_X = 0.4   # Nửa chiều rộng
	const SHIP_HALF_Y = 0.15  # Nửa chiều cao  
	const SHIP_HALF_Z = 0.8   # Nửa chiều dài
	
	for obs in obstacles.duplicate():
		if not is_instance_valid(obs):
			obstacles.erase(obs)
			continue
			
		# Check if passed player
		if obs.position.z > 10:
			release_obstacle(obs)
			add_score(10)
			continue
		
		# Check collision and near-miss with spaceship
		if spaceship:
			var ship_pos = spaceship.position
			var obs_pos = obs.position
			var obs_size = obs.obstacle_size
			
			# Calculate distance for warning
			var dist = ship_pos.distance_to(obs_pos)
			if dist < closest_distance:
				closest_distance = dist
			
			# Collision detection - AABB với kích thước chính xác
			var collision_x = abs(ship_pos.x - obs_pos.x) < (obs_size.x / 2 + SHIP_HALF_X)
			var collision_y = abs(ship_pos.y - obs_pos.y) < (obs_size.y / 2 + SHIP_HALF_Y)
			var collision_z = abs(ship_pos.z - obs_pos.z) < (obs_size.z / 2 + SHIP_HALF_Z)
			
			if collision_x and collision_y and collision_z:
				apply_obstacle_collision_penalty()
				release_obstacle(obs)
				continue
			
			# Near-miss detection (obstacle just passed beside player)
			if obs.position.z > -1 and obs.position.z < 2:
				var lateral_dist = sqrt(pow(ship_pos.x - obs_pos.x, 2) + pow(ship_pos.y - obs_pos.y, 2))
				var min_dist = SHIP_HALF_X + obs_size.x / 2
				if lateral_dist < min_dist + 1.5 and lateral_dist > min_dist:
					# Near miss! Add bonus
					if not obs.has_meta("near_miss_counted"):
						obs.set_meta("near_miss_counted", true)
						add_score(5)  # Bonus for near miss
						combo_count += 1
						combo_timer = COMBO_TIMEOUT
	
	# Update warning intensity based on closest obstacle
	if closest_distance < WARNING_DISTANCE:
		warning_intensity = 1.0 - (closest_distance / WARNING_DISTANCE)
	else:
		warning_intensity = max(0, warning_intensity - 0.1)


func apply_obstacle_collision_penalty():
	"""Va chạm không game-over: giảm tốc theo mức boost hiện tại."""
	var boost_excess = max(0.0, speed_multiplier - 1.0)
	var penalty = 0.25 + boost_excess * 0.9
	if shield_timer > 0.0:
		penalty *= 0.35
	collision_slowdown = clamp(collision_slowdown + penalty, 0.0, 2.8)
	shake_intensity = max(shake_intensity, 0.2 + penalty * 0.08)
	if audio_explosion and audio_explosion.stream:
		audio_explosion.play()
	
	if spaceship:
		spawn_collision_effect(spaceship.position)


func spawn_collision_effect(effect_position: Vector3):
	# Ưu tiên Pixelpart nếu project có effect resource phù hợp.
	if try_spawn_pixelpart_effect("res://effects/hit_impact.res", effect_position, 1.0):
		return
	
	# Fallback GPU particles nếu chưa có file Pixelpart effect.
	var burst = GPUParticles3D.new()
	burst.amount = 40
	burst.lifetime = 0.35
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.position = effect_position
	
	var process_mat = ParticleProcessMaterial.new()
	process_mat.direction = Vector3.ZERO
	process_mat.spread = 180.0
	process_mat.initial_velocity_min = 6.0
	process_mat.initial_velocity_max = 12.0
	process_mat.gravity = Vector3(0, -2, 0)
	process_mat.scale_min = 0.05
	process_mat.scale_max = 0.18
	process_mat.color = Color(1.0, 0.65, 0.2, 1.0)
	burst.process_material = process_mat
	
	var mesh = SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	burst.draw_pass_1 = mesh
	
	add_child(burst)
	burst.emitting = true
	
	var timer = get_tree().create_timer(1.2)
	timer.timeout.connect(func(): burst.queue_free())


func try_spawn_pixelpart_effect(effect_path: String, effect_position: Vector3, lifetime: float = 1.5) -> bool:
	if not ClassDB.class_exists("PixelpartEffect"):
		return false
	if not ResourceLoader.exists(effect_path):
		return false
	
	var effect_node = ClassDB.instantiate("PixelpartEffect")
	if effect_node == null:
		return false
	
	add_child(effect_node)
	effect_node.position = effect_position
	var effect_resource = load(effect_path)
	var assigned = false
	
	for property in effect_node.get_property_list():
		var property_name = str(property.get("name", ""))
		if property_name == "effect" or property_name == "effect_resource" or property_name == "resource":
			effect_node.set(property_name, effect_resource)
			assigned = true
			break
	
	if not assigned:
		effect_node.queue_free()
		return false
	
	if effect_node.has_method("play"):
		effect_node.call("play")
	
	var timer = get_tree().create_timer(lifetime)
	timer.timeout.connect(func(): effect_node.queue_free())
	return true


func add_score(points: int):
	"""Thêm điểm với combo multiplier"""
	var multiplier = 1.0 + combo_count * 0.1  # 10% bonus per combo
	var actual_points = int(points * multiplier)
	score += actual_points
	
	if audio_score and audio_score.stream and score_sound_cooldown <= 0.0:
		audio_score.play()
		score_sound_cooldown = 0.08


func trigger_game_over():
	game_over = true
	set_game_state("game_over")
	game_over_label.text = "GAME OVER"
	restart_label.text = "R - Restart | ESC - Menu"
	
	# Trigger explosion on spaceship
	if spaceship and spaceship.has_method("trigger_explosion"):
		spaceship.trigger_explosion()
	
	# Camera shake
	shake_intensity = 0.5
	
	# Update high score
	if score > high_score:
		high_score = score
		save_high_score()
		high_score_label.text = "NEW BEST: %d" % high_score
		high_score_label.add_theme_color_override("font_color", Color.WHITE)


func update_camera(delta):
	if not spaceship:
		return
	
	var safe_delta = max(delta, 0.0001)
	var follow_alpha = 1.0 - exp(-CAMERA_FOLLOW_RESPONSE * safe_delta)
	var look_alpha = 1.0 - exp(-CAMERA_LOOK_RESPONSE * safe_delta)
	var speed_norm = clamp((speed_multiplier - 0.9) / 1.6, 0.0, 1.0)
	var lateral_lead = clamp(-spaceship.rotation_degrees.z * 0.045, -2.8, 2.8)
	
	# Pilot-like chase offset: increased minimum distance to prevent clipping
	var target_x = spaceship.position.x * 0.52 + track_offset.x * 1.15 + lateral_lead
	var target_y = 2.85 + spaceship.position.y * 0.24 + sin(track_wave_phase * 0.8) * track_wave_amount * 0.45 + speed_norm * 0.28
	var target_z = 13.2 - speed_norm * 2.25 - abs(track_rotation) * 0.028
	
	camera.position.x = lerp(camera.position.x, target_x, follow_alpha)
	camera.position.y = lerp(camera.position.y, target_y, follow_alpha)
	camera.position.z = lerp(camera.position.z, target_z, follow_alpha)
	
	var look_target = Vector3(
		spaceship.position.x + lateral_lead * 1.4 + track_offset.x * 1.08,
		spaceship.position.y * 0.3 + sin(track_wave_phase) * track_wave_amount * 0.35,
		-14.5 - speed_norm * 8.0
	)
	camera.look_at(look_target, Vector3.UP)
	
	var bank_target = clamp(-spaceship.rotation_degrees.z * 0.45 - track_rotation * 0.42, -20.0, 20.0)
	camera.rotation_degrees.z = lerp(camera.rotation_degrees.z, bank_target, look_alpha)
	
	var target_fov = CAMERA_BASE_FOV + speed_norm * CAMERA_BOOST_FOV + (2.0 if speed_boost_timer > 0.0 else 0.0)
	camera.fov = lerp(camera.fov, target_fov, follow_alpha)


func update_camera_shake(delta):
	if shake_intensity > 0:
		shake_intensity = max(0, shake_intensity - shake_decay * delta)
		camera.position.x += randf_range(-shake_intensity, shake_intensity)
		camera.position.y += randf_range(-shake_intensity, shake_intensity)
		camera.position.z += randf_range(-shake_intensity * 0.5, shake_intensity * 0.5)


func update_warning_effect(delta):
	"""Cập nhật hiệu ứng cảnh báo khi gần obstacle"""
	if warning_overlay:
		# Fade in/out warning overlay
		var current_alpha = warning_overlay.modulate.a
		var target_alpha = warning_intensity * 0.4  # Max 40% opacity
		warning_overlay.modulate.a = lerp(current_alpha, target_alpha, delta * 10)
	
	# Light camera shake when near obstacles
	if warning_intensity > 0.5 and not game_over:
		shake_intensity = max(shake_intensity, warning_intensity * 0.1)
	if warning_intensity > 0.78 and warning_sound_cooldown <= 0.0 and audio_warning and audio_warning.stream:
		audio_warning.play()
		warning_sound_cooldown = 0.35


func update_combo(delta):
	"""Cập nhật combo timer và UI"""
	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			combo_count = 0
	
	# Update combo label
	if combo_label:
		if combo_count > 1:
			combo_label.text = "COMBO x%d" % combo_count
			combo_label.visible = true
			# Flash effect
			var flash = abs(sin(Time.get_ticks_msec() * 0.01))
			combo_label.modulate.a = 0.7 + flash * 0.3
		else:
			combo_label.visible = false


func update_stars(delta):
	"""Animate twinkling stars"""
	var stars_container = get_node_or_null("BackgroundStars")
	if not stars_container:
		return
	
	for star in stars_container.get_children():
		if star.has_meta("twinkle_phase"):
			var phase = star.get_meta("twinkle_phase")
			var speed = star.get_meta("twinkle_speed")
			phase += delta * speed
			star.set_meta("twinkle_phase", phase)
			
			# Twinkle effect
			if star.material_override:
				var twinkle = 1.0 + 0.5 * sin(phase)
				star.material_override.emission_energy_multiplier = twinkle
		
		if star.has_meta("drift_speed"):
			var drift_speed = float(star.get_meta("drift_speed"))
			star.position.z += drift_speed * delta * 8.0
			if star.position.z > -60.0:
				star.position.z = randf_range(-260.0, -180.0)
				star.position.x = randf_range(-80.0, 80.0)


func refresh_pause_overlay_text():
	if not pause_label:
		return
	
	var stage_text = "STAGE %d/%d" % [current_campaign_level + 1, CAMPAIGN_LEVELS.size()]
	var progress = clamp(player_race_distance / max(race_target_distance, 1.0), 0.0, 1.0) * 100.0
	pause_label.text = "PAUSED\n%s | RACE %.0f%%\n\nESC - Resume    R - Restart    M - Main Menu" % [
		stage_text,
		progress
	]


func set_pause_aux_ui_hidden(is_paused: bool):
	if score_label:
		score_label.visible = not is_paused
	if speed_label:
		speed_label.visible = not is_paused
	if status_label:
		status_label.visible = not is_paused
	if race_label:
		race_label.visible = not is_paused
	if high_score_label:
		high_score_label.visible = not is_paused
	if control_help_label:
		control_help_label.visible = not is_paused
	if instruction_label and is_paused:
		instruction_label.visible = false
	if combo_label and is_paused:
		combo_label.visible = false
	if warning_overlay and is_paused:
		warning_overlay.modulate.a = 0.0
	if runtime_profiler:
		runtime_profiler.visible = not is_paused


func toggle_pause():
	"""Toggle pause state"""
	paused = not paused
	if pause_menu:
		pause_menu.visible = paused
	if paused:
		refresh_pause_overlay_text()
	set_pause_aux_ui_hidden(paused)
	
	if paused:
		set_game_state("paused")
	elif game_over:
		set_game_state("game_over")
	elif calibration_mode:
		set_game_state("calibration")
	else:
		set_game_state("playing")
	
	# Pause/resume particles and audio
	get_tree().paused = paused
	if audio_music:
		audio_music.stream_paused = paused


func return_to_menu():
	"""Quay lại menu chính"""
	# Dừng tracker trước khi chuyển scene
	stop_hand_tracker()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _input(event):
	if event is InputEventKey and event.pressed and not event.is_echo():
		# is_echo() check prevents repeated triggers when holding key
		match event.keycode:
			KEY_F3:
				# Toggle debug mode
				debug_mode = not debug_mode
				print("Debug mode: ", "ON" if debug_mode else "OFF")
			KEY_F4:
				# Bắt đầu calibration
				start_calibration()
			KEY_F9:
				# Toggle control mode: Hand -> KB/Mouse -> Hybrid
				cycle_control_mode()
			KEY_F5:
				# Ship part: body (Shift+F5 để lùi variant)
				if spaceship and spaceship.has_method("cycle_ship_part"):
					print("Ship customization: ", spaceship.cycle_ship_part("body", -1 if event.shift_pressed else 1))
			KEY_F6:
				# Ship part: wings
				if spaceship and spaceship.has_method("cycle_ship_part"):
					print("Ship customization: ", spaceship.cycle_ship_part("wings", -1 if event.shift_pressed else 1))
			KEY_F7:
				# Ship part: tail
				if spaceship and spaceship.has_method("cycle_ship_part"):
					print("Ship customization: ", spaceship.cycle_ship_part("tail", -1 if event.shift_pressed else 1))
			KEY_F8:
				# Ship part: engine
				if spaceship and spaceship.has_method("cycle_ship_part"):
					print("Ship customization: ", spaceship.cycle_ship_part("engine", -1 if event.shift_pressed else 1))
			KEY_5:
				if spaceship and spaceship.has_method("cycle_ship_color"):
					print("Ship colors: ", spaceship.cycle_ship_color("body", -1 if event.shift_pressed else 1))
			KEY_6:
				if spaceship and spaceship.has_method("cycle_ship_color"):
					print("Ship colors: ", spaceship.cycle_ship_color("wings", -1 if event.shift_pressed else 1))
			KEY_7:
				if spaceship and spaceship.has_method("cycle_ship_color"):
					print("Ship colors: ", spaceship.cycle_ship_color("tail", -1 if event.shift_pressed else 1))
			KEY_8:
				if spaceship and spaceship.has_method("cycle_ship_color"):
					print("Ship colors: ", spaceship.cycle_ship_color("engine", -1 if event.shift_pressed else 1))
			KEY_1:
				# Preset: Default
				if spaceship:
					spaceship.set_control_preset("default")
			KEY_2:
				# Preset: Sensitive
				if spaceship:
					spaceship.set_control_preset("sensitive")
			KEY_3:
				# Preset: Smooth
				if spaceship:
					spaceship.set_control_preset("smooth")
			KEY_4:
				# Preset: Beginner
				if spaceship:
					spaceship.set_control_preset("beginner")


func restart_game():
	apply_campaign_level(0, true)


func _exit_tree():
	if udp_server:
		udp_server.close()
	
	# Lưu control config trước khi thoát
	if spaceship and spaceship.has_method("save_control_config"):
		spaceship.save_control_config()
	
	# Dừng tracker process khi game thoát
	stop_hand_tracker()


func _request_tracker_soft_stop():
	if tracker_stop_flag_abs_path.is_empty():
		tracker_stop_flag_abs_path = ProjectSettings.globalize_path(TRACKER_STOP_FLAG_PATH)
	var stop_flag = FileAccess.open(tracker_stop_flag_abs_path, FileAccess.WRITE)
	if stop_flag:
		stop_flag.store_line("stop")
		stop_flag.flush()
	else:
		print("Warning: failed to create tracker stop flag at ", tracker_stop_flag_abs_path)


func _remove_tracker_stop_flag_if_present():
	if tracker_stop_flag_abs_path.is_empty():
		return
	if not FileAccess.file_exists(tracker_stop_flag_abs_path):
		return
	var remove_err = DirAccess.remove_absolute(tracker_stop_flag_abs_path)
	if remove_err != OK and remove_err != ERR_DOES_NOT_EXIST:
		print("Warning: failed to clear tracker stop flag (error ", remove_err, ")")


func stop_hand_tracker():
	"""Dừng hand tracker process hiện tại."""
	if tracker_pid > 0:
		print("Stopping Hand Tracker (PID: ", tracker_pid, ")...")
		if OS.is_process_running(tracker_pid):
			_request_tracker_soft_stop()
			var wait_start = Time.get_ticks_msec()
			while OS.is_process_running(tracker_pid):
				if Time.get_ticks_msec() - wait_start >= TRACKER_STOP_WAIT_TIMEOUT_MS:
					break
				OS.delay_msec(TRACKER_STOP_POLL_INTERVAL_MS)
		
		if OS.is_process_running(tracker_pid):
			print("Tracker did not stop gracefully, forcing termination...")
			OS.kill(tracker_pid)
	
	_remove_tracker_stop_flag_if_present()
	tracker_pid = -1
	tracker_running = false


func start_calibration():
	"""Bắt đầu quá trình calibration"""
	if not hand_data.get("found", false):
		print("Cannot calibrate - no hands detected!")
		return
	
	calibration_mode = true
	calibration_progress = 0
	set_game_state("calibration")
	if spaceship:
		spaceship.calibrate()
	
	print("Calibration started - hold hands steady in neutral position")
	if calibration_label:
		calibration_label.visible = true
		calibration_label.text = "CALIBRATING...\nHold wheel steady ~2 giây ở vị trí neutral\n0%"


func process_calibration():
	"""Xử lý từng frame calibration"""
	if not calibration_mode:
		return
	
	if not hand_data.get("found", false):
		if calibration_label:
			var progress_percent: int = int(round(float(calibration_progress) * 100.0 / float(CALIBRATION_SAMPLE_TARGET)))
			calibration_label.text = "CALIBRATING...\nShow both hands!\n%d%%" % progress_percent
		return
	
	if spaceship and spaceship.has_method("apply_calibration_sample"):
		var done = spaceship.apply_calibration_sample(hand_data)
		calibration_progress += 1
		
		if calibration_label:
			var progress_percent: int = int(round(float(calibration_progress) * 100.0 / float(CALIBRATION_SAMPLE_TARGET)))
			calibration_label.text = "CALIBRATING...\nHold steady!\n%d%%" % progress_percent
		
		if done:
			finish_calibration()


func finish_calibration():
	"""Hoàn tất calibration"""
	calibration_mode = false
	calibration_progress = 0
	if game_over:
		set_game_state("game_over")
	elif paused:
		set_game_state("paused")
	else:
		set_game_state("playing")
	
	if spaceship and spaceship.has_method("save_control_config"):
		spaceship.save_control_config()
	
	print("Calibration complete!")
	
	if calibration_label:
		calibration_label.text = "CALIBRATION COMPLETE!"
		# Ẩn sau 2 giây
		var timer = get_tree().create_timer(2.0)
		timer.timeout.connect(func(): calibration_label.visible = false)


func load_high_score():
	var config = ConfigFile.new()
	var err = config.load("user://highscore.cfg")
	if err == OK:
		high_score = config.get_value("game", "high_score", 0)


func save_high_score():
	var config = ConfigFile.new()
	config.set_value("game", "high_score", high_score)
	config.save("user://highscore.cfg")


func draw_debug():
	# Chỉ vẽ nếu DebugDraw3D có sẵn
	if not Engine.has_singleton("DebugDraw3D"):
		# Fallback: check if class exists
		if not ClassDB.class_exists("DebugDraw3D"):
			return
	
	# Spaceship collision size (phải khớp với check_collisions)
	const SHIP_SIZE = Vector3(0.8, 0.3, 1.6)  # 2 * half sizes
	
	# Draw spaceship collision box
	if spaceship:
		var ship_pos = spaceship.position
		# is_box_centered=true để box trùng với collision AABB (centered at ship_pos)
		DebugDraw3D.draw_box(ship_pos, Quaternion.IDENTITY, SHIP_SIZE, Color.CYAN, true)
		
		# Draw position marker
		DebugDraw3D.draw_sphere(ship_pos, 0.1, Color.GREEN)
	
	# Draw track bounds (lane boundaries)
	if spaceship:
		var player_z = spaceship.position.z
		for boundary_x in [-8.2, 8.2]:
			DebugDraw3D.draw_line(Vector3(boundary_x, -6.0, player_z - 25.0), Vector3(boundary_x, -6.0, player_z + 10.0), Color(0.4, 0.4, 1.0))
	
	# Draw obstacle collision boxes
	for obs in obstacles:
		if is_instance_valid(obs):
			var obs_pos = obs.position
			var obs_size = obs.obstacle_size
			# is_box_centered=true để box trùng với collision AABB (centered at obs_pos)
			DebugDraw3D.draw_box(obs_pos, Quaternion.IDENTITY, obs_size, Color.RED, true)
	
	# Draw rival collision boxes with distance info
	for rival_data in rival_ships:
		var rival_node = rival_data.get("node")
		if is_instance_valid(rival_node):
			DebugDraw3D.draw_box(rival_node.position, Quaternion.IDENTITY, Vector3(0.84, 0.32, 1.64), Color.YELLOW, true)
			# Draw lane position marker
			var lane = float(rival_data.get("lane", 0.0))
			DebugDraw3D.draw_sphere(Vector3(lane, -6.0, rival_node.position.z), 0.08, Color.WHITE)
	
	# Draw hand tracking info on 2D overlay
	if hand_data["found"]:
		DebugDraw2D.set_text("Hand X", "%.2f" % hand_data["mid_x"])
		DebugDraw2D.set_text("Hand Y", "%.2f" % hand_data["mid_y"])
		DebugDraw2D.set_text("Hand Angle", "%.2f°" % rad_to_deg(hand_data["angle"]))
	DebugDraw2D.set_text("Wheel Depth", "%.2f" % hand_data["distance"])
	
	DebugDraw2D.set_text("Obstacles", obstacles.size())
	DebugDraw2D.set_text("Obstacle Pool", obstacle_pool.size())
	DebugDraw2D.set_text("Game State", str(game_state_stack.current) if game_state_stack else "unknown")
	DebugDraw2D.set_text("Spawn Interval", "%.2fs" % current_spawn_interval)
	DebugDraw2D.set_text("Speed", "%.1fx" % speed_multiplier)
	DebugDraw2D.set_text("Player Dist", "%.1fm" % player_race_distance)
	DebugDraw2D.set_text("Rivals", rival_ships.size())
	for i in range(rival_ships.size()):
		var rival_data = rival_ships[i]
		var rival_dist = float(rival_data.get("distance", 0.0))
		DebugDraw2D.set_text("Rival %d Dist" % (i + 1), "%.1fm" % rival_dist)
