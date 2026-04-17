extends Control


var _tracker_connected: bool = false
var _tracking_found: bool = false
var _wheel_angle: float = 0.0
var _wheel_depth: float = 0.5
var _mid_x: float = 0.5
var _mid_y: float = 0.5


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_tracking_state(packet: Dictionary, connected_state: bool):
	_tracker_connected = connected_state
	_tracking_found = bool(packet.get("found", false))
	_wheel_angle = float(packet.get("angle", 0.0))
	_wheel_depth = clampf(float(packet.get("distance", 0.5)), 0.0, 1.0)
	_mid_x = clampf(float(packet.get("mid_x", 0.5)), 0.0, 1.0)
	_mid_y = clampf(float(packet.get("mid_y", 0.5)), 0.0, 1.0)
	queue_redraw()


func _notification(what: int):
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw():
	var rect := Rect2(Vector2.ZERO, size)
	if rect.size.x <= 2.0 or rect.size.y <= 2.0:
		return
	
	draw_rect(rect, Color(0.06, 0.08, 0.11, 0.86), true)
	
	var wheel_center := Vector2(rect.size.x * 0.34, rect.size.y * 0.48)
	var radius: float = minf(rect.size.x * 0.25, rect.size.y * 0.37)
	radius = maxf(radius, 18.0)
	
	var status_color := Color(1.0, 0.38, 0.38)
	if _tracker_connected and _tracking_found:
		status_color = Color(0.25, 1.0, 0.74)
	elif _tracker_connected:
		status_color = Color(1.0, 0.85, 0.35)
	
	draw_arc(wheel_center, radius, 0.0, TAU, 64, status_color, 4.0, true)
	
	var heading := Vector2(cos(_wheel_angle), sin(_wheel_angle))
	var tangent := Vector2(-heading.y, heading.x)
	draw_line(
		wheel_center - heading * radius * 0.72,
		wheel_center + heading * radius * 0.72,
		status_color,
		4.0,
		true
	)
	draw_line(
		wheel_center - tangent * radius * 0.52,
		wheel_center + tangent * radius * 0.52,
		status_color * Color(1.0, 1.0, 1.0, 0.75),
		3.0,
		true
	)
	
	var marker_offset := Vector2((_mid_x - 0.5) * radius * 1.2, (_mid_y - 0.5) * radius * 1.2)
	draw_circle(wheel_center + marker_offset, 4.5, Color.WHITE)
	draw_circle(wheel_center, 6.0, status_color)
	
	var bar_rect := Rect2(
		Vector2(rect.size.x * 0.72, 10.0),
		Vector2(rect.size.x * 0.18, maxf(12.0, rect.size.y - 20.0))
	)
	draw_rect(bar_rect, Color(0.02, 0.03, 0.05, 0.92), true)
	draw_rect(bar_rect, Color(0.5, 0.58, 0.72, 0.7), false, 2.0)
	
	var neutral_y := bar_rect.position.y + bar_rect.size.y * 0.5
	draw_line(
		Vector2(bar_rect.position.x, neutral_y),
		Vector2(bar_rect.end.x, neutral_y),
		Color(0.92, 0.92, 0.92, 0.5),
		1.0,
		true
	)
	
	var fill_height := bar_rect.size.y * _wheel_depth
	var fill_rect := Rect2(
		Vector2(bar_rect.position.x + 3.0, bar_rect.end.y - fill_height),
		Vector2(maxf(0.0, bar_rect.size.x - 6.0), fill_height)
	)
	draw_rect(fill_rect, status_color * Color(1.0, 1.0, 1.0, 0.8), true)
