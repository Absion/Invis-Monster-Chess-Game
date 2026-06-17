extends Node
class_name TurnManager

## Service managing the turn phases.
##
## Phases run in order: MONSTERS -> GIRL -> MAN.
## This service is responsible for keeping track of whose turn it is
## and alerting the rest of the game when the phase changes via signals.

## Enum defining the specific phases of a turn.
enum TurnPhase {
	MONSTERS,
	GIRL,
	MAN
}

## The currently active phase.
var current_phase: TurnPhase = TurnPhase.MONSTERS

## Emitted whenever the turn phase changes so UI, AI, and Contexts can react.
signal turn_started(phase: TurnPhase)

## Initializer called by CombatContext.
func setup() -> void:
	# Use call_deferred to give the rest of the scene tree a moment to settle
	# (like grid loading and actors spawning) before kicking off the first turn.
	call_deferred("_start_current_phase")

## Internal method to fire the signal and announce the current phase.
func _start_current_phase() -> void:
	print("Turn started: ", get_phase_name(current_phase))
	turn_started.emit(current_phase)

## Ends the active phase and cycles to the next one in the order.
func end_turn() -> void:
	if process_mode == Node.PROCESS_MODE_DISABLED:
		return
		
	print("Turn ended: ", get_phase_name(current_phase))
	
	# Cycle the enum state
	match current_phase:
		TurnPhase.MONSTERS:
			current_phase = TurnPhase.GIRL
		TurnPhase.GIRL:
			current_phase = TurnPhase.MAN
		TurnPhase.MAN:
			current_phase = TurnPhase.MONSTERS
			
	_start_current_phase()

## Helper function to retrieve a human-readable string for the UI.
func get_phase_name(phase: TurnPhase) -> String:
	match phase:
		TurnPhase.MONSTERS: return "Monsters"
		TurnPhase.GIRL: return "Little Girl"
		TurnPhase.MAN: return "Old Man"
	return "Unknown"
