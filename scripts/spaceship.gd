extends Node3D
## Spaceship Controller with Part Customization + Improved Steering

# Hand Control Mapper
var control_mapper: HandControlMapper

# Movement
var target_position: Vector3 = Vector3.ZERO
var target_roll: float = 0.0
var speed_boost: float = 1.0
var preview_mode: bool = false

# Steering feel (frame-rate independent)
var steer_response: float = 11.0
var roll_response: float = 13.0
var neutral_return_response: float = 7.0
var speed_response: float = 8.0
var bank_from_lateral_velocity: float = 1.2
var max_dynamic_bank: float = 9.0

# Materials
var body_material: StandardMaterial3D
var wing_material: StandardMaterial3D
var tail_material: StandardMaterial3D
var engine_material: StandardMaterial3D
var engine_base_color: Color = Color(1, 0.5, 0)

# Particles
var engine_particles: GPUParticles3D
var trail_particles: GPUParticles3D
var boost_particles: GPUParticles3D

# Current gesture for visual feedback
var current_gesture: int = 0
var visual_phase: float = 0.0
var _last_control_snapshot: Dictionary = {
	"valid": false,
	"steering": 0.0,
	"throttle": 0.0,
	"brake": 0.0,
	"speed": 1.0,
	"gesture": HandControlMapper.GestureType.NONE,
}

# Ship part variants
const BODY_VARIANTS = [
	{
		"name": "Vanguard",
		"mesh": "capsule",
		"radius": 0.28,
		"height": 2.25,
		"offset": Vector3(0, 0, 0.08),
		"rotation": Vector3(90, 0, 0),
		"details": [
			{"mesh": "sphere", "radius": 0.16, "height": 0.32, "offset": Vector3(0, 0.02, -0.95), "scale": Vector3(1.0, 0.7, 1.0)},
			{"mesh": "prism", "size": Vector3(0.34, 0.16, 0.65), "offset": Vector3(0, 0.2, -0.18), "rotation": Vector3(0, 180, 0)},
		],
	},
	{
		"name": "Arrowhead",
		"mesh": "prism",
		"size": Vector3(0.96, 0.42, 2.15),
		"offset": Vector3(0, -0.03, 0.06),
		"rotation": Vector3(0, 180, 0),
		"details": [
			{"mesh": "cylinder", "radius": 0.11, "height": 0.55, "offset": Vector3(0, -0.08, 0.58), "rotation": Vector3(90, 0, 0)},
			{"mesh": "sphere", "radius": 0.17, "height": 0.34, "offset": Vector3(0, 0.03, -0.86), "scale": Vector3(1.0, 0.6, 1.0)},
		],
	},
	{
		"name": "Bulwark",
		"mesh": "cylinder",
		"radius": 0.42,
		"height": 1.85,
		"offset": Vector3(0, 0, 0.03),
		"rotation": Vector3(90, 0, 0),
		"details": [
			{"mesh": "capsule", "radius": 0.18, "height": 0.72, "offset": Vector3(0, 0.26, -0.42), "rotation": Vector3(90, 0, 0)},
			{"mesh": "prism", "size": Vector3(0.38, 0.2, 0.74), "offset": Vector3(0, 0.28, 0.25), "rotation": Vector3(0, 180, 0)},
		],
	},
]

const WING_VARIANTS = [
	{
		"name": "Raptor",
		"mesh": "prism",
		"size": Vector3(1.75, 0.1, 1.18),
		"offset": Vector3(0, 0.0, 0.14),
		"rotation": Vector3(0, 0, 6),
		"details": [
			{"mesh": "cylinder", "radius": 0.06, "height": 0.5, "offset": Vector3(0.72, -0.02, -0.22), "rotation": Vector3(90, 0, 0)},
		],
	},
	{
		"name": "Falcon",
		"mesh": "prism",
		"size": Vector3(1.48, 0.1, 0.96),
		"offset": Vector3(0, 0.02, 0.05),
		"rotation": Vector3(0, 0, 14),
		"details": [
			{"mesh": "capsule", "radius": 0.08, "height": 0.42, "offset": Vector3(0.6, 0.03, 0.2), "rotation": Vector3(0, 0, 90)},
		],
	},
	{
		"name": "Guardian",
		"mesh": "capsule",
		"radius": 0.11,
		"height": 1.65,
		"offset": Vector3(0, -0.01, 0.08),
		"rotation": Vector3(90, 0, 0),
		"scale": Vector3(1.0, 0.65, 1.0),
		"details": [
			{"mesh": "prism", "size": Vector3(0.78, 0.12, 0.55), "offset": Vector3(0.3, 0.0, 0.02), "rotation": Vector3(0, 180, 0)},
		],
	},
]

const TAIL_VARIANTS = [
	{
		"name": "Twin-Fin",
		"mesh": "prism",
		"size": Vector3(0.24, 0.74, 0.32),
		"offset": Vector3(0, 0.05, 0.02),
		"details": [
			{"mesh": "prism", "size": Vector3(0.14, 0.44, 0.2), "offset": Vector3(0.14, 0.04, 0.0), "rotation": Vector3(0, 0, 6)},
			{"mesh": "prism", "size": Vector3(0.14, 0.44, 0.2), "offset": Vector3(-0.14, 0.04, 0.0), "rotation": Vector3(0, 0, -6)},
		],
	},
	{
		"name": "Blade",
		"mesh": "prism",
		"size": Vector3(0.18, 0.9, 0.24),
		"offset": Vector3(0, 0.08, 0.0),
		"rotation": Vector3(0, 180, 0),
		"details": [
			{"mesh": "cylinder", "radius": 0.07, "height": 0.3, "offset": Vector3(0, -0.12, 0.09), "rotation": Vector3(90, 0, 0)},
		],
	},
	{
		"name": "Stabilizer",
		"mesh": "cylinder",
		"radius": 0.13,
		"height": 0.62,
		"offset": Vector3(0, 0.02, 0.0),
		"rotation": Vector3(90, 0, 0),
		"details": [
			{"mesh": "prism", "size": Vector3(0.12, 0.52, 0.22), "offset": Vector3(0.18, 0.08, 0.0)},
			{"mesh": "prism", "size": Vector3(0.12, 0.52, 0.22), "offset": Vector3(-0.18, 0.08, 0.0)},
		],
	},
]

const ENGINE_VARIANTS = [
	{
		"name": "Vector",
		"mesh": "cylinder",
		"radius": 0.18,
		"height": 0.54,
		"rotation": Vector3(90, 0, 0),
		"details": [
			{"mesh": "torus", "inner_radius": 0.05, "outer_radius": 0.22, "offset": Vector3(0, 0, 0.18), "rotation": Vector3(90, 0, 0)},
		],
	},
	{
		"name": "Ion-Core",
		"mesh": "capsule",
		"radius": 0.16,
		"height": 0.62,
		"rotation": Vector3(90, 0, 0),
		"details": [
			{"mesh": "sphere", "radius": 0.09, "height": 0.18, "offset": Vector3(0, 0, -0.24)},
		],
	},
	{
		"name": "Halo",
		"mesh": "torus",
		"inner_radius": 0.07,
		"outer_radius": 0.25,
		"rotation": Vector3(90, 0, 0),
		"details": [
			{"mesh": "cylinder", "radius": 0.08, "height": 0.3, "rotation": Vector3(90, 0, 0)},
		],
	},
]

var body_variant_index: int = 0
var wing_variant_index: int = 0
var tail_variant_index: int = 0
var engine_variant_index: int = 0
var body_color_index: int = 0
var wing_color_index: int = 1
var tail_color_index: int = 2
var engine_color_index: int = 3

const SHIP_COLOR_VARIANTS = [
	{"name": "Arctic White", "color": Color(1.0, 1.0, 1.0)},
	{"name": "Neon Cyan", "color": Color(0.1, 0.95, 1.0)},
	{"name": "Nova Magenta", "color": Color(1.0, 0.25, 0.95)},
	{"name": "Solar Amber", "color": Color(1.0, 0.65, 0.2)},
	{"name": "Plasma Violet", "color": Color(0.72, 0.42, 1.0)},
	{"name": "Pulse Green", "color": Color(0.45, 1.0, 0.55)},
	{"name": "Crimson", "color": Color(1.0, 0.24, 0.24)},
]

# Cache default local offsets from scene
var _default_body_pos: Vector3 = Vector3.ZERO
var _default_wing_left_pos: Vector3 = Vector3.ZERO
var _default_wing_right_pos: Vector3 = Vector3.ZERO
var _default_tail_pos: Vector3 = Vector3.ZERO
var _default_engine_pos: Vector3 = Vector3.ZERO
var _default_body_rot: Vector3 = Vector3.ZERO
var _default_wing_left_rot: Vector3 = Vector3.ZERO
var _default_wing_right_rot: Vector3 = Vector3.ZERO
var _default_tail_rot: Vector3 = Vector3.ZERO
var _default_engine_rot: Vector3 = Vector3.ZERO
var _default_body_scale: Vector3 = Vector3.ONE
var _default_wing_left_scale: Vector3 = Vector3.ONE
var _default_wing_right_scale: Vector3 = Vector3.ONE
var _default_tail_scale: Vector3 = Vector3.ONE
var _default_engine_scale: Vector3 = Vector3.ONE
var _engine_visual_scale_base: Vector3 = Vector3.ONE

# Child nodes
@onready var body = $Body
@onready var wing_left = $WingLeft
@onready var wing_right = $WingRight
@onready var tail = $Tail
@onready var engine = $Engine


func _ready():
	cache_default_part_positions()
	if not preview_mode:
		setup_control_mapper()
	setup_meshes()
	setup_materials()
	setup_particles()
	load_ship_customization()
	if preview_mode:
		set_preview_mode(true)


func cache_default_part_positions():
	_default_body_pos = body.position
	_default_wing_left_pos = wing_left.position
	_default_wing_right_pos = wing_right.position
	_default_tail_pos = tail.position
	_default_engine_pos = engine.position
	_default_body_rot = body.rotation_degrees
	_default_wing_left_rot = wing_left.rotation_degrees
	_default_wing_right_rot = wing_right.rotation_degrees
	_default_tail_rot = tail.rotation_degrees
	_default_engine_rot = engine.rotation_degrees
	_default_body_scale = body.scale
	_default_wing_left_scale = wing_left.scale
	_default_wing_right_scale = wing_right.scale
	_default_tail_scale = tail.scale
	_default_engine_scale = engine.scale


func setup_control_mapper():
	"""Khởi tạo bộ ánh xạ điều khiển"""
	control_mapper = HandControlMapper.new()
	control_mapper.apply_preset_default()
	
	# Load cấu hình đã lưu nếu có
	if control_mapper.load_config("user://hand_control.cfg"):
		print("Loaded hand control config")
	else:
		print("Using default hand control config")
	
	# Áp dụng settings từ main menu (nếu có) mà KHÔNG phá mất các key khác trong hand_control.cfg
	apply_menu_settings()


func setup_meshes():
	apply_all_ship_part_variants()


func _build_mesh_from_variant(variant: Dictionary) -> Mesh:
	var mesh_type := str(variant.get("mesh", "prism"))
	match mesh_type:
		"prism":
			var prism = PrismMesh.new()
			prism.size = _get_variant_vec3(variant, "size", Vector3.ONE)
			return prism
		"sphere":
			var sphere = SphereMesh.new()
			sphere.radius = float(variant.get("radius", 0.2))
			sphere.height = float(variant.get("height", sphere.radius * 2.0))
			return sphere
		"cylinder":
			var cylinder = CylinderMesh.new()
			cylinder.top_radius = float(variant.get("radius", 0.2))
			cylinder.bottom_radius = float(variant.get("radius", 0.2))
			cylinder.height = float(variant.get("height", 0.5))
			return cylinder
		"capsule":
			var capsule = CapsuleMesh.new()
			capsule.radius = float(variant.get("radius", 0.15))
			capsule.height = float(variant.get("height", 0.5))
			return capsule
		"torus":
			var torus = TorusMesh.new()
			torus.inner_radius = float(variant.get("inner_radius", 0.08))
			torus.outer_radius = float(variant.get("outer_radius", 0.24))
			return torus
	
	var fallback = PrismMesh.new()
	fallback.size = Vector3.ONE
	return fallback


func _get_variant_vec3(variant: Dictionary, key: String, default_value: Vector3 = Vector3.ZERO) -> Vector3:
	var value = variant.get(key, default_value)
	return value if value is Vector3 else default_value


func _clear_variant_details(part: MeshInstance3D):
	for child in part.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("VariantDetail"):
			part.remove_child(child)
			child.queue_free()


func _apply_variant_details(part: MeshInstance3D, details: Array, mirror_x: bool = false):
	_clear_variant_details(part)
	var idx = 0
	for entry in details:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var detail: Dictionary = entry
		var detail_node = MeshInstance3D.new()
		detail_node.name = "VariantDetail%d" % idx
		detail_node.mesh = _build_mesh_from_variant(detail)
		
		var detail_pos = _get_variant_vec3(detail, "offset", Vector3.ZERO)
		if mirror_x:
			detail_pos.x = -detail_pos.x
		detail_node.position = detail_pos
		
		var detail_rot = _get_variant_vec3(detail, "rotation", Vector3.ZERO)
		if mirror_x:
			detail_rot.y = -detail_rot.y
			detail_rot.z = -detail_rot.z
		detail_node.rotation_degrees = detail_rot
		
		detail_node.scale = _get_variant_vec3(detail, "scale", Vector3.ONE)
		if part.material_override:
			detail_node.material_override = part.material_override
		part.add_child(detail_node)
		idx += 1


func _apply_part_variant(
	part: MeshInstance3D,
	variant: Dictionary,
	default_pos: Vector3,
	default_rot: Vector3,
	default_scale: Vector3,
	mirror_x: bool = false
):
	part.mesh = _build_mesh_from_variant(variant)
	
	var offset = _get_variant_vec3(variant, "offset", Vector3.ZERO)
	if mirror_x:
		offset.x = -offset.x
	part.position = default_pos + offset
	
	var variant_rot = _get_variant_vec3(variant, "rotation", Vector3.ZERO)
	if mirror_x:
		variant_rot.y = -variant_rot.y
		variant_rot.z = -variant_rot.z
	part.rotation_degrees = default_rot + variant_rot
	
	var scale_multiplier = _get_variant_vec3(variant, "scale", Vector3.ONE)
	part.scale = Vector3(
		default_scale.x * scale_multiplier.x,
		default_scale.y * scale_multiplier.y,
		default_scale.z * scale_multiplier.z
	)
	
	var details = variant.get("details", [])
	if details is Array:
		_apply_variant_details(part, details, mirror_x)
	else:
		_clear_variant_details(part)


func apply_all_ship_part_variants():
	apply_body_variant()
	apply_wing_variant()
	apply_tail_variant()
	apply_engine_variant()


func apply_body_variant():
	var variant: Dictionary = BODY_VARIANTS[body_variant_index]
	_apply_part_variant(body, variant, _default_body_pos, _default_body_rot, _default_body_scale)


func apply_wing_variant():
	var variant: Dictionary = WING_VARIANTS[wing_variant_index]
	_apply_part_variant(wing_left, variant, _default_wing_left_pos, _default_wing_left_rot, _default_wing_left_scale, false)
	_apply_part_variant(wing_right, variant, _default_wing_right_pos, _default_wing_right_rot, _default_wing_right_scale, true)


func apply_tail_variant():
	var variant: Dictionary = TAIL_VARIANTS[tail_variant_index]
	_apply_part_variant(tail, variant, _default_tail_pos, _default_tail_rot, _default_tail_scale)


func apply_engine_variant():
	var variant: Dictionary = ENGINE_VARIANTS[engine_variant_index]
	_apply_part_variant(engine, variant, _default_engine_pos, _default_engine_rot, _default_engine_scale)
	_engine_visual_scale_base = engine.scale


func setup_materials():
	# Body material
	body_material = StandardMaterial3D.new()
	body_material.emission_enabled = true
	body_material.emission_energy_multiplier = 0.8
	
	# Wings material
	wing_material = StandardMaterial3D.new()
	wing_material.emission_enabled = true
	wing_material.emission_energy_multiplier = 0.75
	
	# Tail material
	tail_material = StandardMaterial3D.new()
	tail_material.emission_enabled = true
	tail_material.emission_energy_multiplier = 0.7
	
	# Engine material
	engine_material = StandardMaterial3D.new()
	engine_material.emission_enabled = true
	engine_material.emission_energy_multiplier = 2.0
	
	body.material_override = body_material
	wing_left.material_override = wing_material
	wing_right.material_override = wing_material
	tail.material_override = tail_material
	engine.material_override = engine_material
	
	apply_ship_colors()


func setup_particles():
	# Engine exhaust particles
	engine_particles = GPUParticles3D.new()
	engine_particles.name = "EngineParticles"
	engine_particles.amount = 50
	engine_particles.lifetime = 0.5
	engine_particles.explosiveness = 0.1
	engine_particles.emitting = true
	
	var engine_mat = ParticleProcessMaterial.new()
	engine_mat.direction = Vector3(0, 0, 1)
	engine_mat.spread = 15.0
	engine_mat.initial_velocity_min = 5.0
	engine_mat.initial_velocity_max = 10.0
	engine_mat.gravity = Vector3.ZERO
	engine_mat.scale_min = 0.1
	engine_mat.scale_max = 0.3
	engine_mat.color = Color(1, 0.6, 0.2, 1)
	engine_particles.process_material = engine_mat
	
	var particle_mesh = SphereMesh.new()
	particle_mesh.radius = 0.1
	particle_mesh.height = 0.2
	engine_particles.draw_pass_1 = particle_mesh
	
	engine_particles.position = Vector3(0, 0, 1.2)
	add_child(engine_particles)
	
	# Trail particles
	trail_particles = GPUParticles3D.new()
	trail_particles.name = "TrailParticles"
	trail_particles.amount = 30
	trail_particles.lifetime = 1.0
	trail_particles.emitting = true
	
	var trail_mat = ParticleProcessMaterial.new()
	trail_mat.direction = Vector3(0, 0, 1)
	trail_mat.spread = 5.0
	trail_mat.initial_velocity_min = 2.0
	trail_mat.initial_velocity_max = 4.0
	trail_mat.gravity = Vector3.ZERO
	trail_mat.scale_min = 0.05
	trail_mat.scale_max = 0.15
	trail_mat.color = Color(0, 1, 1, 0.5)
	trail_particles.process_material = trail_mat
	trail_particles.draw_pass_1 = particle_mesh.duplicate()
	
	trail_particles.position = Vector3(0, 0, 1.5)
	add_child(trail_particles)
	
	# Boost particles (when speeding)
	boost_particles = GPUParticles3D.new()
	boost_particles.name = "BoostParticles"
	boost_particles.amount = 80
	boost_particles.lifetime = 0.3
	boost_particles.emitting = false
	
	var boost_mat = ParticleProcessMaterial.new()
	boost_mat.direction = Vector3(0, 0, 1)
	boost_mat.spread = 30.0
	boost_mat.initial_velocity_min = 15.0
	boost_mat.initial_velocity_max = 25.0
	boost_mat.gravity = Vector3.ZERO
	boost_mat.scale_min = 0.05
	boost_mat.scale_max = 0.2
	boost_mat.color = Color(1, 0.8, 0.2, 1)
	boost_particles.process_material = boost_mat
	boost_particles.draw_pass_1 = particle_mesh.duplicate()
	
	boost_particles.position = Vector3(0, 0, 1.2)
	add_child(boost_particles)


func set_preview_mode(enabled: bool):
	"""Disable runtime effects for menu preview rendering."""
	preview_mode = enabled
	if not enabled:
		return
	speed_boost = 1.0
	if engine_particles:
		engine_particles.emitting = false
	if trail_particles:
		trail_particles.emitting = false
	if boost_particles:
		boost_particles.emitting = false
	if engine_material:
		engine_material.emission_energy_multiplier = 1.4


func update_from_hands(mid_x: float, mid_y: float, angle: float, distance: float, delta: float):
	"""Wrapper cũ: cập nhật từ các giá trị rời rạc"""
	var hand_data = {
		"found": true,
		"mid_x": mid_x,
		"mid_y": mid_y,
		"angle": angle,
		"distance": distance,
		"hands": 2
	}
	update_from_hand_data(hand_data, delta)


func update_from_hand_data(hand_data: Dictionary, delta: float):
	"""Nhận trực tiếp hand_data và áp dụng steering frame-rate independent."""
	if not control_mapper:
		return
	
	var control = control_mapper.process_hand_data(hand_data, delta)
	_last_control_snapshot = {
		"valid": control.is_valid,
		"steering": control.steering,
		"throttle": control.throttle,
		"brake": control.brake,
		"speed": control.speed,
		"gesture": control.gesture,
	}
	
	var game_pos = control_mapper.get_game_position(control)
	target_position.x = game_pos.x
	target_position.y = game_pos.y
	target_roll = control_mapper.get_game_rotation(control)
	
	var target_speed_boost = control.speed
	var safe_delta = max(delta, 0.0001)
	var boost_factor = 1.0 + max(0.0, target_speed_boost - 1.0) * 0.35
	
	var current_steer_response = steer_response * boost_factor
	var current_roll_response = roll_response * boost_factor
	
	if not control.is_valid:
		current_steer_response = neutral_return_response
		current_roll_response = neutral_return_response
	
	var pos_alpha = 1.0 - exp(-current_steer_response * safe_delta)
	var roll_alpha = 1.0 - exp(-current_roll_response * safe_delta)
	var speed_alpha = 1.0 - exp(-speed_response * safe_delta)
	
	var prev_x = position.x
	position.x = lerp(position.x, target_position.x, pos_alpha)
	position.y = lerp(position.y, target_position.y, pos_alpha)
	
	var lateral_velocity = (position.x - prev_x) / safe_delta
	var dynamic_bank = clamp(-lateral_velocity * bank_from_lateral_velocity, -max_dynamic_bank, max_dynamic_bank)
	rotation_degrees.z = lerp(rotation_degrees.z, target_roll + dynamic_bank, roll_alpha)
	
	speed_boost = lerp(speed_boost, target_speed_boost, speed_alpha)
	current_gesture = control.gesture
	visual_phase += safe_delta * (2.4 + speed_boost * 0.85)
	
	# Thêm pitch/yaw động để cảm giác lái "phi thuyền" rõ hơn.
	var pitch_target = clamp(
		-position.y * 2.1 - max(0.0, speed_boost - 1.0) * 6.5 + sin(visual_phase) * 1.3,
		-15.0,
		12.0
	)
	var yaw_target = clamp(-lateral_velocity * 0.42 + target_roll * 0.28, -10.0, 10.0)
	rotation_degrees.x = lerp(rotation_degrees.x, pitch_target, roll_alpha * 0.85)
	rotation_degrees.y = lerp(rotation_degrees.y, yaw_target, roll_alpha * 0.75)
	
	# Clamp position (dùng giá trị từ mapper)
	position.x = clamp(position.x, -control_mapper.max_move_x, control_mapper.max_move_x)
	position.y = clamp(position.y, -control_mapper.max_move_y, control_mapper.max_move_y)
	
	update_visual_feedback()
	update_particles()


func apply_menu_settings():
	"""Đọc settings từ main menu và apply vào control mapper."""
	var config := ConfigFile.new()
	if config.load("user://menu_settings.cfg") != OK:
		return
	
	var preset_index := int(config.get_value("controls", "preset", 0))
	var sensitivity := float(config.get_value("controls", "sensitivity", 2.0))
	var grip_mode_index := int(config.get_value("controls", "grip_mode", HandControlMapper.GripMode.HORIZONTAL))
	
	match preset_index:
		0:
			set_control_preset("default")
		1:
			set_control_preset("sensitive")
		2:
			set_control_preset("smooth")
		3:
			set_control_preset("beginner")
		_:
			set_control_preset("default")
	
	# Slider hiện tại là “XY sensitivity”
	control_mapper.sensitivity_x = sensitivity
	control_mapper.sensitivity_y = sensitivity
	control_mapper.set_grip_mode_index(grip_mode_index)
	
	# Persist full config (không ghi đè thiếu key như menu trước đây)
	save_control_config()


func _get_color_entry(index: int) -> Dictionary:
	var safe_index = clampi(index, 0, SHIP_COLOR_VARIANTS.size() - 1)
	return SHIP_COLOR_VARIANTS[safe_index]


func _get_color_name(index: int) -> String:
	return str(_get_color_entry(index)["name"])


func _get_color_value(index: int) -> Color:
	return _get_color_entry(index)["color"]


func apply_ship_colors():
	if body_material:
		var body_color = _get_color_value(body_color_index)
		body_material.albedo_color = body_color
		body_material.emission = body_color
	
	if wing_material:
		var wing_color = _get_color_value(wing_color_index)
		wing_material.albedo_color = wing_color
		wing_material.emission = wing_color
	
	if tail_material:
		var tail_color = _get_color_value(tail_color_index)
		tail_material.albedo_color = tail_color
		tail_material.emission = tail_color
	
	if engine_material:
		engine_base_color = _get_color_value(engine_color_index)
		engine_material.albedo_color = engine_base_color
		engine_material.emission = engine_base_color


func set_ship_part_color_index(part: String, color_index: int):
	var normalized = part.to_lower()
	var safe_index = clampi(color_index, 0, SHIP_COLOR_VARIANTS.size() - 1)
	match normalized:
		"body":
			body_color_index = safe_index
		"wings", "wing":
			wing_color_index = safe_index
		"tail":
			tail_color_index = safe_index
		"engine":
			engine_color_index = safe_index
		_:
			return
	
	apply_ship_colors()
	save_ship_customization()


func cycle_ship_color(part: String, step: int = 1) -> String:
	var normalized = part.to_lower()
	match normalized:
		"body":
			body_color_index = wrapi(body_color_index + step, 0, SHIP_COLOR_VARIANTS.size())
		"wings", "wing":
			wing_color_index = wrapi(wing_color_index + step, 0, SHIP_COLOR_VARIANTS.size())
		"tail":
			tail_color_index = wrapi(tail_color_index + step, 0, SHIP_COLOR_VARIANTS.size())
		"engine":
			engine_color_index = wrapi(engine_color_index + step, 0, SHIP_COLOR_VARIANTS.size())
		_:
			return get_ship_color_summary()
	
	apply_ship_colors()
	save_ship_customization()
	return get_ship_color_summary()


func get_ship_part_color_label(part: String) -> String:
	var normalized = part.to_lower()
	match normalized:
		"body":
			return _get_color_name(body_color_index)
		"wings", "wing":
			return _get_color_name(wing_color_index)
		"tail":
			return _get_color_name(tail_color_index)
		"engine":
			return _get_color_name(engine_color_index)
		_:
			return "-"


func get_ship_color_summary() -> String:
	return "BodyColor=%s | WingColor=%s | TailColor=%s | EngineColor=%s" % [
		_get_color_name(body_color_index),
		_get_color_name(wing_color_index),
		_get_color_name(tail_color_index),
		_get_color_name(engine_color_index),
	]


func update_visual_feedback():
	"""Cập nhật hiệu ứng visual theo gesture"""
	if not engine_material:
		return
	
	var pulse = 0.5 + 0.5 * sin(visual_phase * 2.2)
	if body_material:
		body_material.emission_energy_multiplier = 0.65 + pulse * 0.45
	if wing_material:
		wing_material.emission_energy_multiplier = 0.55 + pulse * 0.9
	if tail_material:
		tail_material.emission_energy_multiplier = 0.45 + pulse * 0.75
	
	# Engine glow based on speed
	var intensity = 1.0 + speed_boost
	engine_material.emission_energy_multiplier = intensity
	engine.scale = _engine_visual_scale_base * (0.8 + speed_boost * 0.3)
	
	# Thay đổi màu engine theo gesture
	match current_gesture:
		HandControlMapper.GestureType.DRIFT:
			engine_material.emission = engine_base_color.lerp(Color(0.7, 0.35, 1.0), 0.62)
		HandControlMapper.GestureType.BOOST:
			engine_material.emission = engine_base_color.lerp(Color(1, 0.25, 0.05), 0.65)
		HandControlMapper.GestureType.BRAKE:
			engine_material.emission = engine_base_color.lerp(Color(0.35, 0.45, 1), 0.7)
		HandControlMapper.GestureType.ITEM_USE:
			engine_material.emission = engine_base_color.lerp(Color(0.2, 1.0, 0.8), 0.6)
		_:
			engine_material.emission = engine_base_color


func calibrate():
	"""Bắt đầu quá trình calibration"""
	control_mapper.reset_calibration()
	print("Calibration started - hold hands in neutral position")


func apply_calibration_sample(hand_data: Dictionary) -> bool:
	"""Thêm mẫu calibration và trả về true khi hoàn tất"""
	return control_mapper.calibrate_center(hand_data)


func cycle_ship_part(part: String, step: int = 1) -> String:
	"""Cycle ship part variant and persist customization."""
	var normalized = part.to_lower()
	match normalized:
		"body":
			body_variant_index = wrapi(body_variant_index + step, 0, BODY_VARIANTS.size())
			apply_body_variant()
		"wings", "wing":
			wing_variant_index = wrapi(wing_variant_index + step, 0, WING_VARIANTS.size())
			apply_wing_variant()
		"tail":
			tail_variant_index = wrapi(tail_variant_index + step, 0, TAIL_VARIANTS.size())
			apply_tail_variant()
		"engine":
			engine_variant_index = wrapi(engine_variant_index + step, 0, ENGINE_VARIANTS.size())
			apply_engine_variant()
		_:
			return get_ship_customization_summary()
	
	save_ship_customization()
	return get_ship_customization_summary()


func get_ship_part_variant_label(part: String) -> String:
	var normalized = part.to_lower()
	match normalized:
		"body":
			return str(BODY_VARIANTS[body_variant_index]["name"])
		"wings", "wing":
			return str(WING_VARIANTS[wing_variant_index]["name"])
		"tail":
			return str(TAIL_VARIANTS[tail_variant_index]["name"])
		"engine":
			return str(ENGINE_VARIANTS[engine_variant_index]["name"])
		_:
			return "-"


func get_ship_customization_summary() -> String:
	return "Body=%s (%s) | Wings=%s (%s) | Tail=%s (%s) | Engine=%s (%s)" % [
		BODY_VARIANTS[body_variant_index]["name"],
		_get_color_name(body_color_index),
		WING_VARIANTS[wing_variant_index]["name"],
		_get_color_name(wing_color_index),
		TAIL_VARIANTS[tail_variant_index]["name"],
		_get_color_name(tail_color_index),
		ENGINE_VARIANTS[engine_variant_index]["name"],
		_get_color_name(engine_color_index),
	]


func save_ship_customization():
	var config = ConfigFile.new()
	config.set_value("ship_parts", "body", body_variant_index)
	config.set_value("ship_parts", "wings", wing_variant_index)
	config.set_value("ship_parts", "tail", tail_variant_index)
	config.set_value("ship_parts", "engine", engine_variant_index)
	config.set_value("ship_colors", "body", body_color_index)
	config.set_value("ship_colors", "wings", wing_color_index)
	config.set_value("ship_colors", "tail", tail_color_index)
	config.set_value("ship_colors", "engine", engine_color_index)
	config.save("user://ship_customization.cfg")


func load_ship_customization():
	var config = ConfigFile.new()
	if config.load("user://ship_customization.cfg") == OK:
		body_variant_index = clampi(int(config.get_value("ship_parts", "body", body_variant_index)), 0, BODY_VARIANTS.size() - 1)
		wing_variant_index = clampi(int(config.get_value("ship_parts", "wings", wing_variant_index)), 0, WING_VARIANTS.size() - 1)
		tail_variant_index = clampi(int(config.get_value("ship_parts", "tail", tail_variant_index)), 0, TAIL_VARIANTS.size() - 1)
		engine_variant_index = clampi(int(config.get_value("ship_parts", "engine", engine_variant_index)), 0, ENGINE_VARIANTS.size() - 1)
		body_color_index = clampi(int(config.get_value("ship_colors", "body", body_color_index)), 0, SHIP_COLOR_VARIANTS.size() - 1)
		wing_color_index = clampi(int(config.get_value("ship_colors", "wings", wing_color_index)), 0, SHIP_COLOR_VARIANTS.size() - 1)
		tail_color_index = clampi(int(config.get_value("ship_colors", "tail", tail_color_index)), 0, SHIP_COLOR_VARIANTS.size() - 1)
		engine_color_index = clampi(int(config.get_value("ship_colors", "engine", engine_color_index)), 0, SHIP_COLOR_VARIANTS.size() - 1)
	
	apply_all_ship_part_variants()
	apply_ship_colors()


func save_control_config():
	"""Lưu cấu hình điều khiển + ship customization"""
	if control_mapper.save_config("user://hand_control.cfg"):
		print("Control config saved")
	else:
		print("Failed to save control config")
	save_ship_customization()


func set_control_preset(preset: String):
	"""Đặt preset điều khiển"""
	match preset:
		"default":
			control_mapper.apply_preset_default()
		"sensitive":
			control_mapper.apply_preset_sensitive()
		"smooth":
			control_mapper.apply_preset_smooth()
		"beginner":
			control_mapper.apply_preset_beginner()
	print("Applied preset: ", preset)


func reset():
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	target_position = Vector3.ZERO
	target_roll = 0.0
	speed_boost = 1.0
	visual_phase = 0.0
	_last_control_snapshot = {
		"valid": false,
		"steering": 0.0,
		"throttle": 0.0,
		"brake": 0.0,
		"speed": 1.0,
		"gesture": HandControlMapper.GestureType.NONE,
	}
	if boost_particles:
		boost_particles.emitting = false


func update_particles():
	if preview_mode:
		return
	
	# Boost particles activate when going fast
	if boost_particles:
		boost_particles.emitting = speed_boost > 1.8
	
	# Adjust engine particle intensity based on speed
	if engine_particles and engine_particles.process_material:
		var mat = engine_particles.process_material as ParticleProcessMaterial
		if mat:
			mat.initial_velocity_min = 5.0 + speed_boost * 3
			mat.initial_velocity_max = 10.0 + speed_boost * 5


func trigger_explosion():
	# Stop normal particles
	if engine_particles:
		engine_particles.emitting = false
	if trail_particles:
		trail_particles.emitting = false
	if boost_particles:
		boost_particles.emitting = false
	
	# Create explosion effect
	var explosion = GPUParticles3D.new()
	explosion.name = "Explosion"
	explosion.amount = 100
	explosion.lifetime = 1.0
	explosion.one_shot = true
	explosion.explosiveness = 1.0
	explosion.emitting = true
	
	var exp_mat = ParticleProcessMaterial.new()
	exp_mat.direction = Vector3(0, 0, 0)
	exp_mat.spread = 180.0
	exp_mat.initial_velocity_min = 10.0
	exp_mat.initial_velocity_max = 20.0
	exp_mat.gravity = Vector3(0, -5, 0)
	exp_mat.scale_min = 0.1
	exp_mat.scale_max = 0.4
	exp_mat.color = Color(1, 0.3, 0.1, 1)
	explosion.process_material = exp_mat
	
	var particle_mesh = SphereMesh.new()
	particle_mesh.radius = 0.15
	particle_mesh.height = 0.3
	explosion.draw_pass_1 = particle_mesh
	
	explosion.position = position
	get_parent().add_child(explosion)
	
	# Auto-remove after animation
	var timer = Timer.new()
	timer.wait_time = 2.0
	timer.one_shot = true
	timer.timeout.connect(func(): explosion.queue_free(); timer.queue_free())
	get_parent().add_child(timer)
	timer.start()


func resume_particles():
	if preview_mode:
		return
	if engine_particles:
		engine_particles.emitting = true
	if trail_particles:
		trail_particles.emitting = true


func get_current_gesture() -> int:
	return current_gesture


func get_tracking_control_snapshot() -> Dictionary:
	return _last_control_snapshot.duplicate()
