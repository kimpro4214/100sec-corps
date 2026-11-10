extends Node
## 100초 군단의 효과음과 짧은 음악 신호. 소리는 Kenney 사운드 팩(CC0).
## sim 이벤트를 받아 소리를 고르고, 너무 잦은 소리는 최소 간격으로 걸러 낸다.
## 효과음은 SFX 버스, 음악 신호는 Music 버스로 보낸다.

const DIR := "res://legion/audio/"
const VOICES := 20

# files: 무작위로 고를 파일들, db: 볼륨(데시벨), pitch: 음높이 흔들림 폭, gap: 같은 소리의 최소 간격(초)
const SOUNDS := {
	"bolt": {"files": ["laserSmall_000", "laserSmall_001", "laserSmall_002", "laserSmall_003", "laserSmall_004"], "db": -18.0, "pitch": 0.12, "gap": 0.07},
	"aura": {"files": ["forceField_000"], "db": -24.0, "pitch": 0.08, "gap": 0.3},
	"lightning": {"files": ["explosionCrunch_000", "explosionCrunch_001", "explosionCrunch_002", "explosionCrunch_003", "explosionCrunch_004"], "db": -14.0, "pitch": 0.15, "gap": 0.05},
	"loop": {"files": ["impactMetal_heavy_003", "impactMetal_heavy_004"], "db": -9.0, "pitch": 0.2, "gap": 0.1},
	"kill": {"files": ["impactSoft_medium_000", "impactSoft_medium_001", "impactSoft_medium_002", "impactSoft_medium_003", "impactSoft_medium_004"], "db": -14.0, "pitch": 0.18, "gap": 0.03},
	"ghost_kill": {"files": ["impactMetal_heavy_000", "impactMetal_heavy_001", "impactMetal_heavy_002"], "db": -6.0, "pitch": 0.05, "gap": 0.1},
	"boss_kill": {"files": ["lowFrequency_explosion_000"], "db": -2.0, "pitch": 0.0, "gap": 0.5},
	"hurt": {"files": ["impactPunch_heavy_000", "impactPunch_heavy_001", "impactPunch_heavy_002", "impactPunch_heavy_003", "impactPunch_heavy_004"], "db": -10.0, "pitch": 0.1, "gap": 0.12},
	"pickup": {"files": ["confirmation_001"], "db": -8.0, "pitch": 0.05, "gap": 0.1},
	"ghost": {"files": ["glitch_002"], "db": -8.0, "pitch": 0.05, "gap": 0.3},
	"wave": {"files": ["bong_001"], "db": -8.0, "pitch": 0.0, "gap": 0.5},
	"boss_warning": {"files": ["spaceEngineLow_000"], "db": -6.0, "pitch": 0.0, "gap": 1.0},
	"boss_windup": {"files": ["forceField_002"], "db": -10.0, "pitch": 0.1, "gap": 0.5},
	"ult_charge": {"files": ["forceField_001"], "db": -6.0, "pitch": 0.0, "gap": 0.5},
	"ult_fire": {"files": ["lowFrequency_explosion_001"], "db": -3.0, "pitch": 0.0, "gap": 0.5},
	"slash": {"files": ["impactPlate_heavy_000", "impactPlate_heavy_001"], "db": -4.0, "pitch": 0.08, "gap": 0.2},
	"web": {"files": ["slime_000"], "db": -6.0, "pitch": 0.15, "gap": 0.15},
	"fire": {"files": ["thrusterFire_000"], "db": -10.0, "pitch": 0.15, "gap": 0.15},
	"click": {"files": ["click_001"], "db": -8.0, "pitch": 0.05, "gap": 0.05},
	"hover": {"files": ["tick_001"], "db": -20.0, "pitch": 0.05, "gap": 0.04},
	"select": {"files": ["select_001"], "db": -6.0, "pitch": 0.0, "gap": 0.05},
}
# 길이만 보고 고른 배치라, 들어 보고 바꿀 수 있게 한곳에 둔다.
const JINGLES := {
	"level_up": "jingles_NES03",
	"round_clear": "jingles_NES05",
	"awaken": "jingles_NES11",
	"win": "jingles_NES00",
	"lose": "jingles_NES13",
}

var streams := {}
var jingle_streams := {}
var last_played := {}
var players: Array[AudioStreamPlayer] = []
var next_player := 0
var jingle_player: AudioStreamPlayer
var music_player: AudioStreamPlayer
var music_id := ""
var music_tween: Tween

# 배경 음악(OpenGameArt, CC0). 필드와 보스 방에서 바꿔 튼다.
const MUSIC := {
	"field": "res://legion/audio/music/field_8bit_battle_loop.ogg",
	"boss": "res://legion/audio/music/boss_basilisk_battle_loop.ogg",
}
const MUSIC_DB := -10.0
const MUSIC_DUCK_DB := -22.0
const MUSIC_FADE := 1.0


func _ready() -> void:
	_ensure_bus("SFX")
	_ensure_bus("Music")
	for id in SOUNDS:
		var list: Array = []
		for file in SOUNDS[id].files:
			list.append(load(DIR + "sfx/" + file + ".ogg"))
		streams[id] = list
	for id in JINGLES:
		jingle_streams[id] = load(DIR + "jingles/" + JINGLES[id] + ".ogg")
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		players.append(player)
	jingle_player = AudioStreamPlayer.new()
	jingle_player.bus = "Music"
	add_child(jingle_player)
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	add_child(music_player)


## 화면의 모든 버튼에 소리를 붙인다. 누르면 딸깍, 마우스를 올리면 작게 틱. 나중에 생기는 버튼도 붙는다.
func watch_buttons() -> void:
	for node in get_tree().root.find_children("*", "BaseButton", true, false):
		_hook_button(node)
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is BaseButton:
			_hook_button(node))


func _hook_button(button: BaseButton) -> void:
	if button.has_meta("sfx_hooked"):
		return
	button.set_meta("sfx_hooked", true)
	button.pressed.connect(play.bind("click"))
	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			play("hover"))


## 배경 음악을 바꾼다. 같은 곡이면 그대로 두고, 다른 곡이면 잠깐 줄였다가 바꿔 키운다.
func play_music(id: String) -> void:
	if id == music_id:
		return
	music_id = id
	_kill_music_tween()
	music_tween = create_tween()
	if music_player.playing:
		music_tween.tween_property(music_player, "volume_db", -40.0, MUSIC_FADE * 0.5)
	music_tween.tween_callback(func() -> void:
		music_player.stream = load(MUSIC[id])
		music_player.volume_db = -40.0
		music_player.play())
	music_tween.tween_property(music_player, "volume_db", MUSIC_DB, MUSIC_FADE)


func stop_music() -> void:
	music_id = ""
	_kill_music_tween()
	music_tween = create_tween()
	music_tween.tween_property(music_player, "volume_db", -40.0, MUSIC_FADE)
	music_tween.tween_callback(music_player.stop)


func _kill_music_tween() -> void:
	if music_tween != null and music_tween.is_valid():
		music_tween.kill()


func play(id: String) -> void:
	var cfg: Dictionary = SOUNDS[id]
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(last_played.get(id, -100.0)) < float(cfg.gap):
		return
	last_played[id] = now
	# 목소리가 모자라면 가장 오래된 것부터 끊고 다시 쓴다.
	var player := players[next_player]
	next_player = (next_player + 1) % players.size()
	var list: Array = streams[id]
	player.stream = list[randi() % list.size()]
	player.volume_db = float(cfg.db)
	player.pitch_scale = 1.0 + randf_range(-float(cfg.pitch), float(cfg.pitch))
	player.play()


## 짧은 음악 신호. 배경 음악과 겹치지 않게 그동안 배경 음악을 줄였다가 되돌린다.
func play_jingle(id: String) -> void:
	jingle_player.stream = jingle_streams[id]
	jingle_player.play()
	if music_player.playing and music_id != "":
		_kill_music_tween()
		music_tween = create_tween()
		music_tween.tween_property(music_player, "volume_db", MUSIC_DUCK_DB, 0.1)
		music_tween.tween_interval(jingle_streams[id].get_length())
		music_tween.tween_property(music_player, "volume_db", MUSIC_DB, 0.6)


## sim 이벤트 중 소리를 낼 것을 골라 재생한다.
func handle(event: Dictionary) -> void:
	match event.type:
		"bolt":
			if not event.hostile:
				play("bolt")
		"aura":
			if not event.hostile:
				play("aura")
		"lightning":
			match event.get("source", ""):
				"boss_meteor":
					play("fire")
				"boss_boulder":
					play("boss_kill")
				"boss_quake":
					pass
				_:
					play("lightning")
		"loop":
			play("loop")
		"boss_slash":
			play("slash")
		"boss_web", "web_land":
			play("web")
		"kill":
			match event.kind:
				"ghost":
					play("ghost_kill")
				"boss":
					play("boss_kill")
				_:
					play("kill")
		"hurt":
			play("hurt")
		"pickup":
			play("pickup")
		"ghost":
			play("ghost")
		"wave":
			play("wave")
		"boss_warning":
			play("boss_warning")
		"boss_windup":
			play("boss_windup")
		"boss_quake":
			play("boss_kill")
		"interact":
			match event.reward:
				"nothing":
					play("click")
				"ambush":
					play("wave")
				"bomb":
					play("ult_fire")
				"jackpot":
					play_jingle("awaken")
				_:
					play("pickup")
		"portal":
			play("ult_charge")
		"boss_room":
			play("ghost")
			play_music("boss")
		"boss_blink":
			play("ghost")
		"ultimate":
			play("ult_fire")
		"awaken":
			play_jingle("awaken")
		"round":
			play_music("field")
		"round_clear":
			play_jingle("round_clear")
		"won":
			stop_music()
			play_jingle("win")
		"lost":
			stop_music()
			play_jingle("lose")


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")
