## 2026-06-27 - Godot testing in this repo
**Learning:** The repo contains only Windows executables (PE32+) and no Godot headless linux binary is installed or present.
**Action:** If modifying Godot scripts on a linux runner without a custom engine installed, I can only verify syntax visually or rely on godot test setups if configured.

## 2026-06-27 - Expensive Pathfinding in Loops
**Learning:** In Godot 4.x AStarGrid2D, calling a method that loops over all units to toggle cell solid states *inside* a nested loop for range calculation creates an enormous performance bottleneck ((R^2 	imes N)$). It effectively makes a simple radial highlight scale terribly with the number of actors.
**Action:** Always batch grid/AStar state mutations (like clearing solid points for ignored units) OUTSIDE of pathfinding iteration loops, do the AStar path calculations, and restore them afterwards.
## 2026-06-27 - AStarGrid2D State Mutation in Nested Loops
**Learning:** Mutating the global state of an `AStarGrid2D` (e.g., `astar.set_point_solid`) inside a nested loop that calls a pathfinding function (like `get_id_path`) for every cell is an $O(Cells \times Entities)$ anti-pattern that heavily bottlenecks GDScript execution. The `highlight_attack_range` function was calling `get_naive_path` in a nested loop over the grid area, and `get_naive_path` iterated over the entire dictionary of actors to clear and restore monster obstacles for every single cell check.
**Action:** Extract the clearing and restoring of dynamic obstacles (like ignoring specific actors) outside of the pathfinding loop. Clear the obstacles once before the loop, use standard pathfinding inside the loop, and restore the obstacles after the loop finishes to avoid redundant state mutations and iterations.
## 2026-06-27 - AStarGrid2D Wrapper Functions in Loops
**Learning:** Using wrapper pathfinding functions (like `get_grid_path` in `GridManager`) inside deep nested loops (like calculating escape routes in `GirlAIController`) introduces severe performance overhead. These wrappers often contain safety checks or state mutations (like clearing start/end node solid states) that become redundant and costly when executed $O(R^2)$ times for the same origin.
**Action:** When pathfinding inside a loop where the origin point is fixed, hoist any state mutations for the origin outside the loop. Use the underlying `astar.get_id_path()` directly inside the loop, relying on loop preconditions (like `is_cell_walkable`) to guarantee the destination node's state instead of running wrapper checks.
## 2026-06-27 - AStar Grid Rebuild on Actor Movement
**Learning:** Rebuilding the entire AStar grid's solid region by iterating over all actors (`astar.fill_solid_region` and subsequent `set_point_solid` in a loop) during every actor placement or movement creates an unnecessary $O(N)$ overhead. Godot's AStar allows incremental, specific point updates.
**Action:** Use O(1) incremental updates like `astar.set_point_solid(pos, true/false)` when placing or removing actors instead of recalculating the entire grid of obstacles from scratch.
