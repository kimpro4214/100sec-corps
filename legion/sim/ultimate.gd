extends RefCounted
## 처치 수로 충전되는 메인 무기별 궁극기. 플레이어만 사용한다.

const Entities := preload("res://legion/sim/entities.gd")
const Combat := preload("res://legion/sim/combat.gd")


static func is_ready(sim) -> bool:
	return sim.ult_charge >= int(sim.data.ultimate.charge_kills)


static func use(sim) -> bool:
	if sim.is_over() or not is_ready(sim) or not sim.pending_choices.is_empty() or not sim.round_summary.is_empty():
		return false
	sim.ult_charge = 0
	sim.ultimates_used += 1
	sim.ult_guard = float(sim.data.ultimate.invuln)
	var ult: Dictionary = sim.data.ultimate[sim.main_weapon]
	var damage: float = float(ult.damage) * (1.0 + float(sim.data.ultimate.damage_per_round) * (sim.round_index - 1))
	var player_pos: Vector2 = sim.player_pos
	sim.emit_event({"type": "ultimate", "weapon": sim.main_weapon, "name": ult.name, "pos": player_pos})
	match sim.main_weapon:
		"bolt":
			var count := int(ult.count)
			for i in count:
				var shot := Combat.add_projectile(sim, player_pos, Vector2.from_angle(TAU * i / count) * float(ult.speed), damage, float(ult.radius), float(ult.life), false, "ultimate")
				shot.pierce = 999
		"aura":
			var radius := float(ult.radius)
			sim.emit_event({"type": "ult_blast", "pos": player_pos, "radius": radius})
			for enemy: Entities.Enemy in sim.enemies:
				if player_pos.distance_to(enemy.pos) > radius + enemy.radius:
					continue
				Combat.damage_enemy(sim, enemy, damage, "ultimate")
				if enemy.kind != "boss":
					enemy.pos = sim.clamp_to_arena(enemy.pos + (enemy.pos - player_pos).normalized() * float(ult.knockback))
		"thread":
			var radius := float(ult.radius)
			sim.emit_event({"type": "ult_blast", "pos": player_pos, "radius": radius})
			for enemy: Entities.Enemy in sim.enemies:
				if player_pos.distance_to(enemy.pos) > radius + enemy.radius:
					continue
				Combat.damage_enemy(sim, enemy, damage, "ultimate")
				enemy.slow_time = float(ult.slow_seconds)
				enemy.slow_amount = float(ult.slow)
		"lightning":
			var range_sq := float(ult.range) * float(ult.range)
			var targets: Array[Entities.Enemy] = []
			for enemy: Entities.Enemy in sim.enemies:
				if player_pos.distance_squared_to(enemy.pos) <= range_sq:
					targets.append(enemy)
			var count := int(ult.count)
			for i in count:
				var pos: Vector2 = targets[i % targets.size()].pos if not targets.is_empty() else player_pos + sim.random_offset(float(ult.range))
				Combat.add_strike(sim, pos, float(ult.duration) * (i + 1) / count, damage, float(ult.radius), "ultimate", false)
	return true
