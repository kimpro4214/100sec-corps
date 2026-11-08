extends RefCounted
## 카메라(줌, 초점, 흔들림)와 시간 연출(히트스톱, 슬로 모션), 시네마틱 타임라인.
## 게임 규칙에는 손대지 않는다. 화면이 sim을 얼마나 진행할지만 정한다.

const Palette := preload("res://legion/game/palette.gd")

const INTRO_SECONDS := 3.4
const ULT_CAST_SECONDS := 0.5
const ULT_SECONDS := 1.1
const ENDING_PANEL_AT := 2.8
const ULT_ZOOM := 1.7
const ENDING_ZOOM := 1.8
const MAX_SHAKE := 24.0
const BOSS_INTRO_SECONDS := 2.6
const BOSS_PAN_SECONDS := 0.5
const BOSS_ZOOM := 1.6

var cinema := "" # "", intro, ult, boss_intro, ending
var cinema_time := 0.0
var ult_fired := false
var roared := false
var ending_focus := Vector2.ZERO
var boss_focus := Vector2.ZERO

var zoom := 1.0
var focus := Vector2.ZERO
var shake := 0.0
var hitstop := 0.0
var slowmo := 0.0
var flash := 0.0
var flash_color := Color.WHITE
var hurt_tint := 0.0
var letterbox := 0.0
var text_alpha := 1.0
var title_scale := 1.0


func reset() -> void:
	cinema = ""
	shake = 0.0
	hitstop = 0.0
	slowmo = 0.0
	flash = 0.0
	hurt_tint = 0.0
	letterbox = 0.0


func start(kind: String) -> void:
	cinema = kind
	cinema_time = 0.0
	ult_fired = false
	text_alpha = 1.0
	title_scale = 1.0


func start_ending(won: bool, target: Vector2) -> void:
	start("ending")
	ending_focus = target
	if won:
		add_flash(Color.WHITE, 0.9)
	else:
		add_flash(Color(Palette.GRUNT), 0.6)
	text_alpha = 0.0


func end_intro() -> void:
	cinema = ""


## 보스 등장: 보스에게 카메라가 날아가 이름을 보여 주고 돌아온다.
func start_boss_intro(target: Vector2) -> void:
	start("boss_intro")
	boss_focus = target
	roared = false
	text_alpha = 0.0


## 시네마틱 중 sim을 멈출지. 궁극기는 발동 순간부터 다시 진행한다.
func blocks_sim() -> bool:
	return not (cinema == "" or (cinema == "ult" and ult_fired))


func is_casting() -> bool:
	return cinema == "ult" and not ult_fired


## 히트스톱이면 0, 슬로 모션이면 느리게. 반환값만큼 게임 시간이 흐른다.
func world_delta(delta: float) -> float:
	if hitstop > 0.0:
		hitstop -= delta
		return 0.0
	if slowmo > 0.0:
		slowmo -= delta
		return delta * 0.35
	return delta


## 타임라인을 진행하고, 이번 프레임에 화면이 처리할 일을 돌려준다.
## "intro_done", "fire_ult", "ult_done", "boss_roar", "boss_intro_done", "show_end" 또는 "".
func update(delta: float, player: Vector2, view: Vector2, arena: Vector2) -> String:
	if cinema == "":
		zoom = lerpf(zoom, 1.0, 1.0 - exp(-8.0 * delta))
		focus = player
		letterbox = move_toward(letterbox, 0.0, delta * 3.0)
		return ""
	cinema_time += delta
	match cinema:
		"intro":
			var t := clampf(cinema_time / INTRO_SECONDS, 0.0, 1.0)
			var overview := minf(view.x / arena.x, view.y / arena.y) * 0.95
			var move := ease_in_out(clampf((t - 0.35) / 0.65, 0.0, 1.0))
			zoom = lerpf(overview, 1.0, move)
			focus = (arena * 0.5).lerp(player, move)
			letterbox = 1.0
			text_alpha = 1.0 - clampf((t - 0.6) / 0.3, 0.0, 1.0)
			if cinema_time >= INTRO_SECONDS:
				cinema = ""
				return "intro_done"
		"ult":
			focus = player
			if not ult_fired:
				var t := ease_out(clampf(cinema_time / ULT_CAST_SECONDS, 0.0, 1.0))
				zoom = lerpf(1.0, ULT_ZOOM, t)
				letterbox = t
				title_scale = lerpf(1.6, 1.0, t)
				if cinema_time >= ULT_CAST_SECONDS:
					ult_fired = true
					zoom = 0.85
					shake = MAX_SHAKE
					slowmo = 0.3
					add_flash(Color(Palette.AWAKEN), 0.35)
					return "fire_ult"
			else:
				zoom = lerpf(zoom, 1.0, 1.0 - exp(-6.0 * delta))
				letterbox = move_toward(letterbox, 0.0, delta * 3.0)
				text_alpha = 1.0 - clampf((cinema_time - ULT_CAST_SECONDS) / 0.3, 0.0, 1.0)
				if cinema_time >= ULT_SECONDS:
					cinema = ""
					title_scale = 1.0
					return "ult_done"
		"boss_intro":
			var back_at := BOSS_INTRO_SECONDS - BOSS_PAN_SECONDS
			var into := ease_in_out(clampf(cinema_time / BOSS_PAN_SECONDS, 0.0, 1.0))
			var out := ease_in_out(clampf((cinema_time - back_at) / BOSS_PAN_SECONDS, 0.0, 1.0))
			var t := into - out
			focus = player.lerp(boss_focus, t)
			zoom = lerpf(1.0, BOSS_ZOOM, t)
			letterbox = t
			text_alpha = clampf((cinema_time - BOSS_PAN_SECONDS) / 0.3, 0.0, 1.0) * (1.0 - clampf((cinema_time - back_at + 0.2) / 0.3, 0.0, 1.0))
			if not roared and cinema_time >= BOSS_PAN_SECONDS:
				roared = true
				shake = MAX_SHAKE * 0.8
				add_flash(Color(Palette.BOSS), 0.45)
				return "boss_roar"
			if cinema_time >= BOSS_INTRO_SECONDS:
				cinema = ""
				return "boss_intro_done"
		"ending":
			var t := ease_out(clampf(cinema_time / 1.4, 0.0, 1.0))
			zoom = lerpf(1.0, ENDING_ZOOM, t)
			focus = player.lerp(ending_focus, t)
			letterbox = t
			text_alpha = clampf((cinema_time - 0.6) / 0.5, 0.0, 1.0)
			if cinema_time >= ENDING_PANEL_AT:
				return "show_end"
	return ""


## 흔들림, 플래시, 피격 테두리는 실제 시간 기준으로 줄어든다.
func decay(delta: float) -> void:
	shake = lerpf(shake, 0.0, 1.0 - exp(-9.0 * delta))
	flash = maxf(0.0, flash - delta * 2.2)
	hurt_tint = maxf(0.0, hurt_tint - delta * 1.5)


func add_flash(color: Color, amount: float) -> void:
	flash_color = color
	flash = maxf(flash, amount)


func add_shake(amount: float) -> void:
	shake = minf(MAX_SHAKE, maxf(shake, amount))


## 월드 좌표를 화면에 그릴 때의 이동량. 흔들림이 섞여 있다.
func world_offset(view: Vector2, center: Vector2) -> Vector2:
	var shake_offset := Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	return view * 0.5 - center * zoom + shake_offset


func draw_screen(canvas: CanvasItem, view: Vector2) -> void:
	if hurt_tint > 0.0:
		var edge := Color(Palette.GRUNT, hurt_tint)
		var clear := Color(Palette.GRUNT, 0.0)
		var w := view.x * 0.12
		canvas.draw_polygon([Vector2.ZERO, Vector2(w, 0), Vector2(w, view.y), Vector2(0, view.y)], [edge, clear, clear, edge])
		canvas.draw_polygon([Vector2(view.x - w, 0), Vector2(view.x, 0), Vector2(view.x, view.y), Vector2(view.x - w, view.y)], [clear, edge, edge, clear])
	if flash > 0.0:
		canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(flash_color, minf(flash, 0.8)))
	if letterbox > 0.0:
		var bar := view.y * 0.11 * letterbox
		canvas.draw_rect(Rect2(0, 0, view.x, bar), Color.BLACK)
		canvas.draw_rect(Rect2(0, view.y - bar, view.x, bar), Color.BLACK)


static func ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)


static func ease_in_out(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)
