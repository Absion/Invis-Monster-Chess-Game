## 2026-06-27 - Godot testing in this repo
**Learning:** The repo contains only Windows executables (PE32+) and no Godot headless linux binary is installed or present.
**Action:** If modifying Godot scripts on a linux runner without a custom engine installed, I can only verify syntax visually or rely on godot test setups if configured.

## 2026-06-27 - Expensive Pathfinding in Loops
**Learning:** In Godot 4.x AStarGrid2D, calling a method that loops over all units to toggle cell solid states *inside* a nested loop for range calculation creates an enormous performance bottleneck ((R^2 	imes N)$). It effectively makes a simple radial highlight scale terribly with the number of actors.
**Action:** Always batch grid/AStar state mutations (like clearing solid points for ignored units) OUTSIDE of pathfinding iteration loops, do the AStar path calculations, and restore them afterwards.
## 2026-06-27 - AStarGrid2D State Mutation in Nested Loops
**Learning:** Mutating the global state of an `AStarGrid2D` (e.g., `astar.set_point_solid`) inside a nested loop that calls a pathfinding function (like `get_id_path`) for every cell is an $O(Cells \times Entities)$ anti-pattern that heavily bottlenecks GDScript execution. The `highlight_attack_range` function was calling `get_naive_path` in a nested loop over the grid area, and `get_naive_path` iterated over the entire dictionary of actors to clear and restore monster obstacles for every single cell check.
**Action:** Extract the clearing and restoring of dynamic obstacles (like ignoring specific actors) outside of the pathfinding loop. Clear the obstacles once before the loop, use standard pathfinding inside the loop, and restore the obstacles after the loop finishes to avoid redundant state mutations and iterations.
