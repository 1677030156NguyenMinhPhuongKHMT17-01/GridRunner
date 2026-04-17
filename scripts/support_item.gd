extends Node3D
## Support item: buffs for player and debuffs for rival ships

enum ItemType {
	BOOST,
	SHIELD,
	RIVAL_SLOW,
	JAMMER,
}

var item_type: int = ItemType.BOOST
var base_speed: float = 16.0
var rotation_speed: float = 80.0
var pickup_radius: float = 1.1
var glow_phase: float = 0.0
var item_material: StandardMaterial3D

@onready var mesh_instance = $MeshInstance3D


func _ready():
	randomize_item()
	setup_material()
	setup_mesh()


func randomize_item():
	var weighted_types = [
		ItemType.BOOST,
		ItemType.BOOST,
		ItemType.SHIELD,
		ItemType.RIVAL_SLOW,
		ItemType.JAMMER,
	]
	item_type = weighted_types[randi() % weighted_types.size()]
	base_speed = randf_range(14.0, 19.0)
	rotation_speed = randf_range(55.0, 110.0)
	glow_phase = randf_range(0.0, TAU)
	pickup_radius = randf_range(0.95, 1.25)


func setup_material():
	item_material = StandardMaterial3D.new()
	item_material.emission_enabled = true
	item_material.emission_energy_multiplier = 1.15
	
	match item_type:
		ItemType.BOOST:
			item_material.albedo_color = Color(1.0, 0.72, 0.25)
			item_material.emission = Color(1.0, 0.72, 0.25)
		ItemType.SHIELD:
			item_material.albedo_color = Color(0.25, 0.85, 1.0)
			item_material.emission = Color(0.25, 0.85, 1.0)
		ItemType.RIVAL_SLOW:
			item_material.albedo_color = Color(0.95, 0.4, 1.0)
			item_material.emission = Color(0.95, 0.4, 1.0)
		ItemType.JAMMER:
			item_material.albedo_color = Color(1.0, 0.32, 0.35)
			item_material.emission = Color(1.0, 0.32, 0.35)


func setup_mesh():
	var mesh: Mesh
	match item_type:
		ItemType.BOOST:
			var torus = TorusMesh.new()
			torus.inner_radius = 0.09
			torus.outer_radius = 0.42
			mesh = torus
		ItemType.SHIELD:
			var sphere = SphereMesh.new()
			sphere.radius = 0.38
			sphere.height = 0.76
			mesh = sphere
		ItemType.RIVAL_SLOW:
			var prism = PrismMesh.new()
			prism.size = Vector3(0.55, 0.55, 0.65)
			mesh = prism
		ItemType.JAMMER:
			var cylinder = CylinderMesh.new()
			cylinder.top_radius = 0.25
			cylinder.bottom_radius = 0.25
			cylinder.height = 0.66
			mesh = cylinder
	
	mesh_instance.mesh = mesh
	mesh_instance.material_override = item_material


func get_item_type_name() -> String:
	match item_type:
		ItemType.BOOST:
			return "boost"
		ItemType.SHIELD:
			return "shield"
		ItemType.RIVAL_SLOW:
			return "rival_slow"
		ItemType.JAMMER:
			return "jammer"
	return "boost"


func get_pickup_radius() -> float:
	return pickup_radius


func activate_for_pool(spawn_position: Vector3):
	position = spawn_position
	rotation = Vector3.ZERO
	visible = true
	randomize_item()
	setup_material()
	setup_mesh()


func deactivate_for_pool():
	visible = false
	position = Vector3(0, -1000, 0)
	rotation = Vector3.ZERO


func update_movement(speed_multiplier: float, delta: float, lateral_velocity: float = 0.0):
	position.z += base_speed * delta * speed_multiplier
	position.x += lateral_velocity * delta * 0.6
	position.x = clamp(position.x, -10.0, 10.0)
	
	rotation_degrees.y += rotation_speed * delta
	rotation_degrees.x += rotation_speed * 0.35 * delta
	
	glow_phase += delta * 5.0
	if item_material:
		item_material.emission_energy_multiplier = 0.9 + 0.55 * abs(sin(glow_phase))
