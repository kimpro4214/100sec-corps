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
	"click": {"files": ["click_001"], "db": -8.0, "pitch": 0.05, "gap": 0.05},
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


func play_jingle(id: String) -> void:
	jingle_player.stream = jingle_streams[id]
	jingle_player.play()


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
			play("lightning")
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
		"boss_blink":
			play("ghost")
		"ultimate":
			play("ult_fire")
		"awaken":
			play_jingle("awaken")
		"round_clear":
			play_jingle("round_clear")
		"won":
			play_jingle("win")
		"lost":
			play_jingle("lose")


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")
