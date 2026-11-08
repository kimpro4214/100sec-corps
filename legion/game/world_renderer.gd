extends RefCounted
## sim 상태를 그린다. 캐릭터와 아이템은 Kenney Tiny Dungeon(CC0) 16px 스프라이트, 탄과 보석은 도형.

const Palette := preload("res://legion/game/palette.gd")
const Animator := preload("res://legion/game/animator.gd")
const Interactables := preload("res://legion/sim/interactables.gd")

const TILE := 16
const FONT := preload("res://legion/art/font/Galmuri11.ttf")
const FLOOR_SCALE := 3
const SPRITES := {
	"player": preload("res://legion/art/player.png"),
	"grunt": preload("res://legion/art/grunt.png"),
	"runner": preload("res://legion/art/runner.png"),
	"swarmling": preload("res://legion/art/swarmling.png"),
	"brute": preload("res://legion/art/brute.png"),
	"boss": preload("res://legion/art/boss.png"),
	"boss_spider": preload("res://legion/art/boss_spider.png"),
	"boss_wraith": preload("res://legion/art/boss_wraith.png"),
	"boss_knight": preload("res://legion/art/boss_knight.png"),
	"magnet": preload("res://legion/art/magnet.png"),
	"potion": preload("res://legion/art/potion.png"),
	"chest": preload("res://legion/art/chest.png"),
	"chest_open": preload("res://legion/art/chest_open.png"),
	"casino": preload("res://legion/art/mimic.png"),
	"shrine": preload("res://legion/art/shrine.png"),
	"sword": preload("res://legion/art/sword.png"),
}
const FLOORS := [
	preload("res://legion/art/floor.png"),
	preload("res://legion/art/floor_rocks.png"),
	preload("res://legion/art/floor_pebbles.png"),
]
const FLOOR_TINT := Color(0.36, 0.34, 0.42)
const FLOOR_ROOM := preload("res://legion/art/floor_room.png")
const ROOM_TINT := Color(0.32, 0.21, 0.23)
const WALL := preload("res://legion/art/wall.png")
const WALL_TINT := Color(0.55, 0.52, 0.6)
const GHOST_TINT := Color(0.85, 0.55, 1.0, 0.8)
const AWAKEN_TINT := Color(1.0, 0.9, 0.45)
const FLASH_TINT := Color(4.0, 4.0, 4.0)
const FRENZY_TINT := Color(1.35, 0.75, 0.55)
const COIN := Color("ffd23f")
const COIN_EDGE := Color("8a5a00")
const SHRINE_TINT := Color(1.3, 0.55, 0.55)
const WEB_COLOR := Color(0.93, 0.93, 0.97)
# 기사의 칼: 준비 때 어깨 뒤로 당기는 각도, 휘두른 뒤 지나치는 각도, 휘두르는 시간, 칼날 폭(길이 대비).
const SWORD_PULLBACK := 0.9
const SWORD_OVERSHOOT := 0.3
const SWORD_SWING_SECONDS := 0.12
const SWORD_WIDTH := 0.32


## 지금 서 있는 공간(필드나 보스 방)의 바닥, 벽, 포탈. 그을음 같은 바닥 효과가 이 위, 캐릭터 아래에 깔린다.
## view는 월드 좌표로 화면에 보이는 영역이다. 넓은 필드라도 보이는 칸만 그린다.
static func draw_floor(canvas: CanvasItem, sim, view: Rect2) -> void:
	var area: Rect2 = sim.area
	var step := TILE * FLOOR_SCALE
	var room: bool = sim.in_boss_room
	var visible := area.intersection(view.grow(step))
	var x0 := int(floor((visible.position.x - area.position.x) / step))
	var y0 := int(floor((visible.position.y - area.position.y) / step))
	var x1 := int(ceil((visible.end.x - area.position.x) / step))
	var y1 := int(ceil((visible.end.y - area.position.y) / step))
	for gx in range(x0, x1):
		for gy in range(y0, y1):
			var tex: Texture2D = FLOOR_ROOM
			var tint := ROOM_TINT
			if not room:
				# 칸 좌표로 정한 고정 무늬. 매 프레임 같은 바닥이 나온다.
				var roll := hash(Vector2i(gx, gy)) % 60
				tex = FLOORS[1] if roll == 0 else (FLOORS[2] if roll == 1 else FLOORS[0])
				tint = FLOOR_TINT
			canvas.draw_texture_rect(tex, Rect2(area.position + Vector2(gx * step, gy * step), Vector2(step, step)), false, tint)
	_draw_walls(canvas, area, view, step)
	if sim.portal_open and not room:
		_draw_portal(canvas, sim)


## 공간 바깥 둘레를 돌벽으로 두른다.
static func _draw_walls(canvas: CanvasItem, area: Rect2, view: Rect2, step: int) -> void:
	var outer := area.grow(step)
	for x in range(int(outer.position.x), int(outer.end.x), step):
		for y in [outer.position.y, area.end.y]:
			var cell := Rect2(x, y, step, step)
			if cell.intersects(view):
				canvas.draw_texture_rect(WALL, cell, false, WALL_TINT)
	for y in range(int(area.position.y), int(area.end.y), step):
		for x in [outer.position.x, area.end.x]:
			var cell := Rect2(x, y, step, step)
			if cell.intersects(view):
				canvas.draw_texture_rect(WALL, cell, false, WALL_TINT)


## 바닥에 뚫린 포탈 구멍과 남은 시간. 빛나는 소용돌이는 Fx가 그린다.
static func _draw_portal(canvas: CanvasItem, sim) -> void:
	var radius := float(sim.data.boss_room.portal_radius)
	canvas.draw_circle(sim.portal_pos, radius * 1.4, Color(0.08, 0.0, 0.12, 0.9))
	canvas.draw_arc(sim.portal_pos, radius * 1.4, 0.0, TAU, 48, Palette.GHOST, 3.0)
	var left := maxf(0.0, float(sim.data.round_seconds) - sim.round_time)
	canvas.draw_string(FONT, sim.portal_pos + Vector2(-120, -radius * 1.4 - 14), "보스 방 (강제 입장 %d초)" % ceili(left), HORIZONTAL_ALIGNMENT_CENTER, 240, 12)


## 플레이어 아래에 깔리는 것들: 보석, 아이템, 낙뢰 예고, 오라, 군단장 예고, 적. 탄은 Fx의 빛 레이어가 그린다.
static func draw_world(canvas: CanvasItem, sim, data: Dictionary, alpha: float, player: Vector2) -> void:
	if not sim.in_boss_room:
		for item in sim.interactables:
			_draw_interactable(canvas, sim, item)
	for gem in sim.gems:
		if gem.gold:
			canvas.draw_circle(gem.pos, 5.0, COIN_EDGE)
			canvas.draw_circle(gem.pos, 3.5, COIN)
		else:
			canvas.draw_circle(gem.pos, 4.0, Palette.GEM)
	for item in sim.pickups:
		var item_color := Palette.MAGNET if item.kind == "magnet" else Palette.POTION
		canvas.draw_circle(item.pos, float(data.items.radius), Color(item_color, 0.2))
		canvas.draw_arc(item.pos, float(data.items.radius), 0.0, TAU, 24, item_color, 2.0)
		_draw_sprite(canvas, SPRITES[item.kind], item.pos, 2, Color.WHITE)
		canvas.draw_string(FONT, item.pos + Vector2(-40, 34), "자석" if item.kind == "magnet" else "포션", HORIZONTAL_ALIGNMENT_CENTER, 80, 12)
	# 낙뢰 예고는 피해야 하는 적의 공격만 보여 준다. 내 낙뢰는 떨어질 때 Fx가 그린다.
	for strike in sim.strikes:
		if strike.hostile:
			canvas.draw_arc(strike.pos, strike.radius, 0.0, TAU, 48, Palette.HOSTILE, 3.0)
			canvas.draw_circle(strike.pos, strike.radius, Color(Palette.HOSTILE, 0.15))
	for zone in sim.zones:
		_draw_zone(canvas, zone)
	_draw_auras(canvas, sim, data, player)
	_draw_boss_telegraph(canvas, sim)
	var t: float = sim.time + alpha * sim.tick
	for enemy in sim.enemies:
		_draw_enemy(canvas, sim, enemy, alpha, player, t)
	_draw_sword_windup(canvas, sim, t)


## facing: 1이면 오른쪽, -1이면 왼쪽을 바라본다. 스프라이트 원본은 오른쪽을 본다.
## moving: 이번 틱에 움직였으면 걷고, 아니면 제자리에서 숨 쉰다.
static func draw_player(canvas: CanvasItem, sim, data: Dictionary, player: Vector2, facing: float, moving: bool, t: float) -> void:
	var tint := AWAKEN_TINT if sim.is_awakened(sim.build) else Color.WHITE
	if sim.frenzy_time > 0.0:
		tint = FRENZY_TINT
	var pose := Animator.hop("player", t, 0.0) if moving else Animator.breathe(t, 0.0)
	pose = Animator.with_hit(pose, sim.player_flash)
	_draw_character(canvas, SPRITES.player, player, float(data.player.radius), FLASH_TINT if sim.player_flash > 0.0 else tint, facing, pose)


## 보물상자, 룰렛, 제단. 위에 서 있으면 고리가 차오르고, 대가를 낼 수 없으면 흐리게 보인다.
static func _draw_interactable(canvas: CanvasItem, sim, item) -> void:
	var def: Dictionary = sim.data.interactables.kinds[item.kind]
	var key: String = item.kind
	if item.kind == "chest" and item.used:
		key = "chest_open"
	var tint := SHRINE_TINT if item.kind == "shrine" else Color.WHITE
	var affordable: bool = Interactables.can_afford(sim, item.kind)
	if item.used:
		tint = Color(0.5, 0.5, 0.5, 0.6)
	elif not affordable:
		tint = Color(tint.r * 0.6, tint.g * 0.6, tint.b * 0.6, 0.8)
	_draw_character(canvas, SPRITES[key], item.pos, 16.0, tint, 1.0)
	if item.used:
		return
	var radius := float(sim.data.interactables.radius)
	canvas.draw_arc(item.pos, radius, 0.0, TAU, 32, Color(COIN, 0.35), 2.0)
	if item.progress > 0.0:
		var ratio: float = item.progress / float(sim.data.interactables.activate_seconds)
		canvas.draw_arc(item.pos, radius, -PI * 0.5, -PI * 0.5 + TAU * ratio, 32, COIN, 5.0)
	var cost := "체력 %d%%" % int(float(def.cost_hp) * 100.0) if def.has("cost_hp") else "금화 %d" % Interactables.gold_cost(sim, item.kind)
	var color := Color.WHITE if affordable else Color(1, 0.5, 0.5)
	canvas.draw_string(FONT, item.pos + Vector2(-110, -radius - 14), "%s (%s)" % [def.name, cost], HORIZONTAL_ALIGNMENT_CENTER, 220, 12, color)


## 포탈이 화면 밖에 있으면 화면 가장자리에 방향 화살표를 띄운다. 화면 좌표로 그린다.
static func draw_portal_pointer(canvas: CanvasItem, sim, world_offset: Vector2, world_scale: Vector2, view: Vector2) -> void:
	if not sim.portal_open or sim.in_boss_room:
		return
	var screen: Vector2 = world_offset + sim.portal_pos * world_scale
	var inner := Rect2(Vector2.ZERO, view).grow(-40.0)
	if inner.has_point(screen):
		return
	var center := view * 0.5
	var dir := (screen - center).normalized()
	# 화면 안쪽 사각형의 테두리와 만나는 점에 화살표를 둔다.
	var scale_x := (inner.size.x * 0.5) / maxf(absf(dir.x), 0.001)
	var scale_y := (inner.size.y * 0.5) / maxf(absf(dir.y), 0.001)
	var tip := center + dir * minf(scale_x, scale_y)
	var side := dir.orthogonal() * 12.0
	canvas.draw_colored_polygon([tip + dir * 14.0, tip - dir * 10.0 + side, tip - dir * 10.0 - side], Palette.GHOST)
	canvas.draw_string(FONT, tip - dir * 36.0 + Vector2(-40, 6), "보스 방", HORIZONTAL_ALIGNMENT_CENTER, 80, 12)


## 화면 좌표로 그리는 체력, 경험치, 궁극기, 군단장 체력 막대.
static func draw_bars(canvas: CanvasItem, sim, data: Dictionary, view: Vector2) -> void:
	var hp_bar := Rect2(16, 10, minf(320.0, view.x - 32.0), 16)
	canvas.draw_rect(hp_bar, Color.BLACK)
	canvas.draw_rect(Rect2(hp_bar.position, Vector2(hp_bar.size.x * maxf(sim.hp, 0.0) / sim.max_hp, hp_bar.size.y)), Palette.GRUNT)
	var xp_bar := Rect2(0, view.y - 8, view.x, 8)
	canvas.draw_rect(xp_bar, Color.BLACK)
	canvas.draw_rect(Rect2(xp_bar.position, Vector2(view.x * float(sim.xp) / sim.xp_needed(), 8)), Palette.GEM)
	var ult_bar := Rect2(16, view.y - 40, minf(320.0, view.x - 32.0), 14)
	var ult_ratio := float(sim.ult_charge) / float(data.ultimate.charge_kills)
	var ult_color := Palette.AWAKEN
	var ult_text := "궁극기 %d%%" % int(ult_ratio * 100.0)
	if sim.ultimate_ready():
		ult_color = Palette.AWAKEN.lerp(Color.WHITE, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012))
		ult_text = "궁극기 준비! [Space] %s" % data.ultimate[sim.main_weapon].name
	canvas.draw_rect(ult_bar, Color.BLACK)
	canvas.draw_rect(Rect2(ult_bar.position, Vector2(ult_bar.size.x * ult_ratio, ult_bar.size.y)), ult_color)
	canvas.draw_string(FONT, ult_bar.position + Vector2(0, -8), ult_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	if sim.boss != null and sim.boss.hp > 0.0:
		# 왼쪽 위 HUD 문구와 겹치지 않게 아래 가운데에 둔다.
		var width := minf(400.0, view.x - 40.0)
		var boss_bar := Rect2((view.x - width) * 0.5, view.y - 44, width, 18)
		var title: String = sim.boss.label + (" (광폭화)" if sim.is_enraged() else "")
		canvas.draw_string(FONT, Vector2(boss_bar.position.x, boss_bar.position.y - 8), title, HORIZONTAL_ALIGNMENT_CENTER, width, 24)
		canvas.draw_rect(boss_bar, Color.BLACK)
		canvas.draw_rect(Rect2(boss_bar.position, Vector2(width * sim.boss.hp / sim.boss.max_hp, 18)), Palette.BOSS)


## 반지름에 맞춰 정수 배율로 키운 캐릭터와 발밑 그림자. pose는 Animator가 계산한 자세다.
## 발이 닿는 아래쪽을 기준으로 찌그러뜨리고, 떠오르면 그림자가 작아진다.
static func _draw_character(canvas: CanvasItem, tex: Texture2D, pos: Vector2, radius: float, tint: Color, facing: float, pose := Animator.NEUTRAL) -> void:
	var scale := maxi(2, roundi(radius * 3.0 / TILE))
	var size := float(TILE * scale)
	var lift: float = pose.lift
	var feet := pos + Vector2(0, size * 0.5)
	canvas.draw_circle(pos + Vector2(0, size * 0.36), size * 0.26 * clampf(1.0 - lift / size, 0.6, 1.0), Color(0, 0, 0, 0.35))
	var draw_size: Vector2 = Vector2(size, size) * pose.squash
	var top_left: Vector2 = feet + pose.offset - Vector2(draw_size.x * 0.5, draw_size.y + lift)
	var rect := Rect2(top_left, draw_size)
	if facing < 0.0:
		rect = Rect2(top_left, Vector2(-draw_size.x, draw_size.y))
	canvas.draw_texture_rect(tex, rect, false, tint * pose.tint)


## 너비를 음수로 주면 좌우가 뒤집힌다. 위치는 그대로 왼쪽 위 모서리로 쓰인다.
static func _draw_sprite(canvas: CanvasItem, tex: Texture2D, pos: Vector2, scale: int, tint: Color, facing := 1.0) -> void:
	var size := Vector2.ONE * TILE * scale
	if facing < 0.0:
		size.x = -size.x
	canvas.draw_texture_rect(tex, Rect2(pos - size.abs() * 0.5, size), false, tint)


static func _draw_auras(canvas: CanvasItem, sim, data: Dictionary, player: Vector2) -> void:
	if int(sim.build.weapons.aura) > 0:
		var color := Palette.AWAKEN if sim.main_weapon == "aura" and sim.is_awakened(sim.build) else Palette.PLAYER
		canvas.draw_circle(player, sim.weapon_stats("aura", sim.build).radius, Color(color, 0.08))
	for enemy in sim.enemies:
		if enemy.kind == "ghost" and int(enemy.build.weapons.aura) > 0:
			canvas.draw_circle(enemy.pos, sim.weapon_stats("aura", enemy.build).radius * float(data.weapons.aura.hostile_radius_mult), Color(Palette.HOSTILE, 0.12))


static func _draw_boss_telegraph(canvas: CanvasItem, sim) -> void:
	if sim.boss == null or sim.boss_state != "windup":
		return
	var pattern: Dictionary = sim.boss_pattern
	match pattern.type:
		"charge":
			var length := float(pattern.speed) * float(pattern.duration)
			var end: Vector2 = sim.boss.pos + sim.charge_dir * length
			canvas.draw_line(sim.boss.pos, end, Color(Palette.BOSS, 0.55), sim.boss.radius * 2.0)
		"ring":
			canvas.draw_arc(sim.boss.pos, sim.boss.radius + 26.0, 0.0, TAU, 48, Palette.HOSTILE, 5.0)
		"summon":
			canvas.draw_arc(sim.boss.pos, 120.0, 0.0, TAU, 48, Palette.GHOST, 3.0)
		"spray":
			# 부채꼴로 날아갈 방향을 미리 보여 준다.
			var count := int(pattern.count)
			for i in count:
				var offset := 0.0 if count == 1 else (i / float(count - 1) - 0.5) * float(pattern.spread)
				canvas.draw_line(sim.boss.pos, sim.boss.pos + sim.charge_dir.rotated(offset) * 260.0, Color(Palette.HOSTILE, 0.35), 3.0)
		"quake":
			# 내리찍을 범위가 준비 시간 동안 안쪽부터 차오른다.
			var radius := float(pattern.radius)
			var progress := clampf(1.0 - sim.boss_timer / maxf(float(pattern.windup), 0.01), 0.0, 1.0)
			canvas.draw_circle(sim.boss.pos, radius * progress, Color(Palette.BOSS, 0.25))
			canvas.draw_arc(sim.boss.pos, radius, 0.0, TAU, 64, Palette.BOSS, 4.0)
		"slash":
			# 칼이 닿는 부채꼴이 준비 동안 차오르고, 칼을 등 뒤로 치켜든다.
			var reach := float(pattern.range)
			var arc := float(pattern.arc)
			var progress := clampf(1.0 - sim.boss_timer / maxf(float(pattern.windup), 0.01), 0.0, 1.0)
			var facing: float = sim.charge_dir.angle()
			_draw_sector(canvas, sim.boss.pos, reach * progress, facing, arc, Color(Palette.BOSS, 0.25))
			_draw_sector(canvas, sim.boss.pos, reach, facing, arc, Color(Palette.BOSS, 0.0), Palette.BOSS)


## 중심에서 angle 방향으로 arc 폭만큼 벌어진 부채꼴.
static func _draw_sector(canvas: CanvasItem, center: Vector2, reach: float, angle: float, arc: float, fill: Color, outline := Color(0, 0, 0, 0)) -> void:
	var points := PackedVector2Array([center])
	var steps := 16
	for i in steps + 1:
		points.append(center + Vector2.from_angle(angle - arc * 0.5 + arc * i / steps) * reach)
	if fill.a > 0.0:
		canvas.draw_colored_polygon(points, fill)
	if outline.a > 0.0:
		points.append(center)
		canvas.draw_polyline(points, outline, 3.0)


## 칼 스프라이트를 angle 방향으로 뻗어 그린다. 원본은 칼날이 위(-y)를 향한다.
static func draw_sword_at(canvas: CanvasItem, center: Vector2, angle: float, length: float, tint := Color.WHITE) -> void:
	# 칼자루가 center에 오도록 칼 길이의 절반만큼 앞으로 민다.
	draw_rotated(canvas, SPRITES.sword, center + Vector2.from_angle(angle) * length * 0.5, Vector2(length * SWORD_WIDTH, length), angle + PI * 0.5, tint)


## 칼을 쥔 손의 위치. 몸 가운데보다 조금 위(가슴)에서 휘두른다.
static func sword_pivot(boss_pos: Vector2, radius: float) -> Vector2:
	return boss_pos + Vector2(0, -radius * 0.25)


static func sword_length(radius: float) -> float:
	return radius * 2.6


## 칼을 머리 위쪽에서 아래로 내리긋도록, 바라보는 방향에 따라 휘두르는 쪽을 정한다.
## 오른쪽을 보면 각도가 줄어드는 쪽(위), 왼쪽을 보면 늘어나는 쪽(위)에서 시작한다.
static func sword_side(facing: float) -> float:
	return 1.0 if cos(facing) >= 0.0 else -1.0


## 휘두르기 시작 각도와 끝 각도. 부채꼴 위쪽 끝 너머(어깨 뒤)에서 아래쪽 끝을 조금 지나칠 때까지.
static func sword_swing_range(facing: float, arc: float) -> Vector2:
	var side := sword_side(facing)
	return Vector2(facing - side * (arc * 0.5 + SWORD_PULLBACK), facing + side * (arc * 0.5 + SWORD_OVERSHOOT))


## 휘두르기 준비 중인 칼의 각도: 부채꼴 위쪽 끝에서 어깨 뒤로 치켜들고, 끝 무렵에는 힘을 모으듯 떤다.
static func sword_windup_angle(sim, t: float) -> float:
	var pattern: Dictionary = sim.boss_pattern
	var progress := clampf(1.0 - sim.boss_timer / maxf(float(pattern.windup), 0.01), 0.0, 1.0)
	var facing: float = sim.charge_dir.angle()
	var side := sword_side(facing)
	var ready := facing - side * float(pattern.arc) * 0.5
	var tremble := sin(t * 90.0) * 0.05 * progress * progress
	return ready - side * SWORD_PULLBACK * (1.0 - pow(1.0 - progress, 3.0)) + tremble


static func is_sword_windup(sim) -> bool:
	return sim.boss != null and sim.boss_state == "windup" and sim.boss_pattern.get("type", "") == "slash"


## 기사가 칼을 등 뒤로 치켜드는 모습. 캐릭터 위에 그려야 보인다.
static func _draw_sword_windup(canvas: CanvasItem, sim, t: float) -> void:
	if not is_sword_windup(sim):
		return
	var radius: float = sim.boss.radius
	draw_sword_at(canvas, sword_pivot(sim.boss.pos, radius), sword_windup_angle(sim, t), sword_length(radius))


## 회전한 텍스처를 네 꼭짓점 다각형으로 그린다.
## draw_set_transform을 쓰면 캔버스에 걸어 둔 카메라 변환이 덮어써지므로, 월드 캔버스에서는 이 함수를 쓴다.
static func draw_rotated(canvas: CanvasItem, tex: Texture2D, center: Vector2, size: Vector2, angle: float, tint := Color.WHITE) -> void:
	var half := size * 0.5
	var corners := PackedVector2Array()
	for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		corners.append(center + corner.rotated(angle))
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	canvas.draw_polygon(corners, PackedColorArray([tint]), uvs, tex)


## 거미줄: 날아가는 동안은 거미줄 뭉치와 떨어질 자리, 깔린 뒤에는 바닥의 거미줄.
static func _draw_zone(canvas: CanvasItem, zone) -> void:
	if zone.delay > 0.0:
		var t: float = 1.0 - zone.delay / maxf(zone.travel, 0.01)
		var flying: Vector2 = zone.origin.lerp(zone.pos, t) - Vector2(0, sin(t * PI) * 90.0)
		canvas.draw_arc(zone.pos, zone.radius, 0.0, TAU, 32, Color(WEB_COLOR, 0.35), 2.0)
		_draw_web(canvas, flying, 16.0, 0.9)
		return
	var fade := clampf(zone.time / 0.8, 0.0, 1.0)
	_draw_web(canvas, zone.pos, zone.radius, 0.6 * fade)


static func _draw_web(canvas: CanvasItem, center: Vector2, radius: float, alpha: float) -> void:
	var color := Color(WEB_COLOR, alpha)
	var spokes := 8
	for i in spokes:
		canvas.draw_line(center, center + Vector2.from_angle(TAU * i / spokes) * radius, color, 2.0)
	for ring in [0.35, 0.65, 1.0]:
		var points := PackedVector2Array()
		for i in spokes + 1:
			# 바큇살 사이가 살짝 처지게 해서 거미줄처럼 보이게 한다.
			var sag := 0.92 if i % 2 == 1 else 1.0
			points.append(center + Vector2.from_angle(TAU * i / spokes) * radius * ring * sag)
		canvas.draw_polyline(points, color, 1.5)


## 과거의 나는 플레이어 그림을, 보스는 라운드별 보스 정의의 그림을 쓴다.
static func _sprite_key(sim, enemy) -> String:
	match enemy.kind:
		"ghost":
			return "player"
		"boss":
			return sim.boss_def.get("sprite", "boss")
	return enemy.kind


## 적은 항상 플레이어를 바라본다. 쫓거나 노리는 대상이 플레이어이기 때문이다.
static func _draw_enemy(canvas: CanvasItem, sim, enemy, alpha: float, player: Vector2, t: float) -> void:
	var pos: Vector2 = enemy.prev.lerp(enemy.pos, alpha)
	var tex: Texture2D = SPRITES[_sprite_key(sim, enemy)]
	var tint := Color.WHITE
	if enemy.kind == "ghost":
		tint = AWAKEN_TINT * GHOST_TINT if sim.is_awakened(enemy.build) else GHOST_TINT
	var facing := 1.0 if player.x >= pos.x else -1.0
	# 태어난 시각으로 위상을 흩어, 무리가 한 박자로 튀지 않게 한다.
	var seed: float = enemy.born * 7.31 + enemy.max_hp
	var pose: Dictionary
	match enemy.kind:
		"boss":
			pose = Animator.boss(sim.boss_state, sim.boss_timer, sim.boss_pattern, t)
		"ghost":
			pose = Animator.float_ghost(t, seed)
		"swarmling":
			pose = Animator.flap(t, seed)
		_:
			pose = Animator.hop(enemy.kind, t, seed)
	pose = Animator.with_hit(pose, enemy.flash)
	_draw_character(canvas, tex, pos, enemy.radius, FLASH_TINT if enemy.flash > 0.0 else tint, facing, pose)
	if enemy.kind == "ghost":
		canvas.draw_string(FONT, pos + Vector2(-80, -enemy.radius - 18), enemy.label, HORIZONTAL_ALIGNMENT_CENTER, 160, 12)
		var bar := Rect2(pos + Vector2(-30, -enemy.radius - 12), Vector2(60, 5))
		canvas.draw_rect(bar, Color.BLACK)
		canvas.draw_rect(Rect2(bar.position, Vector2(60.0 * maxf(enemy.hp, 0.0) / enemy.max_hp, 5)), Palette.GHOST)
