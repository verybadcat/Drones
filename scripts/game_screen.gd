class_name GameScreen
extends Control
## One screen of the game (level select, deployment, the battle, the end-of-battle
## report). main.gd holds at most one at a time, opens it with everything it needs already
## set, and closes it by freeing it: a screen owns every widget it creates — under itself,
## or, for what has to live in the map's SubViewport (add_map_node), tracked here and
## freed with it — so nothing from one screen can be left behind on the next. What a
## screen needs from the parts of the display that outlast it (the map marks and clock,
## the elevation readout) it says through the small methods below, not by main.gd
## knowing which screen is up.
##
## Full-rect and mouse-transparent, so it adds nothing of its own to the layout: its
## children are placed in screen coordinates exactly as if they were children of main.

var _map_nodes: Array[Node] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Whether the map's own marks — the scale bar, the compass, the weather block — and the
## tactical clock are shown while this screen is up.
func shows_map_marks() -> bool:
	return true


## Whether the weather is presented while this screen is up: the wind and precipitation block
## on the map and the wind and rain sound. Weather.current itself is global — it outlives every
## screen, and is rolled when deployment starts — so a screen that has no weather to show says
## so here rather than clearing it.
func shows_weather() -> bool:
	return true


## What the tactical clock reads while this screen is up (frozen at the planned H-hour
## until a battle is running).
func clock_text() -> String:
	return "%02d:00:00" % int(GameConfig.SCENARIO_START_HOUR)


## The mouse's position in the map's own world space, for the elevation readout;
## Vector2.ZERO when this screen has no map.
func map_mouse_world_position() -> Vector2:
	return Vector2.ZERO


## Whether the battle shown on this screen has finished (the wind and rain sound stop with it).
func battle_is_over() -> bool:
	return false


## Adds `node` to the map's SubViewport (the map itself lives there), and remembers it so
## it is freed with this screen.
func add_map_node(map_viewport: SubViewport, node: Node) -> void:
	map_viewport.add_child(node)
	_map_nodes.append(node)


func _exit_tree() -> void:
	for node in _map_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_map_nodes.clear()
