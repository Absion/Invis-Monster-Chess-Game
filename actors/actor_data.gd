extends Resource
class_name ActorData

## Represents the base statistics for any actor in the game.
## 
## Use this class to create .tres files for specific characters or monster types.

@export var name: String = "Unknown Actor"
@export var max_health: int = 10
@export var damage: int = 2
@export var movement_range: int = 3
