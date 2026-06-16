# Architecture Guidelines

This document outlines the core architectural patterns used in this project. We emphasize **Composition over Inheritance** and utilize a **Context-Service Dependency Injection** pattern.

## 1. Composition over Inheritance

Rather than building deep inheritance trees (e.g., `Entity` -> `Character` -> `Player` -> `OldMan`), we build our objects using compositional nodes.

- A character is a basic Node3D with components (child nodes) such as `HealthComponent`, `MovementComponent`, `VisionComponent`.
- By composing nodes, we maximize flexibility and adherence to the Extensible and Maintainable design pillars.

## 2. Contexts

A **Context** represents a discrete game state or scene (e.g., `MainMenuContext`, `CombatContext`, `CutsceneContext`). Contexts manage their own isolated rules and coordinate their services. 

There is also a `GlobalContext` that acts as the highest-level orchestrator. It holds data that needs to be available across different context states (e.g., current save data, persistent game settings) to keep the code modular and clean.

### Lifecycle of a Context

Every context inherits from `Context` (defined in `context/context.gd`). The lifecycle methods must be executed in the following order:

1. **`build_services()`**: Instantiates the Services required by this Context and adds them to the tree as child nodes.
2. **`bind_services()`**: Passes dependencies into the services. Services should not directly use `get_node()` to find siblings; instead, the Context injects them.
3. **`setup()`**: Initializes the logic for the context and its services now that all dependencies are resolved.

## 3. Services

**Services** are managers or systems that handle specific domain logic (e.g., `TurnManager`, `GridManager`, `CameraManager`).

- Services are instantiated as node children of a Context.
- Services should have clear boundaries and defined inputs/outputs.
- If a Service needs access to another Service, it is provided via Dependency Injection during the Context's `bind_services()` phase.

## Example Flow

```gdscript
# Inside CombatContext

func build_services() -> void:
    grid_manager = GridManager.new()
    add_child(grid_manager)
    
    turn_manager = TurnManager.new()
    add_child(turn_manager)

func bind_services() -> void:
    # Inject grid_manager into turn_manager so turn_manager knows about the grid
    turn_manager.inject_grid(grid_manager)

func setup() -> void:
    grid_manager.setup()
    turn_manager.setup()
```

## 4. The Camera System

We use a custom 3D **Gimbal Camera** that simulates an isometric perspective using `Orthogonal` projection.
- **Rotation**: Standard X: -30°, Y: 45°, Z: 0°
- **Controls**: Edge panning, WASD panning, mouse drag rotation around the Y-axis, and scroll zooming.
- The camera should be managed by a `CameraManager` or directly inside the active Context depending on the scope of control required.
