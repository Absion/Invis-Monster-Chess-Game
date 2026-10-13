extends Node
class_name RogueliteManager

## Service managing Roguelite run progression, round scaling, and power-up blessings.
##
## Tracks current round, monsters defeated, active perks, and generates
## 3-choice random power-up cards between rounds in the style of Hades and Vampire Survivors.

signal perk_acquired(perk_id: String, perk_name: String)
@warning_ignore("unused_signal")
signal round_started(round_number: int)

## Catalog of all available blessings tailored to the Old Man, Little Girl, and Invis Monster mechanics.
const PERK_DEFINITIONS: Array[Dictionary] = [
	{
		"id": "echo_pulse",
		"name": "Echo Radar",
		"icon": "📡",
		"type": "INTEL",
		"color": Color(0.25, 0.85, 1.0),
		"tagline": "The air vibrates with unseen presences.",
		"description": "Swings that miss an empty tile emit an acoustic pulse, revealing all invisible monsters within 3 tiles for 1.5 seconds."
	},
	{
		"id": "heavy_cleaver",
		"name": "Sweeping Cleave",
		"icon": "⚔️",
		"type": "OFFENSE",
		"color": Color(1.0, 0.42, 0.2),
		"tagline": "Massive axes carve an unstoppable arc.",
		"description": "+3 Attack Damage. Successful strikes cleave for 4 damage to all enemies adjacent to the target."
	},
	{
		"id": "super_knockback",
		"name": "Thunder Impact",
		"icon": "🔨",
		"type": "FORCE",
		"color": Color(1.0, 0.85, 0.22),
		"tagline": "Send them hurtling across the stones.",
		"description": "Knockback pushes monsters 3 tiles away. Monsters slammed into walls or obstacles suffer 4 collision damage."
	},
	{
		"id": "swift_stride",
		"name": "Windwalker",
		"icon": "👟",
		"type": "MOBILITY",
		"color": Color(0.35, 0.9, 0.5),
		"tagline": "Close distances in the blink of an eye.",
		"description": "Old Man gains +2 Movement Range per turn, allowing rapid repositioning to intercept attackers."
	},
	{
		"id": "adrenaline_flow",
		"name": "Adrenaline Rush",
		"icon": "⚡",
		"type": "COMBO",
		"color": Color(0.85, 0.6, 1.0),
		"tagline": "Time slows as battle momentum builds.",
		"description": "Combo timer extended to 4.0s (was 2.4s). Special Whirlwind attack unlocks at Combo x2 instead of x3!"
	},
	{
		"id": "whirlwind_tempest",
		"name": "Tempest Fury",
		"icon": "🌪️",
		"type": "FINISHER",
		"color": Color(0.2, 0.7, 1.0),
		"tagline": "Unleash a vortex of dual axes.",
		"description": "Whirlwind Special Attack deals +6 bonus damage (11 total) and blasts all caught enemies backward."
	},
	{
		"id": "guardian_medic",
		"name": "Sacred Remedy",
		"icon": "✚",
		"type": "SUPPORT",
		"color": Color(0.35, 1.0, 0.65),
		"tagline": "A tether of life that bridges distance.",
		"description": "Heal can be cast from up to 3 tiles away, restores +10 HP (was 5), and has 2 charges per round."
	},
	{
		"id": "aegis_barrier",
		"name": "Aegis of Light",
		"icon": "🛡️",
		"type": "DEFENSE",
		"color": Color(1.0, 0.92, 0.4),
		"tagline": "A crystalline barrier shields the innocent.",
		"description": "Little Girl gains a Divine Shield that negates the first monster attack each round. Increases her Max HP by +10."
	},
	{
		"id": "retribution_spikes",
		"name": "Vengeful Thorns",
		"icon": "🌵",
		"type": "COUNTER",
		"color": Color(1.0, 0.3, 0.6),
		"tagline": "To touch her is to bleed.",
		"description": "When any monster strikes the Little Girl, it instantly takes 5 counter-damage and is blasted back 1 tile."
	}
]

## Current active run round
var current_round: int = 1

## Highest round reached in current session
var highest_round: int = 1

## Total monsters defeated during this run
var monsters_slain_run: int = 0

## Map of perk_id -> int (stack level)
var active_perks: Dictionary = {}

func setup() -> void:
	reset_run()

## Resets all run variables to round 1 baseline.
func reset_run() -> void:
	current_round = 1
	monsters_slain_run = 0
	active_perks.clear()
	round_started.emit(current_round)

## Advances to the next round, updating records and notifying listeners.
func advance_round() -> int:
	current_round += 1
	if current_round > highest_round:
		highest_round = current_round
	round_started.emit(current_round)
	return current_round

## Checks if the player possesses a specific perk.
func has_perk(perk_id: String) -> bool:
	return active_perks.has(perk_id) and active_perks[perk_id] > 0

## Gets the level of a specific perk.
func get_perk_level(perk_id: String) -> int:
	return active_perks.get(perk_id, 0)

## Grants a perk to the player's run build.
func add_perk(perk_id: String) -> void:
	if active_perks.has(perk_id):
		active_perks[perk_id] += 1
	else:
		active_perks[perk_id] = 1
		
	var data = get_perk_data(perk_id)
	var perk_name = data.get("name", perk_id)
	perk_acquired.emit(perk_id, perk_name)
	print("Roguelite: Acquired perk [", perk_name, "] (Level ", active_perks[perk_id], ")")

## Looks up dictionary definition by ID.
func get_perk_data(perk_id: String) -> Dictionary:
	for def in PERK_DEFINITIONS:
		if def["id"] == perk_id:
			return def
	return {}

## Generates 3 distinct random perk choices for the power-up screen.
## Prioritizes perks not yet acquired, then upgradeable ones.
func get_random_perk_choices(count: int = 3) -> Array[Dictionary]:
	var unacquired: Array[Dictionary] = []
	var acquired: Array[Dictionary] = []
	
	for perk in PERK_DEFINITIONS:
		var pid = perk["id"]
		if active_perks.has(pid):
			acquired.append(perk)
		else:
			unacquired.append(perk)
			
	unacquired.shuffle()
	acquired.shuffle()
	
	var pool: Array[Dictionary] = []
	pool.append_array(unacquired)
	pool.append_array(acquired)
	
	var result: Array[Dictionary] = []
	for i in range(mini(count, pool.size())):
		result.append(pool[i])
		
	return result

## Returns list of full perk data dictionaries for all currently owned perks.
func get_all_active_perk_data() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for def in PERK_DEFINITIONS:
		if active_perks.has(def["id"]):
			var copy = def.duplicate()
			copy["level"] = active_perks[def["id"]]
			list.append(copy)
	return list

## Computes how many monsters should spawn in the given round.
func get_monster_count_for_round(round_num: int, difficulty: Global.Difficulty) -> int:
	var base = 2 + round_num # Round 1: 3, Round 2: 4, Round 3: 5, Round 4: 6...
	if difficulty == Global.Difficulty.EASY:
		base -= 1
	elif difficulty == Global.Difficulty.HARD:
		base += 2
	return clampi(base, 2, 12)

## Computes monster health bonus for higher rounds.
func get_monster_hp_bonus(round_num: int) -> int:
	if round_num <= 2:
		return 0
	return (round_num - 2) * 2

## Computes title/name flavor for monsters in higher rounds.
func get_monster_flavor_name(index: int, round_num: int) -> String:
	if round_num >= 5 and index == 1:
		return "Monster %d (Dread Fiend)" % index
	elif round_num >= 4 and index % 2 == 0:
		return "Monster %d (Shadow Stalker)" % index
	return "Monster %d" % index

