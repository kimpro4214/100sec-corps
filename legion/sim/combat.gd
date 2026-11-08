extends RefCounted
## 무기 발사, 탄과 낙뢰 판정, 피해, 사망 처리. 플레이어와 과거의 나가 같은 무기 코드를 쓴다.

const Entities := preload("res://legion/sim/entities.gd")
const BuildRules := preload("res://legion/sim/build_rules.gd")
const Loot := preload("res://legion/sim/loot.gd")


static func fire_weapons(sim, origin: Vector2, owner_build: Dictionary, owner_timers: Dictionary, hostile: bool, hostile_mult: float) -> void:
	for weapon_id in BuildRules.WEAPON_IDS:
		var weapon_level := int(owner_build.weapons[weapon_id])
		if weapon_level <= 0:
			continue
		owner_timers[weapon_id] -= sim.tick
		if owner_timers[weapon_id] > 0.0:
			continue
		var weapon: Dictionary = sim.data.weapons[weapon_id]
		var stats := BuildRules.weapon_stats(sim.data, weapon_id, owner_build)
		var damage: float = stats.damage * hostile_mult
		if hostile:
			damage *= float(weapon.hostile_damage_mult)
		var fired := false
		match weapon_id:
			"bolt":
				fired = _fire_bolt(sim, origin, weapon, stats, damage, hostile)
			"aura":
				fired = _fire_aura(sim, origin, stats, damage, hostile)
			"lightning":
				fired = _fire_lightning(sim, origin, weapon, stats, damage, hostile)
		var cooldown: float = stats.cooldown
		if hostile:
			cooldown *= float(weapon.hostile_cooldown_mult)
		elif sim.frenzy_time > 0.0:
			# 보물상자의 광폭 효과. 빌드에 남지 않아 과거의 나에게는 없다.
			cooldown *= 1.0 - sim.frenzy_amount
		owner_timers[weapon_id] = cooldown if fired else 0.0


static func _fire_bolt(sim, origin: Vector2, weapon: Dictionary, stats: Dictionary, damage: float, hostile: bool) -> bool:
	var target := Vector2.ZERO
	var max_range := float(weapon.range)
	if hostile:
		if origin.distance_to(sim.player_pos) > max_range:
			return false
		target = sim.player_pos
	else:
		var best: Entities.Enemy = null
		var best_dist := max_range * max_range
		for enemy: Entities.Enemy in sim.enemies:
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
		var shot := add_projectile(sim, origin, base_dir.rotated((i - (count - 1) * 0.5) * 0.18) * speed, damage, float(weapon.radius),
				float(weapon.life) * (float(weapon.speed) / speed if hostile else 1.0), hostile, "ghost_bolt")
		if not hostile:
			shot.pierce = stats.pierce
			shot.splash_radius = stats.splash_radius
			shot.splash_mult = stats.splash_mult
	sim.emit_event({"type": "bolt", "hostile": hostile})
	return true


static func add_projectile(sim, origin: Vector2, vel: Vector2, damage: float, radius: float, life: float, hostile: bool, source: String) -> Entities.Projectile:
	var shot := Entities.Projectile.new()
	shot.pos = origin
	shot.prev = origin
	shot.vel = vel
	shot.damage = damage
	shot.radius = radius
	shot.life = life
	shot.hostile = hostile
	shot.source = source
	sim.projectiles.append(shot)
	return shot


static func _fire_aura(sim, origin: Vector2, stats: Dictionary, damage: float, hostile: bool) -> bool:
	var radius: float = stats.radius
	if hostile:
		radius *= float(sim.data.weapons.aura.hostile_radius_mult)
	sim.emit_event({"type": "aura", "pos": origin, "radius": radius, "hostile": hostile})
	if hostile:
		if origin.distance_to(sim.player_pos) <= radius + float(sim.data.player.radius):
			hurt_player(sim, damage, "ghost_aura")
			if stats.slow > 0.0:
				sim.player_slow_time = float(sim.data.ghost.slow_seconds)
				sim.player_slow_amount = stats.slow
		return true
	var hit_any := false
	for enemy: Entities.Enemy in sim.enemies:
		if origin.distance_to(enemy.pos) > radius + enemy.radius:
			continue
		hit_any = true
		damage_enemy(sim, enemy, damage)
		if stats.slow > 0.0:
			enemy.slow_time = 1.0
			enemy.slow_amount = stats.slow
		if stats.knockback > 0.0 and enemy.kind != "boss":
			enemy.pos += (enemy.pos - origin).normalized() * stats.knockback
	if hit_any:
		sim.hp = minf(sim.max_hp, sim.hp + stats.leech)
	return true


static func add_strike(sim, pos: Vector2, delay: float, damage: float, radius: float, source: String, hostile := true) -> void:
	var strike := Entities.Strike.new()
	strike.pos = sim.clamp_to_arena(pos)
	strike.delay = delay
	strike.damage = damage
	strike.radius = radius
	strike.source = source
	strike.hostile = hostile
	sim.strikes.append(strike)


static func _fire_lightning(sim, origin: Vector2, weapon: Dictionary, stats: Dictionary, damage: float, hostile: bool) -> bool:
	var radius: float = stats.radius
	var count: int = stats.count
	var echo_delay: float = stats.echo_delay
	if hostile:
		if origin.distance_to(sim.player_pos) > float(weapon.range):
			return false
		var strike_delay := float(sim.data.ghost.strike_delay)
		for i in mini(count, int(weapon.hostile_max_count)):
			var offset: Vector2 = Vector2.ZERO if i == 0 else sim.random_offset(float(sim.data.ghost.strike_spread))
			add_strike(sim, sim.player_pos + offset, strike_delay, damage, radius, "ghost_lightning")
			if echo_delay > 0.0:
				add_strike(sim, sim.player_pos + offset, strike_delay + echo_delay, damage, radius, "ghost_lightning")
		return true
	var in_range: Array[Entities.Enemy] = []
	var range_sq := float(weapon.range) * float(weapon.range)
	for enemy: Entities.Enemy in sim.enemies:
		if origin.distance_squared_to(enemy.pos) <= range_sq:
			in_range.append(enemy)
	if in_range.is_empty():
		return false
	for i in count:
		var center: Entities.Enemy = in_range[sim.rng.randi_range(0, in_range.size() - 1)]
		sim.emit_event({"type": "lightning", "pos": center.pos, "radius": radius, "hostile": false})
		damage_area(sim, center.pos, radius, damage)
		if echo_delay > 0.0:
			add_strike(sim, center.pos, echo_delay, damage, radius, "", false)
	return true


static func damage_area(sim, center: Vector2, radius: float, damage: float, source := "") -> void:
	for enemy: Entities.Enemy in sim.enemies:
		if center.distance_to(enemy.pos) <= radius + enemy.radius:
			damage_enemy(sim, enemy, damage, source)


static func damage_enemy(sim, enemy: Entities.Enemy, damage: float, source := "") -> void:
	if source == "ultimate" and (enemy.kind == "ghost" or enemy.kind == "boss"):
		damage *= float(sim.data.ultimate.elite_damage_mult)
	enemy.hp -= damage
	enemy.flash = 0.1


static func hurt_player(sim, damage: float, source: String) -> void:
	if sim.ult_guard > 0.0:
		return
	sim.hp -= damage
	sim.emit_event({"type": "hurt", "damage": damage})
	sim.last_hit = source
	sim.player_flash = 0.15
	sim.damage_by_source[source] = sim.damage_by_source.get(source, 0.0) + damage


static func update_projectiles(sim) -> void:
	var player_radius := float(sim.data.player.radius)
	var tick: float = sim.tick
	var alive: Array[Entities.Projectile] = []
	for shot: Entities.Projectile in sim.projectiles:
		shot.prev = shot.pos
		shot.pos += shot.vel * tick
		shot.life -= tick
		var hit := false
		if shot.hostile:
			if shot.pos.distance_to(sim.player_pos) <= shot.radius + player_radius:
				hurt_player(sim, shot.damage, shot.source)
				hit = true
		else:
			for enemy: Entities.Enemy in sim.enemies:
				if enemy.hp <= 0.0 or enemy in shot.hit_list or shot.pos.distance_to(enemy.pos) > shot.radius + enemy.radius:
					continue
				damage_enemy(sim, enemy, shot.damage, shot.source)
				if shot.splash_radius > 0.0:
					sim.emit_event({"type": "burst", "pos": shot.pos, "radius": shot.splash_radius})
					damage_area(sim, shot.pos, shot.splash_radius, shot.damage * shot.splash_mult)
				if shot.pierce > 0:
					shot.pierce -= 1
					shot.hit_list.append(enemy)
				else:
					hit = true
				break
		if not hit and shot.life > 0.0:
			alive.append(shot)
	sim.projectiles = alive


static func update_strikes(sim) -> void:
	var alive: Array[Entities.Strike] = []
	for strike: Entities.Strike in sim.strikes:
		strike.delay -= sim.tick
		if strike.delay > 0.0:
			alive.append(strike)
			continue
		sim.emit_event({"type": "lightning", "pos": strike.pos, "radius": strike.radius, "hostile": strike.hostile})
		if not strike.hostile:
			damage_area(sim, strike.pos, strike.radius, strike.damage, strike.source)
		elif strike.pos.distance_to(sim.player_pos) <= strike.radius + float(sim.data.player.radius):
			hurt_player(sim, strike.damage, strike.source)
	sim.strikes = alive


## 체력이 0 이하인 적을 치우고 처치 기록, 궁극기 충전, 경험치 보석, 드롭을 남긴다.
static func resolve_deaths(sim) -> void:
	var alive: Array[Entities.Enemy] = []
	for enemy: Entities.Enemy in sim.enemies:
		if enemy.hp > 0.0:
			alive.append(enemy)
			continue
		sim.kills += 1
		sim.ult_charge = mini(sim.ult_charge + 1, int(sim.data.ultimate.charge_kills))
		sim.emit_event({"type": "kill", "pos": enemy.pos, "kind": enemy.kind, "radius": enemy.radius})
		if enemy.kind == "ghost":
			sim.ghost_kills += 1
			sim.ghost_ttk_total += sim.time - enemy.born
			if sim.rng.randf() < float(sim.data.items.ghost_drop_chance):
				Loot.add_pickup(sim, enemy.pos)
		elif enemy.kind == "boss":
			sim.boss_dead = true
			sim.boss_log.append({"round": sim.round_index, "fight_time": sim.time - enemy.born, "in_time": sim.round_time <= float(sim.data.round_seconds)})
		var gem := Entities.Gem.new()
		gem.pos = enemy.pos
		gem.value = enemy.xp
		sim.gems.append(gem)
		_drop_gold(sim, enemy)
	sim.enemies = alive


## 종류별 확률로 금화를 떨어뜨린다. 금화는 필드의 보물상자와 룰렛에 쓴다.
static func _drop_gold(sim, enemy: Entities.Enemy) -> void:
	var gold: Dictionary = sim.data.gold
	if not gold.chance.has(enemy.kind) or sim.rng.randf() >= float(gold.chance[enemy.kind]):
		return
	var coin := Entities.Gem.new()
	coin.pos = enemy.pos + Vector2(8, 0)
	coin.value = int(gold.amount[enemy.kind])
	coin.gold = true
	sim.gems.append(coin)
