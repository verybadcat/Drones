extends SceneTree
# Renders the real terrain layer (the game's own draw_terrain) of a map into a PNG.
var map_id := "voznesensk"
var out_path := ""
var crop := Rect2(-1500, 0, 6500, 3500) # meters
var scale_px_per_m := 0.5
func _initialize():
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--map="): map_id = a.substr(6)
		elif a.begins_with("--out="): out_path = a.substr(6)
		elif a.begins_with("--crop="):
			var p := a.substr(7).split(",")
			crop = Rect2(float(p[0]), float(p[1]), float(p[2]), float(p[3]))
		elif a.begins_with("--scale="): scale_px_per_m = float(a.substr(8))
	call_deferred("run")
func run():
	GameConfig.set_active_map(map_id)
	var vp := SubViewport.new()
	vp.size = Vector2i(int(crop.size.x * scale_px_per_m), int(crop.size.y * scale_px_per_m))
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.40, 0.28)
	bg.size = Vector2(vp.size)
	vp.add_child(bg)
	var holder := Node2D.new()
	# world px = meters * PIXELS_PER_METER; we want screen px = (meters - crop.position) * scale
	var k: float = scale_px_per_m / GameConfig.PIXELS_PER_METER
	holder.scale = Vector2(k, k)
	holder.position = -crop.position * scale_px_per_m
	vp.add_child(holder)
	var layer = preload("res://scripts/terrain_layer.gd").new()
	holder.add_child(layer)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png(out_path)
	print("saved ", out_path, " ", img.get_size())
	quit()
