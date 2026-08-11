extends Control

@onready var title_label = $TitleLabel
@onready var main_vbox = $CenterContainer/MainVBox
@onready var settings_vbox = $CenterContainer/SettingsVBox
@onready var difficulty_label = $CenterContainer/SettingsVBox/DifficultyLabel
@onready var music_slider = $CenterContainer/SettingsVBox/MusicSlider
@onready var sfx_slider = $CenterContainer/SettingsVBox/SFXSlider

func _ready() -> void:
	settings_vbox.hide()
	main_vbox.show()
	if title_label: title_label.show()
	_update_difficulty_label()
	
	if music_slider: music_slider.value = Global.music_volume
	if sfx_slider: sfx_slider.value = Global.sfx_volume
	
	if Global.has_method("play_main_menu_music"):
		Global.play_main_menu_music()

func _on_start_button_pressed() -> void:
	if Global.has_method("play_button_sound"):
		Global.play_button_sound()
	get_tree().change_scene_to_file("res://scenes/combat_test.tscn")

func _on_settings_button_pressed() -> void:
	if Global.has_method("play_button_sound"):
		Global.play_button_sound()
	main_vbox.hide()
	if title_label: title_label.hide()
	settings_vbox.show()

func _on_back_button_pressed() -> void:
	if Global.has_method("play_button_sound"):
		Global.play_button_sound()
	settings_vbox.hide()
	if title_label: title_label.show()
	main_vbox.show()

func _on_easy_button_pressed() -> void:
	if Global.has_method("play_button_sound"):
		Global.play_button_sound()
	Global.current_difficulty = Global.Difficulty.EASY
	_update_difficulty_label()

func _on_normal_button_pressed() -> void:
	if Global.has_method("play_button_sound"):
		Global.play_button_sound()
	Global.current_difficulty = Global.Difficulty.NORMAL
	_update_difficulty_label()

func _on_hard_button_pressed() -> void:
	if Global.has_method("play_button_sound"):
		Global.play_button_sound()
	Global.current_difficulty = Global.Difficulty.HARD
	_update_difficulty_label()

func _update_difficulty_label() -> void:
	match Global.current_difficulty:
		Global.Difficulty.EASY:
			difficulty_label.text = "Current: Easy (4 Enemies)"
		Global.Difficulty.NORMAL:
			difficulty_label.text = "Current: Normal (6 Enemies)"
		Global.Difficulty.HARD:
			difficulty_label.text = "Current: Hard (10 Enemies)"

func _on_music_slider_changed(value: float) -> void:
	Global.music_volume = value
	if Global.has_method("update_volumes"):
		Global.update_volumes()

func _on_sfx_slider_changed(value: float) -> void:
	Global.sfx_volume = value
	if Global.has_method("update_volumes"):
		Global.update_volumes()
