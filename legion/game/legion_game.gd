extends Node2D
## 100초 군단 화면의 진행 담당. 입력을 sim에 넘기고, 고정 틱으로 sim을 돌리고, 각 담당에게 표시를 맡긴다.
##   LegionUI: 패널과 문구
##   CinemaDirector: 카메라, 시간 연출, 시네마틱
##   Fx: 이벤트 이펙트와 파편
##   WorldRenderer: 월드와 막대 그리기
##   Sfx: 효과음과 음악 신호
## 그리는 순서: 이 노드(월드) → glow(더하기 혼합 빛) → overlay(화면 효과와 막대) → UI

const LegionSim := preload("res://legion/sim/legion_sim.gd")
const LegionUI := preload("res://legion/game/legion_ui.gd")
const CinemaDirector := preload("res://legion/game/cinema_director.gd")
const Fx := preload("res://legion/game/fx.gd")
const WorldRenderer := preload("res://legion/game/world_renderer.gd")
const DrawLayer := preload("res://legion/game/draw_layer.gd")
const Sfx := preload("res://legion/game/sfx.gd")
const Palette := preload("res://legion/game/palette.gd")
const DATA_PATH := "res://legion/data/balance.json"

var data: Dictionary
var sim
var acc := 0.0
var player_facing := 1.0
var ui: LegionUI
var director := CinemaDirector.new()
var fx := Fx.new()
var glow: DrawLayer
var overlay: DrawLayer
var sfx: Sfx
var world_offset := Vector2.ZERO
var world_scale := Vector2.ONE


func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var settings := get_node_or_null("/root/Settings")
	if settings != null:
		director.motion = settings.screen_shake
	glow = DrawLayer.new()
	glow.additive = true
	glow.draw_fn = _draw_glow
	add_child(glow)
	overlay = DrawLayer.new()
	overlay.draw_fn = _draw_overlay
	add_child(overlay)
	sfx = Sfx.new()
	add_child(sfx)
	ui = LegionUI.new()
	add_child(ui)
	ui.setup(data)
	ui.main_chosen.connect(_begin_run)
	ui.option_chosen.connect(_choose)
	ui.continue_pressed.connect(_continue_round)
	ui.restart_pressed.connect(_restart)
	ui.menu_pressed.connect(_to_menu)
	_start_run()


func _start_run() -> void:
	sim = null
	fx.reset()
	director.reset()
	ui.reset()
	_redraw_all()


func _restart() -> void:
	sfx.play("click")
	_start_run()


func _begin_run(main_id: String) -> void:
	sfx.play("click")
	sim = LegionSim.new(data, randi(), main_id)
	sim.record_events = true
	acc = 0.0
	player_facing = 1.0
	ui.hide_start()
	director.start("intro")
	ui.show_cinema_text("100초 군단", "100초마다, 지난 내가 돌아온다")


func _to_menu() -> void:
	get_tree().change_scene_to_file("res://legion/game/title.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_ESCAPE:
		_to_menu()
	elif sim == null:
		var main_index: int = event.physical_keycode - KEY_1
		if main_index >= 0 and main_index < LegionUI.MAIN_WEAPONS.size():
			_begin_run(LegionUI.MAIN_WEAPONS[main_index])
	elif director.cinema == "intro":
		if event.physical_keycode == KEY_SPACE:
			_end_intro()
	elif director.cinema != "":
		return
	elif not sim.pending_choices.is_empty():
		var index: int = event.physical_keycode - KEY_1
		if index >= 0 and index < sim.pending_choices.size():
			_choose(index)
	elif ui.is_summary_visible() and event.physical_keycode == KEY_SPACE:
		_continue_round()
	elif event.physical_keycode == KEY_SPACE and sim.ultimate_ready() and not sim.is_over():
		sfx.play("ult_charge")
		director.start("ult")
		var ult: Dictionary = data.ultimate[sim.main_weapon]
		ui.show_cinema_text(ult.name, ult.desc)


func _process(delta: float) -> void:
	if sim == null:
		return
	_update_cinema(delta)
	var world_delta := director.world_delta(delta)
	if not director.blocks_sim():
		acc += world_delta
	while acc >= sim.tick:
		acc -= sim.tick
		sim.step(_read_input())
		_consume_events()
		var moved_x: float = sim.player_pos.x - sim.player_prev.x
		if absf(moved_x) > 0.01:
			player_facing = signf(moved_x)
		# 이번 틱에 컷신이 시작됐으면 남은 시간을 버리고 멈춘다.
		if director.blocks_sim():
			acc = 0.0
			break
	if sim.is_over():
		pass
	elif not sim.pending_choices.is_empty():
		acc = 0.0
		if not ui.is_choice_visible():
			ui.show_choices(sim)
			# 라운드 종료 직후에는 라운드 돌파 신호가 이미 울리고 있으니 겹치지 않게 한다.
			if sim.round_summary.is_empty():
				sfx.play_jingle("level_up")
	elif not sim.round_summary.is_empty():
		acc = 0.0
		if not ui.is_summary_visible():
			ui.show_summary(sim)
	if sim.is_over() and director.cinema != "ending" and not ui.is_end_visible():
		_start_ending()
	fx.update(world_delta, sim, director.is_casting())
	director.decay(delta)
	ui.tick_banner(delta, director.cinema == "")
	ui.update_hud(sim, director.cinema == "" or director.cinema == "ult")
	_update_camera()
	_redraw_all()


## 이번 프레임의 카메라 변환. 흔들림이 섞여 있어 프레임마다 한 번만 계산해 모든 층이 같이 쓴다.
func _update_camera() -> void:
	var view := get_viewport_rect().size
	var alpha: float = clampf(acc / sim.tick, 0.0, 1.0)
	var player: Vector2 = sim.player_prev.lerp(sim.player_pos, alpha)
	var center: Vector2 = player if director.cinema == "" else director.focus
	world_offset = director.world_offset(view, center)
	world_scale = Vector2(director.zoom, director.zoom)
	glow.transform = Transform2D(0.0, world_scale, 0.0, world_offset)


func _redraw_all() -> void:
	queue_redraw()
	glow.queue_redraw()
	overlay.queue_redraw()


func _update_cinema(delta: float) -> void:
	var arena := Vector2(float(data.arena.w), float(data.arena.h))
	var action := director.update(delta, sim.player_pos, get_viewport_rect().size, arena)
	match action:
		"intro_done":
			_end_intro()
		"fire_ult":
			sim.use_ultimate()
		"ult_done", "boss_intro_done":
			ui.hide_cinema_text()
		"boss_roar":
			sfx.play("boss_kill")
		"show_end":
			if not ui.is_end_visible():
				ui.hide_cinema_text()
				ui.show_end(sim)
	if director.cinema != "":
		ui.set_cinema_style(director.text_alpha, director.title_scale)


func _end_intro() -> void:
	director.end_intro()
	ui.hide_cinema_text()
	ui.show_banner("이동: WASD / 방향키   궁극기: Space   70초에 보스 방 포탈이 열립니다")


func _start_ending() -> void:
	var won: bool = sim.state == "won"
	director.start_ending(won, sim.boss.pos if won and sim.boss != null else sim.player_pos)
	ui.hide_round_panels()
	if won:
		ui.show_cinema_text("승리", "군단을 넘어섰습니다")
	else:
		ui.show_cinema_text("패배", "라운드 %d에서 쓰러졌습니다" % sim.round_index)
	ui.set_cinema_style(director.text_alpha, director.title_scale)


func _read_input() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1.0
	return dir


func _consume_events() -> void:
	for event in sim.events:
		fx.handle(event, director)
		ui.handle_event(event)
		sfx.handle(event)
		if event.type == "boss" and not sim.is_over():
			director.start_boss_intro(event.pos)
			ui.show_cinema_text(event.label, event.title, true)
			ui.set_cinema_style(0.0, 1.0)
	sim.events.clear()


func _choose(index: int) -> void:
	sfx.play("select")
	sim.choose(index)
	ui.hide_round_panels()
	if not sim.pending_choices.is_empty():
		ui.show_choices(sim)


func _continue_round() -> void:
	sfx.play("click")
	sim.continue_round()
	ui.hide_round_panels()


func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Palette.BG)
	if sim == null:
		return
	var alpha: float = clampf(acc / sim.tick, 0.0, 1.0)
	var player: Vector2 = sim.player_prev.lerp(sim.player_pos, alpha)
	draw_set_transform(world_offset, 0.0, world_scale)
	WorldRenderer.draw_floor(self, sim, Rect2(-world_offset / world_scale, view / world_scale))
	fx.draw_under(self)
	WorldRenderer.draw_world(self, sim, data, alpha, player)
	fx.draw_debris(self)
	if director.is_casting():
		draw_set_transform(Vector2.ZERO)
		draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 0.55 * director.letterbox))
		draw_set_transform(world_offset, 0.0, world_scale)
	var moving: bool = sim.player_pos.distance_squared_to(sim.player_prev) > 0.01
	WorldRenderer.draw_player(self, sim, data, player, player_facing, moving, sim.time + alpha * sim.tick)
	draw_set_transform(Vector2.ZERO)


func _draw_glow(canvas: CanvasItem) -> void:
	if sim == null:
		return
	fx.draw_glow(canvas, sim, clampf(acc / sim.tick, 0.0, 1.0), director)


## 화면 좌표: 피격 테두리, 플래시, 레터박스, 막대. 빛 레이어보다 위에 그린다.
func _draw_overlay(canvas: CanvasItem) -> void:
	if sim == null:
		return
	var view := get_viewport_rect().size
	director.draw_screen(canvas, view)
	if director.cinema == "" or director.cinema == "ult":
		WorldRenderer.draw_bars(canvas, sim, data, view)
		WorldRenderer.draw_portal_pointer(canvas, sim, world_offset, world_scale, view)
