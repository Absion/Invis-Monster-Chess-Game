extends CanvasLayer
class_name CombatUI

## Handles the user interface for combat.
##
## Displays the current turn and provides a button for the player to end their turn.

@onready var turn_label: Label = Label.new()
@onready var end_turn_button: Button = Button.new()

@onready var hp_panel: Panel = Panel.new()
@onready var hp_label: Label = Label.new()

var combo_panel: Panel = Panel.new()
var combo_label: Label = Label.new()
var special_label: Label = Label.new()
var heal_label: Label = Label.new()

var turn_manager: TurnManager
var grid_manager: GridManager

# ⚡ Bolt Optimization: Cache for HP UI to avoid continuous string rebuilds and GC overhead
var _last_hp_state: Dictionary = {}
var _last_actor_count: int = -1

var _last_combo_count: int = -1
var _last_combo_time: float = -1.0

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
	hp_panel.size = Vector2(250, 280)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	hp_panel.add_theme_stylebox_override("panel", style)
	add_child(hp_panel)
	
	# Combo UI
	combo_panel.position = Vector2(20, 150)
	combo_panel.size = Vector2(200, 80)
	var combo_style = StyleBoxFlat.new()
	combo_style.bg_color = Color(0, 0, 0, 0.7)
	combo_style.corner_radius_top_left = 8
	combo_style.corner_radius_top_right = 8
	combo_style.corner_radius_bottom_left = 8
	combo_style.corner_radius_bottom_right = 8
	combo_panel.add_theme_stylebox_override("panel", combo_style)
	add_child(combo_panel)
	combo_panel.hide()
	
	combo_label.position = Vector2(15, 10)
	combo_label.add_theme_font_size_override("font_size", 20)
	combo_label.add_theme_color_override("font_color", Color.YELLOW)
	combo_panel.add_child(combo_label)
	
	# Special Ready UI
	special_label.position = Vector2(20, 240)
	special_label.add_theme_font_size_override("font_size", 22)
	special_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.0))
	special_label.add_theme_color_override("font_outline_color", Color.BLACK)
	special_label.add_theme_constant_override("outline_size", 4)
	special_label.text = "★ Special Attack Ready! ★\n       [ Right Click ]"
	special_label.hide()
	add_child(special_label)
	
	# Heal UI
	heal_label.position = Vector2(20, 320)
	heal_label.add_theme_font_size_override("font_size", 22)
	heal_label.add_theme_color_override("font_color", Color.GREEN)
	heal_label.add_theme_color_override("font_outline_color", Color.BLACK)
	heal_label.add_theme_constant_override("outline_size", 4)
	heal_label.text = "✚ Heal Available [ Press H ]"
	add_child(heal_label)
	
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(10, 10)
	scroll.size = Vector2(230, 260)
	hp_panel.add_child(scroll)
	
	hp_label.add_theme_font_size_override("font_size", 20)
	hp_label.add_theme_color_override("font_color", Color.WHITE)
	scroll.add_child(hp_label)

## Injects the TurnManager and GridManager into the UI, connecting signals.
func setup(turn_mgr: TurnManager, grid: GridManager) -> void:
	turn_manager = turn_mgr
	grid_manager = grid
	turn_manager.turn_started.connect(_on_turn_started)

## Called every frame to update the health status display dynamically.
func _process(_delta: float) -> void:
	if not grid_manager: return
	
	# ⚡ Bolt Optimization: Check for changes before allocating strings and mutating UI
	var needs_update = false
	var current_actor_count = grid_manager.grid.size()

	if current_actor_count != _last_actor_count:
		needs_update = true
		_last_actor_count = current_actor_count

	# Quick check for health changes without allocating strings
	# ⚡ Bolt Optimization: Iterate directly on keys to prevent Array allocations per frame
	for pos in grid_manager.grid:
		var actor = grid_manager.grid[pos]
		var a_name = actor.name
		var a_hp = actor.current_health
		if not _last_hp_state.has(a_name) or _last_hp_state[a_name] != a_hp:
			needs_update = true
			_last_hp_state[a_name] = a_hp

	if not needs_update and hp_label.text != "":
		return

	var girl_hp = "Dead"
	var monster_hps = {}
	
	# ⚡ Bolt Optimization: Iterate directly on keys
	for pos in grid_manager.grid:
		var actor = grid_manager.grid[pos]
		if actor.get_actor_name() == "Little Girl":
			girl_hp = str(actor.current_health) + "/" + str(actor.data.max_health)
		elif actor.name.begins_with("Monster"):
			monster_hps[actor.name] = str(actor.current_health) + "/" + str(actor.data.max_health)
			
	var text = "Health Status\n------------------\nLittle Girl: " + girl_hp
	for i in range(1, 7):
		var m_name = "Monster" + str(i)
		var hp = monster_hps.get(m_name, "Dead")
		text += "\nMonster " + str(i) + ": " + hp
		
	hp_label.text = text

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

func update_combo(count: int, time_left: float) -> void:
	# ⚡ Bolt Optimization: Prevent redundant string allocations and layout recalculations every frame
	# Snap the float to the UI's display precision to avoid constant cache misses from microscopic frame deltas
	var display_time = snapped(time_left, 0.01)
	if count == _last_combo_count and display_time == _last_combo_time:
		return

	_last_combo_count = count
	_last_combo_time = display_time

	if count > 0:
		combo_panel.show()
		combo_label.text = "COMBO: x%d\nTime: %.2fs" % [count, display_time]
		if count >= 3:
			special_label.show()
		else:
			special_label.hide()
	else:
		combo_panel.hide()
		special_label.hide()

func clear_heal_ui() -> void:
	heal_label.hide()
