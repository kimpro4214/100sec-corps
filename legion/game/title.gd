extends Node2D
## 100초 군단 타이틀. 빌드를 켜면 가장 먼저 나오는 화면이다.
## 배경에서는 마법사와 뒤따르는 과거의 나가 걷고, 적들이 오른쪽에서 몰려온다.

const UiTheme := preload("res://legion/game/ui_theme.gd")
const MenuPanels := preload("res://legion/game/menu_panels.gd")
const Animator := preload("res://legion/game/animator.gd")
const Sfx := preload("res://legion/game/sfx.gd")
const Palette := preload("res://legion/game/palette.gd")
const GAME_SCENE := "res://legion/game/legion_game.tscn"

const TILE := 48
const FLOOR := preload("res://legion/art/floor.png")
const FLOOR_ROCKS := preload("res://legion/art/floor_rocks.png")
const PLAYER := preload("res://legion/art/player.png")
const MARCHERS := [
	preload("res://legion/art/grunt.png"),
	preload("res://legion/art/swarmling.png"),
	preload("res://legion/art/runner.png"),
	preload("res://legion/art/brute.png"),
]
const SCROLL_SPEED := 40.0
const MARCH_SPEED := 70.0

var time := 0.0
var marchers: Array = []
var ui_root: Control
var menu: VBoxContainer
var sfx: Sfx


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sfx = Sfx.new()
	add_child(sfx)
	sfx.play_music("field")
	sfx.watch_buttons()
	for i in 14:
		marchers.append({"x": randf() * 1600.0, "lane": randf_range(0.62, 0.92), "sprite": randi() % MARCHERS.size(), "seed": randf() * TAU})
	_build_ui()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ui_root.theme = UiTheme.build()
	layer.add_child(ui_root)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	ui_root.add_child(column)

	var logo := Label.new()
	logo.text = "100초 군단"
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_font_size_override("font_size", UiTheme.FONT_TITLE + UiTheme.FONT_NORMAL)
	logo.add_theme_constant_override("outline_size", 16)
	logo.add_theme_color_override("font_color", Palette.AWAKEN)
	column.add_child(logo)

	var subtitle := Label.new()
	subtitle.text = "100초마다, 지난 내가 돌아온다"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_constant_override("outline_size", 8)
	column.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	column.add_child(spacer)

	var center := CenterContainer.new()
	column.add_child(center)
	menu = VBoxContainer.new()
	menu.add_theme_constant_override("separation", 8)
	center.add_child(menu)
	_add_button("시작하기", _start)
	_add_button("게임 방법", _open.bind("how_to"))
	_add_button("설정", _open.bind("settings"))
	# 웹 빌드에서는 브라우저 탭을 닫으면 되므로 종료 버튼을 숨긴다.
	if not OS.has_feature("web"):
		_add_button("종료", get_tree().quit)
	menu.get_child(0).call_deferred("grab_focus")


func _add_button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 0)
	button.pressed.connect(action)
	menu.add_child(button)


func _start() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _open(kind: String) -> void:
	menu.visible = false
	var reopen := func() -> void:
		menu.visible = true
		menu.get_child(0).grab_focus()
	var window: Control
	match kind:
		"how_to":
			window = MenuPanels.build_how_to(reopen)
		"settings":
			window = MenuPanels.build_settings(get_node("/root/Settings"), reopen)
	ui_root.add_child(window)


func _process(delta: float) -> void:
	time += delta
	for marcher in marchers:
		marcher.x -= MARCH_SPEED * delta
		if marcher.x < -80.0:
			marcher.x += 1700.0
	queue_redraw()


func _draw() -> void:
	var view := get_viewport_rect().size
	# 천천히 왼쪽으로 흐르는 바닥.
	var offset := fmod(time * SCROLL_SPEED, TILE)
	for x in range(-1, int(view.x / TILE) + 2):
		for y in range(0, int(view.y / TILE) + 1):
			var world_x := x + int(time * SCROLL_SPEED / TILE)
			var tex: Texture2D = FLOOR_ROCKS if hash(Vector2i(world_x, y)) % 23 == 0 else FLOOR
			draw_texture_rect(tex, Rect2(x * TILE - offset, y * TILE, TILE, TILE), false, Color(0.3, 0.28, 0.36))
	# 오른쪽에서 몰려오는 적들.
	for marcher in marchers:
		var pose := Animator.hop("grunt", time, marcher.seed)
		_draw_sprite(MARCHERS[marcher.sprite], Vector2(marcher.x, view.y * marcher.lane), 3, pose, -1.0, Color(0.85, 0.8, 0.85))
	# 걷는 마법사와 뒤에서 떠다니는 과거의 나.
	var hero := Vector2(view.x * 0.28, view.y * 0.78)
	_draw_sprite(PLAYER, hero - Vector2(90, 20), 4, Animator.float_ghost(time, 1.0), 1.0, Color(0.85, 0.55, 1.0, 0.8))
	_draw_sprite(PLAYER, hero, 4, Animator.hop("player", time, 0.0), 1.0, Color.WHITE)
	# 위아래를 어둡게 눌러 로고와 메뉴를 돋보이게 한다.
	draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 0.35))


func _draw_sprite(tex: Texture2D, feet: Vector2, scale: int, pose: Dictionary, facing: float, tint: Color) -> void:
	var size: Vector2 = Vector2.ONE * 16 * scale * pose.squash
	var lift: float = pose.lift
	draw_circle(feet + Vector2(0, -4), size.x * 0.28, Color(0, 0, 0, 0.35))
	var top_left := feet - Vector2(size.x * 0.5, size.y + lift)
	var rect := Rect2(top_left, Vector2(size.x * facing, size.y))
	draw_texture_rect(tex, rect, false, tint * pose.tint)
