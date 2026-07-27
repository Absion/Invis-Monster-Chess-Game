extends SceneTree
func _init():
	var scene = load("res://scenes/low_poly_combat_axes.tscn")
	var inst = scene.instantiate()
	print("ROOT: ", inst.name)
	_print_tree(inst, "")
	quit()
func _print_tree(node, indent):
	var info = indent + node.name + " ( " + node.get_class() + " )"
	if node is Node3D:
		info += " | pos: " + str(node.position) + " | scale: " + str(node.scale) + " | vis: " + str(node.visible)
	print(info)
	for c in node.get_children():
		_print_tree(c, indent + "  ")
