extends RefCounted
## 잡몹, 웨이브 편성, 과거의 나의 등장 시점과 생성.

const Entities := preload("res://legion/sim/entities.gd")
const BuildRules := preload("res://legion/sim/build_rules.gd")


static func spawn_position(sim) -> Vector2:
	return sim.clamp_to_arena(sim.player_pos + Vector2.from_angle(sim.rng.randf() * TAU) * float(sim.data.spawn.distance))


static func spawn_enemies(sim) -> void:
	var spawn: Dictionary = sim.data.spawn
	var ramp_time := minf(sim.round_time, float(sim.data.round_seconds))
	var rate: float = float(spawn.base_rate) + float(spawn.rate_per_round) * (sim.round_index - 1) + float(spawn.ramp_per_second) * ramp_time
	if sim.boss_spawned:
		rate *= float(spawn.boss_rate_mult)
	sim.spawn_acc += rate * sim.tick
	while sim.spawn_acc >= 1.0:
		sim.spawn_acc -= 1.0
		if sim.enemies.size() < int(spawn.max_enemies):
			add_minion(sim, spawn_position(sim))


static func add_minion(sim, pos: Vector2) -> void:
	var spawn: Dictionary = sim.data.spawn
	var runner_chance: float = float(spawn.runner_chance) + float(spawn.runner_chance_per_round) * (sim.round_index - 1)
	var roll: float = sim.rng.randf()
	var kind := "grunt"
	if roll < runner_chance:
		kind = "runner"
	elif roll < runner_chance + float(spawn.swarmling_chance):
		kind = "swarmling"
	_add_enemy(sim, kind, pos)


static func _add_enemy(sim, kind: String, pos: Vector2) -> void:
	var def: Dictionary = sim.data.enemies[kind]
	var enemy := Entities.Enemy.new()
	enemy.kind = kind
	enemy.label = def.name
	enemy.pos = pos
	enemy.prev = pos
	enemy.max_hp = float(def.hp) * (1.0 + float(sim.data.spawn.hp_per_round) * (sim.round_index - 1))
	enemy.hp = enemy.max_hp
	enemy.speed = float(def.speed)
	enemy.radius = float(def.radius)
	enemy.contact = float(def.contact)
	enemy.xp = int(def.xp)
	enemy.born = sim.time
	sim.enemies.append(enemy)


static func schedule_waves(sim) -> void:
	sim.wave_queue = sim.data.waves.times.duplicate()


## 웨이브는 필드에서만 온다.
static func spawn_waves(sim) -> void:
	if sim.in_boss_room:
		return
	while not sim.wave_queue.is_empty() and sim.round_time >= float(sim.wave_queue[0]):
		sim.wave_queue.pop_front()
		var formations: Array = sim.data.waves.formations
		var formation: Dictionary = formations[sim.wave_index % formations.size()]
		sim.wave_index += 1
		sim.waves_spawned += 1
		_spawn_formation(sim, formation)
		sim.emit_event({"type": "wave", "name": formation.name})


## 룰렛 꽝: 플레이어를 둘러싸는 잔챙이 무리.
static func ambush(sim, count: int) -> void:
	_spawn_formation(sim, {"type": "encircle", "kind": "swarmling", "count": count})
	sim.emit_event({"type": "wave", "name": "매복"})


static func _spawn_formation(sim, formation: Dictionary) -> void:
	var count := int(round(float(formation.count) * (1.0 + float(sim.data.waves.count_per_round) * (sim.round_index - 1))))
	var kind: String = formation.kind
	var distance := float(sim.data.waves.distance)
	var angle: float = sim.rng.randf() * TAU
	var player_pos: Vector2 = sim.player_pos
	match formation.type:
		"encircle":
			for i in count:
				_add_wave_enemy(sim, kind, player_pos + Vector2.from_angle(TAU * i / count) * distance)
		"rush":
			_spawn_line(sim, kind, count, angle, distance)
		"flank":
			_spawn_line(sim, kind, count / 2, angle, distance)
			_spawn_line(sim, kind, count - count / 2, angle + PI, distance)
		"elite":
			for i in int(formation.elites):
				_add_wave_enemy(sim, formation.elite_kind, player_pos + Vector2.from_angle(angle + 0.5 * i) * distance)
			for i in count:
				_add_wave_enemy(sim, kind, player_pos + Vector2.from_angle(angle + TAU * i / count) * (distance + 60.0))


static func _spawn_line(sim, kind: String, count: int, angle: float, distance: float) -> void:
	var center: Vector2 = sim.player_pos + Vector2.from_angle(angle) * distance
	var side := Vector2.from_angle(angle).orthogonal()
	var spacing := float(sim.data.waves.line_spacing)
	for i in count:
		_add_wave_enemy(sim, kind, center + side * (i - (count - 1) * 0.5) * spacing)


static func _add_wave_enemy(sim, kind: String, pos: Vector2) -> void:
	if sim.enemies.size() < int(sim.data.waves.max_enemies):
		_add_enemy(sim, kind, sim.clamp_to_arena(pos))


## 오래된 빌드일수록 복제본이 늘어난다. 전원은 군단장 등장 때 한 번 더 출동한다.
static func schedule_ghosts(sim) -> void:
	sim.ghost_queue = []
	var ghost_def: Dictionary = sim.data.ghost
	var total := 0
	for i in sim.past_builds.size():
		total += _ghost_count(sim, i)
	var slot := 0
	for i in sim.past_builds.size():
		for copy in _ghost_count(sim, i):
			var at := float(ghost_def.first_at)
			if total > 1:
				at += (float(ghost_def.last_at) - float(ghost_def.first_at)) * slot / (total - 1)
			var is_copy: bool = copy > 0
			sim.ghost_queue.append({
				"time": at, "index": i,
				"hp_mult": float(ghost_def.copy_hp_mult) if is_copy else 1.0,
				"damage_mult": float(ghost_def.copy_damage_mult) if is_copy else 1.0,
				"copy": is_copy, "boss_wave": false,
			})
			slot += 1
	for i in sim.past_builds.size():
		sim.ghost_queue.append({
			"time": float(sim.data.boss_at), "index": i,
			"hp_mult": float(ghost_def.boss_wave_hp_mult), "damage_mult": 1.0, "copy": true, "boss_wave": true,
		})


static func _ghost_count(sim, index: int) -> int:
	return 1 + _build_age(sim, index) / int(sim.data.ghost.age_per_copy)


static func _build_age(sim, index: int) -> int:
	return sim.round_index - index - 2


static func spawn_ghosts(sim) -> void:
	while not sim.ghost_queue.is_empty() and sim.round_time >= float(sim.ghost_queue[0].time):
		# 보스와 함께 나오는 과거의 나는 보스 방에 들어갈 때까지 기다린다.
		if sim.ghost_queue[0].boss_wave and not sim.in_boss_room:
			break
		var entry: Dictionary = sim.ghost_queue.pop_front()
		add_ghost(sim, entry.index, entry.hp_mult, entry.damage_mult, entry.copy, spawn_position(sim))


static func add_ghost(sim, index: int, hp_mult: float, damage_mult: float, is_copy: bool, pos: Vector2) -> void:
	var past: Dictionary = sim.past_builds[index]
	var ghost_def: Dictionary = sim.data.ghost
	var behavior: Dictionary = ghost_def.behaviors[BuildRules.dominant_weapon(past)]
	var ghost := Entities.Enemy.new()
	ghost.kind = "ghost"
	ghost.label = "%d라운드의 나%s" % [index + 1, " 복제" if is_copy else " (%s)" % behavior.name]
	ghost.pos = pos
	ghost.prev = pos
	ghost.max_hp = BuildRules.ghost_hp(sim.data, past, _build_age(sim, index)) * hp_mult
	ghost.hp = ghost.max_hp
	ghost.speed = float(behavior.speed)
	ghost.keep_distance = float(behavior.keep_distance)
	ghost.radius = float(ghost_def.radius) * (0.75 if is_copy else 1.0)
	ghost.contact = float(ghost_def.contact)
	ghost.xp = int(ghost_def.xp)
	ghost.build = BuildRules.copy_build(past) if is_copy else past
	ghost.timers = {"bolt": 1.0, "aura": 1.0, "lightning": 1.0}
	ghost.damage_mult = float(ghost_def.damage_mult) * damage_mult
	ghost.born = sim.time
	# 복제본은 지금처럼 쫓기만 하고, 원본만 그 라운드의 내 경로를 따라 걷는다.
	if not is_copy and index < sim.past_paths.size():
		ghost.path = sim.past_paths[index]
	sim.enemies.append(ghost)
	if not is_copy:
		sim.emit_event({"type": "ghost", "label": ghost.label})
