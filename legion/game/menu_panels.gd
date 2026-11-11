extends RefCounted
## 타이틀에서 여는 창: 설정, 게임 방법.
## 각 함수는 화면 전체를 덮는 창을 만들어 돌려준다. 닫기를 누르면 창이 스스로 사라지고 on_close가 불린다.

const UiTheme := preload("res://legion/game/ui_theme.gd")

const PANEL_WIDTH := 760.0
const HOW_TO_PAGES := [
	{
		"title": "목표", "sprite": "res://legion/art/player.png",
		"body": "라운드마다 100초를 버티고 보스를 쓰러뜨리세요.\n5라운드를 모두 넘기면 승리합니다.\n\n이동은 WASD 또는 방향키, 공격은 자동입니다.",
	},
	{
		"title": "과거의 나", "sprite": "res://legion/art/player.png", "tint": Color(0.85, 0.55, 1.0, 0.85),
		"body": "레벨 업으로 고른 빌드는 다음 라운드에\n'과거의 나'가 되어 적으로 돌아옵니다.\n\n강해질수록 미래의 적도 강해집니다.\n레벨 업 화면에서 과거의 나가 어떻게 바뀌는지 미리 볼 수 있습니다.",
	},
	{
		"title": "레벨 업과 각성", "sprite": "res://legion/art/potion.png",
		"body": "초록 보석을 모으면 레벨이 오릅니다.\n선택지는 1, 2, 3 키나 마우스로 고릅니다.\n\n메인 무기가 5레벨이 되면 각성해 크게 강해집니다.\n각성은 2라운드부터 가능합니다.",
	},
	{
		"title": "궁극기", "sprite": "res://legion/art/magnet.png",
		"body": "적을 80명 처치하면 궁극기가 찹니다.\nSpace를 누르면 발동하고, 잠시 무적이 됩니다.\n\n마력탄은 사방으로 탄환을, 가시 오라는 큰 폭발을,\n낙뢰는 연속 낙뢰를, 시간의 실은 거대한 고리를 터뜨립니다.",
	},
	{
		"title": "시간의 실", "sprite": "res://legion/art/player.png",
		"body": "시간의 실은 조준하지 않습니다. 지나간 자리에 실이 남아 닿는 적을 벱니다.\n\n적을 빙 둘러 걸어 실 끝을 실에 다시 닿게 하면\n고리가 닫히며 안쪽이 한꺼번에 터집니다.\n\n다음 라운드의 과거의 나는 내가 걸었던 길을 그대로 걷습니다.\n내가 그린 고리가 함정이 되어 돌아옵니다.",
	},
	{
		"title": "포탈과 보스 방", "sprite": "res://legion/art/boss.png",
		"body": "70초에 보스 방 포탈이 열립니다.\n들어가면 보스와 과거의 나 전원이 기다립니다.\n\n100초까지 들어가지 않으면 강제로 끌려가고 보스가 광폭화합니다.\n100초 안에 보스를 잡으면 보너스 레벨 업을 받습니다.",
	},
	{
		"title": "보물상자와 룰렛", "sprite": "res://legion/art/chest.png",
		"body": "적이 떨어뜨린 금화로 보물상자와 미믹 룰렛을,\n체력으로 피의 제단을 쓸 수 있습니다. 위에 1초 서 있으면 작동합니다.\n\n상자와 룰렛의 레벨 업은 과거의 나에게도 복사됩니다.\n보호막, 광폭, 폭탄 같은 1회용 효과는 복사되지 않습니다.",
	},
]


static func build_settings(settings: Node, on_close: Callable) -> Control:
	var window := _window("설정", on_close)
	var box: VBoxContainer = window.get_meta("box")
	box.add_child(_slider_row("효과음", settings.sfx_volume, func(v: float) -> void: settings.set_value("sfx_volume", v)))
	box.add_child(_slider_row("음악", settings.music_volume, func(v: float) -> void: settings.set_value("music_volume", v)))
	box.add_child(_toggle("전체 화면", settings.fullscreen, func(on: bool) -> void: settings.set_value("fullscreen", on)))
	box.add_child(_toggle("화면 흔들림과 번쩍임", settings.screen_shake, func(on: bool) -> void: settings.set_value("screen_shake", on)))
	box.add_child(_toggle("2배속", settings.double_speed, func(on: bool) -> void: settings.set_value("double_speed", on)))
	box.add_child(_text("조작키\n이동: WASD / 방향키    선택: 1, 2, 3\n궁극기, 컷신 건너뛰기, 다음 라운드: Space    메뉴로: Esc", UiTheme.FONT_SMALL * 2))
	_add_close(window, box, on_close)
	return window


## 페이지를 넘기며 보는 게임 방법. 좌우 방향키로도 넘긴다.
static func build_how_to(on_close: Callable) -> Control:
	var window := _window("게임 방법", on_close)
	var box: VBoxContainer = window.get_meta("box")
	var picture := TextureRect.new()
	picture.custom_minimum_size = Vector2(96, 96)
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(picture)
	var heading := _text("", UiTheme.FONT_LARGE)
	box.add_child(heading)
	var body := _text("", UiTheme.FONT_NORMAL)
	body.custom_minimum_size = Vector2(PANEL_WIDTH - 80, 220)
	box.add_child(body)
	var page_label := _text("", UiTheme.FONT_SMALL * 2)
	box.add_child(page_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	var prev := _button("이전")
	var next := _button("다음")
	var close := _button("닫기")
	for button in [prev, next, close]:
		buttons.add_child(button)
	var state := {"page": 0}
	var show_page := func(index: int) -> void:
		state.page = clampi(index, 0, HOW_TO_PAGES.size() - 1)
		var page: Dictionary = HOW_TO_PAGES[state.page]
		picture.texture = load(page.sprite)
		picture.modulate = page.get("tint", Color.WHITE)
		heading.text = page.title
		body.text = page.body
		page_label.text = "%d / %d" % [state.page + 1, HOW_TO_PAGES.size()]
		prev.disabled = state.page == 0
		next.disabled = state.page == HOW_TO_PAGES.size() - 1
	prev.pressed.connect(func() -> void: show_page.call(state.page - 1))
	next.pressed.connect(func() -> void: show_page.call(state.page + 1))
	close.pressed.connect(_closer(window, on_close))
	window.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == KEY_LEFT:
				show_page.call(state.page - 1)
			elif event.physical_keycode == KEY_RIGHT:
				show_page.call(state.page + 1))
	show_page.call(0)
	next.call_deferred("grab_focus")
	return window


# --- 부품 ---

## 화면을 어둡게 덮고 가운데에 양피지 창을 띄운다. 창 안의 세로 상자는 meta "box"에 담는다.
static func _window(title: String, on_close: Callable) -> Control:
	var window := Control.new()
	window.set_anchors_preset(Control.PRESET_FULL_RECT)
	window.focus_mode = Control.FOCUS_ALL
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	window.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	window.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_text(title, UiTheme.FONT_LARGE))
	window.set_meta("box", box)
	# Esc로도 닫는다.
	window.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			window.accept_event()
			_closer(window, on_close).call())
	window.call_deferred("grab_focus")
	return window


static func _closer(window: Control, on_close: Callable) -> Callable:
	return func() -> void:
		window.queue_free()
		if on_close.is_valid():
			on_close.call()


static func _add_close(window: Control, box: VBoxContainer, on_close: Callable) -> void:
	var close := _button("닫기")
	close.pressed.connect(_closer(window, on_close))
	box.add_child(close)
	close.call_deferred("grab_focus")


static func _text(text: String, size: int) -> Label:
	var label := Label.new()
	label.theme_type_variation = "PanelLabel"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	return label


static func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 0)
	return button


static func _slider_row(name: String, value: float, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := _text(name, UiTheme.FONT_NORMAL)
	label.custom_minimum_size = Vector2(200, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(0, 32)
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	return row


static func _toggle(name: String, on: bool, on_change: Callable) -> Control:
	var toggle := CheckButton.new()
	toggle.text = name
	toggle.button_pressed = on
	toggle.toggled.connect(on_change)
	return toggle
