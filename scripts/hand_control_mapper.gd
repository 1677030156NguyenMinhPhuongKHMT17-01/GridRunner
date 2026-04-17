extends RefCounted
class_name HandControlMapper

## Steering-wheel style mapping for hand tracking packet:
## {found, mid_x, mid_y, angle, distance, hands}
## - angle: wheel vector angle in radians
## - distance: normalized wheel depth (0..1), where higher = farther from camera

enum GestureType {
	NONE,
	MOVE,
	TILT,
	BOOST,
	BRAKE,
	HANDS_UP,
	HANDS_DOWN,
	HANDS_LEFT,
	HANDS_RIGHT,
	DRIFT,
	ITEM_USE,
	ITEM_NEXT,
}

enum GripMode {
	HORIZONTAL,
	VERTICAL,
}


class ControlOutput:
	var move_x: float = 0.0
	var move_y: float = 0.0
	var roll: float = 0.0
	var speed: float = 1.0
	var gesture: int = GestureType.NONE
	var is_valid: bool = false
	var steering: float = 0.0
	var throttle: float = 0.0
	var brake: float = 0.0
	
	func _to_string() -> String:
		return "Control(valid=%s, steer=%.2f, throttle=%.2f, brake=%.2f, speed=%.2f)" % [
			str(is_valid),
			steering,
			throttle,
			brake,
			speed,
		]


# ============================================================
# CALIBRATION + MAPPING SETTINGS
# ============================================================

var grip_mode: int = GripMode.HORIZONTAL

var dead_zone_y: float = 0.02
var steering_dead_zone: float = 0.04
var depth_dead_zone: float = 0.015

var sensitivity_x: float = 2.0
var sensitivity_y: float = 1.9
var sensitivity_roll: float = 1.0

var active_area_min_y: float = 0.12
var active_area_max_y: float = 0.88

var center_x: float = 0.5
var center_y: float = 0.5
var center_angle: float = 0.0
var neutral_depth: float = 0.5

var max_steering_angle_degrees: float = 60.0
var max_move_x: float = 9.0
var max_move_y: float = 5.0
var max_roll_degrees: float = 30.0

var throttle_sensitivity: float = 3.2
var brake_sensitivity: float = 3.0
var max_throttle_boost: float = 1.5
var max_brake_cut: float = 0.6
var min_speed_multiplier: float = 0.5
var max_speed_multiplier: float = 2.5

var smoothing_factor: float = 0.12
var response_power_xy: float = 0.9
var response_power_steering: float = 0.9

var drift_angle_threshold_degrees: float = 45.0
var drift_speed_threshold: float = 1.08
var boost_shake_steering_threshold: float = 0.35
var boost_shake_window_sec: float = 0.30
var boost_shake_switches_required: int = 2
var boost_push_velocity_threshold: float = 1.4
var boost_cooldown_sec: float = 0.45
var item_raise_velocity_threshold: float = 0.65
var item_raise_min_offset: float = 0.08
var item_trigger_cooldown_sec: float = 0.55
var item_next_cooldown_sec: float = 0.40

var lost_hand_hold_time: float = 0.5
var lost_hand_fade_time: float = 0.55


# ============================================================
# INTERNAL STATE
# ============================================================

var _last_output: ControlOutput = ControlOutput.new()
var _last_valid_output: ControlOutput = ControlOutput.new()
var _calibrated: bool = false
var _calibration_samples: Array = []
const CALIBRATION_SAMPLE_COUNT: int = 120

var _time_seconds: float = 0.0
var _last_center_y: float = 0.5
var _last_depth: float = 0.5
var _lost_tracking_time: float = 0.0
var _last_hands_count: int = 0
var _boost_cooldown_timer: float = 0.0
var _item_cooldown_timer: float = 0.0
var _item_next_cooldown_timer: float = 0.0
var _last_shake_sign: int = 0
var _shake_switch_times: Array = []


# ============================================================
# PUBLIC METHODS
# ============================================================

func process_hand_data(hand_data: Dictionary, delta: float = 1.0 / 60.0) -> ControlOutput:
	var safe_delta = max(delta, 0.0001)
	_time_seconds += safe_delta
	_boost_cooldown_timer = max(0.0, _boost_cooldown_timer - safe_delta)
	_item_cooldown_timer = max(0.0, _item_cooldown_timer - safe_delta)
	_item_next_cooldown_timer = max(0.0, _item_next_cooldown_timer - safe_delta)
	
	var hands_count = int(hand_data.get("hands", 0))
	var found = bool(hand_data.get("found", false))
	
	if not found:
		var missing_output = _process_missing_tracking(safe_delta, hands_count)
		_last_hands_count = hands_count
		return missing_output
	
	var raw_x = float(hand_data.get("mid_x", 0.5))
	var raw_y = float(hand_data.get("mid_y", 0.5))
	var raw_angle = _prepare_angle_for_mode(float(hand_data.get("angle", 0.0)))
	var raw_depth = float(hand_data.get("distance", 0.5))
	
	_lost_tracking_time = 0.0
	
	var y_velocity = (raw_y - _last_center_y) / safe_delta
	var depth_velocity = (raw_depth - _last_depth) / safe_delta
	_last_center_y = raw_y
	_last_depth = raw_depth
	
	var output = ControlOutput.new()
	output.is_valid = true
	
	# Steering from wheel angle relative to neutral.
	var centered_angle = _wrap_angle(raw_angle - center_angle)
	var steering_norm = centered_angle / max(0.001, deg_to_rad(max_steering_angle_degrees))
	steering_norm = clamp(steering_norm, -1.0, 1.0)
	steering_norm = _apply_dead_zone(steering_norm, steering_dead_zone)
	steering_norm = _apply_response_curve(steering_norm, response_power_steering)
	output.steering = steering_norm
	output.roll = clamp(steering_norm * sensitivity_roll, -1.0, 1.0)
	output.move_x = clamp(steering_norm * sensitivity_x, -1.0, 1.0)
	
	# Optional vertical offset mapping.
	var range_y = max(0.001, (active_area_max_y - active_area_min_y) * 0.5)
	var centered_y = (center_y - raw_y) / range_y
	centered_y = clamp(centered_y, -1.5, 1.5)
	centered_y = _apply_dead_zone(centered_y, dead_zone_y)
	centered_y = _apply_response_curve(centered_y, response_power_xy)
	output.move_y = clamp(centered_y * sensitivity_y, -1.0, 1.0)
	
	# Depth-based throttle/brake.
	var delta_depth = raw_depth - neutral_depth
	if abs(delta_depth) < depth_dead_zone:
		delta_depth = 0.0
	
	if delta_depth > 0.0:
		output.throttle = clamp(delta_depth * throttle_sensitivity, 0.0, 1.0)
		output.brake = 0.0
	else:
		output.throttle = 0.0
		output.brake = clamp(-delta_depth * brake_sensitivity, 0.0, 1.0)
	
	output.speed = clamp(
		1.0 + output.throttle * max_throttle_boost - output.brake * max_brake_cut,
		min_speed_multiplier,
		max_speed_multiplier
	)
	
	var steering_abs_deg = abs(rad_to_deg(centered_angle))
	output.gesture = _detect_gesture(output, steering_abs_deg, raw_y, y_velocity, delta_depth, depth_velocity)
	
	_last_valid_output = _clone_output(output)
	_last_hands_count = hands_count
	return _apply_smoothing(output)


func calibrate_center(hand_data: Dictionary) -> bool:
	if not bool(hand_data.get("found", false)):
		return false
	
	_calibration_samples.append({
		"x": float(hand_data.get("mid_x", 0.5)),
		"y": float(hand_data.get("mid_y", 0.5)),
		"angle": _prepare_angle_for_mode(float(hand_data.get("angle", 0.0))),
		"depth": float(hand_data.get("distance", 0.5)),
	})
	
	if _calibration_samples.size() < CALIBRATION_SAMPLE_COUNT:
		return false
	
	var sum_x = 0.0
	var sum_y = 0.0
	var sum_depth = 0.0
	var sum_sin = 0.0
	var sum_cos = 0.0
	
	for sample in _calibration_samples:
		var s: Dictionary = sample
		sum_x += float(s["x"])
		sum_y += float(s["y"])
		sum_depth += float(s["depth"])
		var a = float(s["angle"])
		sum_sin += sin(a)
		sum_cos += cos(a)
	
	var count = float(_calibration_samples.size())
	center_x = sum_x / count
	center_y = sum_y / count
	neutral_depth = sum_depth / count
	center_angle = atan2(sum_sin / count, sum_cos / count)
	
	_calibration_samples.clear()
	_calibrated = true
	_last_center_y = center_y
	_last_depth = neutral_depth
	_lost_tracking_time = 0.0
	_last_output = ControlOutput.new()
	_last_valid_output = ControlOutput.new()
	
	print(
		"Calibration complete: center=(%.2f, %.2f), neutral_depth=%.3f, angle=%.2f, mode=%s" %
		[center_x, center_y, neutral_depth, center_angle, get_grip_mode_name()]
	)
	return true


func reset_calibration():
	center_x = 0.5
	center_y = 0.5
	center_angle = 0.0
	neutral_depth = 0.5
	_calibrated = false
	_calibration_samples.clear()
	_lost_tracking_time = 0.0
	_last_center_y = center_y
	_last_depth = neutral_depth
	_last_output = ControlOutput.new()
	_last_valid_output = ControlOutput.new()


func is_calibrated() -> bool:
	return _calibrated


func set_grip_mode(mode_name: String):
	var normalized = mode_name.strip_edges().to_lower()
	if normalized == "vertical" or normalized == "doc":
		grip_mode = GripMode.VERTICAL
	else:
		grip_mode = GripMode.HORIZONTAL


func set_grip_mode_index(mode_index: int):
	grip_mode = GripMode.VERTICAL if mode_index == GripMode.VERTICAL else GripMode.HORIZONTAL


func get_grip_mode_name() -> String:
	return "vertical" if grip_mode == GripMode.VERTICAL else "horizontal"


func get_game_position(output: ControlOutput) -> Vector3:
	return Vector3(
		output.move_x * max_move_x,
		output.move_y * max_move_y,
		0.0
	)


func get_game_rotation(output: ControlOutput) -> float:
	return output.roll * max_roll_degrees


# ============================================================
# PRESETS
# ============================================================

func apply_preset_default():
	sensitivity_x = 2.0
	sensitivity_y = 1.9
	sensitivity_roll = 1.0
	steering_dead_zone = 0.04
	dead_zone_y = 0.02
	depth_dead_zone = 0.015
	smoothing_factor = 0.12
	throttle_sensitivity = 3.2
	brake_sensitivity = 3.0


func apply_preset_sensitive():
	sensitivity_x = 2.8
	sensitivity_y = 2.5
	sensitivity_roll = 1.3
	steering_dead_zone = 0.03
	dead_zone_y = 0.015
	depth_dead_zone = 0.012
	smoothing_factor = 0.07
	throttle_sensitivity = 3.6
	brake_sensitivity = 3.4


func apply_preset_smooth():
	sensitivity_x = 1.7
	sensitivity_y = 1.6
	sensitivity_roll = 0.8
	steering_dead_zone = 0.05
	dead_zone_y = 0.03
	depth_dead_zone = 0.02
	smoothing_factor = 0.2
	throttle_sensitivity = 2.8
	brake_sensitivity = 2.8


func apply_preset_beginner():
	sensitivity_x = 1.4
	sensitivity_y = 1.3
	sensitivity_roll = 0.65
	steering_dead_zone = 0.07
	dead_zone_y = 0.045
	depth_dead_zone = 0.025
	smoothing_factor = 0.25
	throttle_sensitivity = 2.2
	brake_sensitivity = 2.2
	max_move_x = 7.0
	max_move_y = 4.0


# ============================================================
# SERIALIZATION
# ============================================================

func save_config(path: String) -> bool:
	var config = ConfigFile.new()
	
	config.set_value("wheel", "grip_mode", grip_mode)
	config.set_value("wheel", "max_steering_angle_deg", max_steering_angle_degrees)
	config.set_value("wheel", "throttle_sensitivity", throttle_sensitivity)
	config.set_value("wheel", "brake_sensitivity", brake_sensitivity)
	config.set_value("wheel", "depth_dead_zone", depth_dead_zone)
	config.set_value("wheel", "neutral_depth", neutral_depth)
	config.set_value("wheel", "drift_angle_threshold_deg", drift_angle_threshold_degrees)
	
	config.set_value("sensitivity", "x", sensitivity_x)
	config.set_value("sensitivity", "y", sensitivity_y)
	config.set_value("sensitivity", "roll", sensitivity_roll)
	
	config.set_value("dead_zone", "y", dead_zone_y)
	config.set_value("dead_zone", "steering", steering_dead_zone)
	
	config.set_value("calibration", "center_x", center_x)
	config.set_value("calibration", "center_y", center_y)
	config.set_value("calibration", "center_angle", center_angle)
	
	config.set_value("limits", "max_move_x", max_move_x)
	config.set_value("limits", "max_move_y", max_move_y)
	config.set_value("limits", "max_roll_degrees", max_roll_degrees)
	config.set_value("limits", "min_speed_multiplier", min_speed_multiplier)
	config.set_value("limits", "max_speed_multiplier", max_speed_multiplier)
	
	config.set_value("smoothing", "factor", smoothing_factor)
	config.set_value("response", "xy_power", response_power_xy)
	config.set_value("response", "steering_power", response_power_steering)
	
	config.set_value("gesture", "boost_push_velocity", boost_push_velocity_threshold)
	config.set_value("gesture", "boost_shake_threshold", boost_shake_steering_threshold)
	config.set_value("gesture", "item_raise_velocity", item_raise_velocity_threshold)
	
	return config.save(path) == OK


func load_config(path: String) -> bool:
	var config = ConfigFile.new()
	if config.load(path) != OK:
		return false
	
	grip_mode = int(config.get_value("wheel", "grip_mode", grip_mode))
	max_steering_angle_degrees = float(config.get_value("wheel", "max_steering_angle_deg", max_steering_angle_degrees))
	throttle_sensitivity = float(config.get_value("wheel", "throttle_sensitivity", throttle_sensitivity))
	brake_sensitivity = float(config.get_value("wheel", "brake_sensitivity", brake_sensitivity))
	depth_dead_zone = float(config.get_value("wheel", "depth_dead_zone", depth_dead_zone))
	neutral_depth = float(config.get_value("wheel", "neutral_depth", neutral_depth))
	drift_angle_threshold_degrees = float(config.get_value("wheel", "drift_angle_threshold_deg", drift_angle_threshold_degrees))
	
	sensitivity_x = float(config.get_value("sensitivity", "x", sensitivity_x))
	sensitivity_y = float(config.get_value("sensitivity", "y", sensitivity_y))
	sensitivity_roll = float(config.get_value("sensitivity", "roll", sensitivity_roll))
	
	dead_zone_y = float(config.get_value("dead_zone", "y", dead_zone_y))
	steering_dead_zone = float(config.get_value("dead_zone", "steering", steering_dead_zone))
	
	center_x = float(config.get_value("calibration", "center_x", center_x))
	center_y = float(config.get_value("calibration", "center_y", center_y))
	center_angle = float(config.get_value("calibration", "center_angle", center_angle))
	
	max_move_x = float(config.get_value("limits", "max_move_x", max_move_x))
	max_move_y = float(config.get_value("limits", "max_move_y", max_move_y))
	max_roll_degrees = float(config.get_value("limits", "max_roll_degrees", max_roll_degrees))
	min_speed_multiplier = float(config.get_value("limits", "min_speed_multiplier", min_speed_multiplier))
	max_speed_multiplier = float(config.get_value("limits", "max_speed_multiplier", max_speed_multiplier))
	
	smoothing_factor = float(config.get_value("smoothing", "factor", smoothing_factor))
	response_power_xy = float(config.get_value("response", "xy_power", response_power_xy))
	response_power_steering = float(config.get_value("response", "steering_power", response_power_steering))
	
	boost_push_velocity_threshold = float(config.get_value("gesture", "boost_push_velocity", boost_push_velocity_threshold))
	boost_shake_steering_threshold = float(config.get_value("gesture", "boost_shake_threshold", boost_shake_steering_threshold))
	item_raise_velocity_threshold = float(config.get_value("gesture", "item_raise_velocity", item_raise_velocity_threshold))
	
	grip_mode = GripMode.VERTICAL if grip_mode == GripMode.VERTICAL else GripMode.HORIZONTAL
	max_steering_angle_degrees = clamp(max_steering_angle_degrees, 25.0, 90.0)
	neutral_depth = clamp(neutral_depth, 0.0, 1.0)
	min_speed_multiplier = clamp(min_speed_multiplier, 0.25, 1.0)
	max_speed_multiplier = clamp(max_speed_multiplier, 1.0, 3.5)
	
	_calibrated = true
	_last_center_y = center_y
	_last_depth = neutral_depth
	return true


# ============================================================
# PRIVATE HELPERS
# ============================================================

func _detect_gesture(
	output: ControlOutput,
	steering_abs_deg: float,
	raw_y: float,
	y_velocity: float,
	delta_depth: float,
	depth_velocity: float
) -> int:
	var shake_trigger = _update_shake_detection(output.steering)
	var push_trigger = depth_velocity > boost_push_velocity_threshold and delta_depth > depth_dead_zone * 0.5
	
	if (shake_trigger or push_trigger) and _boost_cooldown_timer <= 0.0:
		_boost_cooldown_timer = boost_cooldown_sec
		return GestureType.BOOST
	
	var wheel_raised = y_velocity < -item_raise_velocity_threshold and (center_y - raw_y) > item_raise_min_offset
	if wheel_raised and _item_cooldown_timer <= 0.0:
		_item_cooldown_timer = item_trigger_cooldown_sec
		return GestureType.ITEM_USE
	
	if steering_abs_deg >= drift_angle_threshold_degrees and output.speed >= drift_speed_threshold:
		return GestureType.DRIFT
	
	if output.brake > 0.2:
		return GestureType.BRAKE
	
	if abs(output.steering) > 0.45:
		return GestureType.TILT
	
	if abs(output.move_x) > 0.2 or abs(output.move_y) > 0.2:
		return GestureType.MOVE
	
	return GestureType.NONE


func _update_shake_detection(steering: float) -> bool:
	var now = _time_seconds
	while _shake_switch_times.size() > 0 and now - float(_shake_switch_times[0]) > boost_shake_window_sec:
		_shake_switch_times.remove_at(0)
	
	if abs(steering) < boost_shake_steering_threshold:
		_last_shake_sign = 0
		return false
	
	var sign_val = -1 if steering < 0.0 else 1
	if _last_shake_sign != 0 and sign_val != _last_shake_sign:
		_shake_switch_times.append(now)
	_last_shake_sign = sign_val
	
	if _shake_switch_times.size() >= boost_shake_switches_required:
		_shake_switch_times.clear()
		return true
	return false


func _process_missing_tracking(delta: float, hands_count: int) -> ControlOutput:
	var output = _clone_output(_last_valid_output)
	output.is_valid = false
	output.gesture = GestureType.NONE
	output.throttle = 0.0
	
	if hands_count == 1 and _last_hands_count == 2 and _item_next_cooldown_timer <= 0.0:
		output.gesture = GestureType.ITEM_NEXT
		_item_next_cooldown_timer = item_next_cooldown_sec
	
	_lost_tracking_time += delta
	
	if _lost_tracking_time <= lost_hand_hold_time:
		var hold_ratio = _lost_tracking_time / max(0.001, lost_hand_hold_time)
		output.speed = lerp(_last_valid_output.speed, 1.0, hold_ratio)
		return _apply_smoothing(output)
	
	var fade_ratio = clamp((_lost_tracking_time - lost_hand_hold_time) / max(0.001, lost_hand_fade_time), 0.0, 1.0)
	output.move_x = lerp(_last_valid_output.move_x, 0.0, fade_ratio)
	output.move_y = lerp(_last_valid_output.move_y, 0.0, fade_ratio)
	output.roll = lerp(_last_valid_output.roll, 0.0, fade_ratio)
	output.steering = lerp(_last_valid_output.steering, 0.0, fade_ratio)
	output.brake = lerp(_last_valid_output.brake, 0.0, fade_ratio)
	output.speed = lerp(_last_valid_output.speed, 1.0, fade_ratio)
	return _apply_smoothing(output)


func _prepare_angle_for_mode(raw_angle: float) -> float:
	if grip_mode == GripMode.VERTICAL:
		return _wrap_angle(raw_angle - PI * 0.5)
	return _wrap_angle(raw_angle)


func _wrap_angle(value: float) -> float:
	var wrapped = fmod(value + PI, TAU)
	if wrapped < 0.0:
		wrapped += TAU
	return wrapped - PI


func _clone_output(source: ControlOutput) -> ControlOutput:
	var cloned = ControlOutput.new()
	cloned.move_x = source.move_x
	cloned.move_y = source.move_y
	cloned.roll = source.roll
	cloned.speed = source.speed
	cloned.gesture = source.gesture
	cloned.is_valid = source.is_valid
	cloned.steering = source.steering
	cloned.throttle = source.throttle
	cloned.brake = source.brake
	return cloned


func _apply_dead_zone(value: float, dead_zone: float) -> float:
	if abs(value) < dead_zone:
		return 0.0
	var sign_val = -1.0 if value < 0.0 else 1.0
	var abs_val = abs(value)
	return sign_val * (abs_val - dead_zone) / max(0.001, (1.0 - dead_zone))


func _apply_response_curve(value: float, power: float) -> float:
	if power <= 0.0:
		return value
	var sign_val = -1.0 if value < 0.0 else 1.0
	var abs_val = abs(value)
	if abs_val <= 1.0:
		return sign_val * pow(abs_val, power)
	return value


func _apply_smoothing(output: ControlOutput) -> ControlOutput:
	if smoothing_factor <= 0.0:
		_last_output = output
		return output
	
	var smoothed = ControlOutput.new()
	smoothed.is_valid = output.is_valid
	smoothed.gesture = output.gesture
	
	smoothed.move_x = lerp(_last_output.move_x, output.move_x, 1.0 - smoothing_factor)
	smoothed.move_y = lerp(_last_output.move_y, output.move_y, 1.0 - smoothing_factor)
	smoothed.roll = lerp(_last_output.roll, output.roll, 1.0 - smoothing_factor)
	smoothed.speed = lerp(_last_output.speed, output.speed, 1.0 - smoothing_factor)
	smoothed.steering = lerp(_last_output.steering, output.steering, 1.0 - smoothing_factor)
	smoothed.throttle = lerp(_last_output.throttle, output.throttle, 1.0 - smoothing_factor)
	smoothed.brake = lerp(_last_output.brake, output.brake, 1.0 - smoothing_factor)
	
	_last_output = smoothed
	return smoothed
