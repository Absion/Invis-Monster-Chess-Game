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

## 5. Godot 3D Asset Handling (GLTF/GLB)

When dynamically loading and manipulating `.glb` or `.tscn` files imported from external software (e.g., Blender) via code, keep these critical lessons in mind:

- **Visibility & Hidden Meshes**: Godot's `instantiate()` brings in the entire file hierarchy exactly as exported. Hidden or extraneous meshes (like modeling bases, cylinders, or unused weapon variants) must be forcefully hidden recursively in GDScript if they weren't fully stripped during the Godot import process.
- **Orientation Mismatches**: External tools often treat `+Z` or `+Y` as "Forward", while Godot's built-in 3D functions like `look_at()` strictly use `-Z` as Forward. When attaching 3D assets to actors, wrap the instantiated scene in a spatial `Pivot` (e.g., `Node3D`) and permanently rotate the child asset (e.g., `rotation.y = PI`) so the front of the model actually faces `-Z` before using `look_at()` on the pivot.
- **Animation Tracks & Conflicts**: 
  - `AnimationPlayer` tracks use strict relative `NodePath` structures. Duplicating or reparenting the `AnimationPlayer` at runtime without maintaining the exact relative paths to the target meshes will cause the animation to silently fail (the engine plays it, but no mesh moves because the paths break).
  - If a 3D file has multiple animations intended for different subsets of the mesh (e.g., a left hand swing vs a right hand swing), a single `AnimationPlayer` cannot reliably play both simultaneously on the same tree without overriding. For dual-wield setups baked into a single GLB, spawn the single instance, isolate the relevant sub-meshes, and trigger the native animation tracks designed by the creator to preserve their offsets and synchronization.
