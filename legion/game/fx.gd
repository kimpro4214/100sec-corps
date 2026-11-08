extends RefCounted
## sim 이벤트를 받아 이펙트(고리, 낙뢰, 충격파)와 처치 파편을 만들고 그린다.
## 화면 흔들림, 히트스톱, 플래시는 CinemaDirector에 요청한다.

const Palette := preload("res://legion/game/palette.gd")
const CinemaDirector := preload("res://legion/game/cinema_director.gd")

const MAX_PARTICLES := 700
const KILL_JUICE := {
	"swarmling": {"particles": 4, "shake": 0.0, "hitstop": 0.0},
	"runner": {"particles": 4, "shake": 0.0, "hitstop": 0.0},
	"grunt": {"particles": 6, "shake": 0.0, "hitstop": 0.0},
	"brute": {"particles": 12, "shake": 4.0, "hitstop": 0.03},
	"ghost": {"particles": 22, "shake": 8.0, "hitstop": 0.08},
	"boss": {"particles": 48, "shake": 22.0, "hitstop": 0.35},
}

var effects: Array = []
var particles: Array = []


func reset() -> void:
	effects = []
	particles = []


func handle(event: Dictionary, director: CinemaDirector) -> void:
	match event.type:
		"aura":
			_add_effect("ring", event.pos, event.radius, 0.2, Palette.HOSTILE if event.hostile else Palette.PLAYER)
		"burst":
			_add_effect("ring", event.pos, event.radius, 0.2, Palette.AWAKEN)
		"lightning":
			_add_effect("bolt", event.pos, event.radius, 0.25, Color.WHITE)
		"kill":
			var juice: Dictionary = KILL_JUICE.get(event.kind, KILL_JUICE.grunt)
			_spawn_particles(event.pos, juice.particles, Palette.enemy_color(event.kind), 160.0 + event.radius * 6.0, 3.0 + event.radius * 0.15)
			if juice.shake > 0.0:
				director.add_shake(juice.shake)
			director.hitstop = maxf(director.hitstop, juice.hitstop)
			if event.kind == "boss":
				director.add_flash(Color.WHITE, 0.6)
				_add_effect("shock", event.pos, 260.0, 0.6, Palette.BOSS)
		"hurt":
			director.add_shake(minf(3.0 + event.damage * 0.5, 12.0))
			director.hurt_tint = minf(0.45, director.hurt_tint + 0.15 + event.damage * 0.01)
		"ult_blast":
			_add_effect("shock", event.pos, event.radius, 0.5, Palette.AWAKEN)
		"ultimate":
			_add_effect("shock", event.pos, 140.0, 0.35, Color.WHITE)


## 게임 시간 기준으로 진행하므로 히트스톱 중에는 멈춘다.
func update(world_delta: float) -> void:
	var alive: Array = []
	for effect in effects:
		effect.time -= world_delta
		if effect.time > 0.0:
			alive.append(effect)
	effects = alive
	var alive_particles: Array = []
	for particle in particles:
		particle.time -= world_delta
		particle.pos += particle.vel * world_delta
		particle.vel *= 1.0 - minf(1.0, 4.0 * world_delta)
		if particle.time > 0.0:
			alive_particles.append(particle)
	particles = alive_particles


func draw(canvas: CanvasItem) -> void:
	for effect in effects:
		var fade: float = effect.time / effect.max
		match effect.kind:
			"ring":
				canvas.draw_arc(effect.pos, effect.radius, 0.0, TAU, 48, Color(effect.color, 0.5 * fade), 2.0)
			"shock":
				var grow := CinemaDirector.ease_out(1.0 - fade)
				canvas.draw_circle(effect.pos, effect.radius * grow, Color(effect.color, 0.18 * fade))
				canvas.draw_arc(effect.pos, effect.radius * grow, 0.0, TAU, 64, Color(effect.color, fade), 6.0 * fade + 1.0)
			_:
				canvas.draw_circle(effect.pos, effect.radius, Color(effect.color, 0.5 * fade))
				canvas.draw_line(effect.pos + Vector2(0, -500), effect.pos, Color(effect.color, fade), 3.0)
	for particle in particles:
		canvas.draw_circle(particle.pos, particle.size * particle.time / particle.max, particle.color)


func _add_effect(kind: String, pos: Vector2, radius: float, life: float, color: Color) -> void:
	effects.append({"kind": kind, "pos": pos, "radius": radius, "time": life, "max": life, "color": color})


func _spawn_particles(pos: Vector2, count: int, color: Color, speed: float, size: float) -> void:
	for i in count:
		if particles.size() >= MAX_PARTICLES:
			return
		var life := randf_range(0.25, 0.55)
		particles.append({
			"pos": pos, "vel": Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.0) * speed,
			"time": life, "max": life, "color": color, "size": size * randf_range(0.6, 1.2),
		})
