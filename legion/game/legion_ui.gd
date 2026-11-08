extends CanvasLayer
## 100초 군단의 UI 패널과 문구. sim을 읽어 표시만 하고, 버튼 입력은 시그널로 알린다.

signal main_chosen(main_id: String)
signal option_chosen(index: int)
signal continue_pressed
signal restart_pressed
signal menu_pressed
signal resume_pressed

const Palette := preload("res://legion/game/palette.gd")
const UiTheme := preload("res://legion/game/ui_theme.gd")
const MenuPanels := preload("res://legion/game/menu_panels.gd")
const MAIN_WEAPONS := ["bolt", "aura", "lightning"]
const BANNER_SECONDS := 2.5

const CAUSE_TEXT := {
	"ghost_aura": "과거의 나의 가시 오라",
	"ghost_bolt": "과거의 나의 마력탄",
	"ghost_lightning": "과거의 나의 낙뢰",
	"ghost": "과거의 나와 부딪힘",
	"boss_contact": "보스와 부딪힘",
	"boss_charge": "보스의 돌진",
	"boss_ring": "보스의 원형탄",
	"boss_spray": "보스의 부채꼴 탄",
	"boss_blink": "보스의 순간이동 탄막",
	"boss_quake": "보스의 내리찍기",
	"boss_strike": "보스의 낙뢰",
	"boss_slash": "타락한 기사의 칼",
	"boss_sword_wave": "타락한 기사의 검기",
	"boss_venom": "거미 여왕의 독침",
	"boss_soul": "망령의 영혼탄",
	"boss_boulder": "외눈 거인의 바위",
	"boss_fire": "군단장의 불꽃",
	"boss_meteor": "군단장의 운석",
}
const REWARD_TEXT := {
	"level": "레벨 업! (과거의 나에게도 복사됩니다)",
	"jackpot": "잭팟! 레벨 업 2회",
	"heal": "체력 회복",
	"shield": "보호막: 잠시 무적",
	"frenzy": "광폭: 공격 속도 증가",
	"bomb": "폭탄! 주변을 쓸어버립니다",
	"refund": "당첨! 금화 2배",
	"nothing": "꽝...",
	"ambush": "꽝! 매복이다",
}

var data: Dictionary
var banner_time := 0.0

var start_panel: PanelContainer
var hud: Label
var build_label: Label
var banner: Label
var cinema_title: Label
var cinema_sub: Label
var cinema_title_y := 0.0
var cinema_sub_y := 0.0
var choice_panel: PanelContainer
var choice_box: VBoxContainer
var summary_panel: PanelContainer
var summary_label: Label
var end_panel: PanelContainer
var pause_panel: PanelContainer
var pause_label: Label
var pause_resume: Button
var end_label: Label
var end_title: Label
var end_again: Button


func setup(balance: Dictionary) -> void:
	data = balance
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.theme = UiTheme.build()
	add_child(root)

	hud = Label.new()
	hud.position = Vector2(16, 32)
	root.add_child(hud)

	build_label = Label.new()
	build_label.position = Vector2(16, 92)
	build_label.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	root.add_child(build_label)

	banner = Label.new()
	banner.theme_type_variation = "Banner"
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.position.y = 112
	root.add_child(banner)

	cinema_title = _cinema_label(root, UiTheme.FONT_TITLE, -48.0)
	cinema_sub = _cinema_label(root, UiTheme.FONT_NORMAL, 36.0)
	cinema_title_y = cinema_title.position.y
	cinema_sub_y = cinema_sub.position.y

	_build_start_panel(root)

	choice_panel = _centered_panel(root)
	choice_box = VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 8)
	choice_panel.add_child(choice_box)

	summary_panel = _centered_panel(root)
	var summary_box := VBoxContainer.new()
	summary_box.add_theme_constant_override("separation", 12)
	summary_panel.add_child(summary_box)
	summary_label = Label.new()
	summary_label.theme_type_variation = "PanelLabel"
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_box.add_child(summary_label)
	var next_round := Button.new()
	next_round.text = "다음 라운드 (Space)"
	next_round.pressed.connect(continue_pressed.emit)
	summary_box.add_child(next_round)

	end_panel = _centered_panel(root)
	var end_box := VBoxContainer.new()
	end_box.add_theme_constant_override("separation", 10)
	end_panel.add_child(end_box)
	end_title = Label.new()
	end_title.theme_type_variation = "PanelLabel"
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_title.add_theme_font_size_override("font_size", UiTheme.FONT_LARGE)
	end_box.add_child(end_title)
	end_label = Label.new()
	end_label.theme_type_variation = "PanelLabel"
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_label.custom_minimum_size = Vector2(680, 0)
	end_box.add_child(end_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	end_box.add_child(buttons)
	end_again = Button.new()
	end_again.text = "다시 하기"
	end_again.pressed.connect(restart_pressed.emit)
	buttons.add_child(end_again)
	var menu := Button.new()
	menu.text = "타이틀로"
	menu.pressed.connect(menu_pressed.emit)
	buttons.add_child(menu)

	_build_pause_panel(root)


## Esc로 여는 일시정지 창. 지금 빌드의 레벨과 다음 라운드의 과거의 나를 보여 준다.
func _build_pause_panel(root: Control) -> void:
	pause_panel = _centered_panel(root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	pause_panel.add_child(box)
	var title := Label.new()
	title.theme_type_variation = "PanelLabel"
	title.text = "일시정지"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UiTheme.FONT_LARGE)
	box.add_child(title)
	pause_label = Label.new()
	pause_label.theme_type_variation = "PanelLabel"
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pause_label.custom_minimum_size = Vector2(680, 0)
	box.add_child(pause_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	pause_resume = Button.new()
	pause_resume.text = "계속하기 (Esc)"
	pause_resume.pressed.connect(resume_pressed.emit)
	buttons.add_child(pause_resume)
	var settings_button := Button.new()
	settings_button.text = "설정"
	settings_button.pressed.connect(func() -> void:
		pause_panel.hide()
		root.add_child(MenuPanels.build_settings(get_node("/root/Settings"), func() -> void:
			pause_panel.show()
			pause_resume.grab_focus())))
	buttons.add_child(settings_button)
	var menu := Button.new()
	menu.text = "타이틀로"
	menu.pressed.connect(menu_pressed.emit)
	buttons.add_child(menu)


func show_pause(sim) -> void:
	pause_label.text = _pause_text(sim)
	pause_panel.show()
	pause_resume.grab_focus()


func hide_pause() -> void:
	pause_panel.hide()


func _pause_text(sim) -> String:
	var lines: Array = []
	lines.append("라운드 %d/%d   레벨 %d   금화 %d   궁극기 %d%%" % [
		sim.round_index, int(data.rounds), sim.level, sim.gold, int(100.0 * sim.ult_charge / float(data.ultimate.charge_kills)),
	])
	lines.append("")
	var main_id: String = sim.main_weapon
	var main_max := int(data.max_levels.main)
	var main_level: int = sim.option_level(main_id)
	if main_level >= main_max:
		lines.append("메인 무기: 각성 %s (Lv%d)" % [data.weapons[main_id].awaken.name, main_level])
	else:
		lines.append("메인 무기: %s Lv%d/%d (각성까지 %d레벨)" % [data.weapons[main_id].name, main_level, main_max, main_max - main_level])
	lines.append(_level_line("보조 무기", sim, sim.WEAPON_IDS.filter(func(id: String) -> bool: return id != main_id), int(data.max_levels.sub)))
	var traits: Array = []
	for trait_id in data.traits:
		if data.traits[trait_id].weapon == main_id:
			traits.append(trait_id)
	lines.append(_level_line("특성", sim, traits, int(data.max_levels.trait)))
	lines.append(_level_line("강화", sim, sim.UPGRADE_IDS, int(data.max_levels.upgrade)))
	lines.append("")
	lines.append("다음 라운드의 과거의 나: %s" % _preview_text(sim.ghost_preview("")))
	return "\n".join(lines)


## 레벨이 1 이상인 것만 "이름 Lv현재/최대"로 나열한다.
func _level_line(heading: String, sim, ids: Array, max_level: int) -> String:
	var parts: Array = []
	for id in ids:
		var level: int = sim.option_level(id)
		if level > 0:
			parts.append("%s Lv%d/%d" % [sim.option_def(id).name, level, max_level])
	return "%s: %s" % [heading, ", ".join(parts) if not parts.is_empty() else "없음"]


## 무기 선택 화면으로 돌아간다.
func reset() -> void:
	hide_cinema_text()
	hud.text = ""
	build_label.text = ""
	end_panel.hide()
	pause_panel.hide()
	choice_panel.hide()
	summary_panel.hide()
	banner.hide()
	start_panel.show()


func hide_start() -> void:
	start_panel.hide()


func hide_round_panels() -> void:
	choice_panel.hide()
	summary_panel.hide()


func is_summary_visible() -> bool:
	return summary_panel.visible


func is_choice_visible() -> bool:
	return choice_panel.visible


func is_end_visible() -> bool:
	return end_panel.visible


# --- 배너, HUD, 시네마틱 문구 ---

func show_banner(text: String) -> void:
	banner.text = text
	banner_time = BANNER_SECONDS


## sim 이벤트 중 배너로 알릴 것을 골라 보여준다.
func handle_event(event: Dictionary) -> void:
	match event.type:
		"awaken":
			show_banner("각성! %s" % event.name)
		"pickup":
			show_banner("%s 획득" % event.name)
		"ghost":
			show_banner("%s 등장!" % event.label)
		"wave":
			show_banner("웨이브: %s!" % event.name)
		"boss_warning":
			show_banner("곧 보스 방 포탈이 열립니다")
		"portal":
			show_banner("포탈 개방! 100초가 되면 강제로 끌려갑니다")
		"boss_room":
			if event.forced:
				show_banner("시간 초과! 보스 방으로 끌려갑니다")
		"boss":
			show_banner("%s 등장! 과거의 나 총출동" % event.label)
		"round":
			show_banner("라운드 %d: 지난 빌드가 돌아옵니다" % event.round)
		"interact":
			show_banner(REWARD_TEXT.get(event.reward, event.reward))


func tick_banner(delta: float, allowed: bool) -> void:
	banner_time = maxf(0.0, banner_time - delta)
	banner.visible = banner_time > 0.0 and allowed


func update_hud(sim, visible_now: bool) -> void:
	var buffs := ""
	if sim.frenzy_time > 0.0:
		buffs += "   광폭 %d초" % ceili(sim.frenzy_time)
	hud.text = "라운드 %d/%d   %s\n레벨 %d   처치 %d   과거의 나 %d   금화 %d%s" % [
		sim.round_index, int(data.rounds), _time_text(sim), sim.level, sim.kills, sim.ghost_kills, sim.gold, buffs,
	]
	build_label.text = "빌드: " + _build_text(sim, sim.build)
	hud.visible = visible_now
	build_label.visible = visible_now


## lower가 true면 화면 아래쪽에 띄운다. 가운데의 대상(보스 등)을 가리지 않게 할 때 쓴다.
func show_cinema_text(title: String, sub: String, lower := false) -> void:
	var shift := 170.0 if lower else 0.0
	cinema_title.position.y = cinema_title_y + shift
	cinema_sub.position.y = cinema_sub_y + shift
	cinema_title.text = title
	cinema_sub.text = sub
	cinema_title.show()
	cinema_sub.show()
	set_cinema_style(1.0, 1.0)


func set_cinema_style(alpha: float, title_scale: float) -> void:
	cinema_title.modulate.a = alpha
	cinema_sub.modulate.a = alpha
	cinema_title.scale = Vector2.ONE * title_scale


func hide_cinema_text() -> void:
	cinema_title.hide()
	cinema_sub.hide()
	cinema_title.scale = Vector2.ONE


# --- 패널 ---

func show_choices(sim) -> void:
	for child in choice_box.get_children():
		choice_box.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.theme_type_variation = "PanelLabel"
	title.text = "레벨 업! 하나를 고르세요 (1, 2, 3)\n이 선택은 다음 라운드의 과거의 나에게도 복사됩니다"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	choice_box.add_child(title)
	for i in sim.pending_choices.size():
		var option_id: String = sim.pending_choices[i]
		var def: Dictionary = sim.option_def(option_id)
		var preview: Dictionary = sim.ghost_preview(option_id)
		var button := Button.new()
		var label: String = def.name
		var desc: String = def.desc
		if sim.is_awakening_option(option_id):
			label = "각성! %s → %s" % [def.name, def.awaken.name]
			desc = def.awaken.desc
		button.text = "%d. %s  Lv%d → %d\n%s\n과거의 나: %s" % [
			i + 1, label, sim.option_level(option_id), sim.option_level(option_id) + 1, desc, _preview_text(preview),
		]
		button.custom_minimum_size = Vector2(620, 0)
		if sim.is_awakening_option(option_id):
			button.add_theme_color_override("font_color", Palette.AWAKEN)
		button.pressed.connect(option_chosen.emit.bind(i))
		choice_box.add_child(button)
	choice_panel.show()


func show_summary(sim) -> void:
	var summary: Dictionary = sim.round_summary
	var preview: Dictionary = sim.ghost_preview("")
	var bonus := "제한 시간 안에 처치! 보너스 레벨 업 획득" if summary.in_time else "제한 시간 초과: 보너스 없음"
	summary_label.text = "라운드 %d 돌파!\n군단장 처치 %d초   %s\n\n이번 빌드\n%s\n\n다음 라운드에 돌아오는 과거의 나\n%s" % [
		summary.round, int(summary.fight_time), bonus, _build_text(sim, sim.build), _preview_text(preview),
	]
	summary_panel.show()


## 결과 화면: 플레이 기록과 최종 빌드를 보여 주고, 진 판이면 무엇에 쓰러졌는지 알려 준다.
func show_end(sim) -> void:
	var won: bool = sim.state == "won"
	end_title.text = "승리! 군단을 넘어섰습니다" if won else "패배: 라운드 %d" % sim.round_index
	var bosses: Array = []
	for i in sim.boss_log.size():
		bosses.append(data.bosses[mini(i, data.bosses.size() - 1)].name)
	var lines: Array = [
		"메인 무기 %s   레벨 %d   플레이 시간 %d분 %02d초" % [data.weapons[sim.main_weapon].name, sim.level, int(sim.time) / 60, int(sim.time) % 60],
		"처치 %d   과거의 나 처치 %d   궁극기 %d회   상호작용 %d회" % [sim.kills, sim.ghost_kills, sim.ultimates_used, sim.interactions],
		"쓰러뜨린 보스: %s" % (", ".join(bosses) if not bosses.is_empty() else "없음"),
	]
	if not won:
		lines.append("쓰러진 원인: %s" % _cause_text(sim.last_hit))
	lines.append("")
	lines.append("최종 빌드\n" + _build_text(sim, sim.build))
	end_label.text = "\n".join(lines)
	hide_round_panels()
	end_panel.show()
	end_again.grab_focus()


func _cause_text(source: String) -> String:
	if CAUSE_TEXT.has(source):
		return CAUSE_TEXT[source]
	if data.enemies.has(source):
		return data.enemies[source].name
	return source


# --- 내부 ---

func _build_start_panel(root: Control) -> void:
	start_panel = _centered_panel(root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	start_panel.add_child(box)
	var title := Label.new()
	title.theme_type_variation = "PanelLabel"
	title.text = "메인 무기를 고르세요 (1, 2, 3)\n레벨 업 선택지가 이 무기 위주로 나옵니다"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for i in MAIN_WEAPONS.size():
		var weapon: Dictionary = data.weapons[MAIN_WEAPONS[i]]
		var button := Button.new()
		button.text = "%d. %s (%s)\n%s\n5레벨 각성: %s - %s" % [
			i + 1, weapon.name, data.ghost.behaviors[MAIN_WEAPONS[i]].name, weapon.desc, weapon.awaken.name, weapon.awaken.desc,
		]
		button.custom_minimum_size = Vector2(620, 0)
		button.pressed.connect(main_chosen.emit.bind(MAIN_WEAPONS[i]))
		box.add_child(button)


func _centered_panel(root: Control) -> PanelContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	return panel


func _cinema_label(root: Control, font_size: int, offset_y: float) -> Label:
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position.y += offset_y
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 12)
	label.hide()
	root.add_child(label)
	return label


func _time_text(sim) -> String:
	var limit := float(data.round_seconds)
	if sim.round_time > limit:
		return "시간 초과 +%d초: 보스 광폭화" % int(sim.round_time - limit)
	if sim.round_time < float(data.boss_at):
		return "포탈까지 %d초" % ceili(float(data.boss_at) - sim.round_time)
	if not sim.in_boss_room:
		return "포탈 열림! 강제 입장 %d초" % ceili(limit - sim.round_time)
	return "보너스 제한 %d초" % ceili(limit - sim.round_time)


func _build_text(sim, target_build: Dictionary) -> String:
	var parts: Array = []
	var main_id: String = target_build.main
	if sim.is_awakened(target_build):
		parts.append("각성 %s" % data.weapons[main_id].awaken.name)
	else:
		parts.append("%s %d" % [data.weapons[main_id].name, int(target_build.weapons[main_id])])
	for weapon_id in sim.WEAPON_IDS:
		if weapon_id != main_id and int(target_build.weapons[weapon_id]) > 0:
			parts.append("%s %d" % [data.weapons[weapon_id].name, int(target_build.weapons[weapon_id])])
	for trait_id in data.traits:
		if int(target_build.traits[trait_id]) > 0:
			parts.append("%s %d" % [data.traits[trait_id].name, int(target_build.traits[trait_id])])
	for upgrade_id in sim.UPGRADE_IDS:
		if int(target_build.upgrades[upgrade_id]) > 0:
			parts.append("%s %d" % [data.upgrades[upgrade_id].name, int(target_build.upgrades[upgrade_id])])
	return " / ".join(parts)


func _preview_text(preview: Dictionary) -> String:
	return "%s%s, 체력 %d" % ["각성한 " if preview.awakened else "", preview.behavior, int(preview.hp)]
