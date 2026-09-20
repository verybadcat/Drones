extends Node2D
## The map's terrain, drawn ONCE and then left alone — Godot keeps a canvas
## item's recorded draw commands between frames, so a node that never
## calls queue_redraw() again costs the script nothing per frame after its
## first draw. GameConfig.draw_terrain used to be called from inside
## BattleManager._draw (redrawn EVERY frame, for the fire tracers) and from
## DeploymentMagnifier._draw (redrawn every frame while it's shown), which
## rebuilt every contour segment, building block and tree from scratch each
## time: about 10ms a frame on the older maps and about 67ms on a map with
## real-data tree cover and elevation — battles and the deployment drag
## loupe both stuttered badly. Terrain never changes within a battle, so
## it lives here instead, and only anything that genuinely changes
## (tracers, tokens) stays in a per-frame draw.
##
## Deliberately no class_name (same brand-new-class_name caution as main.
## gd's history_viewer): callers preload this script.

func _draw() -> void:
	GameConfig.draw_terrain(self)
