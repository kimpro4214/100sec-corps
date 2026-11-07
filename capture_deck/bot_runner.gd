extends SceneTree
## 사용법: godot --headless --path . --script res://capture_deck/bot_runner.gd -- --runs 300 --seed 1 --out res://playtest/capture_deck

const DeckSim := preload("res://capture_deck/sim/deck_sim.gd")
const BOTS := ["random", "planner", "always", "never", "explore"]


func _init() -> void:
	var args := _parse_args()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args.data))
	var runs: Array = []
	for bot in BOTS:
		for i in int(args.runs):
			runs.append(_play(bot, data, int(args.seed) + i))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(args.out))
	_write_runs(args.out, runs)
	_write_summary(args.out, runs, data.battle_tiers.size() + 1)
	_write_captures(args.out, runs)
	print("done: %d runs -> %s" % [runs.size(), args.out])
	quit()


func _parse_args() -> Dictionary:
	var args := {"runs": "300", "seed": "1", "out": "res://playtest/capture_deck", "data": "res://capture_deck/data/balance.json"}
	var user_args := OS.get_cmdline_user_args()
	for i in range(0, user_args.size() - 1, 2):
		args[user_args[i].trim_prefix("--")] = user_args[i + 1]
	return args


func _play(bot: String, data: Dictionary, run_seed: int) -> Dictionary:
	var sim = DeckSim.new(data, run_seed)
	var bot_rng := RandomNumberGenerator.new()
	bot_rng.seed = run_seed + 100000
	while not sim.is_over():
		match sim.phase:
			"choose_enemy":
				sim.choose_enemy(_pick_enemy(bot, sim, bot_rng))
			"combat":
				_play_turn(bot, sim, bot_rng)
			"reward":
				if _wants_capture(bot, sim, bot_rng):
					sim.capture()
				else:
					sim.skip_capture()
	return {
		"bot": bot, "seed": run_seed, "won": sim.phase == "won", "battle": sim.battle_index + 1, "hp": sim.hp,
		"death": sim.death_by, "captured": sim.captured.duplicate(), "history": sim.capture_history,
	}


func _play_turn(bot: String, sim, bot_rng: RandomNumberGenerator) -> void:
	while sim.phase == "combat":
		var playable: Array = []
		for i in sim.hand.size():
			if sim.can_play(i):
				playable.append(i)
		if playable.is_empty():
			break
		if bot == "random":
			if bot_rng.randf() < 0.1:
				break
			sim.play_card(playable[bot_rng.randi_range(0, playable.size() - 1)])
			continue
		var best: int = -1
		var best_score := 0.0
		for i in playable:
			var score := _card_score(sim, sim.hand[i])
			if score > best_score:
				best_score = score
				best = i
		if best < 0:
			break
		sim.play_card(best)
	if sim.phase == "combat":
		sim.end_turn()


func _card_score(sim, card_id: String) -> float:
	var def: Dictionary = sim.card_def(card_id)
	var incoming: int = sim.intent_damage()
	var need_block: int = max(0, incoming - sim.block)
	var enemy_left: int = sim.enemy.hp + sim.enemy.block
	var score := 0.0
	for effect in def.effects:
		var value := int(effect.get("value", 0))
		match effect.type:
			"damage":
				var total: int = (value + sim.strength) * int(effect.get("hits", 1))
				score += 100.0 if total >= enemy_left else total
			"block":
				score += min(value, need_block) * 1.5
			"draw":
				score += value * 8.0
			"heal":
				score += min(value, sim.max_hp - sim.hp)
			"poison":
				score += value * 1.5 if sim.enemy.hp > value else 0.0
			"strength":
				score += value * 3.0 if sim.hp > 15 else 0.0
	for effect in def.get("drawback", []):
		var value := int(effect.get("value", 1))
		match effect.type:
			"self_damage", "self_poison":
				score -= value * (3.0 if sim.hp <= value * 2 + need_block else 0.5)
			"max_hp_loss":
				score -= value
			_:
				score -= 2.0
	return score / max(1, int(def.cost))


func _pick_enemy(bot: String, sim, bot_rng: RandomNumberGenerator) -> int:
	if bot == "random" or bot == "explore":
		return bot_rng.randi_range(0, sim.enemy_choices.size() - 1)
	# 플레이어 체력이 낮으면 체력이 적은 적을, 넉넉하면 강한 카드를 주는 적을 고른다.
	var best := 0
	var best_hp: int = -1
	var healthy: bool = sim.hp > sim.max_hp * 0.6
	for i in sim.enemy_choices.size():
		var enemy_hp := int(sim.enemy_def(sim.enemy_choices[i]).hp)
		if best_hp < 0 or (healthy and enemy_hp > best_hp) or (not healthy and enemy_hp < best_hp):
			best_hp = enemy_hp
			best = i
	return best


func _wants_capture(bot: String, sim, bot_rng: RandomNumberGenerator) -> bool:
	match bot:
		"always":
			return true
		"never":
			return false
		"planner":
			return sim.hp > sim.max_hp * 0.5 and sim.captured.size() < 3
	return bot_rng.randf() < 0.5


func _write_runs(out: String, runs: Array) -> void:
	var lines := ["bot,seed,won,battle,hp,death,captured"]
	for run in runs:
		lines.append("%s,%d,%d,%d,%d,%s,%s" % [run.bot, run.seed, 1 if run.won else 0, run.battle, run.hp, run.death, "|".join(run.captured)])
	_write(out.path_join("runs.csv"), lines)


func _write_summary(out: String, runs: Array, battles: int) -> void:
	var header := "bot,runs,win_rate,avg_captured,avg_final_hp_on_win"
	for b in range(2, battles + 1):
		header += ",reach_battle_%d" % b
	var lines := [header]
	var death_lines := ["bot,death,count,share"]
	for bot in BOTS:
		var total := 0
		var wins := 0
		var captured := 0
		var win_hp := 0
		var reached := {}
		var deaths := {}
		for run in runs:
			if run.bot != bot:
				continue
			total += 1
			captured += run.captured.size()
			if run.won:
				wins += 1
				win_hp += run.hp
			else:
				deaths[run.death] = deaths.get(run.death, 0) + 1
			for b in range(2, int(run.battle) + 1):
				reached[b] = reached.get(b, 0) + 1
		var line := "%s,%d,%.3f,%.2f,%.1f" % [bot, total, float(wins) / total, float(captured) / total, float(win_hp) / max(wins, 1)]
		for b in range(2, battles + 1):
			line += ",%.3f" % (float(reached.get(b, 0)) / total)
		lines.append(line)
		var causes: Array = deaths.keys()
		causes.sort()
		for cause in causes:
			death_lines.append("%s,%s,%d,%.3f" % [bot, cause, deaths[cause], float(deaths[cause]) / total])
	_write(out.path_join("summary.csv"), lines)
	_write(out.path_join("deaths.csv"), death_lines)


func _write_captures(out: String, runs: Array) -> void:
	var lines := ["bot,enemy,defeated,captured,capture_rate,win_rate_when_captured,win_rate_when_skipped"]
	for bot in BOTS:
		var stats := {}
		for run in runs:
			if run.bot != bot:
				continue
			for entry in run.history:
				var stat: Dictionary = stats.get(entry.enemy, {"defeated": 0, "captured": 0, "captured_wins": 0, "skipped_wins": 0})
				stat.defeated += 1
				if entry.captured:
					stat.captured += 1
					stat.captured_wins += 1 if run.won else 0
				else:
					stat.skipped_wins += 1 if run.won else 0
				stats[entry.enemy] = stat
		var enemies: Array = stats.keys()
		enemies.sort()
		for enemy_id in enemies:
			var stat: Dictionary = stats[enemy_id]
			var skipped: int = stat.defeated - stat.captured
			lines.append("%s,%s,%d,%d,%.3f,%.3f,%.3f" % [
				bot, enemy_id, stat.defeated, stat.captured,
				float(stat.captured) / stat.defeated,
				float(stat.captured_wins) / max(stat.captured, 1),
				float(stat.skipped_wins) / max(skipped, 1),
			])
	_write(out.path_join("captures.csv"), lines)


func _write(path: String, lines: Array) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
