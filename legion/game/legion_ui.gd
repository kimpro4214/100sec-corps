extends CanvasLayer
## 100초 군단의 UI 패널과 문구. sim을 읽어 표시만 하고, 버튼 입력은 시그널로 알린다.

signal main_chosen(main_id: String)
signal option_chosen(index: int)
signal continue_pressed
signal restart_pressed
signal menu_pressed

const Palette := preload("res://legion/game/palette.gd")
const MAIN_WEAPONS := ["bolt", "aura", "lightning"]
const BANNER_SECONDS := 2.5

# Kenney UI Pack - Pixel Adventure(CC0) 큰 타일 시트를 2배로 키운 것. 한 칸 64px, 가로 13칸.
const UI_SHEET := preload("res://legion/art/ui/ui_large_2x.png")
const FONT := preload("res://legion/art/font/Galmuri11.ttf")
const UI_TILE := 64
const UI_COLUMNS := 13
const TILE_PARCHMENT := 0
const TILE_WOOD := 1
const TILE_WOOD_FANCY := 4
const RIBBON_ROW := 4
const RIBBON_COLUMN := 4
const TEXT_LIGHT := Color("fff3dc")
const TEXT_DARK := Color("3d2a1e")
# 갈무리11은 12px 격자 폰트라 12의 배수에서만 선명하다.
const FONT_SMALL := 12
const FONT_NORMAL := 24
const FONT_TITLE := 72

var data: Dictionary
var banner_time := 0.0

var start_panel: PanelContainer
var hud: Label
var build_label: Label
var banner: Label
var cinema_title: Label
var cinema_sub: Label
var choice_panel: PanelContainer
var choice_box: VBoxContainer
var summary_panel: PanelContainer
var summary_label: Label
var end_panel: PanelContainer
var end_label: Label


func setup(balance: Dictionary) -> void:
	data = balance
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.theme = _build_theme()
	add_child(root)

	hud = Label.new()
	hud.position = Vector2(16, 32)
	root.add_child(hud)

	build_label = Label.new()
	build_label.position = Vector2(16, 92)
	build_label.add_theme_font_size_override("font_size", FONT_SMALL)
	root.add_child(build_label)

	banner = Label.new()
	banner.theme_type_variation = "Banner"
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.position.y = 112
	root.add_child(banner)

	cinema_title = _cinema_label(root, FONT_TITLE, -48.0)
	cinema_sub = _cinema_label(root, FONT_NORMAL, 36.0)

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
	end_label = Label.new()
	end_label.theme_type_variation = "PanelLabel"
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_box.add_child(end_label)
	var again := Button.new()
	again.text = "다시 하기"
	again.pressed.connect(restart_pressed.emit)
	end_box.add_child(again)
	var menu := Button.new()
	menu.text = "메뉴로"
	menu.pressed.connect(menu_pressed.emit)
	end_box.add_child(menu)


## 무기 선택 화면으로 돌아간다.
func reset() -> void:
	hide_cinema_text()
	hud.text = ""
	build_label.text = ""
	end_panel.hide()
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
			show_banner("경고: 군단장이 접근합니다")
		"boss":
			show_banner("%s 등장! 과거의 나 총출동" % event.label)
		"round":
			show_banner("라운드 %d: 지난 빌드가 돌아옵니다" % event.round)


func tick_banner(delta: float, allowed: bool) -> void:
	banner_time = maxf(0.0, banner_time - delta)
	banner.visible = banner_time > 0.0 and allowed


func update_hud(sim, visible_now: bool) -> void:
	hud.text = "라운드 %d/%d   %s\n레벨 %d   처치 %d   과거의 나 처치 %d" % [
		sim.round_index, int(data.rounds), _time_text(sim), sim.level, sim.kills, sim.ghost_kills,
	]
	build_label.text = "빌드: " + _build_text(sim, sim.build)
	hud.visible = visible_now
	build_label.visible = visible_now


func show_cinema_text(title: String, sub: String) -> void:
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


func show_end(sim) -> void:
	var title: String = "승리! 군단을 넘어섰습니다" if sim.state == "won" else "패배: 라운드 %d" % sim.round_index
	end_label.text = "%s\n레벨 %d   처치 %d   과거의 나 처치 %d   군단장 처치 %d" % [title, sim.level, sim.kills, sim.ghost_kills, sim.boss_log.size()]
	hide_round_panels()
	end_panel.show()


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


## 나무 버튼, 양피지 패널, 리본 배너, 갈무리 폰트를 묶은 테마.
func _build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = FONT_NORMAL

	theme.set_color("font_color", "Label", TEXT_LIGHT)
	theme.set_color("font_outline_color", "Label", Color.BLACK)
	theme.set_constant("outline_size", "Label", 6)

	theme.set_type_variation("PanelLabel", "Label")
	theme.set_color("font_color", "PanelLabel", TEXT_DARK)
	theme.set_constant("outline_size", "PanelLabel", 0)

	theme.set_type_variation("Banner", "Label")
	var ribbon := _ui_style(Rect2(RIBBON_COLUMN * UI_TILE, RIBBON_ROW * UI_TILE, UI_TILE * 3, UI_TILE), 0.0, 0.0)
	ribbon.texture_margin_left = 48
	ribbon.texture_margin_right = 48
	ribbon.texture_margin_top = 16
	ribbon.texture_margin_bottom = 24
	ribbon.content_margin_left = 64
	ribbon.content_margin_right = 64
	ribbon.content_margin_top = 12
	ribbon.content_margin_bottom = 24
	theme.set_stylebox("normal", "Banner", ribbon)

	theme.set_stylebox("panel", "PanelContainer", _ui_style(_tile_rect(TILE_PARCHMENT), 20.0, 28.0))

	theme.set_stylebox("normal", "Button", _ui_style(_tile_rect(TILE_WOOD), 16.0, 18.0))
	theme.set_stylebox("hover", "Button", _ui_style(_tile_rect(TILE_WOOD_FANCY), 20.0, 18.0))
	theme.set_stylebox("pressed", "Button", _ui_style(_tile_rect(TILE_WOOD), 16.0, 18.0, Color(0.75, 0.75, 0.75)))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", TEXT_LIGHT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", TEXT_LIGHT)
	theme.set_color("font_focus_color", "Button", TEXT_LIGHT)
	theme.set_color("font_outline_color", "Button", TEXT_DARK)
	theme.set_constant("outline_size", "Button", 6)
	return theme


func _tile_rect(index: int) -> Rect2:
	return Rect2((index % UI_COLUMNS) * UI_TILE, (index / UI_COLUMNS) * UI_TILE, UI_TILE, UI_TILE)


func _ui_style(region: Rect2, margin: float, content: float, tint := Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = UI_SHEET
	style.region_rect = region
	style.set_texture_margin_all(margin)
	style.set_content_margin_all(content)
	style.modulate_color = tint
	return style


func _time_text(sim) -> String:
	var limit := float(data.round_seconds)
	if sim.round_time > limit:
		return "시간 초과 +%d초: 군단장 광폭화" % int(sim.round_time - limit)
	if sim.round_time < float(data.boss_at):
		return "군단장까지 %d초" % ceili(float(data.boss_at) - sim.round_time)
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
