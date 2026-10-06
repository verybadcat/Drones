extends SceneTree
# Renders the real deployment screen (terrain, the shaded mortar-exclusion region, deployment zones, default tokens) of a map into a PNG.
# Needs a rendering driver:  Godot_console.exe --rendering-driver opengl3 --path . --script res://tools/map_pipeline/mortar_exclusion/render_setup.gd -- --map=pishchane --out=C:/x.png --scale=0.3
var map_id := "pishchane"
var out_path := ""
var scale_px_per_m := 0.3
var drag_mortar := false # the red wash shows only while the mortar is being dragged
func _initialize():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="): map_id = a.substr(6)
		elif a.begins_with("--out="): out_path = a.substr(6)
		elif a.begins_with("--scale="): scale_px_per_m = float(a.substr(8))
		elif a == "--drag": drag_mortar = true
	call_deferred("run")
func run():
	GameConfig.set_active_map(map_id)
	var width_m: float = GameConfig.WEST_FLANK_WIDTH_M + GameConfig.MAP_WIDTH_M
	var crop := Rect2(-GameConfig.WEST_FLANK_WIDTH_M, 0, width_m, GameConfig.MAP_HEIGHT_M)
	var vp := SubViewport.new()
	vp.size = Vector2i(int(crop.size.x * scale_px_per_m), int(crop.size.y * scale_px_per_m))
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.40, 0.28)
	bg.size = Vector2(vp.size)
	vp.add_child(bg)
	var holder := Node2D.new()
	var k: float = scale_px_per_m / GameConfig.PIXELS_PER_METER
	holder.scale = Vector2(k, k)
	holder.position = -crop.position * scale_px_per_m
	vp.add_child(holder)
	var screen := DeploymentScreen.new()
	holder.add_child(screen)
	if drag_mortar:
		screen._dragging = screen._mortar_token
		screen.queue_redraw()
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png(out_path)
	print("saved ", out_path, " ", img.get_size())
	quit()
