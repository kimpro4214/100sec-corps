extends Node2D
## 100초 군단 화면. 규칙은 모두 LegionSim에 있고 여기서는 입력과 표시만 처리한다.

const LegionSim := preload("res://legion/sim/legion_sim.gd")
const DATA_PATH := "res://legion/data/balance.json"

const COLOR_BG := Color("15171f")
const COLOR_GRID := Color("232733")
const COLOR_PLAYER := Color("5ad1ff")
const COLOR_GHOST := Color("c77dff")
const COLOR_GRUNT := Color("e0604c")
const COLOR_RUNNER := Color("f2a541")
const COLOR_GEM := Color("7ee081")
const COLOR_HOSTILE := Color("ff5d8f")
const COLOR_BOSS := Color("d7263d")
const COLOR_POTION := Color("ff8fab")
const COLOR_MAGNET := Color("8ecbff")
const COLOR_AWAKEN := Color("ffe066")
const MAIN_WEAPONS := ["bolt", "aura", "lightning"]

var data: Dictionary
var sim
var acc := 0.0
var camera := Vector2.ZERO
var effects: Array = []
var banner_time := 0.0

var start_panel: PanelContainer
var hud: Label
var build_label: Label
var banner: Label
var choice_panel: PanelContainer
var choice_box: VBoxContainer
var summary_panel: PanelContainer
var summary_label: Label
var end_panel: PanelContainer
var end_label: Label


func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	_build_ui()
	_start_run()


func _start_run() -> void:
	sim = null
	effects = []
	hud.text = ""
	build_label.text = ""
	end_panel.hide()
	choice_panel.hide()
	summary_panel.hide()
	banner.hide()
	start_panel.show()
	queue_redraw()


func _begin_run(main_id: String) -> void:
	sim = LegionSim.new(data, randi(), main_id)
	sim.record_events = true
	acc = 0.0
	start_panel.hide()
	_show_banner("이동: WASD / 방향키   70초에 군단장이 등장합니다")


func _build_start_panel(root: Control) -> void:
	start_panel = _centered_panel(root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	start_panel.add_child(box)
	var title := Label.new()
	title.text = "메인 무기를 고르세요 (1, 2, 3)\n레벨 업 선택지가 이 무기 위주로 나옵니다"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for i in MAIN_WEAPONS.size():
		var weapon: Dictionary = data.weapons[MAIN_WEAPONS[i]]
		var button := Button.new()
		button.text = "%d. %s (%s)\n%s\n5레벨 각성: %s - %s" % [
			i + 1, weapon.name, data.ghost.behaviors[MAIN_WEAPONS[i]].name, weapon.desc, weapon.awaken.name, weapon.awaken.desc,
		]
		button.custom_minimum_size = Vector2(460, 84)
		button.pressed.connect(_begin_run.bind(MAIN_WEAPONS[i]))
		box.add_child(button)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	hud = Label.new()
	hud.position = Vector2(16, 34)
	root.add_child(hud)

	build_label = Label.new()
	build_label.position = Vector2(16, 90)
	root.add_child(build_label)

	banner = Label.new()
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.position.y = 124
	banner.add_theme_font_size_override("font_size", 26)
	root.add_child(banner)

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
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_box.add_child(summary_label)
	var next_round := Button.new()
	next_round.text = "다음 라운드 (Space)"
	next_round.pressed.connect(_continue_round)
	summary_box.add_child(next_round)

	end_panel = _centered_panel(root)
	var end_box := VBoxContainer.new()
	end_box.add_theme_constant_override("separation", 10)
	end_panel.add_child(end_box)
	end_label = Label.new()
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_box.add_child(end_label)
	var again := Button.new()
	again.text = "다시 하기"
	again.pressed.connect(_start_run)
	end_box.add_child(again)
	var menu := Button.new()
	menu.text = "메뉴로"
	menu.pressed.connect(_to_menu)
	end_box.add_child(menu)


func _centered_panel(root: Control) -> PanelContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	return panel


func _to_menu() -> void:
	get_tree().change_scene_to_file("res://main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_ESCAPE:
		_to_menu()
	elif sim == null:
		var main_index: int = event.physical_keycode - KEY_1
		if main_index >= 0 and main_index < MAIN_WEAPONS.size():
			_begin_run(MAIN_WEAPONS[main_index])
	elif not sim.pending_choices.is_empty():
		var index: int = event.physical_keycode - KEY_1
		if index >= 0 and index < sim.pending_choices.size():
			_choose(index)
	elif summary_panel.visible and event.physical_keycode == KEY_SPACE:
		_continue_round()


func _process(delta: float) -> void:
	if sim == null:
		return
	acc += delta
	while acc >= sim.tick:
		acc -= sim.tick
		sim.step(_read_input())
		_consume_events()
	if not sim.pending_choices.is_empty():
		acc = 0.0
		if not choice_panel.visible:
			_show_choices()
	elif not sim.round_summary.is_empty():
		acc = 0.0
		if not summary_panel.visible:
			_show_summary()
	if sim.is_over() and not end_panel.visible:
		_show_end()
	_update_timers(delta)
	_update_hud()
	queue_redraw()


func _read_input() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1.0
	return dir


func _consume_events() -> void:
	for event in sim.events:
		match event.type:
			"aura":
				effects.append({"kind": "ring", "pos": event.pos, "radius": event.radius, "time": 0.2, "max": 0.2, "color": COLOR_HOSTILE if event.hostile else COLOR_PLAYER})
			"burst":
				effects.append({"kind": "ring", "pos": event.pos, "radius": event.radius, "time": 0.2, "max": 0.2, "color": COLOR_AWAKEN})
			"awaken":
				_show_banner("각성! %s" % event.name)
			"pickup":
				_show_banner("%s 획득" % event.name)
			"lightning":
				effects.append({"kind": "bolt", "pos": event.pos, "radius": event.radius, "time": 0.25, "max": 0.25, "color": Color.WHITE})
			"ghost":
				_show_banner("%s 등장!" % event.label)
			"boss_warning":
				_show_banner("경고: 군단장이 접근합니다")
			"boss":
				_show_banner("%s 등장! 과거의 나 총출동" % event.label)
			"round":
				_show_banner("라운드 %d: 지난 빌드가 돌아옵니다" % event.round)
	sim.events.clear()


func _update_timers(delta: float) -> void:
	var alive: Array = []
	for effect in effects:
		effect.time -= delta
		if effect.time > 0.0:
			alive.append(effect)
	effects = alive
	banner_time = maxf(0.0, banner_time - delta)
	banner.visible = banner_time > 0.0


func _show_banner(text: String) -> void:
	banner.text = text
	banner_time = 2.5


func _time_text() -> String:
	var limit := float(data.round_seconds)
	if sim.round_time > limit:
		return "시간 초과 +%d초: 군단장 광폭화" % int(sim.round_time - limit)
	if sim.round_time < float(data.boss_at):
		return "군단장까지 %d초" % ceili(float(data.boss_at) - sim.round_time)
	return "보너스 제한 %d초" % ceili(limit - sim.round_time)


func _update_hud() -> void:
	hud.text = "라운드 %d/%d   %s\n레벨 %d   처치 %d   과거의 나 처치 %d" % [
		sim.round_index, int(data.rounds), _time_text(), sim.level, sim.kills, sim.ghost_kills,
	]
	build_label.text = "빌드: " + _build_text(sim.build)


func _build_text(target_build: Dictionary) -> String:
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


func _show_choices() -> void:
	for child in choice_box.get_children():
		choice_box.remove_child(child)
		child.queue_free()
	var title := Label.new()
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
		button.custom_minimum_size = Vector2(440, 78)
		if sim.is_awakening_option(option_id):
			button.add_theme_color_override("font_color", COLOR_AWAKEN)
		button.pressed.connect(_choose.bind(i))
		choice_box.add_child(button)
	choice_panel.show()


func _choose(index: int) -> void:
	sim.choose(index)
	choice_panel.hide()
	if not sim.pending_choices.is_empty():
		_show_choices()


func _show_summary() -> void:
	var summary: Dictionary = sim.round_summary
	var preview: Dictionary = sim.ghost_preview("")
	var bonus := "제한 시간 안에 처치! 보너스 레벨 업 획득" if summary.in_time else "제한 시간 초과: 보너스 없음"
	summary_label.text = "라운드 %d 돌파!\n군단장 처치 %d초   %s\n\n이번 빌드\n%s\n\n다음 라운드에 돌아오는 과거의 나\n%s" % [
		summary.round, int(summary.fight_time), bonus, _build_text(sim.build), _preview_text(preview),
	]
	summary_panel.show()


func _continue_round() -> void:
	sim.continue_round()
	summary_panel.hide()


func _show_end() -> void:
	var title := "승리! 군단을 넘어섰습니다" if sim.state == "won" else "패배: 라운드 %d" % sim.round_index
	end_label.text = "%s\n레벨 %d   처치 %d   과거의 나 처치 %d   군단장 처치 %d" % [title, sim.level, sim.kills, sim.ghost_kills, sim.boss_log.size()]
	choice_panel.hide()
	summary_panel.hide()
	end_panel.show()


func _draw() -> void:
	var view := get_viewport_rect().size
	if sim == null:
		draw_rect(Rect2(Vector2.ZERO, view), COLOR_BG)
		return
	var alpha: float = clampf(acc / sim.tick, 0.0, 1.0)
	var player: Vector2 = sim.player_prev.lerp(sim.player_pos, alpha)
	camera = player - view * 0.5
	draw_rect(Rect2(Vector2.ZERO, view), COLOR_BG)
	draw_set_transform(-camera)
	_draw_arena()
	for gem in sim.gems:
		draw_circle(gem.pos, 4.0, COLOR_GEM)
	for item in sim.pickups:
		var item_color := COLOR_MAGNET if item.kind == "magnet" else COLOR_POTION
		draw_circle(item.pos, float(data.items.radius), Color(item_color, 0.3))
		draw_arc(item.pos, float(data.items.radius), 0.0, TAU, 24, item_color, 2.0)
		draw_string(ThemeDB.fallback_font, item.pos + Vector2(-40, 5), "자석" if item.kind == "magnet" else "포션", HORIZONTAL_ALIGNMENT_CENTER, 80, 13)
	for strike in sim.strikes:
		var strike_color := COLOR_HOSTILE if strike.hostile else COLOR_AWAKEN
		draw_arc(strike.pos, strike.radius, 0.0, TAU, 48, strike_color, 3.0)
		draw_circle(strike.pos, strike.radius, Color(strike_color, 0.15))
	_draw_auras(player)
	_draw_boss_telegraph()
	for enemy in sim.enemies:
		_draw_enemy(enemy, alpha)
	for shot in sim.projectiles:
		draw_circle(shot.prev.lerp(shot.pos, alpha), shot.radius, COLOR_HOSTILE if shot.hostile else Color.WHITE)
	for effect in effects:
		var fade: float = effect.time / effect.max
		if effect.kind == "ring":
			draw_arc(effect.pos, effect.radius, 0.0, TAU, 48, Color(effect.color, 0.5 * fade), 2.0)
		else:
			draw_circle(effect.pos, effect.radius, Color(effect.color, 0.5 * fade))
			draw_line(effect.pos + Vector2(0, -500), effect.pos, Color(effect.color, fade), 3.0)
	var player_color := COLOR_AWAKEN if sim.is_awakened(sim.build) else COLOR_PLAYER
	draw_circle(player, float(data.player.radius), Color.WHITE if sim.player_flash > 0.0 else player_color)
	draw_set_transform(Vector2.ZERO)
	_draw_bars(view)


func _draw_arena() -> void:
	var size := Vector2(float(data.arena.w), float(data.arena.h))
	for x in range(0, int(size.x) + 1, 100):
		draw_line(Vector2(x, 0), Vector2(x, size.y), COLOR_GRID)
	for y in range(0, int(size.y) + 1, 100):
		draw_line(Vector2(0, y), Vector2(size.x, y), COLOR_GRID)
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE, false, 2.0)


func _draw_auras(player: Vector2) -> void:
	if int(sim.build.weapons.aura) > 0:
		var color := COLOR_AWAKEN if sim.main_weapon == "aura" and sim.is_awakened(sim.build) else COLOR_PLAYER
		draw_circle(player, sim.weapon_stats("aura", sim.build).radius, Color(color, 0.08))
	for enemy in sim.enemies:
		if enemy.kind == "ghost" and int(enemy.build.weapons.aura) > 0:
			draw_circle(enemy.pos, sim.weapon_stats("aura", enemy.build).radius * float(data.weapons.aura.hostile_radius_mult), Color(COLOR_HOSTILE, 0.12))


func _draw_boss_telegraph() -> void:
	if sim.boss == null or sim.boss_state != "windup":
		return
	var pattern: Dictionary = sim.boss_pattern
	match pattern.type:
		"charge":
			var length := float(pattern.speed) * float(pattern.duration)
			var end: Vector2 = sim.boss.pos + sim.charge_dir * length
			draw_line(sim.boss.pos, end, Color(COLOR_BOSS, 0.55), sim.boss.radius * 2.0)
		"ring":
			draw_arc(sim.boss.pos, sim.boss.radius + 26.0, 0.0, TAU, 48, COLOR_HOSTILE, 5.0)
		"summon":
			draw_arc(sim.boss.pos, 120.0, 0.0, TAU, 48, COLOR_GHOST, 3.0)


func _draw_enemy(enemy, alpha: float) -> void:
	var pos: Vector2 = enemy.prev.lerp(enemy.pos, alpha)
	var color := COLOR_GRUNT
	match enemy.kind:
		"runner":
			color = COLOR_RUNNER
		"ghost":
			color = COLOR_AWAKEN if sim.is_awakened(enemy.build) else COLOR_GHOST
		"boss":
			color = COLOR_BOSS
	draw_circle(pos, enemy.radius, Color.WHITE if enemy.flash > 0.0 else color)
	if enemy.kind == "ghost":
		var font := ThemeDB.fallback_font
		draw_string(font, pos + Vector2(-80, -enemy.radius - 18), enemy.label, HORIZONTAL_ALIGNMENT_CENTER, 160, 14)
		var bar := Rect2(pos + Vector2(-30, -enemy.radius - 12), Vector2(60, 5))
		draw_rect(bar, Color.BLACK)
		draw_rect(Rect2(bar.position, Vector2(60.0 * maxf(enemy.hp, 0.0) / enemy.max_hp, 5)), COLOR_GHOST)


func _draw_bars(view: Vector2) -> void:
	var hp_bar := Rect2(16, 10, minf(320.0, view.x - 32.0), 16)
	draw_rect(hp_bar, Color.BLACK)
	draw_rect(Rect2(hp_bar.position, Vector2(hp_bar.size.x * maxf(sim.hp, 0.0) / sim.max_hp, hp_bar.size.y)), COLOR_GRUNT)
	var xp_bar := Rect2(0, view.y - 8, view.x, 8)
	draw_rect(xp_bar, Color.BLACK)
	draw_rect(Rect2(xp_bar.position, Vector2(view.x * float(sim.xp) / sim.xp_needed(), 8)), COLOR_GEM)
	if sim.boss != null and sim.boss.hp > 0.0:
		var width := minf(520.0, view.x - 40.0)
		var boss_bar := Rect2((view.x - width) * 0.5, 44, width, 18)
		var title: String = sim.boss.label + (" (광폭화)" if sim.is_enraged() else "")
		draw_string(ThemeDB.fallback_font, Vector2(boss_bar.position.x, 38), title, HORIZONTAL_ALIGNMENT_CENTER, width, 18)
		draw_rect(boss_bar, Color.BLACK)
		draw_rect(Rect2(boss_bar.position, Vector2(width * sim.boss.hp / sim.boss.max_hp, 18)), COLOR_BOSS)
