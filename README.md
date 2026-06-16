# Invisible Monster Chess Game

An isometric 3D turn-based game where the player controls two characters:
- **The Old Man**: A capable fighter who is blind to the monsters.
- **The Little Girl**: A vulnerable character who can see the invisible monsters.

The monsters are invisible to the man but visible to the girl. The player must use the girl's turn to spot the monsters and the man's turn to engage them based on memory, as the monsters will disappear during his turn. Monsters will preferentially hunt the little girl.

Turn Order: Monsters -> Girl -> Man.

## Core Design Pillars

To ensure that the codebase remains robust as new coders join the project, all code MUST adhere to the following core pillars:

1. **Readable**: Code should explain itself. Use clear, descriptive variable and method names. Provide comments and docstrings (`##`) for classes and public methods.
2. **Testable**: Systems should be decoupled to allow for easy unit testing.
3. **Understandable**: The flow of logic should be easy to follow. Avoid deep nesting or overly clever "magic" code.
4. **Maintainable**: The codebase should be structured logically so that fixing bugs does not introduce new ones.
5. **Scalable**: Adding new characters, abilities, or enemy types should not require massive rewrites of core systems.
6. **Extensible**: The architecture must support future feature additions seamlessly. 

*(Compromises to these pillars should only be made for explicitly necessary performance optimizations or security constraints).*

## Architecture Overview

This project uses **Composition over Inheritance** for its file structure and architecture. We use a **Context** and **Dependency Injection** pattern to manage game state and systems.

Please read the [ARCHITECTURE.md](ARCHITECTURE.md) for a detailed breakdown of how to build and integrate features in this project.

## Project Structure

- `context/`: Contains the global and state-specific Contexts (e.g., `GlobalContext`, `CombatContext`) and their base definitions.
- `actors/`: Characters, monsters, and entities.
- `camera/`: Contains the custom 3D isometric Gimbal Camera.
- `scenes/`: General game scenes, UI, and level layouts.

## Setup Instructions

1. Clone the repository.
2. Open the project in Godot 4.x.
3. Ensure the project settings are correctly configured for a 3D isometric view.
4. Read through `ARCHITECTURE.md` before creating new nodes or scripts.

## UML Diagrams

### Architecture & Service Injection
The game uses a composition-based architecture where `CombatContext` manages all the distinct gameplay services.

```mermaid
classDiagram
    class Context {
        +Array[Node] services
        +build_services()
        +bind_services()
        +setup()
        +register_service(service: Node)
    }

    class CombatContext {
        +GridManager grid_manager
        +TurnManager turn_manager
        +MonsterAIController monster_ai
        +GirlAIController girl_ai
        +CombatUI combat_ui
        +Actor active_actor
        +setup()
        +build_services()
        -_handle_grid_click(x, z)
        -_execute_blind_attack(actor, x, z)
    }

    Context <|-- CombatContext

    CombatContext *-- GridManager
    CombatContext *-- TurnManager
    CombatContext *-- MonsterAIController
    CombatContext *-- GirlAIController
    CombatContext *-- CombatUI

    class GridManager {
        +Dictionary grid
        +AStarGrid2D astar
        +move_actor(actor, to_x, to_z)
        +place_actor(actor, x, z)
    }

    class TurnManager {
        +TurnPhase current_phase
        +end_turn()
        +turn_started(phase)
    }

    class MonsterAIController {
        +_process_monsters()
        +_process_single_monster()
    }
    
    class GirlAIController {
        +_process_girl_turn()
    }
```

### Turn Cycle State Machine
The core loop cycles between the three main phases.

```mermaid
stateDiagram-v2
    [*] --> MONSTERS : Game Start
    MONSTERS --> GIRL : end_turn()
    GIRL --> MAN : end_turn()
    MAN --> MONSTERS : end_turn()

    state MONSTERS {
        [*] --> ProcessMonsters
        ProcessMonsters --> MoveTowardsGirl
        MoveTowardsGirl --> AttackIfAdjacent
        AttackIfAdjacent --> [*]
    }

    state GIRL {
        [*] --> FleeMonsters
        FleeMonsters --> MaximizeDistance
        MaximizeDistance --> MoveAndWait
        MoveAndWait --> [*]
    }

    state MAN {
        [*] --> AwaitPlayerInput
        AwaitPlayerInput --> ClickRedSquare
        ClickRedSquare --> MoveAndAttack
        MoveAndAttack --> [*]
    }
```

### Combat Sequence Flow
An example sequence of how the Old Man's blind attack is executed by the system.

```mermaid
sequenceDiagram
    actor Player
    participant CombatContext
    participant GridManager
    participant TurnManager
    participant TargetActor

    Player->>CombatContext: Click on Red Square (x, z)
    CombatContext->>CombatContext: _handle_grid_click()
    CombatContext->>GridManager: get_naive_path(start, target)
    GridManager-->>CombatContext: Path (ignores invisibles)
    
    loop For each step in path
        CombatContext->>GridManager: move_actor(OldMan, step)
    end
    
    CombatContext->>GridManager: get_actor_at(target.x, target.z)
    GridManager-->>CombatContext: TargetActor
    
    alt Target is Monster
        CombatContext->>TargetActor: take_damage(damage)
    else Target is empty
        CombatContext->>CombatContext: Miss! ("SWISH")
    end
    
    CombatContext->>TurnManager: end_turn()
```
