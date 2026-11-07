extends RefCounted
## 100초 군단의 게임 규칙. 화면과 봇이 같은 코드를 사용한다.


class Enemy:
	var kind := ""
	var label := ""
	var pos := Vector2.ZERO
	var prev := Vector2.ZERO
	var hp := 1.0
	var max_hp := 1.0
	var speed := 0.0
	var radius := 1.0
	var contact := 0.0
	var xp := 1
	var build := {}
	var timers := {}
	var flash := 0.0
	var damage_mult := 1.0
	var keep_distance := 0.0
	var born := 0.0


class Projectile:
	var pos := Vector2.ZERO
	var prev := Vector2.ZERO
	var vel := Vector2.ZERO
	var damage := 0.0
	var radius := 1.0
	var life := 1.0
	var hostile := false
	var source := ""


class Strike:
	var pos := Vector2.ZERO
	var delay := 0.0
	var damage := 0.0
	var radius := 1.0
	var source := ""


class Gem:
	var pos := Vector2.ZERO
	var value := 1


const WEAPON_IDS := ["bolt", "aura", "lightning"]
const UPGRADE_IDS := ["might", "haste", "vitality"]

var data: Dictionary
var rng := RandomNumberGenerator.new()
var tick: float
var record_events := false
var events: Array = []

var state := "playing" # playing, won, lost
var round_index := 1
var round_time := 0.0
var time := 0.0
var round_summary := {}

var player_pos := Vector2.ZERO
var player_prev := Vector2.ZERO
var hp := 0.0
var max_hp := 0.0
var invuln := 0.0
var player_flash := 0.0
var build := {}
var timers := {}
var level := 1
var xp := 0
var queued_levels := 0
var pending_choices: Array = []

var enemies: Array[Enemy] = []
var projectiles: Array[Projectile] = []
var strikes: Array[Strike] = []
var gems: Array[Gem] = []
var past_builds: Array = []
var ghost_queue: Array = []

var boss: Enemy = null
var boss_warned := false
var boss_spawned := false
var boss_dead := false
var boss_state := "idle" # idle, windup, charge
var boss_timer := 0.0
var boss_pattern := {}
var boss_pattern_index := 0
var charge_dir := Vector2.RIGHT

var spawn_acc := 0.0
var last_hit := ""
var kills := 0
var ghost_kills := 0
var ghost_ttk_total := 0.0
var picks: Array = []
var boss_log: Array = []
var damage_by_source := {}


func _init(balance: Dictionary, run_seed: int) -> void:
	data = balance
	rng.seed = run_seed
	tick = float(data.tick)
	max_hp = float(data.player.hp)
	hp = max_hp
	player_pos = Vector2(float(data.arena.w), float(data.arena.h)) * 0.5
	player_prev = player_pos
	build = {"weapons": {"bolt": 0, "aura": 0, "lightning": 0}, "upgrades": {"might": 0, "haste": 0, "vitality": 0}}
	build.weapons[data.start_weapon] = 1
	timers = {"bolt": 0.0, "aura": 0.0, "lightning": 0.0}


func is_over() -> bool:
	return state != "playing"


func xp_needed() -> int:
	return int(data.xp.base) + int(data.xp.per_level) * (level - 1)


func option_level(option_id: String) -> int:
	if option_id in WEAPON_IDS:
		return int(build.weapons[option_id])
	return int(build.upgrades[option_id])


func option_def(option_id: String) -> Dictionary:
	if option_id in WEAPON_IDS:
		return data.weapons[option_id]
	return data.upgrades[option_id]


func dominant_weapon(target_build: Dictionary) -> String:
	var best := "bolt"
	for weapon_id in WEAPON_IDS:
		if int(target_build.weapons[weapon_id]) > int(target_build.weapons[best]):
			best = weapon_id
	return best


func build_dps(target_build: Dictionary) -> float:
	var total := 0.0
	var cooldown_mult := _cooldown_mult(target_build)
	for weapon_id in WEAPON_IDS:
		var weapon_level := int(target_build.weapons[weapon_id])
		if weapon_level <= 0:
			continue
		var weapon: Dictionary = data.weapons[weapon_id]
		var damage := float(weapon.damage) + float(weapon.damage_per_level) * (weapon_level - 1)
		var count := 1
		if weapon.has("count_every_levels"):
			count += int((weapon_level - 1) / float(weapon.count_every_levels))
		total += damage * count / (float(weapon.cooldown) * cooldown_mult) * float(weapon.single_target_weight)
	return total * _might_mult(target_build)


func ghost_hp(target_build: Dictionary, age: int) -> float:
	var ghost_def: Dictionary = data.ghost
	var scaled := build_dps(target_build) * float(ghost_def.target_ttk) * (1.0 + float(ghost_def.hp_per_age) * age)
	return maxf(float(ghost_def.hp_min), scaled)


## 이 선택지를 고르면 다음 라운드의 과거의 나가 어떻게 되는지 알려준다.
func ghost_preview(option_id: String) -> Dictionary:
	var preview_build: Dictionary = build.duplicate(true)
	if option_id in WEAPON_IDS:
		preview_build.weapons[option_id] += 1
	elif option_id != "":
		preview_build.upgrades[option_id] += 1
	return {
		"hp": ghost_hp(preview_build, 0),
		"behavior": data.ghost.behaviors[dominant_weapon(preview_build)].name,
	}


func choose(index: int) -> void:
	var option_id: String = pending_choices[index]
	picks.append({"offered": pending_choices.duplicate(), "chosen": option_id})
	if option_id in WEAPON_IDS:
		build.weapons[option_id] += 1
	else:
		build.upgrades[option_id] += 1
		if option_id == "vitality":
			var bonus := float(data.upgrades.vitality.value)
			max_hp += bonus
			hp = minf(hp + bonus, max_hp)
	pending_choices = []
	_offer_next_level()


## 라운드 종료 화면을 닫고 다음 라운드를 시작한다. 레벨 업을 모두 고른 뒤의 빌드가 저장된다.
func continue_round() -> void:
	if round_summary.is_empty() or not pending_choices.is_empty():
		return
	round_summary = {}
	past_builds.append(build.duplicate(true))
	round_index += 1
	round_time = 0.0
	spawn_acc = 0.0
	hp = minf(max_hp, hp + max_hp * float(data.round_heal_ratio))
	boss = null
	boss_warned = false
	boss_spawned = false
	boss_dead = false
	boss_state = "idle"
	boss_pattern_index = 0
	_schedule_ghosts()
	_event({"type": "round", "round": round_index})


func step(move_dir: Vector2) -> void:
	if is_over() or not pending_choices.is_empty() or not round_summary.is_empty():
		return
	time += tick
	round_time += tick
	invuln = maxf(0.0, invuln - tick)
	player_flash = maxf(0.0, player_flash - tick)
	_move_player(move_dir)
	_fire_weapons(player_pos, build, timers, false, 1.0)
	_spawn_enemies()
	_spawn_ghosts()
	_spawn_boss()
	_update_enemies()
	_update_projectiles()
	_update_strikes()
	_remove_dead()
	_collect_gems()
	if hp <= 0.0:
		state = "lost"
		_event({"type": "lost"})
	elif boss_dead:
		_finish_round()


func _event(event: Dictionary) -> void:
	if record_events:
		events.append(event)


func _clamp_to_arena(pos: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, 0.0, float(data.arena.w)), clampf(pos.y, 0.0, float(data.arena.h)))


func _move_player(move_dir: Vector2) -> void:
	player_prev = player_pos
	player_pos = _clamp_to_arena(player_pos + move_dir.limit_length(1.0) * float(data.player.speed) * tick)


func _might_mult(owner_build: Dictionary) -> float:
	return 1.0 + float(data.upgrades.might.value) * int(owner_build.upgrades.might)


func _cooldown_mult(owner_build: Dictionary) -> float:
	var reduced := 1.0 - float(data.upgrades.haste.value) * int(owner_build.upgrades.haste)
	return maxf(float(data.min_cooldown_mult), reduced)


func _fire_weapons(origin: Vector2, owner_build: Dictionary, owner_timers: Dictionary, hostile: bool, hostile_mult: float) -> void:
	for weapon_id in WEAPON_IDS:
		var weapon_level := int(owner_build.weapons[weapon_id])
		if weapon_level <= 0:
			continue
		owner_timers[weapon_id] -= tick
		if owner_timers[weapon_id] > 0.0:
			continue
		var weapon: Dictionary = data.weapons[weapon_id]
		var damage := (float(weapon.damage) + float(weapon.damage_per_level) * (weapon_level - 1)) * _might_mult(owner_build) * hostile_mult
		if hostile:
			damage *= float(weapon.hostile_damage_mult)
		var fired := false
		match weapon_id:
			"bolt":
				fired = _fire_bolt(origin, weapon, weapon_level, damage, hostile)
			"aura":
				fired = _fire_aura(origin, weapon, weapon_level, damage, hostile)
			"lightning":
				fired = _fire_lightning(origin, weapon, weapon_level, damage, hostile)
		var cooldown := float(weapon.cooldown) * _cooldown_mult(owner_build)
		if hostile:
			cooldown *= float(weapon.hostile_cooldown_mult)
		owner_timers[weapon_id] = cooldown if fired else 0.0


func _fire_bolt(origin: Vector2, weapon: Dictionary, weapon_level: int, damage: float, hostile: bool) -> bool:
	var target := Vector2.ZERO
	var max_range := float(weapon.range)
	if hostile:
		if origin.distance_to(player_pos) > max_range:
			return false
		target = player_pos
	else:
		var best: Enemy = null
		var best_dist := max_range * max_range
		for enemy in enemies:
			var dist := origin.distance_squared_to(enemy.pos)
			if dist < best_dist:
				best_dist = dist
				best = enemy
		if best == null:
			return false
		target = best.pos
	var count := 1 + int((weapon_level - 1) / float(weapon.count_every_levels))
	var base_dir := (target - origin).normalized()
	var speed := float(weapon.hostile_speed) if hostile else float(weapon.speed)
	for i in count:
		_add_projectile(origin, base_dir.rotated((i - (count - 1) * 0.5) * 0.18) * speed, damage, float(weapon.radius),
				float(weapon.life) * (float(weapon.speed) / speed if hostile else 1.0), hostile, "ghost_bolt")
	return true


func _add_projectile(origin: Vector2, vel: Vector2, damage: float, radius: float, life: float, hostile: bool, source: String) -> void:
	var shot := Projectile.new()
	shot.pos = origin
	shot.prev = origin
	shot.vel = vel
	shot.damage = damage
	shot.radius = radius
	shot.life = life
	shot.hostile = hostile
	shot.source = source
	projectiles.append(shot)


func _fire_aura(origin: Vector2, weapon: Dictionary, weapon_level: int, damage: float, hostile: bool) -> bool:
	var radius := float(weapon.radius) + float(weapon.radius_per_level) * (weapon_level - 1)
	_event({"type": "aura", "pos": origin, "radius": radius, "hostile": hostile})
	if hostile:
		if origin.distance_to(player_pos) <= radius + float(data.player.radius):
			_hurt_player(damage, "ghost_aura")
	else:
		for enemy in enemies:
			if origin.distance_to(enemy.pos) <= radius + enemy.radius:
				_damage_enemy(enemy, damage)
	return true


func _add_strike(pos: Vector2, delay: float, damage: float, radius: float, source: String) -> void:
	var strike := Strike.new()
	strike.pos = _clamp_to_arena(pos)
	strike.delay = delay
	strike.damage = damage
	strike.radius = radius
	strike.source = source
	strikes.append(strike)


func _random_offset(spread: float) -> Vector2:
	return Vector2.from_angle(rng.randf() * TAU) * rng.randf() * spread


func _fire_lightning(origin: Vector2, weapon: Dictionary, weapon_level: int, damage: float, hostile: bool) -> bool:
	var radius := float(weapon.radius)
	var count := 1 + int((weapon_level - 1) / float(weapon.count_every_levels))
	if hostile:
		if origin.distance_to(player_pos) > float(weapon.range):
			return false
		for i in count:
			var offset := Vector2.ZERO if i == 0 else _random_offset(float(data.ghost.strike_spread))
			_add_strike(player_pos + offset, float(data.ghost.strike_delay), damage, radius, "ghost_lightning")
		return true
	var in_range: Array[Enemy] = []
	var range_sq := float(weapon.range) * float(weapon.range)
	for enemy in enemies:
		if origin.distance_squared_to(enemy.pos) <= range_sq:
			in_range.append(enemy)
	if in_range.is_empty():
		return false
	for i in count:
		var center: Enemy = in_range[rng.randi_range(0, in_range.size() - 1)]
		_event({"type": "lightning", "pos": center.pos, "radius": radius})
		for enemy in enemies:
			if center.pos.distance_to(enemy.pos) <= radius + enemy.radius:
				_damage_enemy(enemy, damage)
	return true


func _damage_enemy(enemy: Enemy, damage: float) -> void:
	enemy.hp -= damage
	enemy.flash = 0.1


func _hurt_player(damage: float, source: String) -> void:
	hp -= damage
	last_hit = source
	player_flash = 0.15
	damage_by_source[source] = damage_by_source.get(source, 0.0) + damage


func _spawn_position() -> Vector2:
	return _clamp_to_arena(player_pos + Vector2.from_angle(rng.randf() * TAU) * float(data.spawn.distance))


func _spawn_enemies() -> void:
	var spawn: Dictionary = data.spawn
	var ramp_time := minf(round_time, float(data.round_seconds))
	var rate := float(spawn.base_rate) + float(spawn.rate_per_round) * (round_index - 1) + float(spawn.ramp_per_second) * ramp_time
	if boss_spawned:
		rate *= float(spawn.boss_rate_mult)
	spawn_acc += rate * tick
	while spawn_acc >= 1.0:
		spawn_acc -= 1.0
		if enemies.size() < int(spawn.max_enemies):
			_add_minion(_spawn_position())


func _add_minion(pos: Vector2) -> void:
	var spawn: Dictionary = data.spawn
	var runner_chance := float(spawn.runner_chance) + float(spawn.runner_chance_per_round) * (round_index - 1)
	var kind := "runner" if rng.randf() < runner_chance else "grunt"
	var def: Dictionary = data.enemies[kind]
	var enemy := Enemy.new()
	enemy.kind = kind
	enemy.label = def.name
	enemy.pos = pos
	enemy.prev = pos
	enemy.max_hp = float(def.hp) * (1.0 + float(spawn.hp_per_round) * (round_index - 1))
	enemy.hp = enemy.max_hp
	enemy.speed = float(def.speed)
	enemy.radius = float(def.radius)
	enemy.contact = float(def.contact)
	enemy.xp = int(def.xp)
	enemy.born = time
	enemies.append(enemy)


## 오래된 빌드일수록 복제본이 늘어난다. 전원은 군단장 등장 때 한 번 더 출동한다.
func _schedule_ghosts() -> void:
	ghost_queue = []
	var ghost_def: Dictionary = data.ghost
	var total := 0
	for i in past_builds.size():
		total += _ghost_count(i)
	var slot := 0
	for i in past_builds.size():
		for copy in _ghost_count(i):
			var at := float(ghost_def.first_at)
			if total > 1:
				at += (float(ghost_def.last_at) - float(ghost_def.first_at)) * slot / (total - 1)
			var is_copy: bool = copy > 0
			ghost_queue.append({
				"time": at, "index": i,
				"hp_mult": float(ghost_def.copy_hp_mult) if is_copy else 1.0,
				"damage_mult": float(ghost_def.copy_damage_mult) if is_copy else 1.0,
				"copy": is_copy,
			})
			slot += 1
	for i in past_builds.size():
		ghost_queue.append({
			"time": float(data.boss_at), "index": i,
			"hp_mult": float(ghost_def.boss_wave_hp_mult), "damage_mult": 1.0, "copy": true,
		})


func _ghost_count(index: int) -> int:
	return 1 + _build_age(index) / int(data.ghost.age_per_copy)


func _build_age(index: int) -> int:
	return round_index - index - 2


func _spawn_ghosts() -> void:
	while not ghost_queue.is_empty() and round_time >= float(ghost_queue[0].time):
		var entry: Dictionary = ghost_queue.pop_front()
		_add_ghost(entry.index, entry.hp_mult, entry.damage_mult, entry.copy, _spawn_position())


func _add_ghost(index: int, hp_mult: float, damage_mult: float, is_copy: bool, pos: Vector2) -> void:
	var past: Dictionary = past_builds[index]
	var ghost_def: Dictionary = data.ghost
	var behavior: Dictionary = ghost_def.behaviors[dominant_weapon(past)]
	var ghost := Enemy.new()
	ghost.kind = "ghost"
	ghost.label = "%d라운드의 나%s" % [index + 1, " 복제" if is_copy else " (%s)" % behavior.name]
	ghost.pos = pos
	ghost.prev = pos
	ghost.max_hp = ghost_hp(past, _build_age(index)) * hp_mult
	ghost.hp = ghost.max_hp
	ghost.speed = float(behavior.speed)
	ghost.keep_distance = float(behavior.keep_distance)
	ghost.radius = float(ghost_def.radius) * (0.75 if is_copy else 1.0)
	ghost.contact = float(ghost_def.contact)
	ghost.xp = int(ghost_def.xp)
	ghost.build = _copy_build(past) if is_copy else past
	ghost.timers = {"bolt": 1.0, "aura": 1.0, "lightning": 1.0}
	ghost.damage_mult = float(ghost_def.damage_mult) * damage_mult
	ghost.born = time
	enemies.append(ghost)
	if not is_copy:
		_event({"type": "ghost", "label": ghost.label})


## 복제본은 주력 무기만 사용해 탄막이 과도하게 쌓이지 않게 한다.
func _copy_build(past: Dictionary) -> Dictionary:
	var copy_build: Dictionary = past.duplicate(true)
	var main := dominant_weapon(past)
	for weapon_id in WEAPON_IDS:
		if weapon_id != main:
			copy_build.weapons[weapon_id] = 0
	return copy_build


func _spawn_boss() -> void:
	var boss_at := float(data.boss_at)
	var cfg: Dictionary = data.boss
	if not boss_warned and round_time >= boss_at - float(cfg.warning_seconds):
		boss_warned = true
		_event({"type": "boss_warning"})
	if boss_spawned or round_time < boss_at:
		return
	boss_spawned = true
	var enemy := Enemy.new()
	enemy.kind = "boss"
	enemy.label = cfg.name
	enemy.pos = _spawn_position()
	enemy.prev = enemy.pos
	var base_hp := float(cfg.hp_base) + float(cfg.hp_per_round) * (round_index - 1)
	enemy.max_hp = maxf(base_hp, build_dps(build) * float(cfg.target_ttk))
	enemy.hp = enemy.max_hp
	enemy.speed = float(cfg.speed)
	enemy.radius = float(cfg.radius)
	enemy.contact = float(cfg.contact)
	enemy.xp = int(cfg.xp)
	enemy.born = time
	boss = enemy
	boss_state = "idle"
	boss_timer = float(cfg.pattern_interval)
	enemies.append(enemy)
	_event({"type": "boss", "label": enemy.label})


func boss_damage_mult() -> float:
	var cfg: Dictionary = data.boss
	var overtime := maxf(0.0, round_time - float(data.round_seconds))
	return 1.0 + float(cfg.damage_per_round) * (round_index - 1) + float(cfg.enrage_per_second) * overtime


func is_enraged() -> bool:
	return boss != null and round_time > float(data.round_seconds)


func _update_boss(enemy: Enemy) -> void:
	boss_timer -= tick
	match boss_state:
		"idle":
			enemy.pos += (player_pos - enemy.pos).normalized() * enemy.speed * tick
			if boss_timer <= 0.0:
				_start_boss_pattern(enemy)
		"windup":
			if boss_timer <= 0.0:
				_run_boss_pattern(enemy)
		"charge":
			enemy.pos = _clamp_to_arena(enemy.pos + charge_dir * float(boss_pattern.speed) * tick)
			if boss_timer <= 0.0:
				_boss_to_idle()


func _start_boss_pattern(enemy: Enemy) -> void:
	var available: Array = []
	for pattern in data.boss.patterns:
		if int(pattern.from_round) <= round_index:
			available.append(pattern)
	boss_pattern = available[boss_pattern_index % available.size()]
	boss_pattern_index += 1
	boss_state = "windup"
	boss_timer = float(boss_pattern.windup)
	charge_dir = (player_pos - enemy.pos).normalized()


func _run_boss_pattern(enemy: Enemy) -> void:
	var pattern := boss_pattern
	var damage := float(pattern.get("damage", 0.0)) * boss_damage_mult()
	match pattern.type:
		"charge":
			boss_state = "charge"
			boss_timer = float(pattern.duration)
			return
		"ring":
			var count := int(pattern.count)
			for i in count:
				_add_projectile(enemy.pos, Vector2.from_angle(TAU * i / count) * float(pattern.speed), damage,
						float(pattern.radius), float(pattern.life), true, "boss_ring")
		"strikes":
			for i in int(pattern.count):
				var offset := Vector2.ZERO if i == 0 else _random_offset(float(pattern.spread))
				_add_strike(player_pos + offset, float(pattern.delay), damage, float(pattern.radius), "boss_strike")
		"summon":
			for i in int(pattern.grunts):
				if enemies.size() < int(data.spawn.max_enemies):
					_add_minion(_clamp_to_arena(enemy.pos + _random_offset(120.0)))
			if not past_builds.is_empty():
				var index := rng.randi_range(0, past_builds.size() - 1)
				_add_ghost(index, float(pattern.ghost_hp_mult), 1.0, true, _clamp_to_arena(enemy.pos + _random_offset(120.0)))
	_boss_to_idle()


func _boss_to_idle() -> void:
	boss_state = "idle"
	boss_timer = float(data.boss.pattern_interval)


func _update_enemies() -> void:
	var player_radius := float(data.player.radius)
	var count := enemies.size()
	for i in count:
		var enemy: Enemy = enemies[i]
		enemy.prev = enemy.pos
		enemy.flash = maxf(0.0, enemy.flash - tick)
		match enemy.kind:
			"boss":
				_update_boss(enemy)
			"ghost":
				_move_ghost(enemy)
				_fire_weapons(enemy.pos, enemy.build, enemy.timers, true, enemy.damage_mult)
			_:
				enemy.pos += (player_pos - enemy.pos).normalized() * enemy.speed * tick
		# 이웃 한 쌍만 밀어내 O(n)으로 겹침을 줄인다.
		var other: Enemy = enemies[(i + 1) % count]
		var gap := enemy.pos - other.pos
		var min_gap := enemy.radius + other.radius
		if other != enemy and enemy.kind != "boss" and other.kind != "boss" and gap.length_squared() < min_gap * min_gap:
			var push := gap.normalized() * 1.5 if gap != Vector2.ZERO else Vector2.RIGHT
			enemy.pos += push
			other.pos -= push
		if invuln <= 0.0 and enemy.pos.distance_to(player_pos) <= enemy.radius + player_radius:
			_touch_player(enemy)


func _touch_player(enemy: Enemy) -> void:
	if enemy.kind == "boss":
		if boss_state == "charge":
			_hurt_player(float(boss_pattern.damage) * boss_damage_mult(), "boss_charge")
		else:
			_hurt_player(enemy.contact * boss_damage_mult(), "boss_contact")
	else:
		_hurt_player(enemy.contact, enemy.kind)
	invuln = float(data.player.contact_invuln)


func _move_ghost(ghost: Enemy) -> void:
	var to_player := player_pos - ghost.pos
	var dist := to_player.length()
	if dist < 0.01:
		return
	var dir := to_player / dist
	var move := dir
	if ghost.keep_distance > 0.0:
		if dist < ghost.keep_distance - 25.0:
			move = -dir
		elif dist <= ghost.keep_distance + 25.0:
			move = dir.orthogonal() * 0.6
	ghost.pos = _clamp_to_arena(ghost.pos + move * ghost.speed * tick)


func _update_projectiles() -> void:
	var player_radius := float(data.player.radius)
	var alive: Array[Projectile] = []
	for shot in projectiles:
		shot.prev = shot.pos
		shot.pos += shot.vel * tick
		shot.life -= tick
		var hit := false
		if shot.hostile:
			if shot.pos.distance_to(player_pos) <= shot.radius + player_radius:
				_hurt_player(shot.damage, shot.source)
				hit = true
		else:
			for enemy in enemies:
				if enemy.hp > 0.0 and shot.pos.distance_to(enemy.pos) <= shot.radius + enemy.radius:
					_damage_enemy(enemy, shot.damage)
					hit = true
					break
		if not hit and shot.life > 0.0:
			alive.append(shot)
	projectiles = alive


func _update_strikes() -> void:
	var alive: Array[Strike] = []
	for strike in strikes:
		strike.delay -= tick
		if strike.delay > 0.0:
			alive.append(strike)
			continue
		_event({"type": "lightning", "pos": strike.pos, "radius": strike.radius})
		if strike.pos.distance_to(player_pos) <= strike.radius + float(data.player.radius):
			_hurt_player(strike.damage, strike.source)
	strikes = alive


func _remove_dead() -> void:
	var alive: Array[Enemy] = []
	for enemy in enemies:
		if enemy.hp > 0.0:
			alive.append(enemy)
			continue
		kills += 1
		if enemy.kind == "ghost":
			ghost_kills += 1
			ghost_ttk_total += time - enemy.born
		elif enemy.kind == "boss":
			boss_dead = true
			boss_log.append({"round": round_index, "fight_time": time - enemy.born, "in_time": round_time <= float(data.round_seconds)})
		var gem := Gem.new()
		gem.pos = enemy.pos
		gem.value = enemy.xp
		gems.append(gem)
	enemies = alive


func _collect_gems() -> void:
	var radius_sq := float(data.player.pickup_radius) * float(data.player.pickup_radius)
	var remaining: Array[Gem] = []
	for gem in gems:
		if gem.pos.distance_squared_to(player_pos) <= radius_sq:
			_gain_xp(gem.value)
		else:
			remaining.append(gem)
	gems = remaining


func _gain_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		queued_levels += 1
	_offer_next_level()


func _offer_next_level() -> void:
	if queued_levels <= 0 or not pending_choices.is_empty():
		return
	var available: Array = []
	for option_id in WEAPON_IDS + UPGRADE_IDS:
		if option_level(option_id) < int(data.max_option_level):
			available.append(option_id)
	queued_levels -= 1
	if available.is_empty():
		queued_levels = 0
		return
	for i in range(available.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = available[i]
		available[i] = available[j]
		available[j] = swap
	pending_choices = available.slice(0, 3)


func _finish_round() -> void:
	if round_index >= int(data.rounds):
		state = "won"
		_event({"type": "won"})
		return
	var in_time: bool = boss_log[-1].in_time
	if in_time:
		queued_levels += int(data.boss.bonus_levels)
	for gem in gems:
		_gain_xp(gem.value)
	gems = []
	_offer_next_level()
	enemies = []
	projectiles = []
	strikes = []
	ghost_queue = []
	round_summary = {"round": round_index, "in_time": in_time, "fight_time": boss_log[-1].fight_time}
	_event({"type": "round_clear", "round": round_index})
