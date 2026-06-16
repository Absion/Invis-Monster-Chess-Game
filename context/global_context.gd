extends Context
class_name GlobalContext

## The highest-level Context orchestrating the game.
##
## Typically set up as an Autoload (Singleton).
## Holds data that needs to be available to other context states 
## (e.g., active save files, global settings).

# Example global state variables
var current_level: int = 1
var music_volume: float = 1.0

func build_services() -> void:
	# E.g., register_service(SaveManager.new())
	# register_service(AudioManager.new())
	pass

func bind_services() -> void:
	# Inject dependencies between global services if needed
	pass

func setup() -> void:
	# Initialize global logic
	pass
