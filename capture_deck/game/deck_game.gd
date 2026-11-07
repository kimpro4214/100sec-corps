extends Control
## 포획 덱 화면. 규칙은 모두 DeckSim에 있고 여기서는 입력과 표시만 처리한다.

const DeckSim := preload("res://capture_deck/sim/deck_sim.gd")
const DATA_PATH := "res://capture_deck/data/balance.json"

const EFFECT_TEXT := {
	"damage": "피해 %d", "block": "방어 %d", "draw": "%d장 뽑기", "heal": "체력 %d 회복",
	"poison": "적에게 독 %d", "strength": "이번 전투 힘 +%d", "self_damage": "자해 %d", "self_poison": "자신에게 독 %d",
	"max_hp_loss": "최대 체력 -%d", "next_draw_penalty": "다음 턴 드로우 -%d", "next_energy_penalty": "다음 턴 에너지 -%d",
	"discard_random": "손패 %d장 무작위 버림",
}

var data: Dictionary
var sim

var status_label: Label
var content: VBoxContainer
var log_label: Label


func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)
	status_label = Label.new()
	page.add_child(status_label)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	page.add_child(content)
	log_label = Label.new()
	log_label.modulate = Color(1, 1, 1, 0.65)
	page.add_child(log_label)
	_start_run()


func _start_run() -> void:
	sim = DeckSim.new(data, randi())
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		_to_menu()


func _to_menu() -> void:
	get_tree().change_scene_to_file("res://main_menu.tscn")


func _refresh() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	status_label.text = "체력 %d/%d    전투 %d/%d    덱 %d장    포획 %d장" % [
		sim.hp, sim.max_hp, min(sim.battle_index + 1, data.battle_tiers.size() + 1),
		data.battle_tiers.size() + 1, sim.deck.size(), sim.captured.size(),
	]
	log_label.text = "\n".join(sim.log_lines.slice(-5))
	match sim.phase:
		"choose_enemy":
			_show_enemy_choice()
		"combat":
			_show_combat()
		"reward":
			_show_reward()
		_:
			_show_end()


func _title(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	content.add_child(label)


func _action_button(parent: Control, text: String, action: Callable, size_hint := Vector2(300, 150)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size_hint
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(func() -> void:
		action.call()
		_refresh()
	)
	parent.add_child(button)
	return button


func _show_enemy_choice() -> void:
	_title("최종 보스가 기다립니다" if sim.is_boss_battle() else "다음 상대를 고르세요")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	for i in sim.enemy_choices.size():
		var def: Dictionary = sim.enemy_def(sim.enemy_choices[i])
		var text := "%s\n체력 %d\n" % [def.name, int(def.hp)]
		if def.has("capture_card"):
			text += "\n포획 시 얻는 카드\n" + _card_text(def.capture_card)
		else:
			text += "\n%s\n현재 추가 피해 +%d" % [def.desc, int(def.bonus_damage_per_capture) * sim.captured.size()]
		_action_button(row, text, sim.choose_enemy.bind(i), Vector2(320, 230))


func _show_combat() -> void:
	var enemy: Dictionary = sim.enemy
	var enemy_label := Label.new()
	enemy_label.add_theme_font_size_override("font_size", 20)
	enemy_label.text = "%s   체력 %d/%d   방어 %d   힘 %d   독 %d\n다음 행동: %s" % [
		enemy.name, enemy.hp, enemy.max_hp, enemy.block, enemy.strength, enemy.poison, _intent_text(),
	]
	content.add_child(enemy_label)
	var player_label := Label.new()
	player_label.text = "에너지 %d/%d   방어 %d   힘 %d   독 %d   뽑을 카드 %d   버린 카드 %d" % [
		sim.energy, int(data.player.energy), sim.block, sim.strength, sim.poison, sim.draw_pile.size(), sim.discard.size(),
	]
	content.add_child(player_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	for i in sim.hand.size():
		var button := _action_button(row, _card_text(sim.hand[i]), sim.play_card.bind(i), Vector2(170, 210))
		button.disabled = not sim.can_play(i)
	_action_button(content, "턴 종료", sim.end_turn, Vector2(200, 44)).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


func _show_reward() -> void:
	var def: Dictionary = sim.enemy_def(sim.enemy.id)
	_title("%s 처치! 어떻게 할까요?" % sim.enemy.name)
	var warning := Label.new()
	warning.text = "포획한 카드가 많을수록 최종 보스의 공격이 강해집니다."
	content.add_child(warning)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	_action_button(row, "포획하기\n\n" + _card_text(def.capture_card), sim.capture, Vector2(320, 210))
	_action_button(row, "포획하지 않기\n\n체력 %d 회복" % int(data.skip_heal), sim.skip_capture, Vector2(320, 210))


func _show_end() -> void:
	_title("승리! 심연의 수집가를 쓰러뜨렸습니다" if sim.phase == "won" else "패배")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	_action_button(row, "다시 하기", _start_run, Vector2(200, 50))
	var menu := Button.new()
	menu.text = "메뉴로"
	menu.custom_minimum_size = Vector2(200, 50)
	menu.pressed.connect(_to_menu)
	row.add_child(menu)


func _intent_text() -> String:
	var intent: Dictionary = sim.enemy_intent
	var value := int(intent.get("value", 0))
	match intent.type:
		"attack":
			var hits := int(intent.get("hits", 1))
			var damage: int = sim.intent_damage() / hits
			return "공격 %d" % damage if hits == 1 else "공격 %d x %d" % [damage, hits]
		"drain":
			return "흡혈 공격 %d" % sim.intent_damage()
		"block":
			return "방어 %d" % value
		"poison":
			return "독 %d 부여" % value
		"strength":
			return "힘 +%d" % value
	return ""


func _card_text(card_id: String) -> String:
	var def: Dictionary = sim.card_def(card_id)
	if int(def.cost) < 0:
		return "%s\n\n%s" % [def.name, def.desc]
	var lines: Array = ["[%d] %s" % [int(def.cost), def.name], ""]
	for effect in def.effects:
		lines.append(_effect_text(effect))
	if def.get("exhaust", false):
		lines.append("전투 중 1회")
	for effect in def.get("drawback", []):
		lines.append("부작용: " + _effect_text(effect))
	return "\n".join(lines)


func _effect_text(effect: Dictionary) -> String:
	if effect.type == "add_junk":
		return "버린 카드에 %s 추가" % sim.card_def(effect.card).name
	var text: String = EFFECT_TEXT[effect.type] % int(effect.get("value", 0))
	if int(effect.get("hits", 1)) > 1:
		text += " x %d" % int(effect.hits)
	return text
