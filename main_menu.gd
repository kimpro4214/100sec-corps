extends Control

const GAMES := [
	["100초 군단", "내가 키운 빌드가 다음 라운드의 적이 된다", "res://legion/game/legion_game.tscn"],
	["포획 덱", "쓰러뜨린 적을 부작용이 붙은 카드로 포획한다", "res://capture_deck/game/deck_game.tscn"],
]


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	var title := Label.new()
	title.text = "프로토타입 선택"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)

	for game in GAMES:
		var button := Button.new()
		button.text = "%s\n%s" % [game[0], game[1]]
		button.custom_minimum_size = Vector2(460, 84)
		button.pressed.connect(get_tree().change_scene_to_file.bind(game[2]))
		box.add_child(button)
