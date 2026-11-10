extends RefCounted
## 무기 발사, 탄과 낙뢰 판정, 피해, 사망 처리. 플레이어와 과거의 나가 같은 무기 코드를 쓴다.

const Entities := preload("res://legion/sim/entities.gd")
const BuildRules := preload("res://legion/sim/build_rules.gd")
const Loot := preload("res://legion/sim/loot.gd")


## owner는 무기를 쓰는 쪽이다. 플레이어면 sim, 과거의 나면 그 Enemy이고, 둘 다 build, timers, trail을 가진다.
static func fire_weapons(sim, owner, origin: Vector2, hostile: bool, hostile_mult: float) -> void:
	var owner_build: Dictionary = owner.build
	var owner_timers: Dictionary = owner.timers
	for weapon_id in BuildRules.WEAPON_IDS:
		var weapon_level := int(owner_build.weapons[weapon_id])
		if weapon_level <= 0:
			continue
		owner_timers[weapon_id] -= sim.tick
		# 실은 쿨다운과 상관없이 매 틱 이어진다. 쿨다운은 실이 베는 간격이다.
		if owner_timers[weapon_id] > 0.0 and weapon_id != "thread":
			continue
		var weapon: Dictionary = sim.data.weapons[weapon_id]
		var stats := BuildRules.weapon_stats(sim.data, weapon_id, owner_build)
		var damage: float = stats.damage * hostile_mult
		if hostile:
			damage *= float(weapon.hostile_damage_mult)
		if weapon_id == "thread":
			_lay_thread(sim, owner, origin, weapon, stats, damage, hostile)
			if owner_timers[weapon_id] > 0.0:
				continue
		var fired := false
		match weapon_id:
			"bolt":
				fired = _fire_bolt(sim, origin, weapon, stats, damage, hostile)
			"aura":
				fired = _fire_aura(sim, origin, stats, damage, hostile)
			"lightning":
				fired = _fire_lightning(sim, origin, weapon, stats, damage, hostile)
			"thread":
				fired = _cut_thread(sim, owner.trail, stats, damage, hostile)
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


## 시간의 실: 걸어온 자리에 실을 잇는다. 실 끝이 오래된 실에 닿아 고리가 닫히면 안쪽이 터지고 실은 처음부터 다시 풀린다.
## 과거의 나의 고리는 바로 터지지 않고, 예고 뒤에 터진다.
static func _lay_thread(sim, owner, origin: Vector2, weapon: Dictionary, stats: Dictionary, damage: float, hostile: bool) -> void:
	var trail: PackedVector2Array = owner.trail
	var spacing := float(weapon.spacing)
	if not trail.is_empty():
		var moved := origin.distance_to(trail[trail.size() - 1])
		if moved < spacing:
			return
		if moved > float(weapon.break_distance):
			# 보스 방 이동처럼 순간이동했으면 실이 끊긴다.
			trail = PackedVector2Array()
	trail.append(origin)
	var length: float = stats.length * (float(weapon.hostile_length_mult) if hostile else 1.0)
	var max_points := int(length / spacing) + 1
	if trail.size() > max_points:
		trail = trail.slice(trail.size() - max_points)
	owner.trail = trail
	var loop := _closed_loop(trail, weapon)
	if loop.is_empty():
		return
	owner.trail = PackedVector2Array([origin])
	var center := Vector2.ZERO
	for point in loop:
		center += point
	center /= loop.size()
	var loop_damage: float = damage * stats.loop_mult
	if hostile:
		var reach := 0.0
		for point in loop:
			reach = maxf(reach, center.distance_to(point))
		add_strike(sim, center, float(sim.data.ghost.strike_delay), loop_damage, reach, "ghost_thread")
		sim.strikes[-1].polygon = loop
		return
	# 고리 안쪽과 고리에 걸친 적이 모두 맞는다. 바로 뒤를 쫓던 적도 함께 터진다.
	var hits := 0
	for enemy: Entities.Enemy in sim.enemies:
		if not Geometry2D.is_point_in_polygon(enemy.pos, loop) and not _touches_trail(loop, enemy.pos, stats.radius + enemy.radius):
			continue
		hits += 1
		enemy.looped = true
		damage_enemy(sim, enemy, loop_damage)
		if stats.pull > 0.0 and enemy.kind != "boss":
			enemy.pos = enemy.pos.lerp(center, stats.pull)
	sim.emit_event({"type": "loop", "points": loop, "pos": center, "hits": hits, "hostile": false, "awakened": stats.pull > 0.0})


## 실 끝에서 가장 오래된 닿는 지점까지를 고리로 돌려준다. 고리가 아니면 빈 배열.
## 온 길을 되짚어 걸으면 넓이가 거의 없으므로 고리로 치지 않는다.
static func _closed_loop(trail: PackedVector2Array, weapon: Dictionary) -> PackedVector2Array:
	var head := trail[trail.size() - 1]
	var close_sq := float(weapon.close_distance) * float(weapon.close_distance)
	for i in trail.size() - int(weapon.min_loop_points):
		if head.distance_squared_to(trail[i]) > close_sq:
			continue
		var loop := trail.slice(i)
		var area := 0.0
		for k in loop.size():
			area += loop[k].cross(loop[(k + 1) % loop.size()])
		if absf(area) * 0.5 >= float(weapon.min_loop_area):
			return loop
		break
	return PackedVector2Array()


## 실에 닿아 있는 상대를 벤다.
static func _cut_thread(sim, trail: PackedVector2Array, stats: Dictionary, damage: float, hostile: bool) -> bool:
	if trail.size() < 2:
		return false
	var reach: float = stats.radius
	if hostile:
		# 닿을 때까지 매 틱 확인해서, 실을 밟는 순간 바로 벤다.
		if not _touches_trail(trail, sim.player_pos, reach + float(sim.data.player.radius)):
			return false
		hurt_player(sim, damage, "ghost_thread")
		if stats.slow > 0.0:
			sim.player_slow_time = float(sim.data.ghost.slow_seconds)
			sim.player_slow_amount = stats.slow
		return true
	for enemy: Entities.Enemy in sim.enemies:
		if not _touches_trail(trail, enemy.pos, reach + enemy.radius):
			continue
		damage_enemy(sim, enemy, damage)
		if stats.slow > 0.0:
			enemy.slow_time = 1.0
			enemy.slow_amount = stats.slow
	return true


static func _touches_trail(trail: PackedVector2Array, pos: Vector2, reach: float) -> bool:
	var reach_sq := reach * reach
	for i in trail.size() - 1:
		if Geometry2D.get_closest_point_to_segment(pos, trail[i], trail[i + 1]).distance_squared_to(pos) <= reach_sq:
			return true
	return false


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
		if not strike.polygon.is_empty():
			# 과거의 나가 닫은 고리. 터질 때 안쪽에 있으면 맞는다.
			sim.emit_event({"type": "loop", "points": strike.polygon, "pos": strike.pos, "hits": 0, "hostile": true})
			if Geometry2D.is_point_in_polygon(sim.player_pos, strike.polygon):
				hurt_player(sim, strike.damage, strike.source)
			continue
		sim.emit_event({"type": "lightning", "pos": strike.pos, "radius": strike.radius, "hostile": strike.hostile, "source": strike.source})
		if not strike.hostile:
			damage_area(sim, strike.pos, strike.radius, strike.damage, strike.source)
		elif strike.pos.distance_to(sim.player_pos) <= strike.radius + float(sim.data.player.radius):
			hurt_player(sim, strike.damage, strike.source)
	sim.strikes = alive


## 거미줄: 날아가는 동안(delay)은 아무 일도 없고, 깔린 뒤 time 동안 밟으면 느려진다.
static func update_zones(sim) -> void:
	var alive: Array[Entities.Zone] = []
	var player_radius := float(sim.data.player.radius)
	for zone: Entities.Zone in sim.zones:
		if zone.delay > 0.0:
			zone.delay -= sim.tick
			if zone.delay <= 0.0:
				sim.emit_event({"type": "web_land", "pos": zone.pos, "radius": zone.radius})
			alive.append(zone)
			continue
		zone.time -= sim.tick
		if zone.pos.distance_to(sim.player_pos) <= zone.radius + player_radius:
			# 이미 다른 감속(과거의 나의 빙결) 중이면 더 센 쪽을 쓴다.
			var was_slowed: bool = sim.player_slow_time > 0.0
			sim.player_slow_amount = maxf(sim.player_slow_amount, zone.slow) if was_slowed else zone.slow
			sim.player_slow_time = maxf(sim.player_slow_time, 0.15)
		if zone.time > 0.0:
			alive.append(zone)
	sim.zones = alive


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
		# 고리로 잡은 적의 보석은 주우러 돌아가지 않아도 날아온다.
		gem.attracted = enemy.looped
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
