extends CanvasLayer
class_name CombatUI

## Handles the user interface for combat and roguelite progression.
##
## Displays the current turn, live HP status, combo counter, special attack prompt,
## heal status, current round badge, active blessing chips, and provides modals for
## Hades / Vampire Survivors style power-up selection and run defeat summary.

@onready var turn_label: Label = Label.new()
@onready var end_turn_button: Button = Button.new()

@onready var hp_panel: Panel = Panel.new()
@onready var hp_label: Label = Label.new()

var combo_panel: Panel = Panel.new()
var combo_label: Label = Label.new()
var special_label: Label = Label.new()
var heal_label: Label = Label.new()

## Roguelite UI Elements
var round_panel: Panel = Panel.new()
var round_label: Label = Label.new()
var perks_scroll: ScrollContainer = ScrollContainer.new()
var perks_hbox: HBoxContainer = HBoxContainer.new()

var power_up_modal: Control = null
var game_over_modal: Control = null
var round_banner: Label = null

var turn_manager: TurnManager
var grid_manager: GridManager

## Currently active round monsters being monitored in the Health Status window
var active_round_monsters: Array[Actor] = []

# ⚡ Bolt Optimization: Cache for HP UI to avoid continuous string rebuilds and GC overhead
var _last_hp_state: Dictionary = {}
var _last_actor_count: int = -1

var _last_combo_count: int = -1
var _last_combo_time: float = -1.0
var _last_required_combo: int = 3

## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_setup_ui()

## Sets up the UI layout and elements programmatically.
func _setup_ui() -> void:
	# 1. Round Display (Top Center / Left)
	round_panel.position = Vector2(20, 16)
	round_panel.size = Vector2(240, 52)
	var round_style = StyleBoxFlat.new()
	round_style.bg_color = Color(0.08, 0.1, 0.15, 0.85)
	round_style.border_color = Color(1.0, 0.8, 0.25, 0.8)
	round_style.set_border_width_all(2)
	round_style.corner_radius_top_left = 8
	round_style.corner_radius_top_right = 8
	round_style.corner_radius_bottom_left = 8
	round_style.corner_radius_bottom_right = 8
	round_panel.add_theme_stylebox_override("panel", round_style)
	add_child(round_panel)
	
	round_label.position = Vector2(12, 10)
	round_label.text = "⚔ ROUND 1"
	round_label.add_theme_font_size_override("font_size", 22)
	round_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.3))
	round_label.add_theme_color_override("font_outline_color", Color.BLACK)
	round_label.add_theme_constant_override("outline_size", 3)
	round_panel.add_child(round_label)

	# 2. Turn Label (Below Round)
	turn_label.text = "Turn: Unknown"
	turn_label.position = Vector2(20, 78)
	turn_label.add_theme_font_size_override("font_size", 26)
	turn_label.add_theme_color_override("font_color", Color.WHITE)
	turn_label.add_theme_color_override("font_outline_color", Color.BLACK)
	turn_label.add_theme_constant_override("outline_size", 4)
	add_child(turn_label)
	
	# 3. End Turn Button
	end_turn_button.text = "End Turn"
	end_turn_button.position = Vector2(20, 120)
	end_turn_button.size = Vector2(130, 42)
	end_turn_button.add_theme_font_size_override("font_size", 18)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	end_turn_button.hide()
	add_child(end_turn_button)
	
	# 4. Active Perks / Blessings Bar (Top Right of screen)
	perks_scroll.position = Vector2(300, 16)
	perks_scroll.size = Vector2(650, 48)
	perks_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	perks_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	perks_hbox.add_theme_constant_override("separation", 8)
	perks_scroll.add_child(perks_hbox)
	add_child(perks_scroll)
	
	# 5. HP Panel (Top Right)
	hp_panel.position = Vector2(980, 20)
	hp_panel.size = Vector2(270, 300)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.1, 0.85)
	style.border_color = Color(0.3, 0.4, 0.5, 0.6)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	hp_panel.add_theme_stylebox_override("panel", style)
	add_child(hp_panel)
	
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(12, 12)
	scroll.size = Vector2(246, 276)
	hp_panel.add_child(scroll)
	
	hp_label.add_theme_font_size_override("font_size", 18)
	hp_label.add_theme_color_override("font_color", Color.WHITE)
	scroll.add_child(hp_label)
	
	# 6. Combo UI
	combo_panel.position = Vector2(20, 180)
	combo_panel.size = Vector2(210, 75)
	var combo_style = StyleBoxFlat.new()
	combo_style.bg_color = Color(0.08, 0.08, 0.12, 0.85)
	combo_style.border_color = Color(1.0, 0.85, 0.2, 0.7)
	combo_style.set_border_width_all(2)
	combo_style.corner_radius_top_left = 8
	combo_style.corner_radius_top_right = 8
	combo_style.corner_radius_bottom_left = 8
	combo_style.corner_radius_bottom_right = 8
	combo_panel.add_theme_stylebox_override("panel", combo_style)
	add_child(combo_panel)
	combo_panel.hide()
	
	combo_label.position = Vector2(15, 10)
	combo_label.add_theme_font_size_override("font_size", 19)
	combo_label.add_theme_color_override("font_color", Color.YELLOW)
	combo_panel.add_child(combo_label)
	
	# 7. Special Ready UI
	special_label.position = Vector2(20, 270)
	special_label.add_theme_font_size_override("font_size", 22)
	special_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.1))
	special_label.add_theme_color_override("font_outline_color", Color.BLACK)
	special_label.add_theme_constant_override("outline_size", 4)
	special_label.text = "★ Special Attack Ready! ★\n       [ Right Click ]"
	special_label.hide()
	add_child(special_label)
	
	# 8. Heal UI
	heal_label.position = Vector2(20, 350)
	heal_label.add_theme_font_size_override("font_size", 20)
	heal_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	heal_label.add_theme_color_override("font_outline_color", Color.BLACK)
	heal_label.add_theme_constant_override("outline_size", 4)
	heal_label.text = "✚ Heal Available [ Press H ]"
	add_child(heal_label)

## Injects the TurnManager and GridManager into the UI, connecting signals.
func setup(turn_mgr: TurnManager, grid: GridManager) -> void:
	turn_manager = turn_mgr
	grid_manager = grid
	turn_manager.turn_started.connect(_on_turn_started)

## Updates the round title banner and refreshes the perks list.
func update_round_display(round_num: int, active_perks: Array[Dictionary]) -> void:
	round_label.text = "⚔ ROUND %d" % round_num
	_last_hp_state.clear()
	_last_actor_count = -1
	hp_label.text = ""
	
	# Clear old perk chips
	for child in perks_hbox.get_children():
		child.queue_free()

	# Populate new perk chips
	for perk in active_perks:
		var chip = PanelContainer.new()
		var chip_style = StyleBoxFlat.new()
		chip_style.bg_color = Color(0.12, 0.14, 0.2, 0.9)
		chip_style.border_color = perk.get("color", Color.CYAN)
		chip_style.set_border_width_all(1)
		chip_style.corner_radius_top_left = 6
		chip_style.corner_radius_top_right = 6
		chip_style.corner_radius_bottom_left = 6
		chip_style.corner_radius_bottom_right = 6
		chip_style.content_margin_left = 8
		chip_style.content_margin_right = 8
		chip_style.content_margin_top = 4
		chip_style.content_margin_bottom = 4
		chip.add_theme_stylebox_override("panel", chip_style)
		
		var chip_label = Label.new()
		var count_str = (" Lv." + str(perk["level"])) if perk.get("level", 1) > 1 else ""
		chip_label.text = "%s %s%s" % [perk.get("icon", "★"), perk.get("name", "Perk"), count_str]
		chip_label.add_theme_font_size_override("font_size", 14)
		chip_label.add_theme_color_override("font_color", perk.get("color", Color.WHITE))
		chip_label.tooltip_text = "%s\n%s" % [perk.get("tagline", ""), perk.get("description", "")]
		chip.add_child(chip_label)
		perks_hbox.add_child(chip)

## Registers the active round monsters and resets the HP status window for the new round.
func register_round_monsters(monsters: Array[Actor]) -> void:
	active_round_monsters = monsters
	_last_hp_state.clear()
	_last_actor_count = -1
	_render_hp_text()

## Displays a stylish animated round banner across the screen.
func show_round_banner(round_num: int) -> void:
	if round_banner and is_instance_valid(round_banner):
		round_banner.queue_free()
		
	round_banner = Label.new()
	round_banner.text = "— ROUND %d —" % round_num
	round_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	round_banner.set_anchors_preset(Control.PRESET_CENTER)
	round_banner.add_theme_font_size_override("font_size", 72)
	round_banner.add_theme_color_override("font_color", Color(1.0, 0.88, 0.3))
	round_banner.add_theme_color_override("font_shadow_color", Color.BLACK)
	round_banner.add_theme_constant_override("shadow_offset_x", 4)
	round_banner.add_theme_constant_override("shadow_offset_y", 4)
	round_banner.modulate.a = 0.0
	round_banner.scale = Vector2(0.8, 0.8)
	round_banner.pivot_offset = Vector2(250, 50)
	add_child(round_banner)
	
	var tween = create_tween()
	tween.tween_property(round_banner, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(round_banner, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.8)
	tween.tween_property(round_banner, "modulate:a", 0.0, 0.4)
	tween.tween_callback(round_banner.queue_free)

## Presents the Hades / Vampire Survivors style 3-card power-up choice modal.
func show_power_up_selection(round_cleared: int, choices: Array[Dictionary], on_selected: Callable) -> void:
	if power_up_modal and is_instance_valid(power_up_modal):
		power_up_modal.queue_free()
		
	power_up_modal = Control.new()
	power_up_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(power_up_modal)
	
	# Darkened frosted backdrop
	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.1, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	power_up_modal.add_child(bg)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_theme_constant_override("separation", 24)
	power_up_modal.add_child(main_vbox)
	
	# Header
	var title = Label.new()
	title.text = "⚔ ROUND %d CLEARED! ⚔" % round_cleared
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	title.add_theme_constant_override("shadow_offset_y", 3)
	main_vbox.add_child(title)
	
	var subtitle = Label.new()
	subtitle.text = "Choose a Blessing to empower your run:"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	main_vbox.add_child(subtitle)
	
	# Cards Container
	var cards_hbox = HBoxContainer.new()
	cards_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_hbox.add_theme_constant_override("separation", 28)
	main_vbox.add_child(cards_hbox)
	
	for choice in choices:
		var card = _create_power_up_card(choice, func():
			if Global.has_method("play_button_sound"): Global.play_button_sound()
			if power_up_modal and is_instance_valid(power_up_modal):
				power_up_modal.queue_free()
				power_up_modal = null
			on_selected.call(choice["id"])
		)
		cards_hbox.add_child(card)

## Builds an individual interactive blessing card.
func _create_power_up_card(choice: Dictionary, on_click: Callable) -> Control:
	var perk_color: Color = choice.get("color", Color.CYAN)
	
	var card_panel = PanelContainer.new()
	card_panel.custom_minimum_size = Vector2(290, 380)
	
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.09, 0.11, 0.16, 0.95)
	card_style.border_color = perk_color
	card_style.set_border_width_all(2)
	card_style.corner_radius_top_left = 14
	card_style.corner_radius_top_right = 14
	card_style.corner_radius_bottom_left = 14
	card_style.corner_radius_bottom_right = 14
	card_style.content_margin_left = 20
	card_style.content_margin_right = 20
	card_style.content_margin_top = 20
	card_style.content_margin_bottom = 20
	card_panel.add_theme_stylebox_override("panel", card_style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	card_panel.add_child(vbox)
	
	# Type Badge
	var badge = Label.new()
	badge.text = "[ %s ]" % choice.get("type", "BLESSING")
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_color", perk_color.lightened(0.2))
	vbox.add_child(badge)
	
	# Icon
	var icon_label = Label.new()
	icon_label.text = choice.get("icon", "★")
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 48)
	vbox.add_child(icon_label)
	
	# Title
	var title_label = Label.new()
	title_label.text = choice.get("name", "Unknown")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", perk_color)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title_label)
	
	# Tagline
	var tagline_label = Label.new()
	tagline_label.text = choice.get("tagline", "")
	tagline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline_label.add_theme_font_size_override("font_size", 13)
	tagline_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
	tagline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(tagline_label)
	
	# Spacer
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	
	# Description
	var desc_label = Label.new()
	desc_label.text = choice.get("description", "")
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_label)
	
	# Spacer
	var spacer2 = Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer2)
	
	# Choose Button
	var choose_btn = Button.new()
	choose_btn.text = "Select Blessing"
	choose_btn.custom_minimum_size = Vector2(0, 42)
	choose_btn.add_theme_font_size_override("font_size", 16)
	choose_btn.pressed.connect(on_click)
	vbox.add_child(choose_btn)
	
	# Hover highlight animation
	card_panel.mouse_entered.connect(func():
		card_style.border_color = perk_color.lightened(0.4)
		card_style.set_border_width_all(3)
		card_panel.scale = Vector2(1.03, 1.03)
	)
	card_panel.mouse_exited.connect(func():
		card_style.border_color = perk_color
		card_style.set_border_width_all(2)
		card_panel.scale = Vector2(1.0, 1.0)
	)
	card_panel.pivot_offset = Vector2(145, 190)
	
	return card_panel

## Presents the Run Defeat Summary screen when the Little Girl or Old Man falls.
func show_game_over(round_reached: int, monsters_slain: int, perks: Array[Dictionary], on_restart: Callable, on_menu: Callable) -> void:
	if game_over_modal and is_instance_valid(game_over_modal):
		game_over_modal.queue_free()
		
	game_over_modal = Control.new()
	game_over_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(game_over_modal)
	
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.02, 0.03, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over_modal.add_child(bg)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	game_over_modal.add_child(vbox)
	
	var title = Label.new()
	title.text = "RUN OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color(0.95, 0.2, 0.2))
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	title.add_theme_constant_override("shadow_offset_y", 4)
	vbox.add_child(title)
	
	var sub = Label.new()
	sub.text = "The shadows overcame the defenseless..."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.8, 0.7, 0.7))
	vbox.add_child(sub)
	
	var stats_panel = PanelContainer.new()
	var sp_style = StyleBoxFlat.new()
	sp_style.bg_color = Color(0.1, 0.06, 0.08, 0.8)
	sp_style.border_color = Color(0.5, 0.2, 0.2, 0.8)
	sp_style.set_border_width_all(1)
	sp_style.corner_radius_top_left = 10
	sp_style.corner_radius_top_right = 10
	sp_style.corner_radius_bottom_left = 10
	sp_style.corner_radius_bottom_right = 10
	sp_style.content_margin_left = 30
	sp_style.content_margin_right = 30
	sp_style.content_margin_top = 20
	sp_style.content_margin_bottom = 20
	stats_panel.add_theme_stylebox_override("panel", sp_style)
	vbox.add_child(stats_panel)
	
	var stats_vbox = VBoxContainer.new()
	stats_vbox.add_theme_constant_override("separation", 10)
	stats_panel.add_child(stats_vbox)
	
	var round_stat = Label.new()
	round_stat.text = "Highest Round Reached:  ROUND %d" % round_reached
	round_stat.add_theme_font_size_override("font_size", 24)
	round_stat.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	stats_vbox.add_child(round_stat)
	
	var slain_stat = Label.new()
	slain_stat.text = "Monsters Slain in Run:  %d" % monsters_slain
	slain_stat.add_theme_font_size_override("font_size", 20)
	slain_stat.add_theme_color_override("font_color", Color.WHITE)
	stats_vbox.add_child(slain_stat)
	
	if perks.size() > 0:
		var perk_names: Array[String] = []
		for p in perks:
			perk_names.append(p.get("name", "Perk"))
		var perks_stat = Label.new()
		perks_stat.text = "Blessings Acquired:  " + ", ".join(perk_names)
		perks_stat.add_theme_font_size_override("font_size", 16)
		perks_stat.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		stats_vbox.add_child(perks_stat)
		
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 24)
	vbox.add_child(btn_hbox)
	
	var retry_btn = Button.new()
	retry_btn.text = "Start From Round 1"
	retry_btn.add_theme_font_size_override("font_size", 24)
	retry_btn.custom_minimum_size = Vector2(240, 56)
	retry_btn.pressed.connect(func():
		if Global.has_method("play_button_sound"): Global.play_button_sound()
		if game_over_modal and is_instance_valid(game_over_modal):
			game_over_modal.queue_free()
			game_over_modal = null
		on_restart.call()
	)
	btn_hbox.add_child(retry_btn)
	
	var menu_btn = Button.new()
	menu_btn.text = "Main Menu"
	menu_btn.add_theme_font_size_override("font_size", 24)
	menu_btn.custom_minimum_size = Vector2(200, 56)
	menu_btn.pressed.connect(func():
		if Global.has_method("play_button_sound"): Global.play_button_sound()
		on_menu.call()
	)
	btn_hbox.add_child(menu_btn)

## Called every frame to update the health status display dynamically.
func _process(_delta: float) -> void:
	if not grid_manager: return
	
	var needs_update = false
	var current_actor_count = grid_manager.grid.size()

	if current_actor_count != _last_actor_count:
		needs_update = true
		_last_actor_count = current_actor_count

	# Check Little Girl health & shield
	for pos in grid_manager.grid:
		var actor = grid_manager.grid[pos]
		if is_instance_valid(actor) and actor.get_actor_name() == "Little Girl":
			var state_key = "%d:%s" % [actor.current_health, str(actor.has_shield)]
			if not _last_hp_state.has("Girl") or _last_hp_state["Girl"] != state_key:
				needs_update = true
				_last_hp_state["Girl"] = state_key
			break

	# Check monster health states
	for i in range(active_round_monsters.size()):
		var m = active_round_monsters[i]
		var key = "m_%d" % i
		var current_hp = m.current_health if (is_instance_valid(m) and m.current_health > 0) else 0
		if not _last_hp_state.has(key) or _last_hp_state[key] != current_hp:
			needs_update = true
			_last_hp_state[key] = current_hp

	if needs_update or hp_label.text == "":
		_render_hp_text()

## Renders the formatted health status text into the UI panel.
func _render_hp_text() -> void:
	var girl_hp = "Dead"
	for pos in grid_manager.grid:
		var actor = grid_manager.grid[pos]
		if is_instance_valid(actor) and actor.get_actor_name() == "Little Girl":
			var shield_str = " [SHIELD]" if actor.has_shield else ""
			girl_hp = "%d/%d%s" % [actor.current_health, actor.get_max_health(), shield_str]
			break
			
	var text = "Health Status\n------------------\nLittle Girl: " + girl_hp
	
	if active_round_monsters.size() > 0:
		text += "\n\nEnemies:"
		for i in range(active_round_monsters.size()):
			var m = active_round_monsters[i]
			if is_instance_valid(m) and m.current_health > 0:
				text += "\n  • %s: %d/%d" % [m.name, m.current_health, m.get_max_health()]
			else:
				var m_name = m.name if is_instance_valid(m) else ("Monster " + str(i + 1))
				text += "\n  • %s: Dead" % m_name
				
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

func update_combo(count: int, time_left: float, required_combo: int = 3) -> void:
	# ⚡ Bolt Optimization: Prevent redundant string allocations and layout recalculations every frame
	var display_time = snapped(time_left, 0.01)
	if count == _last_combo_count and display_time == _last_combo_time and required_combo == _last_required_combo:
		return

	_last_combo_count = count
	_last_combo_time = display_time
	_last_required_combo = required_combo

	if count > 0:
		combo_panel.show()
		combo_label.text = "COMBO: x%d\nTime: %.2fs" % [count, display_time]
		if count >= required_combo:
			special_label.show()
		else:
			special_label.hide()
	else:
		combo_panel.hide()
		special_label.hide()

func update_heal_ui(charges: int, max_range: int) -> void:
	if charges > 0:
		heal_label.show()
		var range_str = (" (Range: %d)" % max_range) if max_range > 1 else ""
		var charges_str = (" [x%d]" % charges) if charges > 1 else ""
		heal_label.text = "✚ Heal Available%s%s [ Press H ]" % [charges_str, range_str]
	else:
		heal_label.hide()

func clear_heal_ui() -> void:
	heal_label.hide()
