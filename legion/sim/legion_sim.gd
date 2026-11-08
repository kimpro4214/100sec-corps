extends RefCounted
## 100초 군단의 게임 상태와 한 틱의 진행 순서. 화면과 봇이 같은 코드를 사용한다.
## 상태는 모두 여기에 두고, 규칙은 책임별 시스템 파일의 정적 함수가 이 객체를 받아 처리한다.
##   build_rules: 빌드 수치 계산 (순수 함수)
##   combat: 무기, 탄, 낙뢰, 피해, 사망 처리
##   enemy_ai / boss: 적 이동과 군단장 패턴
##   spawner: 잡몹, 웨이브, 과거의 나 생성
##   loot / progression: 보석, 아이템, 경험치, 레벨 업
##   ultimate: 궁극기
##   boss_room: 필드에서 보스 방으로 넘어가는 포탈
##   interactables: 필드의 보물상자, 룰렛, 제단

const Entities := preload("res://legion/sim/entities.gd")
const BuildRules := preload("res://legion/sim/build_rules.gd")
const Combat := preload("res://legion/sim/combat.gd")
const EnemyAI := preload("res://legion/sim/enemy_ai.gd")
const Boss := preload("res://legion/sim/boss.gd")
const Spawner := preload("res://legion/sim/spawner.gd")
const Loot := preload("res://legion/sim/loot.gd")
const Progression := preload("res://legion/sim/progression.gd")
const Ultimate := preload("res://legion/sim/ultimate.gd")
const BossRoom := preload("res://legion/sim/boss_room.gd")
const Interactables := preload("res://legion/sim/interactables.gd")

const WEAPON_IDS := BuildRules.WEAPON_IDS
const UPGRADE_IDS := BuildRules.UPGRADE_IDS

var data: Dictionary
var rng := RandomNumberGenerator.new()
var tick: float
var record_events := false
var events: Array = []

var state := "playing" # playing, won, lost
var round_index := 1
var round_time := 0.0
var time := 0.0
var round_summary := {}

var player_pos := Vector2.ZERO
var player_prev := Vector2.ZERO
var hp := 0.0
var max_hp := 0.0
var invuln := 0.0
var player_flash := 0.0
var main_weapon := ""
var build := {}
var timers := {}
var player_slow_time := 0.0
var player_slow_amount := 0.0
var level := 1
var xp := 0
var queued_levels := 0
var pending_choices: Array = []

var enemies: Array[Entities.Enemy] = []
var projectiles: Array[Entities.Projectile] = []
var strikes: Array[Entities.Strike] = []
var zones: Array[Entities.Zone] = []
var gems: Array[Entities.Gem] = []
var pickups: Array[Entities.Pickup] = []
var pickup_timer := 0.0
var pickups_taken := 0
var awaken_round := 0
var past_builds: Array = []
var past_paths: Array = [] # 라운드별 플레이어 이동 경로. past_builds와 같은 순서
var round_path := PackedVector2Array()
var ghost_queue: Array = []
var wave_queue: Array = []
var wave_index := 0
var waves_spawned := 0

var boss: Entities.Enemy = null
var boss_def := {}
var boss_warned := false
var boss_spawned := false
var boss_dead := false
var boss_state := "idle" # idle, windup, charge
var boss_timer := 0.0
var boss_pattern := {}
var boss_pattern_index := 0
var charge_dir := Vector2.RIGHT

var area := Rect2() # 지금 서 있는 공간. 필드나 보스 방
var in_boss_room := false
var portal_open := false
var portal_pos := Vector2.ZERO
var interactables: Array[Entities.Interactable] = []
var gold := 0
var interactions := 0
var frenzy_time := 0.0
var frenzy_amount := 0.0

var spawn_acc := 0.0
var last_hit := ""
var kills := 0
var ghost_kills := 0
var ghost_ttk_total := 0.0
var picks: Array = []
var boss_log: Array = []
var damage_by_source := {}
var ult_charge := 0
var ultimates_used := 0
var ult_guard := 0.0


func _init(balance: Dictionary, run_seed: int, main_id: String) -> void:
	data = balance
	rng.seed = run_seed
	tick = float(data.tick)
	max_hp = float(data.player.hp)
	hp = max_hp
	area = BossRoom.field_rect(data)
	player_pos = area.get_center()
	player_prev = player_pos
	main_weapon = main_id
	build = BuildRules.new_build(data, main_id)
	pickup_timer = float(data.items.interval)
	wave_index = rng.randi_range(0, data.waves.formations.size() - 1)
	Spawner.schedule_waves(self)
	Interactables.place(self)
	timers = {"bolt": 0.0, "aura": 0.0, "lightning": 0.0}


# --- 화면과 봇이 쓰는 조회 API ---

func is_over() -> bool:
	return state != "playing"


func xp_needed() -> int:
	return int(data.xp.base) + int(data.xp.per_level) * (level - 1)


func option_level(option_id: String) -> int:
	return BuildRules.level_of(data, build, option_id)


func option_def(option_id: String) -> Dictionary:
	return BuildRules.option_def(data, option_id)


func is_awakening_option(option_id: String) -> bool:
	return option_id == main_weapon and option_level(option_id) + 1 >= int(data.max_levels.main)


func is_awakened(target_build: Dictionary) -> bool:
	return BuildRules.is_awakened(data, target_build)


func weapon_stats(weapon_id: String, owner_build: Dictionary) -> Dictionary:
	return BuildRules.weapon_stats(data, weapon_id, owner_build)


func is_enraged() -> bool:
	return Boss.is_enraged(self)


func ultimate_ready() -> bool:
	return Ultimate.is_ready(self)


## 이 선택지를 고르면 다음 라운드의 과거의 나가 어떻게 되는지 알려준다.
func ghost_preview(option_id: String) -> Dictionary:
	var preview_build: Dictionary = build.duplicate(true)
	if option_id != "":
		BuildRules.apply_option(data, preview_build, option_id)
	return {
		"hp": BuildRules.ghost_hp(data, preview_build, 0),
		"behavior": data.ghost.behaviors[BuildRules.dominant_weapon(preview_build)].name,
		"awakened": BuildRules.is_awakened(data, preview_build),
	}


# --- 화면과 봇이 쓰는 조작 API ---

func choose(index: int) -> void:
	Progression.choose(self, index)


func use_ultimate() -> bool:
	return Ultimate.use(self)


## 라운드 종료 화면을 닫고 다음 라운드를 시작한다. 레벨 업을 모두 고른 뒤의 빌드가 저장된다.
func continue_round() -> void:
	if round_summary.is_empty() or not pending_choices.is_empty():
		return
	round_summary = {}
	past_builds.append(build.duplicate(true))
	past_paths.append(round_path)
	round_path = PackedVector2Array()
	round_index += 1
	round_time = 0.0
	spawn_acc = 0.0
	hp = minf(max_hp, hp + max_hp * float(data.round_heal_ratio))
	boss = null
	boss_warned = false
	boss_spawned = false
	boss_dead = false
	boss_state = "idle"
	boss_pattern_index = 0
	in_boss_room = false
	portal_open = false
	area = BossRoom.field_rect(data)
	player_pos = area.get_center()
	player_prev = player_pos
	Spawner.schedule_ghosts(self)
	Spawner.schedule_waves(self)
	Interactables.place(self)
	emit_event({"type": "round", "round": round_index})


## 한 틱의 진행 순서. 순서를 바꾸면 같은 시드의 결과가 달라진다.
func step(move_dir: Vector2) -> void:
	if is_over() or not pending_choices.is_empty() or not round_summary.is_empty():
		return
	time += tick
	round_time += tick
	invuln = maxf(0.0, invuln - tick)
	ult_guard = maxf(0.0, ult_guard - tick)
	player_flash = maxf(0.0, player_flash - tick)
	player_slow_time = maxf(0.0, player_slow_time - tick)
	frenzy_time = maxf(0.0, frenzy_time - tick)
	_move_player(move_dir)
	_record_path()
	Combat.fire_weapons(self, player_pos, build, timers, false, 1.0)
	Spawner.spawn_enemies(self)
	Spawner.spawn_waves(self)
	Spawner.spawn_ghosts(self)
	BossRoom.update(self)
	Boss.spawn(self)
	EnemyAI.update(self)
	Combat.update_projectiles(self)
	Combat.update_strikes(self)
	Combat.update_zones(self)
	Combat.resolve_deaths(self)
	Loot.update_pickups(self)
	Loot.collect_gems(self)
	Interactables.update(self)
	if hp <= 0.0:
		state = "lost"
		emit_event({"type": "lost"})
	elif boss_dead:
		_finish_round()


# --- 시스템들이 함께 쓰는 도구 ---

func emit_event(event: Dictionary) -> void:
	if record_events:
		events.append(event)


## 지금 서 있는 공간(필드나 보스 방) 안으로 위치를 제한한다.
func clamp_to_arena(pos: Vector2) -> Vector2:
	return pos.clamp(area.position, area.end)


func random_offset(spread: float) -> Vector2:
	return Vector2.from_angle(rng.randf() * TAU) * rng.randf() * spread


func _move_player(move_dir: Vector2) -> void:
	player_prev = player_pos
	var speed := float(data.player.speed)
	if player_slow_time > 0.0:
		speed *= maxf(0.2, 1.0 - player_slow_amount)
	player_pos = clamp_to_arena(player_pos + move_dir.limit_length(1.0) * speed * tick)


## 다음 라운드의 과거의 나가 따라 걷도록 path_sample초마다 위치를 남긴다.
func _record_path() -> void:
	if round_path.size() * float(data.ghost.path_sample) <= round_time:
		round_path.append(player_pos)


func _finish_round() -> void:
	if round_index >= int(data.rounds):
		state = "won"
		emit_event({"type": "won"})
		return
	var in_time: bool = boss_log[-1].in_time
	if in_time:
		queued_levels += int(data.boss.bonus_levels)
	for gem in gems:
		Loot.take_gem(self, gem)
	gems = []
	Progression.offer_next_level(self)
	enemies = []
	projectiles = []
	strikes = []
	zones.clear()
	pickups = []
	ghost_queue = []
	wave_queue = []
	round_summary = {"round": round_index, "in_time": in_time, "fight_time": boss_log[-1].fight_time}
	emit_event({"type": "round_clear", "round": round_index})
