extends RefCounted
## 적 이동, 겹침 밀어내기, 플레이어 접촉 피해. 과거의 나는 여기서 자기 빌드의 무기도 쏜다.

const Entities := preload("res://legion/sim/entities.gd")
const Combat := preload("res://legion/sim/combat.gd")
const Boss := preload("res://legion/sim/boss.gd")


static func update(sim) -> void:
	var player_radius := float(sim.data.player.radius)
	var tick: float = sim.tick
	var player_pos: Vector2 = sim.player_pos
	var enemies: Array = sim.enemies
	var count := enemies.size()
	for i in count:
		var enemy: Entities.Enemy = enemies[i]
		enemy.prev = enemy.pos
		enemy.flash = maxf(0.0, enemy.flash - tick)
		enemy.slow_time = maxf(0.0, enemy.slow_time - tick)
		match enemy.kind:
			"boss":
				Boss.update(sim, enemy)
			"ghost":
				_move_ghost(sim, enemy)
				Combat.fire_weapons(sim, enemy.pos, enemy.build, enemy.timers, true, enemy.damage_mult)
			_:
				enemy.pos += (player_pos - enemy.pos).normalized() * enemy.current_speed() * tick
		# 이웃 한 쌍만 밀어내 O(n)으로 겹침을 줄인다.
		var other: Entities.Enemy = enemies[(i + 1) % count]
		var gap := enemy.pos - other.pos
		var min_gap := enemy.radius + other.radius
		if other != enemy and enemy.kind != "boss" and other.kind != "boss" and gap.length_squared() < min_gap * min_gap:
			var push := gap.normalized() * 1.5 if gap != Vector2.ZERO else Vector2.RIGHT
			enemy.pos += push
			other.pos -= push
		if sim.invuln <= 0.0 and enemy.pos.distance_to(player_pos) <= enemy.radius + player_radius:
			_touch_player(sim, enemy)


static func _touch_player(sim, enemy: Entities.Enemy) -> void:
	if enemy.kind == "boss":
		if sim.boss_state == "charge":
			Combat.hurt_player(sim, float(sim.boss_pattern.damage) * Boss.damage_mult(sim), "boss_charge")
		else:
			Combat.hurt_player(sim, enemy.contact * Boss.damage_mult(sim), "boss_contact")
	else:
		Combat.hurt_player(sim, enemy.contact, enemy.kind)
	sim.invuln = float(sim.data.player.contact_invuln)


static func _move_ghost(sim, ghost: Entities.Enemy) -> void:
	var to_player: Vector2 = sim.player_pos - ghost.pos
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
	ghost.pos = sim.clamp_to_arena(ghost.pos + move * ghost.current_speed() * sim.tick)
