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

# Cached state to prevent unnecessary string allocation and UI updates in _process
var _last_girl_hp: int = -1
var _last_m1_hp: int = -1
var _last_m2_hp: int = -1
var _last_girl_max_hp: int = -1
var _last_m1_max_hp: int = -1
var _last_m2_max_hp: int = -1

## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_setup_ui()

## Sets up the UI layout and elements programmatically.
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

## Injects the TurnManager and GridManager into the UI, connecting signals.
func setup(turn_mgr: TurnManager, grid: GridManager) -> void:
	turn_manager = turn_mgr
	grid_manager = grid
	turn_manager.turn_started.connect(_on_turn_started)

## Called every frame to update the health status display dynamically.
func _process(delta: float) -> void:
	if not grid_manager: return
	
	var current_girl_hp: int = 0
	var current_m1_hp: int = 0
	var current_m2_hp: int = 0

	var current_girl_max_hp: int = 0
	var current_m1_max_hp: int = 0
	var current_m2_max_hp: int = 0
	
	# ⚡ Bolt Optimization: Iterate directly on the dictionary to avoid allocating an Array from .values()
	for pos in grid_manager.grid:
		var actor = grid_manager.grid[pos]
		if actor.get_actor_name() == "Little Girl":
			current_girl_hp = actor.current_health
			current_girl_max_hp = actor.data.max_health
		elif actor.name == "Monster1":
			current_m1_hp = actor.current_health
			current_m1_max_hp = actor.data.max_health
		elif actor.name == "Monster2":
			current_m2_hp = actor.current_health
			current_m2_max_hp = actor.data.max_health
			
	# ⚡ Bolt Optimization: Only reconstruct strings and update the label if the underlying health values actually changed
	if current_girl_hp != _last_girl_hp or current_m1_hp != _last_m1_hp or current_m2_hp != _last_m2_hp or \
	   current_girl_max_hp != _last_girl_max_hp or current_m1_max_hp != _last_m1_max_hp or current_m2_max_hp != _last_m2_max_hp:

		_last_girl_hp = current_girl_hp
		_last_m1_hp = current_m1_hp
		_last_m2_hp = current_m2_hp
		_last_girl_max_hp = current_girl_max_hp
		_last_m1_max_hp = current_m1_max_hp
		_last_m2_max_hp = current_m2_max_hp

		var girl_hp_str = "Dead" if current_girl_hp <= 0 else "%d/%d" % [current_girl_hp, current_girl_max_hp]
		var m1_hp_str = "Dead" if current_m1_hp <= 0 else "%d/%d" % [current_m1_hp, current_m1_max_hp]
		var m2_hp_str = "Dead" if current_m2_hp <= 0 else "%d/%d" % [current_m2_hp, current_m2_max_hp]

		hp_label.text = "Health Status\n------------------\nLittle Girl: %s\nMonster 1: %s\nMonster 2: %s" % [girl_hp_str, m1_hp_str, m2_hp_str]

## Callback triggered when the TurnManager changes phases. Updates the turn label.
func _on_turn_started(phase: TurnManager.TurnPhase) -> void:
	turn_label.text = "Turn: " + turn_manager.get_phase_name(phase)
	
	if phase == TurnManager.TurnPhase.MONSTERS:
		end_turn_button.hide()
	else:
		end_turn_button.show()

## Callback triggered when the 'End Turn' button is clicked.
func _on_end_turn_pressed() -> void:
	if turn_manager.current_phase != TurnManager.TurnPhase.MONSTERS:
		turn_manager.end_turn()
