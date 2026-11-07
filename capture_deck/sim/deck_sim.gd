extends RefCounted
## 포획 덱의 게임 규칙. 화면과 봇이 같은 코드를 사용한다.

var data: Dictionary
var rng := RandomNumberGenerator.new()

var phase := "choose_enemy" # choose_enemy, combat, reward, won, lost
var battle_index := 0
var enemy_choices: Array = []

var max_hp := 0
var hp := 0
var deck: Array = []
var draw_pile: Array = []
var hand: Array = []
var discard: Array = []

var energy := 0
var block := 0
var strength := 0
var poison := 0
var next_draw_penalty := 0
var next_energy_penalty := 0

var enemy := {}
var enemy_intent := {}
var captured: Array = []
var log_lines: Array = []
var pick_history: Array = []
var capture_history: Array = []
var death_by := ""


func _init(balance: Dictionary, run_seed: int) -> void:
	data = balance
	rng.seed = run_seed
	max_hp = int(data.player.hp)
	hp = max_hp
	deck = data.start_deck.duplicate()
	_roll_enemy_choices()


func is_over() -> bool:
	return phase == "won" or phase == "lost"


func is_boss_battle() -> bool:
	return battle_index >= data.battle_tiers.size()


func card_def(card_id: String) -> Dictionary:
	return data.cards[card_id]


func enemy_def(enemy_id: String) -> Dictionary:
	return data.boss if enemy_id == data.boss.id else data.enemies[enemy_id]


func can_play(hand_index: int) -> bool:
	var cost := int(card_def(hand[hand_index]).cost)
	return cost >= 0 and cost <= energy


func choose_enemy(index: int) -> void:
	var enemy_id: String = enemy_choices[index]
	pick_history.append({"offered": enemy_choices.duplicate(), "chosen": enemy_id})
	var def := enemy_def(enemy_id)
	enemy = {"id": enemy_id, "name": def.name, "hp": int(def.hp), "max_hp": int(def.hp), "block": 0, "strength": 0, "poison": 0, "pattern_index": 0}
	enemy_intent = def.pattern[0]
	draw_pile = deck.duplicate()
	_shuffle(draw_pile)
	hand = []
	discard = []
	strength = 0
	poison = 0
	block = 0
	next_draw_penalty = 0
	next_energy_penalty = 0
	phase = "combat"
	log_lines.append("%s 전투 시작" % def.name)
	_start_turn()


func play_card(hand_index: int) -> void:
	if phase != "combat" or not can_play(hand_index):
		return
	var card_id: String = hand[hand_index]
	var def := card_def(card_id)
	energy -= int(def.cost)
	hand.remove_at(hand_index)
	if not def.get("exhaust", false):
		discard.append(card_id)
	log_lines.append("%s 사용" % def.name)
	for effect in def.effects:
		_apply_effect(effect)
	for effect in def.get("drawback", []):
		_apply_effect(effect)
	_check_battle_end("자해")


func end_turn() -> void:
	if phase != "combat":
		return
	discard.append_array(hand)
	hand = []
	if enemy.poison > 0:
		enemy.hp -= enemy.poison
		log_lines.append("%s 독 피해 %d" % [enemy.name, enemy.poison])
		enemy.poison -= 1
		_check_battle_end("")
		if phase != "combat":
			return
	enemy.block = 0
	_enemy_act()
	_check_battle_end(enemy.name)
	if phase == "combat":
		_start_turn()


func capture() -> void:
	var def := enemy_def(enemy.id)
	var card_id: String = def.capture_card
	deck.append(card_id)
	captured.append(card_id)
	capture_history.append({"enemy": enemy.id, "captured": true})
	log_lines.append("%s 포획: %s 획득" % [enemy.name, card_def(card_id).name])
	_next_battle()


func skip_capture() -> void:
	var heal_amount := int(data.skip_heal)
	hp = min(max_hp, hp + heal_amount)
	capture_history.append({"enemy": enemy.id, "captured": false})
	log_lines.append("포획하지 않고 체력 %d 회복" % heal_amount)
	_next_battle()


func intent_damage() -> int:
	if enemy_intent.type != "attack" and enemy_intent.type != "drain":
		return 0
	return _attack_value(enemy_intent) * int(enemy_intent.get("hits", 1))


func _attack_value(intent: Dictionary) -> int:
	var bonus := 0
	if enemy.id == data.boss.id:
		bonus = int(data.boss.bonus_damage_per_capture) * captured.size()
	return int(intent.value) + int(enemy.strength) + bonus


func _start_turn() -> void:
	block = 0
	if poison > 0:
		hp -= poison
		log_lines.append("독 피해 %d" % poison)
		poison -= 1
		_check_battle_end("독")
		if phase != "combat":
			return
	energy = max(0, int(data.player.energy) - next_energy_penalty)
	var draw_count: int = max(0, int(data.player.draw) - next_draw_penalty)
	next_energy_penalty = 0
	next_draw_penalty = 0
	_draw(draw_count)


func _draw(count: int) -> void:
	for i in count:
		if draw_pile.is_empty():
			if discard.is_empty():
				return
			draw_pile = discard
			discard = []
			_shuffle(draw_pile)
		hand.append(draw_pile.pop_back())


func _shuffle(cards: Array) -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = cards[i]
		cards[i] = cards[j]
		cards[j] = swap


func _apply_effect(effect: Dictionary) -> void:
	var value := int(effect.get("value", 0))
	match effect.type:
		"damage":
			for i in int(effect.get("hits", 1)):
				_hit_enemy(value + strength)
		"block":
			block += value
		"draw":
			_draw(value)
		"heal":
			hp = min(max_hp, hp + value)
		"poison":
			enemy.poison += value
		"strength":
			strength += value
		"self_damage":
			hp -= value
		"self_poison":
			poison += value
		"max_hp_loss":
			max_hp -= value
			hp = min(hp, max_hp)
		"next_draw_penalty":
			next_draw_penalty += value
		"next_energy_penalty":
			next_energy_penalty += value
		"add_junk":
			discard.append(effect.card)
		"discard_random":
			for i in value:
				if hand.is_empty():
					break
				discard.append(hand.pop_at(rng.randi_range(0, hand.size() - 1)))


func _hit_enemy(amount: int) -> void:
	var blocked: int = min(enemy.block, amount)
	enemy.block -= blocked
	enemy.hp -= amount - blocked


func _hit_player(amount: int) -> int:
	var blocked: int = min(block, amount)
	block -= blocked
	hp -= amount - blocked
	return amount - blocked


func _enemy_act() -> void:
	var intent := enemy_intent
	match intent.type:
		"attack":
			var dealt := 0
			for i in int(intent.get("hits", 1)):
				dealt += _hit_player(_attack_value(intent))
			log_lines.append("%s 공격: 피해 %d" % [enemy.name, dealt])
		"drain":
			var dealt := _hit_player(_attack_value(intent))
			enemy.hp = min(enemy.max_hp, enemy.hp + dealt)
			log_lines.append("%s 흡혈: 피해 %d" % [enemy.name, dealt])
		"block":
			enemy.block += int(intent.value)
			log_lines.append("%s 방어 %d" % [enemy.name, int(intent.value)])
		"poison":
			poison += int(intent.value)
			log_lines.append("%s 독 부여 %d" % [enemy.name, int(intent.value)])
		"strength":
			enemy.strength += int(intent.value)
			log_lines.append("%s 힘 +%d" % [enemy.name, int(intent.value)])
	var pattern: Array = enemy_def(enemy.id).pattern
	enemy.pattern_index = (enemy.pattern_index + 1) % pattern.size()
	enemy_intent = pattern[enemy.pattern_index]


func _check_battle_end(death_source: String) -> void:
	if hp <= 0:
		hp = 0
		phase = "lost"
		death_by = "%s@%s" % [death_source, enemy.id]
	elif enemy.hp <= 0:
		enemy.hp = 0
		log_lines.append("%s 처치" % enemy.name)
		phase = "won" if is_boss_battle() else "reward"


func _next_battle() -> void:
	battle_index += 1
	_roll_enemy_choices()
	phase = "choose_enemy"


func _roll_enemy_choices() -> void:
	if is_boss_battle():
		enemy_choices = [data.boss.id]
		return
	var tier := int(data.battle_tiers[battle_index])
	var pool: Array = []
	var ids: Array = data.enemies.keys()
	ids.sort()
	for enemy_id in ids:
		if int(data.enemies[enemy_id].tier) == tier:
			pool.append(enemy_id)
	_shuffle(pool)
	enemy_choices = pool.slice(0, int(data.enemy_choices))
