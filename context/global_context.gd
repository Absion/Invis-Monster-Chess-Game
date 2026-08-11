extends Context
class_name GlobalContext

## The highest-level Context orchestrating the game.
##
## Typically set up as an Autoload (Singleton).
## Holds data that needs to be available to other context states 
## (e.g., active save files, global settings).

var current_level: int = 1

var music_volume: float = 1.0
var sfx_volume: float = 1.0

enum Difficulty { EASY, NORMAL, HARD }
var current_difficulty: Difficulty = Difficulty.NORMAL

var bgm_player: AudioStreamPlayer
var combat_bgm_player: AudioStreamPlayer

var sfx_ui: AudioStreamPlayer
var sfx_special: AudioStreamPlayer
var sfx_attack_man: AudioStreamPlayer
var sfx_attack_monster: AudioStreamPlayer
var sfx_wounded_monster: AudioStreamPlayer
var sfx_win: AudioStreamPlayer
var sfx_lose: AudioStreamPlayer
var sfx_heal: AudioStreamPlayer

func build_services() -> void:
	pass

func bind_services() -> void:
	pass

func setup() -> void:
	bgm_player = AudioStreamPlayer.new()
	bgm_player.stream = preload("res://resources/Sounds/UI/Funky Chill 2 loop.wav")
	add_child(bgm_player)
	bgm_player.finished.connect(func(): bgm_player.play())
	
	combat_bgm_player = AudioStreamPlayer.new()
	combat_bgm_player.stream = preload("res://resources/Sounds/Combat/BRPG_Assault_Rhythm_Loop.wav")
	add_child(combat_bgm_player)
	combat_bgm_player.finished.connect(func(): combat_bgm_player.play())

	sfx_ui = AudioStreamPlayer.new()
	sfx_ui.stream = preload("res://resources/Sounds/UI/CGM3_Select_Button_01_4.wav")
	add_child(sfx_ui)
	
	sfx_special = AudioStreamPlayer.new()
	sfx_special.stream = preload("res://resources/Sounds/Combat/FA_Power_Up_1_1.wav")
	add_child(sfx_special)
	
	sfx_attack_man = AudioStreamPlayer.new()
	sfx_attack_man.stream = preload("res://resources/Sounds/Combat/MetalWeaponEquip2.mp3")
	add_child(sfx_attack_man)
	
	sfx_attack_monster = AudioStreamPlayer.new()
	sfx_attack_monster.stream = preload("res://resources/Sounds/Combat/Warg Attack 1.mp3")
	add_child(sfx_attack_monster)
	
	sfx_wounded_monster = AudioStreamPlayer.new()
	sfx_wounded_monster.stream = preload("res://resources/Sounds/Combat/Warg Wounded 1.mp3")
	add_child(sfx_wounded_monster)
	
	sfx_win = AudioStreamPlayer.new()
	sfx_win.stream = preload("res://resources/Sounds/UI/LQ_Stage Clear.wav")
	add_child(sfx_win)
	
	sfx_lose = AudioStreamPlayer.new()
	sfx_lose.stream = preload("res://resources/Sounds/UI/PP_Negative_Trigger_1_1.wav")
	add_child(sfx_lose)

	sfx_heal = AudioStreamPlayer.new()
	sfx_heal.stream = preload("res://resources/Sounds/Combat/CGM3_Small_Positive_Stinger_01_2.wav")
	add_child(sfx_heal)

	update_volumes()

func update_volumes() -> void:
	# Convert linear 0.0-1.0 scale to logarithmic decibels
	# Avoid log(0) math errors
	var music_db = linear_to_db(max(music_volume, 0.0001))
	var sfx_db = linear_to_db(max(sfx_volume, 0.0001))
	
	if music_volume == 0.0: music_db = -80.0
	if sfx_volume == 0.0: sfx_db = -80.0
	
	if bgm_player: bgm_player.volume_db = music_db - 5.0 # Keep this one slightly quieter 
	if combat_bgm_player: combat_bgm_player.volume_db = music_db
	
	if sfx_ui: sfx_ui.volume_db = sfx_db
	if sfx_special: sfx_special.volume_db = sfx_db
	if sfx_attack_man: sfx_attack_man.volume_db = sfx_db
	if sfx_attack_monster: sfx_attack_monster.volume_db = sfx_db
	if sfx_wounded_monster: sfx_wounded_monster.volume_db = sfx_db
	if sfx_win: sfx_win.volume_db = sfx_db
	if sfx_lose: sfx_lose.volume_db = sfx_db
	if sfx_heal: sfx_heal.volume_db = sfx_db

func play_main_menu_music() -> void:
	if combat_bgm_player and combat_bgm_player.playing:
		combat_bgm_player.stop()
	if bgm_player and not bgm_player.playing:
		bgm_player.play()

func play_combat_music() -> void:
	if bgm_player and bgm_player.playing:
		bgm_player.stop()
	if combat_bgm_player and not combat_bgm_player.playing:
		combat_bgm_player.play()

func play_button_sound() -> void:
	if sfx_ui: sfx_ui.play()

func play_special_attack() -> void:
	if sfx_special: sfx_special.play()

func play_old_man_attack() -> void:
	if sfx_attack_man: sfx_attack_man.play()
	
func play_monster_attack() -> void:
	if sfx_attack_monster: sfx_attack_monster.play()
	
func play_monster_wounded() -> void:
	if sfx_wounded_monster: sfx_wounded_monster.play()
	
func play_win_sound() -> void:
	if sfx_win: sfx_win.play()
	
func play_lose_sound() -> void:
	if sfx_lose: sfx_lose.play()

func play_heal_sound() -> void:
	if sfx_heal: sfx_heal.play()
