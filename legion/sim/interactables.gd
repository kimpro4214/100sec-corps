extends RefCounted
## 필드의 보물상자, 룰렛, 제단. 라운드마다 새로 놓이고, 위에 activate_seconds초 서 있으면 대가를 내고 작동한다.
## 레벨 업 보상은 선택지로 빌드에 들어가므로 다음 라운드의 과거의 나에게도 복사된다.
## 보호막, 광폭, 폭탄 같은 1회용 효과는 빌드에 남지 않는다.

const Entities := preload("res://legion/sim/entities.gd")
const BossRoom := preload("res://legion/sim/boss_room.gd")
const Combat := preload("res://legion/sim/combat.gd")
const Progression := preload("res://legion/sim/progression.gd")
const Spawner := preload("res://legion/sim/spawner.gd")


## 필드 곳곳에 종류별 개수만큼 놓는다. 시작 위치(필드 가운데)와는 떨어뜨린다.
static func place(sim) -> void:
	sim.interactables.clear()
	var cfg: Dictionary = sim.data.interactables
	var field := BossRoom.field_rect(sim.data).grow(-float(cfg.edge_margin))
	var start: Vector2 = BossRoom.field_rect(sim.data).get_center()
	for kind in cfg.kinds:
		for i in int(cfg.kinds[kind].count):
			var item := Entities.Interactable.new()
			item.kind = kind
			for attempt in 8:
				item.pos = field.position + Vector2(sim.rng.randf() * field.size.x, sim.rng.randf() * field.size.y)
				if item.pos.distance_to(start) >= float(cfg.min_distance):
					break
			sim.interactables.append(item)


## 이 라운드에 이 오브젝트를 쓰는 데 드는 금화. 제단처럼 체력을 내는 것은 0이다.
static func gold_cost(sim, kind: String) -> int:
	var def: Dictionary = sim.data.interactables.kinds[kind]
	return int(def.get("cost", 0)) + int(def.get("cost_per_round", 0)) * (sim.round_index - 1)


static func can_afford(sim, kind: String) -> bool:
	var def: Dictionary = sim.data.interactables.kinds[kind]
	if def.has("cost_hp"):
		return sim.hp > sim.max_hp * float(def.cost_hp)
	return sim.gold >= gold_cost(sim, kind)


static func update(sim) -> void:
	if sim.in_boss_room:
		return
	var cfg: Dictionary = sim.data.interactables
	var reach := float(cfg.radius) + float(sim.data.player.radius)
	for item in sim.interactables:
		if item.used:
			continue
		if sim.player_pos.distance_to(item.pos) > reach or not can_afford(sim, item.kind):
			item.progress = 0.0
			continue
		item.progress += sim.tick
		if item.progress >= float(cfg.activate_seconds):
			_activate(sim, item)


static func _activate(sim, item: Entities.Interactable) -> void:
	var def: Dictionary = sim.data.interactables.kinds[item.kind]
	if def.has("cost_hp"):
		sim.hp -= sim.max_hp * float(def.cost_hp)
	else:
		sim.gold -= gold_cost(sim, item.kind)
	item.progress = 0.0
	item.used = not bool(def.repeat)
	var reward := _roll(sim, def.rewards)
	item.last_reward = reward.type
	sim.interactions += 1
	_apply(sim, item, reward)
	sim.emit_event({"type": "interact", "kind": item.kind, "reward": reward.type, "pos": item.pos})


static func _roll(sim, rewards: Array) -> Dictionary:
	var total := 0.0
	for reward in rewards:
		total += float(reward.weight)
	var roll: float = sim.rng.randf() * total
	for reward in rewards:
		roll -= float(reward.weight)
		if roll <= 0.0:
			return reward
	return rewards[-1]


static func _apply(sim, item: Entities.Interactable, reward: Dictionary) -> void:
	match reward.type:
		"level":
			sim.queued_levels += 1
		"jackpot":
			sim.queued_levels += int(reward.levels)
		"heal":
			sim.hp = minf(sim.max_hp, sim.hp + sim.max_hp * float(reward.value))
		"shield":
			sim.ult_guard = maxf(sim.ult_guard, float(reward.seconds))
		"frenzy":
			sim.frenzy_time = float(reward.seconds)
			sim.frenzy_amount = float(reward.value)
		"bomb":
			Combat.damage_area(sim, sim.player_pos, float(reward.radius), float(reward.damage), "ultimate")
		"refund":
			sim.gold += gold_cost(sim, item.kind) * int(reward.mult)
		"ambush":
			Spawner.ambush(sim, int(reward.count))
	Progression.offer_next_level(sim)
