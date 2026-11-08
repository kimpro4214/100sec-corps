extends RefCounted
## 라운드별 보스의 등장, 광폭화, 패턴 상태 머신(idle → windup → 패턴 실행).
## 보스마다 이름, 크기, 패턴 목록은 data.bosses에 있고, 공통 수치는 data.boss에 있다.

const Entities := preload("res://legion/sim/entities.gd")
const BuildRules := preload("res://legion/sim/build_rules.gd")
const Combat := preload("res://legion/sim/combat.gd")
const Spawner := preload("res://legion/sim/spawner.gd")


## 이번 라운드의 보스 정의. 라운드 수가 목록보다 많으면 마지막 보스가 나온다.
static func definition(sim) -> Dictionary:
	var bosses: Array = sim.data.bosses
	return bosses[mini(sim.round_index - 1, bosses.size() - 1)]


## 보스 방에 들어온 순간 방 위쪽에 나타난다.
static func spawn(sim) -> void:
	var cfg: Dictionary = sim.data.boss
	if sim.boss_spawned or not sim.in_boss_room:
		return
	sim.boss_spawned = true
	var def := definition(sim)
	var enemy := Entities.Enemy.new()
	enemy.kind = "boss"
	enemy.label = def.name
	enemy.pos = sim.area.position + Vector2(sim.area.size.x * 0.5, sim.area.size.y * 0.25)
	enemy.prev = enemy.pos
	var base_hp: float = float(cfg.hp_base) + float(cfg.hp_per_round) * (sim.round_index - 1)
	enemy.max_hp = maxf(base_hp, BuildRules.enemy_scaling_dps(sim.data, sim.build) * float(cfg.target_ttk))
	enemy.hp = enemy.max_hp
	enemy.speed = float(def.speed)
	enemy.radius = float(def.radius)
	enemy.contact = float(cfg.contact)
	enemy.xp = int(cfg.xp)
	enemy.born = sim.time
	sim.boss = enemy
	sim.boss_def = def
	sim.boss_state = "idle"
	sim.boss_timer = float(cfg.pattern_interval)
	sim.enemies.append(enemy)
	sim.emit_event({"type": "boss", "label": enemy.label, "title": def.title, "id": def.id, "pos": enemy.pos})


static func damage_mult(sim) -> float:
	var cfg: Dictionary = sim.data.boss
	var overtime := maxf(0.0, sim.round_time - float(sim.data.round_seconds))
	return 1.0 + float(cfg.damage_per_round) * (sim.round_index - 1) + float(cfg.enrage_per_second) * overtime


static func is_enraged(sim) -> bool:
	return sim.boss != null and sim.round_time > float(sim.data.round_seconds)


static func update(sim, enemy: Entities.Enemy) -> void:
	sim.boss_timer -= sim.tick
	match sim.boss_state:
		"idle":
			enemy.pos += (sim.player_pos - enemy.pos).normalized() * enemy.current_speed() * sim.tick
			if sim.boss_timer <= 0.0:
				_start_pattern(sim, enemy)
		"windup":
			if sim.boss_timer <= 0.0:
				_run_pattern(sim, enemy)
		"charge":
			enemy.pos = sim.clamp_to_arena(enemy.pos + sim.charge_dir * float(sim.boss_pattern.speed) * sim.tick)
			if sim.boss_timer <= 0.0:
				_to_idle(sim)


## 패턴은 보스 정의의 순서대로 돌아가며 쓴다. 준비 시작 순간의 플레이어 방향을 조준에 쓴다.
static func _start_pattern(sim, enemy: Entities.Enemy) -> void:
	var patterns: Array = sim.boss_def.patterns
	sim.boss_pattern = patterns[sim.boss_pattern_index % patterns.size()]
	sim.boss_pattern_index += 1
	sim.boss_state = "windup"
	sim.boss_timer = float(sim.boss_pattern.windup)
	sim.charge_dir = (sim.player_pos - enemy.pos).normalized()
	sim.emit_event({"type": "boss_windup", "pattern": sim.boss_pattern.type})


static func _run_pattern(sim, enemy: Entities.Enemy) -> void:
	var pattern: Dictionary = sim.boss_pattern
	var damage := float(pattern.get("damage", 0.0)) * damage_mult(sim)
	match pattern.type:
		"charge":
			sim.boss_state = "charge"
			sim.boss_timer = float(pattern.duration)
			return
		"ring":
			_fire_ring(sim, enemy.pos, pattern, damage, pattern.get("source", "boss_ring"))
		"spray":
			# 준비 때 정한 방향으로 부채꼴 탄막.
			var count := int(pattern.count)
			var spread := float(pattern.spread)
			for i in count:
				var offset := 0.0 if count == 1 else (i / float(count - 1) - 0.5) * spread
				Combat.add_projectile(sim, enemy.pos, sim.charge_dir.rotated(offset) * float(pattern.speed), damage,
						float(pattern.radius), float(pattern.life), true, pattern.get("source", "boss_spray"))
		"blink":
			# 플레이어 근처로 순간이동한 뒤 원형탄.
			var angle: float = sim.rng.randf() * TAU
			enemy.pos = sim.clamp_to_arena(sim.player_pos + Vector2.from_angle(angle) * float(pattern.distance))
			enemy.prev = enemy.pos
			sim.emit_event({"type": "boss_blink", "pos": enemy.pos})
			_fire_ring(sim, enemy.pos, pattern, damage, pattern.get("source", "boss_blink"))
		"quake":
			# 자기 주변을 내리찍는 광역 공격. 준비 동안 범위가 예고된다.
			Combat.add_strike(sim, enemy.pos, 0.05, damage, float(pattern.radius), "boss_quake")
			sim.emit_event({"type": "boss_quake", "pos": enemy.pos, "radius": float(pattern.radius)})
		"web":
			# 거미줄 뭉치를 플레이어 주변으로 던진다. 날아가 깔린 뒤 밟으면 느려진다.
			for i in int(pattern.count):
				var zone := Entities.Zone.new()
				zone.origin = enemy.pos
				var offset: Vector2 = Vector2.ZERO if i == 0 else sim.random_offset(float(pattern.spread))
				zone.pos = sim.clamp_to_arena(sim.player_pos + offset)
				zone.radius = float(pattern.radius)
				zone.travel = float(pattern.travel)
				zone.delay = zone.travel
				zone.time = float(pattern.duration)
				zone.slow = float(pattern.slow)
				sim.zones.append(zone)
			sim.emit_event({"type": "boss_web", "pos": enemy.pos})
		"slash":
			# 준비 때 정한 방향으로 칼을 휘두른다. 부채꼴 안에 있으면 맞는다.
			var to_player: Vector2 = sim.player_pos - enemy.pos
			var reach := float(pattern.range) + float(sim.data.player.radius)
			if to_player.length() <= reach and absf(sim.charge_dir.angle_to(to_player)) <= float(pattern.arc) * 0.5:
				Combat.hurt_player(sim, damage, "boss_slash")
			sim.emit_event({"type": "boss_slash", "pos": enemy.pos, "angle": sim.charge_dir.angle(), "range": float(pattern.range), "arc": float(pattern.arc)})
		"strikes":
			for i in int(pattern.count):
				var offset: Vector2 = Vector2.ZERO if i == 0 else sim.random_offset(float(pattern.spread))
				Combat.add_strike(sim, sim.player_pos + offset, float(pattern.delay), damage, float(pattern.radius), pattern.get("source", "boss_strike"))
		"summon":
			for i in int(pattern.grunts):
				if sim.enemies.size() < int(sim.data.spawn.max_enemies):
					Spawner.add_minion(sim, sim.clamp_to_arena(enemy.pos + sim.random_offset(120.0)))
			if not sim.past_builds.is_empty():
				var index: int = sim.rng.randi_range(0, sim.past_builds.size() - 1)
				Spawner.add_ghost(sim, index, float(pattern.ghost_hp_mult), 1.0, true, sim.clamp_to_arena(enemy.pos + sim.random_offset(120.0)))
	_to_idle(sim)


static func _fire_ring(sim, origin: Vector2, pattern: Dictionary, damage: float, source: String) -> void:
	var count := int(pattern.count)
	for i in count:
		Combat.add_projectile(sim, origin, Vector2.from_angle(TAU * i / count) * float(pattern.speed), damage,
				float(pattern.radius), float(pattern.life), true, source)


static func _to_idle(sim) -> void:
	sim.boss_state = "idle"
	sim.boss_timer = float(sim.data.boss.pattern_interval)
