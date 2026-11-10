extends SceneTree
## 시간의 실 규칙 테스트. 실패하면 종료 코드 1.
## 사용법: godot --headless --path . --script res://legion/test_thread.gd

const LegionSim := preload("res://legion/sim/legion_sim.gd")
const Entities := preload("res://legion/sim/entities.gd")
const Spawner := preload("res://legion/sim/spawner.gd")

var failures := 0


func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://legion/data/balance.json"))
	# 잡몹과 웨이브가 끼어들지 않게 한다.
	data.spawn.base_rate = 0.0
	data.spawn.ramp_per_second = 0.0
	data.waves.times = []
	_test_loop_hits_inside_only(data)
	_test_retrace_is_not_loop(data)
	_test_trail_cuts(data)
	_test_ghost_loop_is_telegraphed(data)
	print("thread tests: %s" % ("ok" if failures == 0 else "%d failed" % failures))
	quit(1 if failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: " + what)


func _walk(sim, dir: Vector2, seconds: float) -> void:
	for i in int(round(seconds / sim.tick)):
		sim.step(dir)


func _dummy(sim, pos: Vector2) -> Entities.Enemy:
	var enemy := Entities.Enemy.new()
	enemy.kind = "grunt"
	enemy.pos = pos
	enemy.prev = pos
	enemy.hp = 1000.0
	enemy.max_hp = 1000.0
	enemy.radius = 12.0
	sim.enemies.append(enemy)
	return enemy


## 한 변 약 108인 정사각형을 시계 방향으로 한 바퀴 걷는다.
func _walk_square(sim) -> void:
	for dir in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
		_walk(sim, dir, 0.5)


func _test_loop_hits_inside_only(data: Dictionary) -> void:
	var sim = LegionSim.new(data, 1, "thread")
	sim.record_events = true
	var start: Vector2 = sim.player_pos
	var inside := _dummy(sim, start + Vector2(54, 54))
	var outside := _dummy(sim, start + Vector2(54, 300))
	_walk_square(sim)
	var loops: Array = sim.events.filter(func(event: Dictionary) -> bool: return event.type == "loop")
	var stats: Dictionary = sim.weapon_stats("thread", sim.build)
	_check(loops.size() == 1, "정사각형을 걸으면 고리가 한 번 닫힌다 (%d번)" % loops.size())
	_check(is_equal_approx(1000.0 - inside.hp, stats.damage * stats.loop_mult), "고리 안의 적은 고리 피해를 받는다 (%.1f)" % (1000.0 - inside.hp))
	_check(outside.hp == 1000.0, "고리 밖의 적은 피해가 없다")
	_check(sim.trail.size() == 1, "고리가 닫히면 실이 새로 풀린다")
	_check(inside.looped and not outside.looped, "고리에 맞은 적만 표시된다 (죽으면 보석이 날아온다)")


func _test_retrace_is_not_loop(data: Dictionary) -> void:
	var sim = LegionSim.new(data, 1, "thread")
	sim.record_events = true
	_walk(sim, Vector2.RIGHT, 1.0)
	_walk(sim, Vector2.LEFT, 1.0)
	_check(not sim.events.any(func(event: Dictionary) -> bool: return event.type == "loop"), "온 길을 되짚으면 고리가 아니다")


func _test_trail_cuts(data: Dictionary) -> void:
	var sim = LegionSim.new(data, 1, "thread")
	var start: Vector2 = sim.player_pos
	var on_trail := _dummy(sim, start + Vector2(60, 0))
	var far := _dummy(sim, start + Vector2(60, 200))
	_walk(sim, Vector2.RIGHT, 1.0)
	_check(on_trail.hp < 1000.0, "실 위의 적은 베인다")
	_check(far.hp == 1000.0, "실에서 먼 적은 베이지 않는다")


## 과거의 나가 닫은 고리는 예고 뒤에 터지고, 그때 안에 있어야 맞는다.
func _test_ghost_loop_is_telegraphed(data: Dictionary) -> void:
	var sim = LegionSim.new(data, 1, "bolt")
	var past: Dictionary = sim.build.duplicate(true)
	past.main = "thread"
	past.weapons = {"bolt": 0, "aura": 0, "lightning": 0, "thread": 1}
	sim.past_builds.append(past)
	sim.past_paths.append(PackedVector2Array())
	sim.round_index = 2
	var center: Vector2 = sim.player_pos
	Spawner.add_ghost(sim, 0, 1.0, 1.0, false, center + Vector2(-54, -54))
	var ghost: Entities.Enemy = sim.enemies[0]
	ghost.speed = 0.0
	ghost.contact = 0.0
	# 플레이어를 가운데 두고 과거의 나를 정사각형으로 옮긴다.
	var hp_before: float = sim.hp
	var corners := [Vector2(54, -54), Vector2(54, 54), Vector2(-54, 54), Vector2(-54, -54)]
	for corner in corners:
		for i in 10:
			ghost.pos = ghost.pos.move_toward(center + corner, 10.8)
			sim.step(Vector2.ZERO)
		if not sim.strikes.is_empty():
			break
	_check(sim.strikes.size() == 1 and not sim.strikes[0].polygon.is_empty(), "과거의 나의 고리는 예고(고리 모양 낙뢰)가 된다")
	_check(sim.hp == hp_before, "예고 동안에는 피해가 없다")
	ghost.pos = center + Vector2(600, 600)
	_walk(sim, Vector2.ZERO, float(data.ghost.strike_delay) + 0.1)
	_check(sim.hp < hp_before, "예고가 끝날 때 고리 안에 있으면 맞는다")
	_check(sim.last_hit == "ghost_thread", "피해 원인은 ghost_thread (%s)" % sim.last_hit)
