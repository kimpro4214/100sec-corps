extends RefCounted
## sim 이벤트를 받아 이펙트와 파편을 만들고 그린다. 텍스처는 Kenney Particle Pack(CC0).
## 세 층으로 그린다.
##   draw_under: 캐릭터 아래 (낙뢰 그을음, 돌진 먼지)
##   draw_debris: 캐릭터와 같은 층 (처치 파편)
##   draw_glow: 더하기 혼합 레이어 (탄의 빛과 꼬리, 낙뢰, 오라 마법진, 고리, 섬광, 궁극기 소용돌이)
## 화면 흔들림, 히트스톱, 플래시는 CinemaDirector에 요청한다.

const Palette := preload("res://legion/game/palette.gd")
const CinemaDirector := preload("res://legion/game/cinema_director.gd")

const TEX := {
	"glow": preload("res://legion/art/fx/circle_05.png"),
	"ring": preload("res://legion/art/fx/circle_02.png"),
	"magic": preload("res://legion/art/fx/magic_01.png"),
	"star": preload("res://legion/art/fx/star_04.png"),
	"spark": preload("res://legion/art/fx/magic_04.png"),
	"burst": preload("res://legion/art/fx/star_08.png"),
	"bolt": preload("res://legion/art/fx/spark_05.png"),
	"zap": preload("res://legion/art/fx/spark_01.png"),
	"twirl": preload("res://legion/art/fx/twirl_01.png"),
	"trail": preload("res://legion/art/fx/trace_01.png"),
	"scorch": preload("res://legion/art/fx/scorch_01.png"),
	"smoke": preload("res://legion/art/fx/smoke_01.png"),
	"slash": preload("res://legion/art/fx/slash_01.png"),
	"flame": preload("res://legion/art/fx/flame_01.png"),
	"dirt": preload("res://legion/art/fx/dirt_01.png"),
}
const LIGHTNING_COLOR := Color(0.65, 0.85, 1.0)
const FIRE_COLOR := Color(1.0, 0.55, 0.2)
const BOULDER_COLOR := Color(0.62, 0.5, 0.4)
const WEB_GLOW := Color(0.85, 0.85, 0.95)
const VENOM_COLOR := Color(0.55, 1.0, 0.35)
const SOUL_COLOR := Color(0.75, 0.5, 1.0)
const SWORD_WAVE_COLOR := Color(0.8, 0.9, 1.0)
const SLASH_COLOR := Color(1.0, 0.45, 0.4)
const SLASH_LIFE := 0.45
const SWORD_AFTERIMAGES := 4
const SWORD_AFTERIMAGE_LAG := 0.018
const WorldRenderer := preload("res://legion/game/world_renderer.gd")
const REWARD_COLOR := {
	"level": Color("ffd23f"), "jackpot": Color("ffd23f"), "refund": Color("ffd23f"),
	"heal": Color("7ee081"), "shield": Color(0.8, 0.95, 1.0), "frenzy": Color("ff8a5b"),
	"bomb": Color("ffe066"), "nothing": Color(0.6, 0.6, 0.6), "ambush": Color("ff5d8f"),
}
const MAX_PARTICLES := 900
const MAX_DECALS := 60
const KILL_JUICE := {
	"swarmling": {"debris": 4, "sparkles": 2, "shake": 0.0, "hitstop": 0.0},
	"runner": {"debris": 4, "sparkles": 2, "shake": 0.0, "hitstop": 0.0},
	"grunt": {"debris": 6, "sparkles": 3, "shake": 0.0, "hitstop": 0.0},
	"brute": {"debris": 12, "sparkles": 6, "shake": 4.0, "hitstop": 0.03},
	"ghost": {"debris": 22, "sparkles": 14, "shake": 8.0, "hitstop": 0.08},
	"boss": {"debris": 48, "sparkles": 36, "shake": 22.0, "hitstop": 0.35},
}

var effects: Array = [] # 더하기 레이어에 그리는 짧은 효과
var particles: Array = [] # glow가 true면 더하기 레이어, 아니면 파편
var decals: Array = [] # 바닥에 남는 그을음과 먼지
var time := 0.0


func reset() -> void:
	effects = []
	particles = []
	decals = []


func handle(event: Dictionary, director: CinemaDirector) -> void:
	match event.type:
		"aura":
			_add_effect("pulse", event.pos, event.radius, 0.3, Palette.HOSTILE if event.hostile else Palette.PLAYER)
		"burst":
			_add_effect("burst", event.pos, event.radius, 0.25, Palette.AWAKEN)
		"lightning":
			# 떨어지는 공격은 출처마다 모양이 다르다: 거인의 바위, 군단장의 운석, 그 밖은 번개.
			match event.get("source", ""):
				"boss_quake":
					pass
				"boss_boulder":
					_add_effect("dirt", event.pos, event.radius * 1.6, 0.4, BOULDER_COLOR)
					_add_decal("smoke", event.pos, event.radius, 0.9, Color(0.5, 0.42, 0.36, 0.6))
					director.add_shake(5.0)
				"boss_meteor":
					_add_effect("fire_burst", event.pos, event.radius * 1.6, 0.45, FIRE_COLOR)
					_add_decal("scorch", event.pos, event.radius * 1.4, 2.5, Color(0, 0, 0, 0.5))
					_spawn_particles(event.pos, 10, FIRE_COLOR, 260.0, 14.0, true)
				_:
					var color := Palette.HOSTILE if event.get("hostile", false) else LIGHTNING_COLOR
					_add_effect("lightning", event.pos, event.radius, 0.3, color)
					_add_decal("scorch", event.pos, event.radius * 1.4, 2.5, Color(0, 0, 0, 0.45))
					_spawn_particles(event.pos, 4, color, 220.0, 10.0, true)
		"boss_slash":
			# 준비 때 머리 위로 치켜든 각도에서 시작해 부채꼴 아래쪽을 조금 지나칠 때까지 내리긋는다.
			var effect := _add_effect("slash", WorldRenderer.sword_pivot(event.pos, event.radius), event.range, SLASH_LIFE, SLASH_COLOR)
			var swing_range := WorldRenderer.sword_swing_range(event.angle, event.arc)
			effect.start = swing_range.x
			effect.end = swing_range.y
			effect.length = WorldRenderer.sword_length(event.radius)
			director.add_shake(7.0)
			director.hitstop = maxf(director.hitstop, 0.05)
		"boss_web":
			_add_effect("burst", event.pos, 70.0, 0.3, WEB_GLOW)
		"web_land":
			_add_effect("burst", event.pos, event.radius, 0.3, WEB_GLOW)
			_spawn_particles(event.pos, 8, WEB_GLOW, 160.0, 10.0, true)
		"kill":
			var juice: Dictionary = KILL_JUICE.get(event.kind, KILL_JUICE.grunt)
			var color := Palette.enemy_color(event.kind)
			_spawn_particles(event.pos, juice.debris, color, 160.0 + event.radius * 6.0, 3.0 + event.radius * 0.15, false)
			_spawn_particles(event.pos, juice.sparkles, color.lightened(0.4), 140.0 + event.radius * 5.0, 14.0 + event.radius * 0.4, true)
			_add_effect("flash", event.pos, event.radius * 1.6, 0.15, color.lightened(0.5))
			if juice.shake > 0.0:
				director.add_shake(juice.shake)
			director.hitstop = maxf(director.hitstop, juice.hitstop)
			if event.kind == "ghost" or event.kind == "boss":
				_add_effect("burst", event.pos, event.radius * 2.5, 0.4, color.lightened(0.3))
				_add_effect("shock", event.pos, event.radius * 4.0, 0.45, color)
			if event.kind == "boss":
				director.add_flash(Color.WHITE, 0.6)
				_add_effect("shock", event.pos, 300.0, 0.7, Palette.BOSS)
		"hurt":
			director.add_shake(minf(3.0 + event.damage * 0.5, 12.0))
			director.hurt_tint = minf(0.45, director.hurt_tint + 0.15 + event.damage * 0.01)
		"ult_blast":
			_add_effect("shock", event.pos, event.radius, 0.6, Palette.AWAKEN)
			_add_effect("magic_burst", event.pos, event.radius, 0.8, Palette.AWAKEN)
			_spawn_particles(event.pos, 40, Palette.AWAKEN, event.radius * 2.2, 18.0, true)
		"interact":
			var color: Color = REWARD_COLOR.get(event.reward, Palette.AWAKEN)
			_add_effect("burst", event.pos, 90.0, 0.5, color)
			_spawn_particles(event.pos, 16, color, 260.0, 14.0, true)
			if event.reward == "bomb":
				_add_effect("shock", event.pos, 420.0, 0.6, Palette.AWAKEN)
				director.add_shake(16.0)
			elif event.reward == "nothing":
				_add_decal("smoke", event.pos, 50.0, 0.8, Color(0.5, 0.5, 0.5, 0.6))
		"portal":
			_add_effect("burst", event.pos, 160.0, 0.6, Palette.GHOST)
			_add_effect("shock", event.pos, 200.0, 0.6, Palette.GHOST)
		"boss_room":
			# 필드에 남은 효과는 보스 방과 상관없으니 지우고, 검은 화면에서 밝아지며 넘어간다.
			reset()
			director.add_flash(Color.BLACK, 1.0)
		"boss_quake":
			_add_effect("shock", event.pos, event.radius, 0.5, Palette.BOSS)
			for i in 6:
				_add_decal("smoke", event.pos + Vector2.from_angle(TAU * i / 6.0) * event.radius * 0.6, event.radius * 0.5, 0.8, Color(0.55, 0.45, 0.4, 0.5))
			director.add_shake(14.0)
		"boss_blink":
			_add_effect("burst", event.pos, 120.0, 0.4, Palette.GHOST)
			_add_effect("magic_burst", event.pos, 140.0, 0.5, Palette.GHOST)
		"ultimate":
			_add_effect("burst", event.pos, 220.0, 0.5, Palette.AWAKEN)
			_add_effect("shock", event.pos, 180.0, 0.4, Color.WHITE)
			_spawn_particles(event.pos, 30, Palette.AWAKEN.lightened(0.3), 520.0, 16.0, true)


## 게임 시간 기준으로 진행하므로 히트스톱 중에는 멈춘다. 군단장 돌진 먼지와 궁극기 기 모으기도 여기서 만든다.
func update(world_delta: float, sim, casting: bool) -> void:
	time += world_delta
	effects = _tick(effects, world_delta)
	decals = _tick(decals, world_delta)
	var alive_particles: Array = []
	for particle in particles:
		particle.time -= world_delta
		particle.pos += particle.vel * world_delta
		particle.vel *= 1.0 - minf(1.0, particle.drag * world_delta)
		if particle.time > 0.0:
			alive_particles.append(particle)
	particles = alive_particles
	if sim == null:
		return
	if sim.boss != null and sim.boss.hp > 0.0 and sim.boss_state == "charge" and randf() < world_delta * 30.0:
		_add_decal("smoke", sim.boss.pos + Vector2(randf_range(-20, 20), sim.boss.radius * 0.8), randf_range(40.0, 70.0), 0.6, Color(0.55, 0.45, 0.4, 0.5))
	if casting:
		# 바깥에서 안쪽으로 빨려 드는 빛 알갱이.
		for i in 2:
			var from := Vector2.from_angle(randf() * TAU) * randf_range(160.0, 240.0)
			_add_particle(sim.player_pos + from, -from * 2.4, 0.4, Palette.AWAKEN, randf_range(10.0, 18.0), true, 0.0)


func draw_under(canvas: CanvasItem) -> void:
	for decal in decals:
		var fade: float = decal.time / decal.max
		var size: float = decal.radius * 2.0
		canvas.draw_texture_rect(TEX[decal.kind], Rect2(decal.pos - Vector2(size, size) * 0.5, Vector2(size, size)), false, Color(decal.color, decal.color.a * fade))


## 캐릭터와 같은 층: 처치 파편, 휘두르는 칼, 떨어지는 바위.
func draw_debris(canvas: CanvasItem, sim) -> void:
	for particle in particles:
		if not particle.glow:
			canvas.draw_circle(particle.pos, particle.size * particle.time / particle.max, particle.color)
	for effect in effects:
		if effect.kind == "slash":
			_draw_sword_swing(canvas, effect)
	if sim == null:
		return
	for strike in sim.strikes:
		if strike.source == "boss_boulder":
			# 하늘에서 떨어지는 바위. 떨어질수록 그림자가 커진다.
			var height: float = strike.delay * 520.0
			canvas.draw_circle(strike.pos, strike.radius * 0.5 * (1.0 - strike.delay * 0.6), Color(0, 0, 0, 0.3))
			var size: Vector2 = Vector2.ONE * strike.radius * 1.2
			WorldRenderer.draw_rotated(canvas, TEX.dirt, strike.pos - Vector2(0, height), size, strike.delay * 6.0, BOULDER_COLOR)


func draw_glow(canvas: CanvasItem, sim, alpha: float, director: CinemaDirector) -> void:
	if sim == null:
		return
	_draw_auras(canvas, sim)
	_draw_boss_telegraph(canvas, sim)
	if WorldRenderer.is_sword_windup(sim):
		# 준비가 끝나 갈 때 칼끝이 번쩍인다. 곧 휘두른다는 신호다.
		var progress: float = 1.0 - sim.boss_timer / maxf(float(sim.boss_pattern.windup), 0.01)
		if progress > 0.55:
			var t: float = sim.time + alpha * sim.tick
			var radius: float = sim.boss.radius
			var tip: Vector2 = WorldRenderer.sword_pivot(sim.boss.pos, radius) + Vector2.from_angle(WorldRenderer.sword_windup_angle(sim, t)) * WorldRenderer.sword_length(radius) * 0.95
			var glint := (progress - 0.55) / 0.45
			_tex(canvas, TEX.star, tip, 30.0 + 40.0 * glint, Color(1, 1, 1, glint), time * 4.0)
	if sim.ult_guard > 0.0:
		# 무적(보호막, 궁극기 직후) 동안 플레이어를 감싸는 빛.
		var player: Vector2 = sim.player_prev.lerp(sim.player_pos, alpha)
		_tex(canvas, TEX.ring, player, 70.0 + 6.0 * sin(time * 10.0), Color(0.8, 0.95, 1.0, 0.7))
		_tex(canvas, TEX.glow, player, 90.0, Color(0.8, 0.95, 1.0, 0.25))
	if sim.portal_open and not sim.in_boss_room:
		var radius := float(sim.data.boss_room.portal_radius)
		_tex(canvas, TEX.glow, sim.portal_pos, radius * 6.0, Color(Palette.GHOST, 0.5 + 0.2 * sin(time * 4.0)))
		_tex(canvas, TEX.twirl, sim.portal_pos, radius * 4.0, Color(Palette.GHOST, 0.9), -time * 4.0)
		_tex(canvas, TEX.magic, sim.portal_pos, radius * 5.0, Color(Palette.GHOST, 0.5), time * 1.2)
	for shot in sim.projectiles:
		_draw_projectile(canvas, shot, shot.prev.lerp(shot.pos, alpha))
	for strike in sim.strikes:
		if strike.source == "boss_meteor":
			# 비스듬히 떨어지는 운석.
			var fall: Vector2 = Vector2(-0.5, -1.0) * strike.delay * 480.0
			_tex(canvas, TEX.flame, strike.pos + fall, strike.radius * 1.6, FIRE_COLOR, Vector2(0.5, 1.0).angle() - PI * 0.5)
			_tex(canvas, TEX.glow, strike.pos + fall, strike.radius * 1.2, Color(FIRE_COLOR, 0.8))
	for effect in effects:
		_draw_effect(canvas, effect)
	for particle in particles:
		if particle.glow:
			var fade: float = particle.time / particle.max
			_tex(canvas, TEX.star, particle.pos, particle.size * (0.5 + fade * 0.5), Color(particle.color, fade), particle.spin * time)
	if director.is_casting():
		var p := clampf(director.cinema_time / CinemaDirector.ULT_CAST_SECONDS, 0.0, 1.0)
		var player: Vector2 = sim.player_prev.lerp(sim.player_pos, alpha)
		_tex(canvas, TEX.twirl, player, lerpf(260.0, 120.0, p), Color(Palette.AWAKEN, 0.3 + 0.5 * p), -time * 9.0)
		_tex(canvas, TEX.glow, player, 80.0 + 120.0 * p, Color(Palette.AWAKEN, 0.6 * p))


# --- 그리기 세부 ---

func _draw_auras(canvas: CanvasItem, sim) -> void:
	var player: Vector2 = sim.player_pos
	if int(sim.build.weapons.aura) > 0:
		var radius: float = sim.weapon_stats("aura", sim.build).radius
		var color := Palette.AWAKEN if sim.main_weapon == "aura" and sim.is_awakened(sim.build) else Palette.PLAYER
		_tex(canvas, TEX.magic, player, radius * 2.3, Color(color, 0.22), time * 0.7)
	for enemy in sim.enemies:
		if enemy.kind == "ghost" and int(enemy.build.weapons.aura) > 0:
			var radius: float = sim.weapon_stats("aura", enemy.build).radius * float(sim.data.weapons.aura.hostile_radius_mult)
			_tex(canvas, TEX.magic, enemy.pos, radius * 2.3, Color(Palette.HOSTILE, 0.25), -time * 0.9)


func _draw_boss_telegraph(canvas: CanvasItem, sim) -> void:
	if sim.boss == null or sim.boss_state != "windup":
		return
	var pulse := 0.5 + 0.5 * sin(time * 24.0)
	match sim.boss_pattern.type:
		"ring":
			_tex(canvas, TEX.ring, sim.boss.pos, sim.boss.radius * 3.0 + pulse * 20.0, Color(Palette.HOSTILE, 0.5 + 0.4 * pulse))
		"summon":
			_tex(canvas, TEX.magic, sim.boss.pos, 260.0, Color(Palette.GHOST, 0.6), time * 2.0)
		"charge":
			_tex(canvas, TEX.glow, sim.boss.pos, sim.boss.radius * 3.0, Color(Palette.BOSS, 0.4 + 0.4 * pulse))


func _draw_projectile(canvas: CanvasItem, shot, pos: Vector2) -> void:
	var color := Palette.PLAYER.lightened(0.3)
	var size: float = shot.radius
	match shot.source:
		"boss_sword_wave":
			# 기사의 검기: 날아가는 방향으로 누운 초승달.
			_tex(canvas, TEX.slash, pos, size * 7.0, Color(SWORD_WAVE_COLOR, 0.95), shot.vel.angle() + PI * 0.5)
			_tex(canvas, TEX.glow, pos, size * 4.0, Color(SWORD_WAVE_COLOR, 0.4))
			return
		"boss_fire":
			# 군단장의 불꽃: 불꽃 꼬리가 뒤로 흐른다.
			_tex(canvas, TEX.flame, pos - shot.vel.normalized() * size * 2.0, size * 7.0, Color(FIRE_COLOR, 0.9), shot.vel.angle() - PI * 0.5)
			_tex(canvas, TEX.glow, pos, size * 4.0, Color(FIRE_COLOR, 0.8))
			return
		"boss_soul":
			_tex(canvas, TEX.twirl, pos, size * 5.0, Color(SOUL_COLOR, 0.8), time * 8.0)
			_tex(canvas, TEX.glow, pos, size * 4.0, Color(SOUL_COLOR, 0.8))
			return
		"boss_venom":
			color = VENOM_COLOR
		_:
			if shot.hostile:
				color = Palette.HOSTILE
			elif shot.source == "ultimate":
				color = Palette.AWAKEN
				size *= 1.4
	if shot.vel != Vector2.ZERO:
		# 꼬리: 세로로 긴 텍스처를 진행 방향 뒤쪽으로 눕힌다.
		var length := size * 9.0
		var center: Vector2 = pos - shot.vel.normalized() * length * 0.4
		canvas.draw_set_transform(center, shot.vel.angle() + PI * 0.5, Vector2.ONE)
		canvas.draw_texture_rect(TEX.trail, Rect2(-size * 1.5, -length * 0.5, size * 3.0, length), false, Color(color, 0.7))
		canvas.draw_set_transform(Vector2.ZERO)
	_tex(canvas, TEX.glow, pos, size * 6.0, Color(color, 0.8))
	_tex(canvas, TEX.glow, pos, size * 2.2, Color.WHITE)


func _draw_effect(canvas: CanvasItem, effect: Dictionary) -> void:
	var fade: float = effect.time / effect.max
	var grow := CinemaDirector.ease_out(1.0 - fade)
	var color: Color = effect.color
	var radius: float = effect.radius
	match effect.kind:
		"pulse":
			_tex(canvas, TEX.ring, effect.pos, radius * 2.0 * lerpf(0.7, 1.05, grow), Color(color, 0.55 * fade))
		"flash":
			_tex(canvas, TEX.glow, effect.pos, radius * 2.0 * (1.0 + grow), Color(color, fade))
		"burst":
			_tex(canvas, TEX.burst, effect.pos, radius * 2.0 * lerpf(0.6, 1.2, grow), Color(color, fade), effect.spin)
		"shock":
			_tex(canvas, TEX.glow, effect.pos, radius * 2.0 * grow, Color(color, 0.25 * fade))
			_tex(canvas, TEX.ring, effect.pos, radius * 2.0 * grow, Color(color, fade))
		"magic_burst":
			_tex(canvas, TEX.magic, effect.pos, radius * 2.0 * lerpf(0.5, 1.1, grow), Color(color, fade), grow * 2.0)
		"slash":
			_draw_slash_trail(canvas, effect)
		"dirt":
			_tex(canvas, TEX.dirt, effect.pos, radius * 2.0 * lerpf(0.6, 1.1, grow), Color(color, fade), effect.spin)
			_tex(canvas, TEX.ring, effect.pos, radius * 2.0 * grow, Color(color, 0.6 * fade))
		"fire_burst":
			_tex(canvas, TEX.flame, effect.pos - Vector2(0, radius * 0.4), radius * 2.0 * lerpf(0.6, 1.2, grow), Color(color, fade))
			_tex(canvas, TEX.glow, effect.pos, radius * 2.4, Color(color, 0.7 * fade))
		"lightning":
			# 하늘에서 내리꽂는 번개 줄기, 착지 섬광, 전기 튐.
			var height := 320.0
			var width := maxf(radius * 1.4, 60.0)
			# 너비가 음수면 좌우만 뒤집히고 위치는 왼쪽 모서리 그대로라, x는 뒤집기와 상관없이 같다.
			var bolt_rect := Rect2(effect.pos.x - width * 0.5, effect.pos.y - height, width * effect.flip, height)
			canvas.draw_texture_rect(TEX.bolt, bolt_rect, false, Color(color, fade))
			canvas.draw_texture_rect(TEX.bolt, bolt_rect, false, Color(1, 1, 1, fade * 0.6))
			_tex(canvas, TEX.glow, effect.pos, radius * 3.0, Color(color, fade))
			_tex(canvas, TEX.zap, effect.pos, radius * 2.6 * (0.8 + grow * 0.4), Color(color, fade), effect.spin)


## 칼 휘두르기: 0.12초 동안 빠르게 베고, 잠깐 멈춘 뒤 사라진다. 휘두르는 동안 뒤로 잔상이 남는다.
func _swing_angle(effect: Dictionary, elapsed: float) -> float:
	var swing := clampf(elapsed / WorldRenderer.SWORD_SWING_SECONDS, 0.0, 1.0)
	return lerpf(effect.start, effect.end, CinemaDirector.ease_out(swing))


func _draw_sword_swing(canvas: CanvasItem, effect: Dictionary) -> void:
	var elapsed: float = effect.max - effect.time
	var swing_end := WorldRenderer.SWORD_SWING_SECONDS
	# 다 휘두른 뒤 잠깐 멈췄다가 흐려진다.
	var alpha := 1.0 - clampf((elapsed - swing_end - 0.12) / (effect.max - swing_end - 0.12), 0.0, 1.0)
	if elapsed < swing_end + SWORD_AFTERIMAGE_LAG * SWORD_AFTERIMAGES:
		for k in range(SWORD_AFTERIMAGES, 0, -1):
			var lag_angle := _swing_angle(effect, elapsed - k * SWORD_AFTERIMAGE_LAG)
			var ghost := Color(1.0, 0.85, 0.85, 0.5 - k * 0.1)
			WorldRenderer.draw_sword_at(canvas, effect.pos, lag_angle, effect.length, ghost)
	WorldRenderer.draw_sword_at(canvas, effect.pos, _swing_angle(effect, elapsed), effect.length, Color(1, 1, 1, alpha))


## 칼끝이 지나간 자리의 초승달 궤적. 칼 쪽이 가장 밝고 뒤로 갈수록 옅어진다.
func _draw_slash_trail(canvas: CanvasItem, effect: Dictionary) -> void:
	var elapsed: float = effect.max - effect.time
	var swing_end := WorldRenderer.SWORD_SWING_SECONDS
	var head := _swing_angle(effect, elapsed)
	var fade := 1.0 - clampf((elapsed - swing_end) / (effect.max - swing_end), 0.0, 1.0)
	var reach: float = effect.radius
	_draw_crescent(canvas, effect.pos, effect.start, head, reach * 0.45, reach, Color(SLASH_COLOR, 0.8 * fade))
	_draw_crescent(canvas, effect.pos, effect.start, head, reach * 0.8, reach * 0.97, Color(1, 1, 1, 0.9 * fade))
	if elapsed < swing_end:
		_tex(canvas, TEX.star, effect.pos + Vector2.from_angle(head) * reach, 46.0, Color(1, 1, 1, 0.9), time * 6.0)


## from 각도에서 to 각도까지의 고리 조각. to 쪽 끝이 진하고 from 쪽은 투명하다.
func _draw_crescent(canvas: CanvasItem, center: Vector2, from: float, to: float, inner: float, outer: float, color: Color) -> void:
	if absf(to - from) < 0.01 or color.a <= 0.0:
		return
	var steps := 20
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	for i in steps + 1:
		var t := i / float(steps)
		points.append(center + Vector2.from_angle(lerpf(from, to, t)) * outer)
		colors.append(Color(color, color.a * t * t))
	for i in range(steps, -1, -1):
		var t := i / float(steps)
		points.append(center + Vector2.from_angle(lerpf(from, to, t)) * inner)
		colors.append(Color(color, color.a * t * t * 0.4))
	canvas.draw_polygon(points, colors)


## 가운데를 기준으로 크기와 회전을 주어 텍스처를 그린다.
## 빛 레이어 전용: 카메라가 노드 변환에 걸려 있어 draw_set_transform을 원점으로 되돌려도 된다.
func _tex(canvas: CanvasItem, tex: Texture2D, pos: Vector2, size: float, color: Color, angle := 0.0) -> void:
	if angle != 0.0:
		canvas.draw_set_transform(pos, angle, Vector2.ONE)
		canvas.draw_texture_rect(tex, Rect2(-size * 0.5, -size * 0.5, size, size), false, color)
		canvas.draw_set_transform(Vector2.ZERO)
	else:
		canvas.draw_texture_rect(tex, Rect2(pos.x - size * 0.5, pos.y - size * 0.5, size, size), false, color)


# --- 생성 ---

func _tick(list: Array, world_delta: float) -> Array:
	var alive: Array = []
	for item in list:
		item.time -= world_delta
		if item.time > 0.0:
			alive.append(item)
	return alive


func _add_effect(kind: String, pos: Vector2, radius: float, life: float, color: Color) -> Dictionary:
	var effect := {
		"kind": kind, "pos": pos, "radius": radius, "time": life, "max": life, "color": color,
		"spin": randf() * TAU, "flip": 1.0 if randf() < 0.5 else -1.0,
	}
	effects.append(effect)
	return effect


func _add_decal(kind: String, pos: Vector2, radius: float, life: float, color: Color) -> void:
	if decals.size() >= MAX_DECALS:
		decals.pop_front()
	decals.append({"kind": kind, "pos": pos, "radius": radius, "time": life, "max": life, "color": color})


func _spawn_particles(pos: Vector2, count: int, color: Color, speed: float, size: float, glow: bool) -> void:
	for i in count:
		var vel := Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.0) * speed
		_add_particle(pos, vel, randf_range(0.25, 0.55), color, size * randf_range(0.6, 1.2), glow, 4.0)


func _add_particle(pos: Vector2, vel: Vector2, life: float, color: Color, size: float, glow: bool, drag: float) -> void:
	if particles.size() >= MAX_PARTICLES:
		return
	particles.append({
		"pos": pos, "vel": vel, "time": life, "max": life, "color": color, "size": size,
		"glow": glow, "drag": drag, "spin": randf_range(-3.0, 3.0),
	})
