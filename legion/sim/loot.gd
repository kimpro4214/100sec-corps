extends RefCounted
## 경험치 보석 수집과 필드 아이템(자석, 포션)의 생성, 획득.

const Entities := preload("res://legion/sim/entities.gd")
const Progression := preload("res://legion/sim/progression.gd")


static func collect_gems(sim) -> void:
	var radius_sq := float(sim.data.player.pickup_radius) * float(sim.data.player.pickup_radius)
	var magnet_step: float = float(sim.data.items.magnet.speed) * sim.tick
	var remaining: Array[Entities.Gem] = []
	for gem: Entities.Gem in sim.gems:
		if gem.attracted:
			gem.pos = gem.pos.move_toward(sim.player_pos, magnet_step)
		if gem.pos.distance_squared_to(sim.player_pos) <= radius_sq:
			take_gem(sim, gem)
		else:
			remaining.append(gem)
	sim.gems = remaining


## 보석은 경험치, 금화는 금화로 받는다.
static func take_gem(sim, gem: Entities.Gem) -> void:
	if gem.gold:
		sim.gold += gem.value
	else:
		Progression.gain_xp(sim, gem.value)


static func update_pickups(sim) -> void:
	var items: Dictionary = sim.data.items
	sim.pickup_timer -= sim.tick
	if sim.pickup_timer <= 0.0:
		sim.pickup_timer = float(items.interval)
		var distance: float = sim.rng.randf_range(float(items.min_distance), float(items.max_distance))
		add_pickup(sim, sim.clamp_to_arena(sim.player_pos + Vector2.from_angle(sim.rng.randf() * TAU) * distance))
	var reach := float(items.radius) + float(sim.data.player.radius)
	var remaining: Array[Entities.Pickup] = []
	for item: Entities.Pickup in sim.pickups:
		item.life -= sim.tick
		if item.pos.distance_to(sim.player_pos) <= reach:
			_use_pickup(sim, item.kind)
		elif item.life > 0.0:
			remaining.append(item)
	sim.pickups = remaining


static func add_pickup(sim, pos: Vector2) -> void:
	var items: Dictionary = sim.data.items
	var magnet_weight := float(items.magnet.weight)
	var roll: float = sim.rng.randf() * (magnet_weight + float(items.potion.weight))
	var item := Entities.Pickup.new()
	item.kind = "magnet" if roll < magnet_weight else "potion"
	item.pos = pos
	item.life = float(items.life)
	sim.pickups.append(item)


static func _use_pickup(sim, kind: String) -> void:
	sim.pickups_taken += 1
	if kind == "magnet":
		for gem: Entities.Gem in sim.gems:
			gem.attracted = true
	else:
		sim.hp = minf(sim.max_hp, sim.hp + sim.max_hp * float(sim.data.items.potion.heal_ratio))
	sim.emit_event({"type": "pickup", "kind": kind, "name": sim.data.items[kind].name})
