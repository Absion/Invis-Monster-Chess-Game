extends SceneTree

func _init() -> void:
	print("Generating actor resources...")
	
	var old_man = preload("res://resources/actor_data.gd").new()
	old_man.name = "Old Man"
	old_man.max_health = 20
	old_man.damage = 5
	old_man.movement_range = 4
	ResourceSaver.save(old_man, "res://resources/old_man.tres")
	
	var girl = preload("res://resources/actor_data.gd").new()
	girl.name = "Little Girl"
	girl.max_health = 5
	girl.damage = 0
	girl.movement_range = 6
	ResourceSaver.save(girl, "res://resources/girl.tres")
	
	var monster = preload("res://resources/actor_data.gd").new()
	monster.name = "Monster"
	monster.max_health = 15
	monster.damage = 10
	monster.movement_range = 3
	ResourceSaver.save(monster, "res://resources/monster.tres")
	
	print("Done!")
	quit()
