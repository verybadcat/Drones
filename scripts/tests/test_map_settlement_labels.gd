extends SceneTree
## Direct user request: "For all maps, if there is a city, put its name on the map in both English and Ukrainian
## letters." (And, when the maps turned out to have villages, not cities: "Right, villages, yes.") Every map
## now lists its named villages in CURRENT_MAP.settlements, and GameConfig.draw_terrain (so the battle map, the
## deployment map and the deployment loupe) draws each one as English over Ukrainian, last, on top of the
## buildings and trees.
##
## What this checks: every map has at least one village; each is named in plain English letters AND in
## Ukrainian (Cyrillic) letters; each stands inside the map; the font the game draws with has every one of
## those letters (a missing glyph would show as an empty box); and the real drawing routine runs through for
## every map without error.
##
## Run: godot --headless --path . --script scripts/tests/test_map_settlement_labels.gd
var failures := 0
var draw_runs := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")


## A node whose only job is to run the game's own terrain drawing.
class Canvas extends Node2D:
	var drawn := false
	func _draw() -> void:
		GameConfig.draw_terrain(self)
		drawn = true


func is_plain_english(text: String) -> bool:
	for i in text.length():
		var c: int = text.unicode_at(i)
		var letter: bool = (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
		if not letter and c != 45 and c != 32:
			return false
	return text.length() > 0


func is_ukrainian(text: String) -> bool:
	var cyrillic := 0
	for i in text.length():
		var c: int = text.unicode_at(i)
		if c >= 0x0400 and c <= 0x04FF:
			cyrillic += 1
		elif c != 0x2019 and c != 39 and c != 45 and c != 32: # the Ukrainian apostrophe, a hyphen or a space
			return false
	return cyrillic > 0


func run() -> void:
	var original: String = GameConfig.current_map_id()
	var font: Font = ThemeDB.fallback_font
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		var settlements: Array = GameConfig.CURRENT_MAP.get("settlements", [])
		check(not settlements.is_empty(), "%s: the map names at least one village" % map_id)
		for s in settlements:
			check(is_plain_english(s.name_en), "%s: %s is written in plain English letters" % [map_id, s.name_en])
			check(is_ukrainian(s.name_uk), "%s: %s is written in Ukrainian (Cyrillic) letters" % [map_id, s.name_uk])
			check(s.name_en != s.name_uk, "%s: the two names are really two different spellings" % map_id)
			var p: Vector2 = s.position_m
			var w: float = GameConfig.CURRENT_MAP.width_m
			var h: float = GameConfig.CURRENT_MAP.height_m
			check(p.x >= -GameConfig.CURRENT_MAP.west_flank_width_m and p.x <= w and p.y >= 0.0 and p.y <= h, "%s: %s stands inside the map (%s)" % [map_id, s.name_en, p])
			for text in [s.name_en, s.name_uk]:
				for i in text.length():
					check(font.has_char(text.unicode_at(i)), "%s: the game's font can draw '%s' in %s" % [map_id, text.substr(i, 1), text])
		# The real drawing, for this map.
		var before: int = GameConfig.settlement_labels_drawn
		var canvas := Canvas.new()
		root.add_child(canvas)
		await process_frame
		await process_frame
		check(canvas.drawn, "%s: the terrain drawing ran through" % map_id)
		check(GameConfig.settlement_labels_drawn - before >= settlements.size(), "%s: every village label was actually drawn (%d of %d)" % [map_id, GameConfig.settlement_labels_drawn - before, settlements.size()])
		canvas.queue_free()
	GameConfig.set_active_map(original)
	print("Map settlement label tests: %d failures" % failures)
	quit(1 if failures else 0)
