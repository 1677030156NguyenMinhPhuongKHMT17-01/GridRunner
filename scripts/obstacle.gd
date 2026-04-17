extends Node3D
## Obstacle with Enhanced Effects and Types

enum ObstacleType {
	BOX,
	SPHERE,
	CYLINDER,
	PILLAR,  # Thay RING bằng PILLAR đơn giản hơn
}

var base_speed: float = 20.0
var obstacle_size: Vector3 = Vector3(1, 1, 1)  # Actual collision box size
var visual_scale: float = 1.0
var obstacle_material: StandardMaterial3D
var glow_phase: float = 0.0
var obstacle_type: int = ObstacleType.BOX
var rotation_speed: float = 50.0

@onready var mesh_instance = $MeshInstance3D


func _ready():
	randomize_obstacle()
	setup_material()
	setup_mesh()


func randomize_obstacle():
	# Random type - chỉ dùng các loại đơn giản
	var types = [ObstacleType.BOX, ObstacleType.BOX, ObstacleType.SPHERE, 
				 ObstacleType.CYLINDER, ObstacleType.PILLAR]
	obstacle_type = types[randi() % types.size()]
	
	# Size based on type - collision box = visual size
	match obstacle_type:
		ObstacleType.BOX:
			var w = randf_range(1.0, 2.5)
			var h = randf_range(1.0, 3.0)
			var d = randf_range(0.8, 1.5)
			obstacle_size = Vector3(w, h, d)
		
		ObstacleType.SPHERE:
			var diameter = randf_range(1.5, 3.0)
			obstacle_size = Vector3(diameter, diameter, diameter)
		
		ObstacleType.CYLINDER:
			var diameter = randf_range(1.0, 2.0)
			var height = randf_range(1.5, 3.5)
			obstacle_size = Vector3(diameter, height, diameter)
		
		ObstacleType.PILLAR:
			var w = randf_range(0.5, 1.0)
			var h = randf_range(3.0, 6.0)
			obstacle_size = Vector3(w, h, w)
	
	base_speed = randf_range(18, 28)
	glow_phase = randf_range(0, TAU)
	rotation_speed = randf_range(20, 60)


func setup_material():
	# Random neon color
	var colors = [
		Color(1, 0, 1),      # Magenta
		Color(1, 0.3, 0.3),  # Red
		Color(1, 0.5, 0),    # Orange
		Color(0.8, 0, 0.8),  # Purple
		Color(1, 1, 0),      # Yellow
		Color(0, 1, 0.7),    # Cyan
		Color(0.3, 1, 0.3),  # Green
	]
	var chosen_color = colors[randi() % colors.size()]
	
	obstacle_material = StandardMaterial3D.new()
	obstacle_material.albedo_color = chosen_color
	obstacle_material.emission_enabled = true
	obstacle_material.emission = chosen_color
	obstacle_material.emission_energy_multiplier = 0.8


func setup_mesh():
	var mesh: Mesh
	
	match obstacle_type:
		ObstacleType.BOX:
			var box = BoxMesh.new()
			box.size = obstacle_size
			mesh = box
		
		ObstacleType.SPHERE:
			var sphere = SphereMesh.new()
			sphere.radius = obstacle_size.x / 2
			sphere.height = obstacle_size.x
			mesh = sphere
		
		ObstacleType.CYLINDER:
			var cylinder = CylinderMesh.new()
			cylinder.top_radius = obstacle_size.x / 2
			cylinder.bottom_radius = obstacle_size.x / 2
			cylinder.height = obstacle_size.y
			mesh = cylinder
		
		ObstacleType.PILLAR:
			var cylinder = CylinderMesh.new()
			cylinder.top_radius = obstacle_size.x / 2
			cylinder.bottom_radius = obstacle_size.x / 2
			cylinder.height = obstacle_size.y
			mesh = cylinder
	
	mesh_instance.mesh = mesh
	mesh_instance.material_override = obstacle_material


func activate_for_pool(spawn_position: Vector3):
	"""Reinitialize obstacle when lấy từ pool."""
	position = spawn_position
	rotation = Vector3.ZERO
	randomize_obstacle()
	setup_material()
	setup_mesh()
	visible = true
	if has_meta("near_miss_counted"):
		remove_meta("near_miss_counted")


func deactivate_for_pool():
	"""Hide obstacle and move away when trả về pool."""
	visible = false
	position = Vector3(0, -1000, 0)
	rotation = Vector3.ZERO
	if has_meta("near_miss_counted"):
		remove_meta("near_miss_counted")


func update_movement(speed_multiplier: float, delta: float, lateral_velocity: float = 0.0):
	position.z += base_speed * delta * speed_multiplier
	position.x += lateral_velocity * delta
	position.x = clamp(position.x, -12.0, 12.0)
	
	# Rotation based on type
	match obstacle_type:
		ObstacleType.BOX:
			rotation_degrees.y += rotation_speed * delta
		ObstacleType.SPHERE:
			rotation_degrees.y += rotation_speed * delta
			rotation_degrees.x += rotation_speed * 0.5 * delta
		ObstacleType.CYLINDER, ObstacleType.PILLAR:
			rotation_degrees.y += rotation_speed * 0.3 * delta
	
	# Pulsing glow effect
	glow_phase += delta * 3.0
	if obstacle_material:
		var pulse = 0.5 + 0.3 * sin(glow_phase)
		obstacle_material.emission_energy_multiplier = pulse


func get_collision_box() -> Vector3:
	"""Trả về kích thước collision box thực tế"""
	return obstacle_size
