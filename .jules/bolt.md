## 2026-06-27 - Godot testing in this repo
**Learning:** The repo contains only Windows executables (PE32+) and no Godot headless linux binary is installed or present.
**Action:** If modifying Godot scripts on a linux runner without a custom engine installed, I can only verify syntax visually or rely on godot test setups if configured.

## 2026-06-27 - Expensive Pathfinding in Loops
**Learning:** In Godot 4.x AStarGrid2D, calling a method that loops over all units to toggle cell solid states *inside* a nested loop for range calculation creates an enormous performance bottleneck ((R^2 	imes N)$). It effectively makes a simple radial highlight scale terribly with the number of actors.
**Action:** Always batch grid/AStar state mutations (like clearing solid points for ignored units) OUTSIDE of pathfinding iteration loops, do the AStar path calculations, and restore them afterwards.
