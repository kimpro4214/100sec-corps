extends RefCounted
## 경험치, 레벨 업 선택지 생성, 선택 적용.

const BuildRules := preload("res://legion/sim/build_rules.gd")


static func gain_xp(sim, amount: int) -> void:
	sim.xp += amount
	while sim.xp >= sim.xp_needed():
		sim.xp -= sim.xp_needed()
		sim.level += 1
		sim.queued_levels += 1
	offer_next_level(sim)


static func offer_next_level(sim) -> void:
	if sim.queued_levels <= 0 or not sim.pending_choices.is_empty():
		return
	var available: Array = []
	var weights: Array = []
	for option_id in _option_pool(sim):
		if sim.is_awakening_option(option_id) and sim.round_index < int(sim.data.awaken_min_round):
			continue
		if sim.option_level(option_id) < BuildRules.option_max(sim.data, sim.main_weapon, option_id):
			available.append(option_id)
			weights.append(_option_weight(sim, option_id))
	sim.queued_levels -= 1
	# 모두 다 올렸으면 상한 없는 작은 강화를 고르게 한다.
	if available.is_empty():
		sim.pending_choices = BuildRules.MINOR_IDS.duplicate()
		return
	sim.pending_choices = []
	while sim.pending_choices.size() < 3 and not available.is_empty():
		var index := _weighted_index(sim, weights)
		sim.pending_choices.append(available.pop_at(index))
		weights.remove_at(index)


static func choose(sim, index: int) -> void:
	var option_id: String = sim.pending_choices[index]
	sim.picks.append({"offered": sim.pending_choices.duplicate(), "chosen": option_id})
	var awakens: bool = sim.is_awakening_option(option_id)
	BuildRules.apply_option(sim.data, sim.build, option_id)
	if option_id == "vitality" or option_id == "vitality_shard":
		var bonus := float(BuildRules.option_def(sim.data, option_id).value)
		sim.max_hp += bonus
		sim.hp = minf(sim.hp + bonus, sim.max_hp)
	if awakens:
		sim.awaken_round = sim.round_index
		sim.emit_event({"type": "awaken", "name": sim.data.weapons[sim.main_weapon].awaken.name})
	sim.pending_choices = []
	offer_next_level(sim)


## 메인 무기, 메인 무기의 특성, 공통 강화, 보조 무기만 선택지로 나온다.
static func _option_pool(sim) -> Array:
	var pool: Array = BuildRules.WEAPON_IDS + BuildRules.UPGRADE_IDS
	for trait_id in sim.data.traits:
		if sim.data.traits[trait_id].weapon == sim.main_weapon:
			pool.append(trait_id)
	return pool


static func _option_weight(sim, option_id: String) -> float:
	var offer: Dictionary = sim.data.offer_weights
	if option_id == sim.main_weapon:
		return float(offer.main)
	if option_id in BuildRules.WEAPON_IDS:
		return float(offer.sub)
	if sim.data.traits.has(option_id):
		return float(offer.trait)
	return float(offer.upgrade)


static func _weighted_index(sim, weights: Array) -> int:
	var total := 0.0
	for weight in weights:
		total += float(weight)
	var roll: float = sim.rng.randf() * total
	for i in weights.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			return i
	return weights.size() - 1
