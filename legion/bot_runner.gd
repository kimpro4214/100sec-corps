extends SceneTree
## 사용법: godot --headless --path . --script res://legion/bot_runner.gd -- --runs 300 --seed 1 --out res://playtest/legion

const LegionSim := preload("res://legion/sim/legion_sim.gd")
const Interactables := preload("res://legion/sim/interactables.gd")
const BOTS := ["random", "survivor", "delay_awaken", "focus_bolt", "focus_aura", "focus_lightning", "focus_thread"]
const MAINS := ["bolt", "aura", "lightning", "thread"]
# 실이 메인일 때의 움직임: 피하는 힘의 비중과, 거기에 섞는 원 그리기의 빠르기(rad/초).
const THREAD_FLEE := 8.0
const THREAD_TURN := 3.2
const THREAD_AVOID := 70.0 # 과거의 나의 실에서 이 거리 안이면 물러난다


func _init() -> void:
	var args := _parse_args()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args.data))
	var bots: Array = BOTS if args.bots == "all" else args.bots.split("+")
	var runs: Array = []
	for bot in bots:
		for i in int(args.runs):
			runs.append(_play(bot, data, int(args.seed) + i))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(args.out))
	_write_runs(args.out, runs)
	_write_summary(args.out, runs, bots, int(data.rounds))
	_write_choices(args.out, runs, bots)
	_write_bosses(args.out, runs, bots, int(data.rounds))
	_write_damage(args.out, runs, bots)
	_write_mains(args.out, runs, bots)
	print("done: %d runs -> %s" % [runs.size(), args.out])
	quit()


func _parse_args() -> Dictionary:
	var args := {"runs": "300", "seed": "1", "out": "res://playtest/legion", "data": "res://legion/data/balance.json", "bots": "all"}
	var user_args := OS.get_cmdline_user_args()
	for i in range(0, user_args.size() - 1, 2):
		args[user_args[i].trim_prefix("--")] = user_args[i + 1]
	return args


func _play(bot: String, data: Dictionary, run_seed: int) -> Dictionary:
	var main: String = bot.trim_prefix("focus_") if bot.begins_with("focus_") else MAINS[run_seed % MAINS.size()]
	var sim = LegionSim.new(data, run_seed, main)
	var bot_rng := RandomNumberGenerator.new()
	bot_rng.seed = run_seed + 100000
	var wander := Vector2.ZERO
	var wander_time := 0.0
	while not sim.is_over():
		if not sim.pending_choices.is_empty():
			sim.choose(_pick(bot, sim, bot_rng))
			continue
		if not sim.round_summary.is_empty():
			sim.continue_round()
			continue
		if bot == "random":
			wander_time -= sim.tick
			if wander_time <= 0.0:
				wander = Vector2.from_angle(bot_rng.randf() * TAU)
				wander_time = bot_rng.randf_range(0.5, 2.0)
			sim.step(wander)
		else:
			if _wants_ultimate(sim):
				sim.use_ultimate()
			sim.step(_survivor_move(bot, sim))
	return {
		"bot": bot, "seed": run_seed, "won": sim.state == "won", "round": sim.round_index,
		"time": sim.time, "level": sim.level, "kills": sim.kills, "ghost_kills": sim.ghost_kills,
		"ghost_ttk_total": sim.ghost_ttk_total, "death": "" if sim.state == "won" else sim.last_hit,
		"picks": sim.picks, "build": sim.build, "boss_log": sim.boss_log, "damage": sim.damage_by_source,
		"main": main, "awaken_round": sim.awaken_round, "pickups": sim.pickups_taken, "ultimates": sim.ultimates_used,
		"interactions": sim.interactions,
	}


## 궁극기가 찼을 때 적에게 둘러싸였거나, 군단장 근처거나, 체력이 낮으면 쓴다.
func _wants_ultimate(sim) -> bool:
	if not sim.ultimate_ready():
		return false
	if sim.hp < sim.max_hp * 0.35:
		return true
	if sim.boss != null and sim.boss.hp > 0.0 and sim.boss.pos.distance_to(sim.player_pos) < 400.0:
		return true
	var near := 0
	for enemy in sim.enemies:
		if enemy.pos.distance_to(sim.player_pos) < 300.0:
			near += 1
	return near >= 15


func _pick(bot: String, sim, bot_rng: RandomNumberGenerator) -> int:
	if bot == "random":
		return bot_rng.randi_range(0, sim.pending_choices.size() - 1)
	var best := 0
	var best_score := -INF
	for i in sim.pending_choices.size():
		var option_id: String = sim.pending_choices[i]
		var option_level: int = sim.option_level(option_id)
		var score: float = 1.0 + option_level
		if option_id == sim.main_weapon:
			score += 20.0
			# 각성하면 과거의 나도 각성하므로 후반까지 미루는 전략.
			if bot == "delay_awaken" and sim.is_awakening_option(option_id) and sim.round_index < 4:
				score = -50.0
		elif option_id in sim.WEAPON_IDS:
			score -= 5.0
		elif sim.data.traits.has(option_id):
			score += 3.0
		if option_id == "vitality" and sim.hp < sim.max_hp * 0.5:
			score += 30.0
		if score > best_score:
			best_score = score
			best = i
	return best


func _survivor_move(bot: String, sim) -> Vector2:
	var move := Vector2.ZERO
	var pos: Vector2 = sim.player_pos
	# 오라가 메인이면 적에게 가까이 있어야 피해를 주므로 덜 도망친다.
	var melee: bool = sim.main_weapon == "aura"
	var ghost_reach := 150.0 if melee else 250.0
	var minion_reach := 90.0 if melee else 130.0
	for enemy in sim.enemies:
		var away: Vector2 = pos - enemy.pos
		var dist := away.length()
		var reach := minion_reach
		var weight := 1.0
		if enemy.kind == "ghost":
			reach = ghost_reach
			if int(enemy.build.weapons.aura) > 0:
				reach = maxf(reach, sim.weapon_stats("aura", enemy.build).radius * float(sim.data.weapons.aura.hostile_radius_mult) + 50.0)
			weight = 3.0
			# 과거의 나가 남긴 실은 밟으면 베이므로 가까운 실에서 물러난다.
			for point in enemy.trail:
				var from_thread: Vector2 = pos - point
				var thread_dist := from_thread.length()
				if thread_dist < THREAD_AVOID and thread_dist > 0.01:
					move += from_thread / thread_dist * (THREAD_AVOID - thread_dist) / THREAD_AVOID
		elif enemy.kind == "boss":
			reach = 130.0 if melee else 260.0
			weight = 4.0
		if dist < reach and dist > 0.01:
			move += away / dist * (reach - dist) / reach * weight
	if sim.boss != null and sim.boss_state != "idle" and sim.boss_pattern.type == "charge":
		var side: Vector2 = sim.charge_dir.orthogonal()
		var offset: float = (pos - sim.boss.pos).dot(side)
		move += side * (1.0 if offset >= 0.0 else -1.0) * 8.0
	for shot in sim.projectiles:
		if shot.hostile and pos.distance_to(shot.pos) < 150.0:
			move += shot.vel.normalized().orthogonal() * 1.5
	# 거미줄은 깔릴 자리와 깔린 자리 모두 피하고, 칼을 치켜들면 사거리 밖으로 물러난다.
	for zone in sim.zones:
		var away_zone: Vector2 = pos - zone.pos
		if away_zone.length() < zone.radius + 30.0:
			move += (away_zone.normalized() if away_zone != Vector2.ZERO else Vector2.RIGHT) * 4.0
	if sim.boss != null and sim.boss_state == "windup" and sim.boss_pattern.type == "slash":
		var away_boss: Vector2 = pos - sim.boss.pos
		if away_boss.length() < float(sim.boss_pattern.range) + 60.0:
			move += away_boss.normalized() * 8.0
	for strike in sim.strikes:
		var away: Vector2 = pos - strike.pos
		if away.length() < strike.radius + 40.0:
			move += (away.normalized() if away != Vector2.ZERO else Vector2.RIGHT) * 6.0
	var nearest_gem := Vector2.ZERO
	var gem_dist := 350.0
	for gem in sim.gems:
		var dist := pos.distance_to(gem.pos)
		if dist < gem_dist:
			gem_dist = dist
			nearest_gem = gem.pos - pos
	if nearest_gem != Vector2.ZERO:
		move += nearest_gem.normalized() * 0.7
	for item in sim.pickups:
		var want := 1.5 if item.kind == "magnet" else (4.0 if sim.hp < sim.max_hp * 0.6 else 0.5)
		if pos.distance_to(item.pos) < 500.0:
			move += (item.pos - pos).normalized() * want
	if sim.portal_open and not sim.in_boss_room:
		move += (sim.portal_pos - pos).normalized() * 3.0
	else:
		var target = _wanted_interactable(sim)
		if target != null:
			var to_target: Vector2 = target.pos - pos
			# 위에 올라서면 피하는 힘을 줄이고 작동할 때까지 버틴다.
			if to_target.length() < float(sim.data.interactables.radius) * 0.7:
				return move * 0.25 if move.length() > 2.0 else Vector2.ZERO
			move += to_target.normalized() * 2.5
	var center: Vector2 = sim.area.get_center()
	move += (center - pos) / (sim.area.size.length() * 0.5) * 1.2
	if sim.main_weapon == "thread":
		# 도망치며 뒤따르는 적을 실로 베는 것이 기본이고, 살짝 휘어 걸어 가끔 고리가 닫히게 한다.
		# 적 무리를 노려서 둘러싸지는 못한다. 고리의 가치는 사람이 플레이해서 확인해야 한다.
		# 보스 둘레를 돌게 하면 보스는 절반 시간에 잡지만 몸에 부딪혀 죽는다(ai_log 2026-11-10). 그래서 넣지 않았다.
		move = move.normalized() * THREAD_FLEE + Vector2.from_angle(sim.time * THREAD_TURN)
	return move.normalized() if move != Vector2.ZERO else Vector2.ZERO


## 가까운 상호작용 중 쓸 만한 것: 상자는 살 수 있으면, 룰렛은 금화가 두 판 이상 있을 때, 제단은 체력이 70% 넘을 때.
func _wanted_interactable(sim):
	var best = null
	var best_dist := 900.0
	for item in sim.interactables:
		if item.used or not Interactables.can_afford(sim, item.kind):
			continue
		if item.kind == "casino" and sim.gold < Interactables.gold_cost(sim, "casino") * 2:
			continue
		if item.kind == "shrine" and sim.hp < sim.max_hp * 0.7:
			continue
		var dist: float = sim.player_pos.distance_to(item.pos)
		if dist < best_dist:
			best_dist = dist
			best = item
	return best


func _write_runs(out: String, runs: Array) -> void:
	var lines := ["bot,seed,main,awaken_round,pickups,won,round,time,level,kills,ghost_kills,avg_ghost_ttk,bosses_killed,bosses_in_time,death,bolt,aura,lightning,thread,might,haste,vitality"]
	for run in runs:
		var build: Dictionary = run.build
		var in_time := 0
		for entry in run.boss_log:
			in_time += 1 if entry.in_time else 0
		lines.append("%s,%d,%s,%d,%d,%d,%d,%.1f,%d,%d,%d,%.1f,%d,%d,%s,%d,%d,%d,%d,%d,%d,%d" % [
			run.bot, run.seed, run.main, run.awaken_round, run.pickups, 1 if run.won else 0, run.round, run.time, run.level, run.kills, run.ghost_kills,
			run.ghost_ttk_total / maxi(run.ghost_kills, 1), run.boss_log.size(), in_time, run.death,
			build.weapons.bolt, build.weapons.aura, build.weapons.lightning, build.weapons.thread,
			build.upgrades.might, build.upgrades.haste, build.upgrades.vitality,
		])
	_write(out.path_join("runs.csv"), lines)


func _write_summary(out: String, runs: Array, bots: Array, rounds: int) -> void:
	var header := "bot,runs,win_rate,avg_level,avg_ghost_kills,avg_ghost_ttk,avg_ultimates,avg_interactions"
	for r in range(2, rounds + 1):
		header += ",reach_round_%d" % r
	var lines := [header]
	var death_lines := ["bot,death,count,share"]
	for bot in bots:
		var total := 0
		var wins := 0
		var levels := 0.0
		var ghost_kills := 0.0
		var ghost_ttk := 0.0
		var ultimates := 0.0
		var interactions := 0.0
		var reached := {}
		var deaths := {}
		for run in runs:
			if run.bot != bot:
				continue
			total += 1
			wins += 1 if run.won else 0
			levels += run.level
			ghost_kills += run.ghost_kills
			ghost_ttk += run.ghost_ttk_total
			ultimates += run.ultimates
			interactions += run.interactions
			for r in range(2, int(run.round) + 1):
				reached[r] = reached.get(r, 0) + 1
			if not run.won:
				deaths[run.death] = deaths.get(run.death, 0) + 1
		var line := "%s,%d,%.3f,%.1f,%.2f,%.1f,%.1f,%.1f" % [bot, total, float(wins) / total, levels / total, ghost_kills / total, ghost_ttk / maxf(ghost_kills, 1.0), ultimates / total, interactions / total]
		for r in range(2, rounds + 1):
			line += ",%.3f" % (float(reached.get(r, 0)) / total)
		lines.append(line)
		var causes: Array = deaths.keys()
		causes.sort()
		for cause in causes:
			death_lines.append("%s,%s,%d,%.3f" % [bot, cause, deaths[cause], float(deaths[cause]) / total])
	_write(out.path_join("summary.csv"), lines)
	_write(out.path_join("deaths.csv"), death_lines)


func _write_choices(out: String, runs: Array, bots: Array) -> void:
	var lines := ["bot,option,offered,chosen,pick_rate,win_rate_when_chosen"]
	for bot in bots:
		var offered := {}
		var chosen := {}
		var chosen_wins := {}
		for run in runs:
			if run.bot != bot:
				continue
			for pick in run.picks:
				for option_id in pick.offered:
					offered[option_id] = offered.get(option_id, 0) + 1
				chosen[pick.chosen] = chosen.get(pick.chosen, 0) + 1
				if run.won:
					chosen_wins[pick.chosen] = chosen_wins.get(pick.chosen, 0) + 1
		var options: Array = offered.keys()
		options.sort()
		for option_id in options:
			var chosen_count: int = chosen.get(option_id, 0)
			lines.append("%s,%s,%d,%d,%.3f,%.3f" % [
				bot, option_id, offered[option_id], chosen_count,
				float(chosen_count) / offered[option_id],
				float(chosen_wins.get(option_id, 0)) / chosen_count if chosen_count > 0 else 0.0,
			])
	_write(out.path_join("choices.csv"), lines)


func _write_bosses(out: String, runs: Array, bots: Array, rounds: int) -> void:
	var lines := ["bot,round,reached,killed,kill_rate,in_time_rate,avg_fight_time"]
	for bot in bots:
		for r in range(1, rounds + 1):
			var reached := 0
			var killed := 0
			var in_time := 0
			var fight_time := 0.0
			for run in runs:
				if run.bot != bot or int(run.round) < r:
					continue
				reached += 1
				for entry in run.boss_log:
					if int(entry.round) == r:
						killed += 1
						in_time += 1 if entry.in_time else 0
						fight_time += entry.fight_time
			if reached > 0:
				lines.append("%s,%d,%d,%d,%.3f,%.3f,%.1f" % [bot, r, reached, killed, float(killed) / reached, float(in_time) / maxi(killed, 1), fight_time / maxi(killed, 1)])
	_write(out.path_join("bosses.csv"), lines)


func _write_damage(out: String, runs: Array, bots: Array) -> void:
	var lines := ["bot,source,total_damage,share"]
	for bot in bots:
		var totals := {}
		var total := 0.0
		for run in runs:
			if run.bot != bot:
				continue
			for source in run.damage:
				totals[source] = totals.get(source, 0.0) + run.damage[source]
				total += run.damage[source]
		var sources: Array = totals.keys()
		sources.sort()
		for source in sources:
			lines.append("%s,%s,%.0f,%.3f" % [bot, source, totals[source], totals[source] / maxf(total, 1.0)])
	_write(out.path_join("damage.csv"), lines)


func _write_mains(out: String, runs: Array, bots: Array) -> void:
	var lines := ["bot,main,runs,win_rate,awaken_rate,avg_awaken_round,avg_level,avg_pickups"]
	for bot in bots:
		for main in MAINS:
			var total := 0
			var wins := 0
			var awakened := 0
			var awaken_rounds := 0
			var levels := 0
			var pickups := 0
			for run in runs:
				if run.bot != bot or run.main != main:
					continue
				total += 1
				wins += 1 if run.won else 0
				levels += run.level
				pickups += run.pickups
				if run.awaken_round > 0:
					awakened += 1
					awaken_rounds += run.awaken_round
			if total > 0:
				lines.append("%s,%s,%d,%.3f,%.3f,%.1f,%.1f,%.1f" % [
					bot, main, total, float(wins) / total, float(awakened) / total,
					float(awaken_rounds) / maxi(awakened, 1), float(levels) / total, float(pickups) / total,
				])
	_write(out.path_join("mains.csv"), lines)


func _write(path: String, lines: Array) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
