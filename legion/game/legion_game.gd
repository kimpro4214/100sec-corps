extends Node2D
## 100초 군단 화면의 진행 담당. 입력을 sim에 넘기고, 고정 틱으로 sim을 돌리고, 각 담당에게 표시를 맡긴다.
##   LegionUI: 패널과 문구
##   CinemaDirector: 카메라, 시간 연출, 시네마틱
##   Fx: 이벤트 이펙트와 파편
##   WorldRenderer: 월드와 막대 그리기

const LegionSim := preload("res://legion/sim/legion_sim.gd")
const LegionUI := preload("res://legion/game/legion_ui.gd")
const CinemaDirector := preload("res://legion/game/cinema_director.gd")
const Fx := preload("res://legion/game/fx.gd")
const WorldRenderer := preload("res://legion/game/world_renderer.gd")
const Palette := preload("res://legion/game/palette.gd")
const DATA_PATH := "res://legion/data/balance.json"

var data: Dictionary
var sim
var acc := 0.0
var ui: LegionUI
var director := CinemaDirector.new()
var fx := Fx.new()


func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	ui = LegionUI.new()
	add_child(ui)
	ui.setup(data)
	ui.main_chosen.connect(_begin_run)
	ui.option_chosen.connect(_choose)
	ui.continue_pressed.connect(_continue_round)
	ui.restart_pressed.connect(_start_run)
	ui.menu_pressed.connect(_to_menu)
	_start_run()


func _start_run() -> void:
	sim = null
	fx.reset()
	director.reset()
	ui.reset()
	queue_redraw()


func _begin_run(main_id: String) -> void:
	sim = LegionSim.new(data, randi(), main_id)
	sim.record_events = true
	acc = 0.0
	ui.hide_start()
	director.start("intro")
	ui.show_cinema_text("100초 군단", "100초마다, 지난 내가 돌아온다")


func _to_menu() -> void:
	get_tree().change_scene_to_file("res://main_menu.tscn")


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
	if sim.is_over():
		pass
	elif not sim.pending_choices.is_empty():
		acc = 0.0
		if not ui.is_choice_visible():
			ui.show_choices(sim)
	elif not sim.round_summary.is_empty():
		acc = 0.0
		if not ui.is_summary_visible():
			ui.show_summary(sim)
	if sim.is_over() and director.cinema != "ending" and not ui.is_end_visible():
		_start_ending()
	fx.update(world_delta)
	director.decay(delta)
	ui.tick_banner(delta, director.cinema == "")
	ui.update_hud(sim, director.cinema == "" or director.cinema == "ult")
	queue_redraw()


func _update_cinema(delta: float) -> void:
	var arena := Vector2(float(data.arena.w), float(data.arena.h))
	var action := director.update(delta, sim.player_pos, get_viewport_rect().size, arena)
	match action:
		"intro_done":
			_end_intro()
		"fire_ult":
			sim.use_ultimate()
		"ult_done":
			ui.hide_cinema_text()
		"show_end":
			if not ui.is_end_visible():
				ui.hide_cinema_text()
				ui.show_end(sim)
	if director.cinema != "":
		ui.set_cinema_style(director.text_alpha, director.title_scale)


func _end_intro() -> void:
	director.end_intro()
	ui.hide_cinema_text()
	ui.show_banner("이동: WASD / 방향키   궁극기: Space   70초에 군단장이 등장합니다")


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
	sim.events.clear()


func _choose(index: int) -> void:
	sim.choose(index)
	ui.hide_round_panels()
	if not sim.pending_choices.is_empty():
		ui.show_choices(sim)


func _continue_round() -> void:
	sim.continue_round()
	ui.hide_round_panels()


func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Palette.BG)
	if sim == null:
		return
	var alpha: float = clampf(acc / sim.tick, 0.0, 1.0)
	var player: Vector2 = sim.player_prev.lerp(sim.player_pos, alpha)
	var center: Vector2 = player if director.cinema == "" else director.focus
	var world_offset := director.world_offset(view, center)
	var world_scale := Vector2(director.zoom, director.zoom)
	draw_set_transform(world_offset, 0.0, world_scale)
	WorldRenderer.draw_world(self, sim, data, alpha, player)
	fx.draw(self)
	if director.is_casting():
		draw_set_transform(Vector2.ZERO)
		draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 0.55 * director.letterbox))
		draw_set_transform(world_offset, 0.0, world_scale)
		draw_circle(player, float(data.player.radius) * (2.0 + director.cinema_time * 4.0), Color(Palette.AWAKEN, 0.25))
	WorldRenderer.draw_player(self, sim, data, player)
	draw_set_transform(Vector2.ZERO)
	director.draw_screen(self, view)
	if director.cinema == "" or director.cinema == "ult":
		WorldRenderer.draw_bars(self, sim, data, view)
