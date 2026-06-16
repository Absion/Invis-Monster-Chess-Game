extends CanvasLayer
class_name CombatUI

## Handles the user interface for combat.
##
## Displays the current turn and provides a button for the player to end their turn.

@onready var turn_label: Label = Label.new()
@onready var end_turn_button: Button = Button.new()

@onready var hp_panel: Panel = Panel.new()
@onready var hp_label: Label = Label.new()

var turn_manager: TurnManager
var grid_manager: GridManager

func _ready() -> void:
	_setup_ui()

func _setup_ui() -> void:
	# Add Turn Label
	turn_label.text = "Turn: Unknown"
	turn_label.position = Vector2(20, 20)
	turn_label.add_theme_font_size_override("font_size", 32)
	turn_label.add_theme_color_override("font_color", Color.WHITE)
	turn_label.add_theme_color_override("font_outline_color", Color.BLACK)
	turn_label.add_theme_constant_override("outline_size", 4)
	add_child(turn_label)
	
	# Add End Turn Button
	end_turn_button.text = "End Turn"
	end_turn_button.position = Vector2(20, 80)
	end_turn_button.size = Vector2(120, 40)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	# Initially hide the button, it's only shown on player turns
	end_turn_button.hide()
	add_child(end_turn_button)
	
	# Add HP Panel
	hp_panel.position = Vector2(1000, 20)
	hp_panel.size = Vector2(250, 160)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	hp_panel.add_theme_stylebox_override("panel", style)
	add_child(hp_panel)
	
	hp_label.position = Vector2(15, 15)
	hp_label.add_theme_font_size_override("font_size", 20)
	hp_label.add_theme_color_override("font_color", Color.WHITE)
	hp_panel.add_child(hp_label)

func setup(turn_mgr: TurnManager, grid: GridManager) -> void:
	turn_manager = turn_mgr
	grid_manager = grid
	turn_manager.turn_started.connect(_on_turn_started)

func _process(delta: float) -> void:
	if not grid_manager: return
	
	var girl_hp = "Dead"
	var m1_hp = "Dead"
	var m2_hp = "Dead"
	
	for actor in grid_manager.grid.values():
		if actor.get_actor_name() == "Little Girl":
			girl_hp = str(actor.current_health) + "/" + str(actor.data.max_health)
		elif actor.name == "Monster1":
			m1_hp = str(actor.current_health) + "/" + str(actor.data.max_health)
		elif actor.name == "Monster2":
			m2_hp = str(actor.current_health) + "/" + str(actor.data.max_health)
			
	hp_label.text = "Health Status\n------------------\n" + \
		"Little Girl: " + girl_hp + "\n" + \
		"Monster 1: " + m1_hp + "\n" + \
		"Monster 2: " + m2_hp

func _on_turn_started(phase: TurnManager.TurnPhase) -> void:
	turn_label.text = "Turn: " + turn_manager.get_phase_name(phase)
	
	if phase == TurnManager.TurnPhase.MONSTERS:
		end_turn_button.hide()
	else:
		end_turn_button.show()

func _on_end_turn_pressed() -> void:
	if turn_manager.current_phase != TurnManager.TurnPhase.MONSTERS:
		turn_manager.end_turn()
