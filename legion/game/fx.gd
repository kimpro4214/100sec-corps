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
}
const LIGHTNING_COLOR := Color(0.65, 0.85, 1.0)
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
			var color := Palette.HOSTILE if event.get("hostile", false) else LIGHTNING_COLOR
			_add_effect("lightning", event.pos, event.radius, 0.3, color)
			_add_decal("scorch", event.pos, event.radius * 1.4, 2.5, Color(0, 0, 0, 0.45))
			_spawn_particles(event.pos, 4, color, 220.0, 10.0, true)
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


func draw_debris(canvas: CanvasItem) -> void:
	for particle in particles:
		if not particle.glow:
			canvas.draw_circle(particle.pos, particle.size * particle.time / particle.max, particle.color)


func draw_glow(canvas: CanvasItem, sim, alpha: float, director: CinemaDirector) -> void:
	if sim == null:
		return
	_draw_auras(canvas, sim)
	_draw_boss_telegraph(canvas, sim)
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
		"lightning":
			# 하늘에서 내리꽂는 번개 줄기, 착지 섬광, 전기 튐.
			var height := 320.0
			var width := maxf(radius * 1.4, 60.0)
			var bolt_rect := Rect2(effect.pos.x - width * 0.5 * effect.flip, effect.pos.y - height, width * effect.flip, height)
			canvas.draw_texture_rect(TEX.bolt, bolt_rect, false, Color(color, fade))
			canvas.draw_texture_rect(TEX.bolt, bolt_rect, false, Color(1, 1, 1, fade * 0.6))
			_tex(canvas, TEX.glow, effect.pos, radius * 3.0, Color(color, fade))
			_tex(canvas, TEX.zap, effect.pos, radius * 2.6 * (0.8 + grow * 0.4), Color(color, fade), effect.spin)


## 가운데를 기준으로 크기와 회전을 주어 텍스처를 그린다.
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


func _add_effect(kind: String, pos: Vector2, radius: float, life: float, color: Color) -> void:
	effects.append({
		"kind": kind, "pos": pos, "radius": radius, "time": life, "max": life, "color": color,
		"spin": randf() * TAU, "flip": 1.0 if randf() < 0.5 else -1.0,
	})


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
