extends Node2D

const TILE_SIZE := 24
const MIN_TILE_SIZE := 12.0
const MAX_TILE_SIZE := 44.0
const HUD_HEIGHT := 56.0
const TOUCH_PANEL_SIZE := Vector2(248, 300)
const MAZE := [
	"###################",
	"#........#........#",
	"#.###.##.#.##.###.#",
	"#o###.##.#.##.###o#",
	"#.................#",
	"#.###.#.###.#.###.#",
	"#.....#...#.#.....#",
	"#####.### #.###.###",
	"#####.#     #.#.###",
	"#####.# ### #.#.###",
	"#.......# #.......#",
	"#####.# ### #.#.###",
	"#####.#     #.#.###",
	"#####.#.###.#.#.###",
	"#........#........#",
	"#.###.##.#.##.###.#",
	"#o..#........#..oo#",
	"###.#.#.###.#.#.###",
	"#.....#...#...#...#",
	"#.#########.#####.#",
	"#.................#",
	"###################",
]

const PLAYER_COLOR := Color(1.0, 0.92, 0.0)
const GHOST_COLORS := [
	Color(1.0, 0.2, 0.2),
	Color(1.0, 0.6, 0.85),
	Color(1.0, 0.65, 0.2),
	Color(0.4, 1.0, 1.0),
]

const DIRS := {
	"left": Vector2i.LEFT,
	"right": Vector2i.RIGHT,
	"up": Vector2i.UP,
	"down": Vector2i.DOWN,
}

var map_size := Vector2i(MAZE[0].length(), MAZE.size())
var pellets: Dictionary = {}
var player_pos := Vector2i(1, 1)
var player_dir := Vector2i.RIGHT
var queued_dir := Vector2i.RIGHT
var touch_dir := Vector2i.ZERO
var ghosts: Array[Dictionary] = []
var move_timer := 0.0
var ghost_timer := 0.0
var move_interval := 0.16
var ghost_interval := 0.20
var ghost_scared_interval := 0.24
var scared_time_left := 0.0
var scared_duration := 7.0
var scared_flash_start := 2.0
var scared_flash_timer := 0.0
var ghost_combo := 0
var score := 0
var game_over := false
var win := false
var player_moved_last_step := false
var mouth_phase := 0.0
var mouth_speed := 12.0
var board_tile_size := TILE_SIZE
var board_origin := Vector2.ZERO
var hud_label: Label
var message_label: Label
var restart_button: Button
var sfx_player: AudioStreamPlayer
var sfx_playback: AudioStreamGeneratorPlayback

func _ready() -> void:
	get_viewport().size_changed.connect(_update_layout)
	_build_pellets()
	_create_ghosts()
	_create_hud()
	_create_touch_controls()
	_create_audio()
	_update_layout()
	set_process(true)
	queue_redraw()

func _build_pellets() -> void:
	for y in MAZE.size():
		var row: String = MAZE[y]
		for x in row.length():
			var cell := row.substr(x, 1)
			if cell == "." or cell == "o":
				pellets[_cell_key(Vector2i(x, y))] = cell

func _create_ghosts() -> void:
	var starts := [Vector2i(9, 10), Vector2i(8, 10), Vector2i(10, 10), Vector2i(9, 9)]
	for i in starts.size():
		ghosts.append({
			"pos": starts[i],
			"start": starts[i],
			"dir": Vector2i.LEFT,
			"color": GHOST_COLORS[i % GHOST_COLORS.size()],
		})

func _create_audio() -> void:
	sfx_player = AudioStreamPlayer.new()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 44100.0
	stream.buffer_length = 0.25
	sfx_player.stream = stream
	add_child(sfx_player)
	sfx_player.play()
	sfx_playback = sfx_player.get_stream_playback() as AudioStreamGeneratorPlayback

func _create_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	hud_label = Label.new()
	hud_label.position = Vector2(8, 6)
	hud_label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(hud_label)

	message_label = Label.new()
	message_label.add_theme_font_size_override("font_size", 30)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.size = Vector2(map_size.x * TILE_SIZE, 40)
	message_label.position = Vector2(0, map_size.y * TILE_SIZE * 0.45)
	canvas.add_child(message_label)
	_update_hud()

func _create_touch_controls() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(12, -TOUCH_PANEL_SIZE.y - 12)
	panel.size = TOUCH_PANEL_SIZE
	canvas.add_child(panel)

	_add_touch_button(panel, "U", Vector2(80, 0), Vector2i.UP)
	_add_touch_button(panel, "L", Vector2(0, 80), Vector2i.LEFT)
	_add_touch_button(panel, "R", Vector2(160, 80), Vector2i.RIGHT)
	_add_touch_button(panel, "D", Vector2(80, 160), Vector2i.DOWN)

	restart_button = Button.new()
	restart_button.text = "START / RESTART"
	restart_button.position = Vector2(20, 236)
	restart_button.size = Vector2(208, 44)
	restart_button.modulate = Color(0.1, 0.1, 0.18, 0.82)
	restart_button.pressed.connect(_restart_game)
	panel.add_child(restart_button)

func _add_touch_button(parent: Control, text: String, pos: Vector2, dir: Vector2i) -> void:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(72, 72)
	b.modulate = Color(0.1, 0.1, 0.18, 0.72)
	parent.add_child(b)
	b.button_down.connect(func() -> void:
		touch_dir = dir
		queued_dir = dir
	)
	b.button_up.connect(func() -> void:
		if touch_dir == dir:
			touch_dir = Vector2i.ZERO
	)

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept") and game_over:
		_restart_game()

	if game_over:
		return

	_read_keyboard()
	move_timer += delta
	ghost_timer += delta
	if scared_time_left > 0.0:
		scared_time_left = max(scared_time_left - delta, 0.0)
		scared_flash_timer += delta

	if player_moved_last_step:
		mouth_phase += delta * mouth_speed
	else:
		mouth_phase = 0.0

	if move_timer >= move_interval:
		move_timer = 0.0
		_step_player()

	var current_ghost_interval := ghost_scared_interval if scared_time_left > 0.0 else ghost_interval
	if ghost_timer >= current_ghost_interval:
		ghost_timer = 0.0
		_step_ghosts()

	_check_collisions()
	_update_hud()
	queue_redraw()

func _read_keyboard() -> void:
	if Input.is_action_pressed("ui_left"):
		queued_dir = Vector2i.LEFT
	elif Input.is_action_pressed("ui_right"):
		queued_dir = Vector2i.RIGHT
	elif Input.is_action_pressed("ui_up"):
		queued_dir = Vector2i.UP
	elif Input.is_action_pressed("ui_down"):
		queued_dir = Vector2i.DOWN
	elif touch_dir != Vector2i.ZERO:
		queued_dir = touch_dir

func _step_player() -> void:
	player_moved_last_step = false
	if _can_walk(player_pos + queued_dir):
		player_dir = queued_dir
	if _can_walk(player_pos + player_dir):
		player_pos += player_dir
		player_moved_last_step = true

	var key := _cell_key(player_pos)
	if pellets.has(key):
		var pellet_type: String = pellets[key]
		pellets.erase(key)
		if pellet_type == ".":
			score += 10
			_play_dot_sfx()
		else:
			score += 50
			_activate_scared_mode()
			_play_powerup_sfx()
		if pellets.is_empty():
			_set_end_state(true)

func _activate_scared_mode() -> void:
	scared_time_left = scared_duration
	scared_flash_timer = 0.0
	ghost_combo = 0

func _step_ghosts() -> void:
	for ghost in ghosts:
		var pos: Vector2i = ghost["pos"]
		var current_dir: Vector2i = ghost["dir"]
		var options: Array[Vector2i] = []
		for d in DIRS.values():
			if _can_walk(pos + d):
				if d != -current_dir or _walkable_neighbor_count(pos) <= 1:
					options.append(d)

		if options.is_empty():
			continue

		var best := options[randi() % options.size()]
		var best_dist := -INF if scared_time_left > 0.0 else INF
		for d in options:
			var test_pos := pos + d
			var dist := test_pos.distance_to(player_pos)
			if scared_time_left > 0.0:
				if dist > best_dist:
					best_dist = dist
					best = d
			else:
				if dist < best_dist:
					best_dist = dist
					best = d
		ghost["dir"] = best
		ghost["pos"] = pos + best

func _check_collisions() -> void:
	for i in ghosts.size():
		var ghost := ghosts[i]
		if ghost["pos"] == player_pos:
			if scared_time_left > 0.0:
				ghost_combo += 1
				score += 200 * ghost_combo
				_play_ghost_sfx()
				ghost["pos"] = ghost["start"]
				ghost["dir"] = Vector2i.LEFT
				ghosts[i] = ghost
			else:
				_set_end_state(false)
				break

func _set_end_state(did_win: bool) -> void:
	game_over = true
	win = did_win
	message_label.text = "YOU WIN! Tap START / RESTART" if win else "CAUGHT! Tap START / RESTART"

func _restart_game() -> void:
	pellets.clear()
	score = 0
	game_over = false
	win = false
	scared_time_left = 0.0
	scared_flash_timer = 0.0
	ghost_combo = 0
	player_pos = Vector2i(1, 1)
	player_dir = Vector2i.RIGHT
	queued_dir = Vector2i.RIGHT
	touch_dir = Vector2i.ZERO
	player_moved_last_step = false
	mouth_phase = 0.0
	_build_pellets()
	ghosts.clear()
	_create_ghosts()
	message_label.text = ""
	_update_layout()
	queue_redraw()

func _update_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var board_width := float(map_size.x * TILE_SIZE)
	var board_height := float(map_size.y * TILE_SIZE)
	var fit_width := (viewport_size.x - 16.0) / board_width
	var fit_height := (viewport_size.y - HUD_HEIGHT - TOUCH_PANEL_SIZE.y - 24.0) / board_height
	var fit_scale := clampf(minf(fit_width, fit_height), 0.5, 2.5)
	board_tile_size = int(round(TILE_SIZE * fit_scale))
	var board_pixel_width := float(map_size.x * board_tile_size)
	var board_pixel_height := float(map_size.y * board_tile_size)
	board_origin = Vector2(
		maxf(8.0, (viewport_size.x - board_pixel_width) * 0.5),
		HUD_HEIGHT + maxf(8.0, (viewport_size.y - HUD_HEIGHT - TOUCH_PANEL_SIZE.y - board_pixel_height) * 0.5)
	)
	message_label.size = Vector2(map_size.x * board_tile_size, 48)
	message_label.position = Vector2(0, board_origin.y + board_pixel_height * 0.45)
	message_label.add_theme_font_size_override("font_size", int(maxf(24.0, board_tile_size * 1.15)))
	if restart_button != null:
		restart_button.text = "START / RESTART" if not game_over else "TAP TO RESTART"
	queue_redraw()

func _draw() -> void:
	var offset := board_origin
	for y in MAZE.size():
		var row: String = MAZE[y]
		for x in row.length():
			var cell := row.substr(x, 1)
			var rect := Rect2(offset.x + x * board_tile_size, offset.y + y * board_tile_size, board_tile_size, board_tile_size)
			if cell == "#":
				draw_rect(rect, Color(0.05, 0.1, 0.65))
				draw_rect(rect.grow(-2.0), Color(0.1, 0.15, 0.85), false, 2.0)

	for key in pellets.keys():
		var p: Vector2i = _parse_key(key)
		var pellet_type: String = pellets[key]
		var radius := board_tile_size * (0.13 if pellet_type == "." else 0.24)
		draw_circle(_cell_center(p), radius, Color(1.0, 0.85, 0.5))

	_draw_player()

	for ghost in ghosts:
		var gp: Vector2i = ghost["pos"]
		var center := _cell_center(gp)
		draw_circle(center, board_tile_size * 0.4, _ghost_draw_color(ghost))
		draw_circle(center + Vector2(-board_tile_size * 0.2, -board_tile_size * 0.12), board_tile_size * 0.08, Color.WHITE)
		draw_circle(center + Vector2(board_tile_size * 0.2, -board_tile_size * 0.12), board_tile_size * 0.08, Color.WHITE)

func _draw_player() -> void:
	var center: Vector2 = _cell_center(player_pos)
	var radius: float = board_tile_size * 0.4
	var open_amount: float = 0.08
	if player_moved_last_step:
		open_amount = 0.08 + 0.26 * (0.5 + 0.5 * sin(mouth_phase))

	var facing: float = _dir_angle(player_dir)
	var start_angle: float = facing + open_amount
	var end_angle: float = facing + TAU - open_amount
	var points := PackedVector2Array()
	points.append(center)
	var segs: int = 26
	for i: int in range(segs + 1):
		var t: float = float(i) / float(segs)
		var a: float = lerpf(start_angle, end_angle, t)
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(points, PLAYER_COLOR)

func _ghost_draw_color(ghost: Dictionary) -> Color:
	if scared_time_left <= 0.0:
		return Color(ghost["color"])
	if scared_time_left <= scared_flash_start:
		var flash: bool = int(floor(scared_flash_timer * 10.0)) % 2 == 0
		return Color.WHITE if flash else Color(0.15, 0.25, 1.0)
	return Color(0.15, 0.25, 1.0)

func _dir_angle(dir: Vector2i) -> float:
	if dir == Vector2i.LEFT:
		return PI
	if dir == Vector2i.UP:
		return -PI * 0.5
	if dir == Vector2i.DOWN:
		return PI * 0.5
	return 0.0

func _play_dot_sfx() -> void:
	_play_tone(760.0, 0.035, 0.20)

func _play_powerup_sfx() -> void:
	_play_tone(380.0, 0.08, 0.24)
	_play_tone(620.0, 0.08, 0.24)

func _play_ghost_sfx() -> void:
	_play_tone(200.0, 0.07, 0.28)
	_play_tone(160.0, 0.08, 0.28)

func _play_tone(freq: float, duration: float, volume: float) -> void:
	if sfx_playback == null:
		return
	var sample_rate: float = 44100.0
	var frames: int = int(duration * sample_rate)
	var available: int = sfx_playback.get_frames_available()
	var to_write: int = mini(frames, available)
	if to_write <= 0:
		return
	for i: int in range(to_write):
		var t: float = float(i) / sample_rate
		var env: float = clampf(1.0 - t / duration, 0.0, 1.0)
		var sample: float = sin(TAU * freq * t) * volume * env
		sfx_playback.push_frame(Vector2(sample, sample))

func _can_walk(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
		return false
	var row: String = MAZE[cell.y]
	var tile := row.substr(cell.x, 1)
	return tile != "#"

func _walkable_neighbor_count(cell: Vector2i) -> int:
	var count := 0
	for d in DIRS.values():
		if _can_walk(cell + d):
			count += 1
	return count

func _cell_center(cell: Vector2i) -> Vector2:
	return board_origin + Vector2(cell.x * board_tile_size + board_tile_size * 0.5, cell.y * board_tile_size + board_tile_size * 0.5)

func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

func _parse_key(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(parts[0].to_int(), parts[1].to_int())

func _update_hud() -> void:
	hud_label.text = "Score: %d   Pellets: %d" % [score, pellets.size()]
	if restart_button != null:
		restart_button.text = "START / RESTART" if not game_over else "TAP TO RESTART"
	if not game_over:
		message_label.text = ""
