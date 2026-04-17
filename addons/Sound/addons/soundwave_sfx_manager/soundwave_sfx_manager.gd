@tool
extends EditorPlugin


func _enable_plugin() -> void:
	if AudioServer.get_bus_index("sfx") == -1:
		print("Please create a <sfx> bus")


func _disable_plugin() -> void:
	# Remove autoloads here.
	pass


func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	pass


func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	pass
