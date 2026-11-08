extends RefCounted
## 군단장의 등장, 광폭화, 패턴 상태 머신(idle → windup → 패턴 실행).

const Entities := preload("res://legion/sim/entities.gd")
const BuildRules := preload("res://legion/sim/build_rules.gd")
const Combat := preload("res://legion/sim/combat.gd")
const Spawner := preload("res://legion/sim/spawner.gd")


static func spawn(sim) -> void:
	var boss_at := float(sim.data.boss_at)
	var cfg: Dictionary = sim.data.boss
	if not sim.boss_warned and sim.round_time >= boss_at - float(cfg.warning_seconds):
		sim.boss_warned = true
		sim.emit_event({"type": "boss_warning"})
	if sim.boss_spawned or sim.round_time < boss_at:
		return
	sim.boss_spawned = true
	var enemy := Entities.Enemy.new()
	enemy.kind = "boss"
	enemy.label = cfg.name
	enemy.pos = Spawner.spawn_position(sim)
	enemy.prev = enemy.pos
	var base_hp: float = float(cfg.hp_base) + float(cfg.hp_per_round) * (sim.round_index - 1)
	enemy.max_hp = maxf(base_hp, BuildRules.enemy_scaling_dps(sim.data, sim.build) * float(cfg.target_ttk))
	enemy.hp = enemy.max_hp
	enemy.speed = float(cfg.speed)
	enemy.radius = float(cfg.radius)
	enemy.contact = float(cfg.contact)
	enemy.xp = int(cfg.xp)
	enemy.born = sim.time
	sim.boss = enemy
	sim.boss_state = "idle"
	sim.boss_timer = float(cfg.pattern_interval)
	sim.enemies.append(enemy)
	sim.emit_event({"type": "boss", "label": enemy.label})


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


static func _start_pattern(sim, enemy: Entities.Enemy) -> void:
	var available: Array = []
	for pattern in sim.data.boss.patterns:
		if int(pattern.from_round) <= sim.round_index:
			available.append(pattern)
	sim.boss_pattern = available[sim.boss_pattern_index % available.size()]
	sim.boss_pattern_index += 1
	sim.boss_state = "windup"
	sim.boss_timer = float(sim.boss_pattern.windup)
	sim.charge_dir = (sim.player_pos - enemy.pos).normalized()


static func _run_pattern(sim, enemy: Entities.Enemy) -> void:
	var pattern: Dictionary = sim.boss_pattern
	var damage := float(pattern.get("damage", 0.0)) * damage_mult(sim)
	match pattern.type:
		"charge":
			sim.boss_state = "charge"
			sim.boss_timer = float(pattern.duration)
			return
		"ring":
			var count := int(pattern.count)
			for i in count:
				Combat.add_projectile(sim, enemy.pos, Vector2.from_angle(TAU * i / count) * float(pattern.speed), damage,
						float(pattern.radius), float(pattern.life), true, "boss_ring")
		"strikes":
			for i in int(pattern.count):
				var offset: Vector2 = Vector2.ZERO if i == 0 else sim.random_offset(float(pattern.spread))
				Combat.add_strike(sim, sim.player_pos + offset, float(pattern.delay), damage, float(pattern.radius), "boss_strike")
		"summon":
			for i in int(pattern.grunts):
				if sim.enemies.size() < int(sim.data.spawn.max_enemies):
					Spawner.add_minion(sim, sim.clamp_to_arena(enemy.pos + sim.random_offset(120.0)))
			if not sim.past_builds.is_empty():
				var index: int = sim.rng.randi_range(0, sim.past_builds.size() - 1)
				Spawner.add_ghost(sim, index, float(pattern.ghost_hp_mult), 1.0, true, sim.clamp_to_arena(enemy.pos + sim.random_offset(120.0)))
	_to_idle(sim)


static func _to_idle(sim) -> void:
	sim.boss_state = "idle"
	sim.boss_timer = float(sim.data.boss.pattern_interval)
