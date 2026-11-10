extends RefCounted
## 빌드(무기, 특성, 공통 강화 레벨)에서 수치를 계산하는 순수 함수 모음.
## 게임 상태를 읽거나 바꾸지 않으므로, 플레이어 빌드와 과거의 나 빌드에 똑같이 쓴다.

const WEAPON_IDS := ["bolt", "aura", "lightning", "thread"]
const UPGRADE_IDS := ["might", "haste", "vitality"]
# 모든 선택지를 다 올린 뒤에만 나오는 작은 강화. 상한 없이 쌓인다.
const MINOR_IDS := ["might_shard", "haste_shard", "vitality_shard"]


static func new_build(data: Dictionary, main_id: String) -> Dictionary:
	var trait_levels := {}
	for trait_id in data.traits:
		trait_levels[trait_id] = 0
	var build := {
		"main": main_id,
		"weapons": {"bolt": 0, "aura": 0, "lightning": 0, "thread": 0},
		"traits": trait_levels,
		"upgrades": {"might": 0, "haste": 0, "vitality": 0},
		"minor": {"might_shard": 0, "haste_shard": 0, "vitality_shard": 0},
	}
	build.weapons[main_id] = 1
	return build


static func level_of(data: Dictionary, build: Dictionary, option_id: String) -> int:
	if option_id in WEAPON_IDS:
		return int(build.weapons[option_id])
	if data.traits.has(option_id):
		return int(build.traits[option_id])
	if option_id in MINOR_IDS:
		return int(build.minor[option_id])
	return int(build.upgrades[option_id])


static func option_def(data: Dictionary, option_id: String) -> Dictionary:
	if option_id in WEAPON_IDS:
		return data.weapons[option_id]
	if data.traits.has(option_id):
		return data.traits[option_id]
	if option_id in MINOR_IDS:
		return data.minor_upgrades[option_id]
	return data.upgrades[option_id]


static func option_max(data: Dictionary, main_id: String, option_id: String) -> int:
	if option_id == main_id:
		return int(data.max_levels.main)
	if option_id in WEAPON_IDS:
		return int(data.max_levels.sub)
	if data.traits.has(option_id):
		return int(data.max_levels.trait)
	return int(data.max_levels.upgrade)


static func apply_option(data: Dictionary, build: Dictionary, option_id: String) -> void:
	if option_id in WEAPON_IDS:
		build.weapons[option_id] += 1
	elif data.traits.has(option_id):
		build.traits[option_id] += 1
	elif option_id in MINOR_IDS:
		build.minor[option_id] += 1
	else:
		build.upgrades[option_id] += 1


static func is_awakened(data: Dictionary, build: Dictionary) -> bool:
	return int(build.weapons[build.main]) >= int(data.max_levels.main)


static func dominant_weapon(build: Dictionary) -> String:
	return build.main


## 레벨, 특성, 각성, 공통 강화를 합친 무기의 실제 수치.
static func weapon_stats(data: Dictionary, weapon_id: String, build: Dictionary) -> Dictionary:
	var weapon: Dictionary = data.weapons[weapon_id]
	var weapon_level := int(build.weapons[weapon_id])
	var stats := {
		"damage": float(weapon.damage) + float(weapon.damage_per_level) * (weapon_level - 1),
		"count": 1,
		"radius": float(weapon.radius) + float(weapon.get("radius_per_level", 0.0)) * (weapon_level - 1),
		"cooldown": float(weapon.cooldown),
		"pierce": 0, "leech": 0.0, "slow": 0.0, "knockback": 0.0,
		"splash_radius": 0.0, "splash_mult": 0.0, "echo_delay": 0.0,
		"length": float(weapon.get("length", 0.0)) + float(weapon.get("length_per_level", 0.0)) * (weapon_level - 1),
		"loop_mult": float(weapon.get("loop_mult", 0.0)), "pull": 0.0,
	}
	if weapon.has("count_every_levels"):
		stats.count += int((weapon_level - 1) / float(weapon.count_every_levels))
	for trait_id in data.traits:
		var trait_def: Dictionary = data.traits[trait_id]
		var trait_level := int(build.traits[trait_id])
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
			"length":
				stats.length += amount
			"loop":
				stats.loop_mult += amount
	if weapon_level >= int(data.max_levels.main):
		var awaken: Dictionary = weapon.awaken
		stats.damage *= float(awaken.get("damage_mult", 1.0))
		stats.count = stats.count * int(awaken.get("count_mult", 1)) + int(awaken.get("extra_count", 0))
		stats.radius *= float(awaken.get("radius_mult", 1.0))
		stats.knockback = float(awaken.get("knockback", 0.0))
		stats.splash_radius = float(awaken.get("splash_radius", 0.0))
		stats.splash_mult = float(awaken.get("splash_mult", 0.0))
		stats.echo_delay = float(awaken.get("echo_delay", 0.0))
		stats.length *= float(awaken.get("length_mult", 1.0))
		stats.pull = float(awaken.get("pull", 0.0))
	stats.damage *= _might_mult(data, build)
	stats.cooldown *= _cooldown_mult(data, build)
	return stats


static func build_dps(data: Dictionary, build: Dictionary) -> float:
	var total := 0.0
	for weapon_id in WEAPON_IDS:
		if int(build.weapons[weapon_id]) <= 0:
			continue
		var stats := weapon_stats(data, weapon_id, build)
		var hits: float = 2.0 if stats.echo_delay > 0.0 else 1.0
		total += stats.damage * stats.count * hits / stats.cooldown * float(data.weapons[weapon_id].single_target_weight)
	return total


## 각성은 화력이 크게 뛰므로, 적 체력 계산에서는 각성 직전 화력에 정해진 배수만 곱한다.
static func enemy_scaling_dps(data: Dictionary, build: Dictionary) -> float:
	if not is_awakened(data, build):
		return build_dps(data, build)
	var before: Dictionary = build.duplicate(true)
	before.weapons[build.main] -= 1
	return build_dps(data, before) * float(data.awaken_scaling_mult)


static func ghost_hp(data: Dictionary, build: Dictionary, age: int) -> float:
	var ghost_def: Dictionary = data.ghost
	var scaled := enemy_scaling_dps(data, build) * float(ghost_def.target_ttk) * (1.0 + float(ghost_def.hp_per_age) * age)
	return maxf(float(ghost_def.hp_min), scaled)


## 복제본은 주력 무기만 사용해 탄막이 과도하게 쌓이지 않게 한다.
static func copy_build(build: Dictionary) -> Dictionary:
	var result: Dictionary = build.duplicate(true)
	var main := dominant_weapon(build)
	for weapon_id in WEAPON_IDS:
		if weapon_id != main:
			result.weapons[weapon_id] = 0
	return result


static func _might_mult(data: Dictionary, build: Dictionary) -> float:
	return 1.0 + float(data.upgrades.might.value) * int(build.upgrades.might) \
		+ float(data.minor_upgrades.might_shard.value) * int(build.minor.might_shard)


static func _cooldown_mult(data: Dictionary, build: Dictionary) -> float:
	var reduced := 1.0 - float(data.upgrades.haste.value) * int(build.upgrades.haste) \
		- float(data.minor_upgrades.haste_shard.value) * int(build.minor.haste_shard)
	return maxf(float(data.min_cooldown_mult), reduced)
