extends Node
## 플레이어 설정. 자동 로드(Settings)로 등록되어 게임을 켜면 바로 불러와 적용한다.
## 바꾸면 user://settings.cfg에 저장되어 다음에 켤 때도 유지된다.

signal changed

const PATH := "user://settings.cfg"
const SECTION := "settings"

var sfx_volume := 0.8 # 0~1
var music_volume := 0.7 # 0~1
var fullscreen := false
var screen_shake := true # 끄면 흔들림이 없어지고 번쩍임이 약해진다
var double_speed := false # 켜면 게임 속 시간이 두 배로 흐른다. 규칙과 수치는 그대로다.


func _ready() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) == OK:
		sfx_volume = float(file.get_value(SECTION, "sfx_volume", sfx_volume))
		music_volume = float(file.get_value(SECTION, "music_volume", music_volume))
		fullscreen = bool(file.get_value(SECTION, "fullscreen", fullscreen))
		screen_shake = bool(file.get_value(SECTION, "screen_shake", screen_shake))
		double_speed = bool(file.get_value(SECTION, "double_speed", double_speed))
	apply()


func set_value(key: String, value) -> void:
	set(key, value)
	apply()
	var file := ConfigFile.new()
	for name in ["sfx_volume", "music_volume", "fullscreen", "screen_shake", "double_speed"]:
		file.set_value(SECTION, name, get(name))
	file.save(PATH)
	changed.emit()


func apply() -> void:
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("Music", music_volume)
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.get_name() != "headless" and DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


## 0~1 음량을 데시벨로 바꿔 버스에 건다. 0이면 아예 끈다.
func _set_bus_volume(bus_name: String, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")
	AudioServer.set_bus_mute(index, volume <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))
