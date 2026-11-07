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
	var slow_time := 0.0
	var slow_amount := 0.0


class Projectile:
	var pos := Vector2.ZERO
	var prev := Vector2.ZERO
	var vel := Vector2.ZERO
	var damage := 0.0
	var radius := 1.0
	var life := 1.0
	var hostile := false
	var source := ""
	var pierce := 0
	var hit_list: Array = []
	var splash_radius := 0.0
	var splash_mult := 0.0


class Strike:
	var pos := Vector2.ZERO
	var delay := 0.0
	var damage := 0.0
	var radius := 1.0
	var source := ""
	var hostile := true


class Gem:
	var pos := Vector2.ZERO
	var value := 1
	var attracted := false


class Pickup:
	var kind := ""
	var pos := Vector2.ZERO
	var life := 0.0


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
var main_weapon := ""
var build := {}
var timers := {}
var player_slow_time := 0.0
var player_slow_amount := 0.0
var level := 1
var xp := 0
var queued_levels := 0
var pending_choices: Array = []

var enemies: Array[Enemy] = []
var projectiles: Array[Projectile] = []
var strikes: Array[Strike] = []
var gems: Array[Gem] = []
var pickups: Array[Pickup] = []
var pickup_timer := 0.0
var pickups_taken := 0
var awaken_round := 0
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


func _init(balance: Dictionary, run_seed: int, main_id: String) -> void:
	data = balance
	rng.seed = run_seed
	tick = float(data.tick)
	max_hp = float(data.player.hp)
	hp = max_hp
	player_pos = Vector2(float(data.arena.w), float(data.arena.h)) * 0.5
	player_prev = player_pos
	main_weapon = main_id
	var trait_levels := {}
	for trait_id in data.traits:
		trait_levels[trait_id] = 0
	build = {
		"main": main_id,
		"weapons": {"bolt": 0, "aura": 0, "lightning": 0},
		"traits": trait_levels,
		"upgrades": {"might": 0, "haste": 0, "vitality": 0},
	}
	build.weapons[main_id] = 1
	pickup_timer = float(data.items.interval)
	timers = {"bolt": 0.0, "aura": 0.0, "lightning": 0.0}


func is_over() -> bool:
	return state != "playing"


func xp_needed() -> int:
	return int(data.xp.base) + int(data.xp.per_level) * (level - 1)


func option_level(option_id: String) -> int:
	return _build_level(build, option_id)


func _build_level(target_build: Dictionary, option_id: String) -> int:
	if option_id in WEAPON_IDS:
		return int(target_build.weapons[option_id])
	if data.traits.has(option_id):
		return int(target_build.traits[option_id])
	return int(target_build.upgrades[option_id])


func option_def(option_id: String) -> Dictionary:
	if option_id in WEAPON_IDS:
		return data.weapons[option_id]
	if data.traits.has(option_id):
		return data.traits[option_id]
	return data.upgrades[option_id]


func option_max(option_id: String) -> int:
	if option_id == main_weapon:
		return int(data.max_levels.main)
	if option_id in WEAPON_IDS:
		return int(data.max_levels.sub)
	if data.traits.has(option_id):
		return int(data.max_levels.trait)
	return int(data.max_levels.upgrade)


func is_awakening_option(option_id: String) -> bool:
	return option_id == main_weapon and option_level(option_id) + 1 >= int(data.max_levels.main)


func is_awakened(target_build: Dictionary) -> bool:
	return int(target_build.weapons[target_build.main]) >= int(data.max_levels.main)


func dominant_weapon(target_build: Dictionary) -> String:
	return target_build.main


## 레벨, 특성, 각성, 공통 강화를 합친 무기의 실제 수치.
func weapon_stats(weapon_id: String, owner_build: Dictionary) -> Dictionary:
	var weapon: Dictionary = data.weapons[weapon_id]
	var weapon_level := int(owner_build.weapons[weapon_id])
	var stats := {
		"damage": float(weapon.damage) + float(weapon.damage_per_level) * (weapon_level - 1),
		"count": 1,
		"radius": float(weapon.radius) + float(weapon.get("radius_per_level", 0.0)) * (weapon_level - 1),
		"cooldown": float(weapon.cooldown),
		"pierce": 0, "leech": 0.0, "slow": 0.0, "knockback": 0.0,
		"splash_radius": 0.0, "splash_mult": 0.0, "echo_delay": 0.0,
	}
	if weapon.has("count_every_levels"):
		stats.count += int((weapon_level - 1) / float(weapon.count_every_levels))
	for trait_id in data.traits:
		var trait_def: Dictionary = data.traits[trait_id]
		var trait_level := int(owner_build.traits[trait_id])
		if trait_def.weapon != weapon_id or trait_level <= 0:
			continue
		var amount := float(trait_def.value) * trait_level
		match trait_def.effect:
			"count":
				stats.count += int(amount)
			"pierce":
				stats.pierce += int(amount)
			"cooldown":
				stats.cooldown *= maxf(float(data.min_cooldown_mult), 1.0 - amount)
			"radius":
				stats.radius += amount
			"leech":
				stats.leech += amount
			"slow":
				stats.slow += amount
			"damage":
				stats.damage *= 1.0 + amount
	if weapon_level >= int(data.max_levels.main):
		var awaken: Dictionary = weapon.awaken
		stats.damage *= float(awaken.get("damage_mult", 1.0))
		stats.count = stats.count * int(awaken.get("count_mult", 1)) + int(awaken.get("extra_count", 0))
		stats.radius *= float(awaken.get("radius_mult", 1.0))
		stats.knockback = float(awaken.get("knockback", 0.0))
		stats.splash_radius = float(awaken.get("splash_radius", 0.0))
		stats.splash_mult = float(awaken.get("splash_mult", 0.0))
		stats.echo_delay = float(awaken.get("echo_delay", 0.0))
	stats.damage *= _might_mult(owner_build)
	stats.cooldown *= _cooldown_mult(owner_build)
	return stats


func build_dps(target_build: Dictionary) -> float:
	var total := 0.0
	for weapon_id in WEAPON_IDS:
		if int(target_build.weapons[weapon_id]) <= 0:
			continue
		var stats := weapon_stats(weapon_id, target_build)
		var hits: float = 2.0 if stats.echo_delay > 0.0 else 1.0
		total += stats.damage * stats.count * hits / stats.cooldown * float(data.weapons[weapon_id].single_target_weight)
	return total


## 각성은 화력이 크게 뛰므로, 적 체력 계산에서는 각성 직전 화력에 정해진 배수만 곱한다.
func enemy_scaling_dps(target_build: Dictionary) -> float:
	if not is_awakened(target_build):
		return build_dps(target_build)
	var before: Dictionary = target_build.duplicate(true)
	before.weapons[target_build.main] -= 1
	return build_dps(before) * float(data.awaken_scaling_mult)


func ghost_hp(target_build: Dictionary, age: int) -> float:
	var ghost_def: Dictionary = data.ghost
	var scaled := enemy_scaling_dps(target_build) * float(ghost_def.target_ttk) * (1.0 + float(ghost_def.hp_per_age) * age)
	return maxf(float(ghost_def.hp_min), scaled)


## 이 선택지를 고르면 다음 라운드의 과거의 나가 어떻게 되는지 알려준다.
func ghost_preview(option_id: String) -> Dictionary:
	var preview_build: Dictionary = build.duplicate(true)
	if option_id != "":
		_apply_option(preview_build, option_id)
	return {
		"hp": ghost_hp(preview_build, 0),
		"behavior": data.ghost.behaviors[dominant_weapon(preview_build)].name,
		"awakened": is_awakened(preview_build),
	}


func _apply_option(target_build: Dictionary, option_id: String) -> void:
	if option_id in WEAPON_IDS:
		target_build.weapons[option_id] += 1
	elif data.traits.has(option_id):
		target_build.traits[option_id] += 1
	else:
		target_build.upgrades[option_id] += 1


func choose(index: int) -> void:
	var option_id: String = pending_choices[index]
	picks.append({"offered": pending_choices.duplicate(), "chosen": option_id})
	var awakens := is_awakening_option(option_id)
	_apply_option(build, option_id)
	if option_id == "vitality":
		var bonus := float(data.upgrades.vitality.value)
		max_hp += bonus
		hp = minf(hp + bonus, max_hp)
	if awakens:
		awaken_round = round_index
		_event({"type": "awaken", "name": data.weapons[main_weapon].awaken.name})
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
	player_slow_time = maxf(0.0, player_slow_time - tick)
	_move_player(move_dir)
	_fire_weapons(player_pos, build, timers, false, 1.0)
	_spawn_enemies()
	_spawn_ghosts()
	_spawn_boss()
	_update_enemies()
	_update_projectiles()
	_update_strikes()
	_remove_dead()
	_update_pickups()
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
	var speed := float(data.player.speed)
	if player_slow_time > 0.0:
		speed *= maxf(0.2, 1.0 - player_slow_amount)
	player_pos = _clamp_to_arena(player_pos + move_dir.limit_length(1.0) * speed * tick)


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
		var stats := weapon_stats(weapon_id, owner_build)
		var damage: float = stats.damage * hostile_mult
		if hostile:
			damage *= float(weapon.hostile_damage_mult)
		var fired := false
		match weapon_id:
			"bolt":
				fired = _fire_bolt(origin, weapon, stats, damage, hostile)
			"aura":
				fired = _fire_aura(origin, stats, damage, hostile)
			"lightning":
				fired = _fire_lightning(origin, weapon, stats, damage, hostile)
		var cooldown: float = stats.cooldown
		if hostile:
			cooldown *= float(weapon.hostile_cooldown_mult)
		owner_timers[weapon_id] = cooldown if fired else 0.0


func _fire_bolt(origin: Vector2, weapon: Dictionary, stats: Dictionary, damage: float, hostile: bool) -> bool:
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
	var count: int = mini(stats.count, int(weapon.hostile_max_count)) if hostile else stats.count
	var base_dir := (target - origin).normalized()
	var speed := float(weapon.hostile_speed) if hostile else float(weapon.speed)
	for i in count:
		var shot := _add_projectile(origin, base_dir.rotated((i - (count - 1) * 0.5) * 0.18) * speed, damage, float(weapon.radius),
				float(weapon.life) * (float(weapon.speed) / speed if hostile else 1.0), hostile, "ghost_bolt")
		if not hostile:
			shot.pierce = stats.pierce
			shot.splash_radius = stats.splash_radius
			shot.splash_mult = stats.splash_mult
	return true


func _add_projectile(origin: Vector2, vel: Vector2, damage: float, radius: float, life: float, hostile: bool, source: String) -> Projectile:
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
	return shot


func _fire_aura(origin: Vector2, stats: Dictionary, damage: float, hostile: bool) -> bool:
	var radius: float = stats.radius
	if hostile:
		radius *= float(data.weapons.aura.hostile_radius_mult)
	_event({"type": "aura", "pos": origin, "radius": radius, "hostile": hostile})
	if hostile:
		if origin.distance_to(player_pos) <= radius + float(data.player.radius):
			_hurt_player(damage, "ghost_aura")
			if stats.slow > 0.0:
				player_slow_time = float(data.ghost.slow_seconds)
				player_slow_amount = stats.slow
		return true
	var hit_any := false
	for enemy in enemies:
		if origin.distance_to(enemy.pos) > radius + enemy.radius:
			continue
		hit_any = true
		_damage_enemy(enemy, damage)
		if stats.slow > 0.0:
			enemy.slow_time = 1.0
			enemy.slow_amount = stats.slow
		if stats.knockback > 0.0 and enemy.kind != "boss":
			enemy.pos += (enemy.pos - origin).normalized() * stats.knockback
	if hit_any:
		hp = minf(max_hp, hp + stats.leech)
	return true


func _add_strike(pos: Vector2, delay: float, damage: float, radius: float, source: String, hostile := true) -> void:
	var strike := Strike.new()
	strike.pos = _clamp_to_arena(pos)
	strike.delay = delay
	strike.damage = damage
	strike.radius = radius
	strike.source = source
	strike.hostile = hostile
	strikes.append(strike)


func _random_offset(spread: float) -> Vector2:
	return Vector2.from_angle(rng.randf() * TAU) * rng.randf() * spread


func _fire_lightning(origin: Vector2, weapon: Dictionary, stats: Dictionary, damage: float, hostile: bool) -> bool:
	var radius: float = stats.radius
	var count: int = stats.count
	var echo_delay: float = stats.echo_delay
	if hostile:
		if origin.distance_to(player_pos) > float(weapon.range):
			return false
		var strike_delay := float(data.ghost.strike_delay)
		for i in mini(count, int(weapon.hostile_max_count)):
			var offset := Vector2.ZERO if i == 0 else _random_offset(float(data.ghost.strike_spread))
			_add_strike(player_pos + offset, strike_delay, damage, radius, "ghost_lightning")
			if echo_delay > 0.0:
				_add_strike(player_pos + offset, strike_delay + echo_delay, damage, radius, "ghost_lightning")
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
		_damage_area(center.pos, radius, damage)
		if echo_delay > 0.0:
			_add_strike(center.pos, echo_delay, damage, radius, "", false)
	return true


func _damage_area(center: Vector2, radius: float, damage: float) -> void:
	for enemy in enemies:
		if center.distance_to(enemy.pos) <= radius + enemy.radius:
			_damage_enemy(enemy, damage)


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
	var roll := rng.randf()
	var kind := "grunt"
	if roll < runner_chance:
		kind = "runner"
	elif roll < runner_chance + float(spawn.swarmling_chance):
		kind = "swarmling"
	_add_enemy(kind, pos)


func _add_enemy(kind: String, pos: Vector2) -> void:
	var def: Dictionary = data.enemies[kind]
	var enemy := Enemy.new()
	enemy.kind = kind
	enemy.label = def.name
	enemy.pos = pos
	enemy.prev = pos
	enemy.max_hp = float(def.hp) * (1.0 + float(data.spawn.hp_per_round) * (round_index - 1))
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
	enemy.max_hp = maxf(base_hp, enemy_scaling_dps(build) * float(cfg.target_ttk))
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
			enemy.pos += (player_pos - enemy.pos).normalized() * _enemy_speed(enemy) * tick
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
		enemy.slow_time = maxf(0.0, enemy.slow_time - tick)
		match enemy.kind:
			"boss":
				_update_boss(enemy)
			"ghost":
				_move_ghost(enemy)
				_fire_weapons(enemy.pos, enemy.build, enemy.timers, true, enemy.damage_mult)
			_:
				enemy.pos += (player_pos - enemy.pos).normalized() * _enemy_speed(enemy) * tick
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


func _enemy_speed(enemy: Enemy) -> float:
	if enemy.slow_time > 0.0:
		return enemy.speed * maxf(0.2, 1.0 - enemy.slow_amount)
	return enemy.speed


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
	ghost.pos = _clamp_to_arena(ghost.pos + move * _enemy_speed(ghost) * tick)


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
				if enemy.hp <= 0.0 or enemy in shot.hit_list or shot.pos.distance_to(enemy.pos) > shot.radius + enemy.radius:
					continue
				_damage_enemy(enemy, shot.damage)
				if shot.splash_radius > 0.0:
					_event({"type": "burst", "pos": shot.pos, "radius": shot.splash_radius})
					_damage_area(shot.pos, shot.splash_radius, shot.damage * shot.splash_mult)
				if shot.pierce > 0:
					shot.pierce -= 1
					shot.hit_list.append(enemy)
				else:
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
		if not strike.hostile:
			_damage_area(strike.pos, strike.radius, strike.damage)
		elif strike.pos.distance_to(player_pos) <= strike.radius + float(data.player.radius):
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
			if rng.randf() < float(data.items.ghost_drop_chance):
				_add_pickup(enemy.pos)
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
	var magnet_step := float(data.items.magnet.speed) * tick
	var remaining: Array[Gem] = []
	for gem in gems:
		if gem.attracted:
			gem.pos = gem.pos.move_toward(player_pos, magnet_step)
		if gem.pos.distance_squared_to(player_pos) <= radius_sq:
			_gain_xp(gem.value)
		else:
			remaining.append(gem)
	gems = remaining


func _update_pickups() -> void:
	var items: Dictionary = data.items
	pickup_timer -= tick
	if pickup_timer <= 0.0:
		pickup_timer = float(items.interval)
		var distance := rng.randf_range(float(items.min_distance), float(items.max_distance))
		_add_pickup(_clamp_to_arena(player_pos + Vector2.from_angle(rng.randf() * TAU) * distance))
	var reach := float(items.radius) + float(data.player.radius)
	var remaining: Array[Pickup] = []
	for item in pickups:
		item.life -= tick
		if item.pos.distance_to(player_pos) <= reach:
			_use_pickup(item.kind)
		elif item.life > 0.0:
			remaining.append(item)
	pickups = remaining


func _add_pickup(pos: Vector2) -> void:
	var items: Dictionary = data.items
	var magnet_weight := float(items.magnet.weight)
	var roll := rng.randf() * (magnet_weight + float(items.potion.weight))
	var item := Pickup.new()
	item.kind = "magnet" if roll < magnet_weight else "potion"
	item.pos = pos
	item.life = float(items.life)
	pickups.append(item)


func _use_pickup(kind: String) -> void:
	pickups_taken += 1
	if kind == "magnet":
		for gem in gems:
			gem.attracted = true
	else:
		hp = minf(max_hp, hp + max_hp * float(data.items.potion.heal_ratio))
	_event({"type": "pickup", "kind": kind, "name": data.items[kind].name})


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
	var weights: Array = []
	for option_id in _option_pool():
		if is_awakening_option(option_id) and round_index < int(data.awaken_min_round):
			continue
		if option_level(option_id) < option_max(option_id):
			available.append(option_id)
			weights.append(_option_weight(option_id))
	queued_levels -= 1
	if available.is_empty():
		queued_levels = 0
		return
	pending_choices = []
	while pending_choices.size() < 3 and not available.is_empty():
		var index := _weighted_index(weights)
		pending_choices.append(available.pop_at(index))
		weights.remove_at(index)


## 메인 무기, 메인 무기의 특성, 공통 강화, 보조 무기만 선택지로 나온다.
func _option_pool() -> Array:
	var pool: Array = WEAPON_IDS + UPGRADE_IDS
	for trait_id in data.traits:
		if data.traits[trait_id].weapon == main_weapon:
			pool.append(trait_id)
	return pool


func _option_weight(option_id: String) -> float:
	var offer: Dictionary = data.offer_weights
	if option_id == main_weapon:
		return float(offer.main)
	if option_id in WEAPON_IDS:
		return float(offer.sub)
	if data.traits.has(option_id):
		return float(offer.trait)
	return float(offer.upgrade)


func _weighted_index(weights: Array) -> int:
	var total := 0.0
	for weight in weights:
		total += float(weight)
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			return i
	return weights.size() - 1


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
	pickups = []
	ghost_queue = []
	round_summary = {"round": round_index, "in_time": in_time, "fight_time": boss_log[-1].fight_time}
	_event({"type": "round_clear", "round": round_index})
