extends RefCounted
## sim 상태를 도형으로 그린다. 에셋이 생기면 이 파일만 스프라이트로 바꾸면 된다.

const Palette := preload("res://legion/game/palette.gd")


## 플레이어 아래에 깔리는 것들: 경기장, 보석, 아이템, 낙뢰 예고, 오라, 군단장 예고, 적, 탄.
static func draw_world(canvas: CanvasItem, sim, data: Dictionary, alpha: float, player: Vector2) -> void:
	_draw_arena(canvas, data)
	for gem in sim.gems:
		canvas.draw_circle(gem.pos, 4.0, Palette.GEM)
	for item in sim.pickups:
		var item_color := Palette.MAGNET if item.kind == "magnet" else Palette.POTION
		canvas.draw_circle(item.pos, float(data.items.radius), Color(item_color, 0.3))
		canvas.draw_arc(item.pos, float(data.items.radius), 0.0, TAU, 24, item_color, 2.0)
		canvas.draw_string(ThemeDB.fallback_font, item.pos + Vector2(-40, 5), "자석" if item.kind == "magnet" else "포션", HORIZONTAL_ALIGNMENT_CENTER, 80, 13)
	for strike in sim.strikes:
		var strike_color := Palette.HOSTILE if strike.hostile else Palette.AWAKEN
		canvas.draw_arc(strike.pos, strike.radius, 0.0, TAU, 48, strike_color, 3.0)
		canvas.draw_circle(strike.pos, strike.radius, Color(strike_color, 0.15))
	_draw_auras(canvas, sim, data, player)
	_draw_boss_telegraph(canvas, sim)
	for enemy in sim.enemies:
		_draw_enemy(canvas, sim, enemy, alpha)
	for shot in sim.projectiles:
		canvas.draw_circle(shot.prev.lerp(shot.pos, alpha), shot.radius, Palette.HOSTILE if shot.hostile else Color.WHITE)


static func draw_player(canvas: CanvasItem, sim, data: Dictionary, player: Vector2) -> void:
	var player_color := Palette.AWAKEN if sim.is_awakened(sim.build) else Palette.PLAYER
	canvas.draw_circle(player, float(data.player.radius), Color.WHITE if sim.player_flash > 0.0 else player_color)


## 화면 좌표로 그리는 체력, 경험치, 궁극기, 군단장 체력 막대.
static func draw_bars(canvas: CanvasItem, sim, data: Dictionary, view: Vector2) -> void:
	var font := ThemeDB.fallback_font
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
	canvas.draw_string(font, ult_bar.position + Vector2(0, -6), ult_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	if sim.boss != null and sim.boss.hp > 0.0:
		var width := minf(520.0, view.x - 40.0)
		var boss_bar := Rect2((view.x - width) * 0.5, 44, width, 18)
		var title: String = sim.boss.label + (" (광폭화)" if sim.is_enraged() else "")
		canvas.draw_string(font, Vector2(boss_bar.position.x, 38), title, HORIZONTAL_ALIGNMENT_CENTER, width, 18)
		canvas.draw_rect(boss_bar, Color.BLACK)
		canvas.draw_rect(Rect2(boss_bar.position, Vector2(width * sim.boss.hp / sim.boss.max_hp, 18)), Palette.BOSS)


static func _draw_arena(canvas: CanvasItem, data: Dictionary) -> void:
	var size := Vector2(float(data.arena.w), float(data.arena.h))
	for x in range(0, int(size.x) + 1, 100):
		canvas.draw_line(Vector2(x, 0), Vector2(x, size.y), Palette.GRID)
	for y in range(0, int(size.y) + 1, 100):
		canvas.draw_line(Vector2(0, y), Vector2(size.x, y), Palette.GRID)
	canvas.draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE, false, 2.0)


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


static func _draw_enemy(canvas: CanvasItem, sim, enemy, alpha: float) -> void:
	var pos: Vector2 = enemy.prev.lerp(enemy.pos, alpha)
	var color := Palette.enemy_color(enemy.kind)
	if enemy.kind == "ghost" and sim.is_awakened(enemy.build):
		color = Palette.AWAKEN
	canvas.draw_circle(pos, enemy.radius, Color.WHITE if enemy.flash > 0.0 else color)
	if enemy.kind == "ghost":
		var font := ThemeDB.fallback_font
		canvas.draw_string(font, pos + Vector2(-80, -enemy.radius - 18), enemy.label, HORIZONTAL_ALIGNMENT_CENTER, 160, 14)
		var bar := Rect2(pos + Vector2(-30, -enemy.radius - 12), Vector2(60, 5))
		canvas.draw_rect(bar, Color.BLACK)
		canvas.draw_rect(Rect2(bar.position, Vector2(60.0 * maxf(enemy.hp, 0.0) / enemy.max_hp, 5)), Palette.GHOST)
