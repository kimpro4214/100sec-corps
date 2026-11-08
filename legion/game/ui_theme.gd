extends RefCounted
## 100초 군단 화면 전체가 함께 쓰는 픽셀 UI 테마. 게임 화면, 타이틀, 설정, 게임 방법이 같은 모양을 쓴다.
## 패널과 버튼은 Kenney UI Pack - Pixel Adventure(CC0), 글꼴은 갈무리11(OFL).

# 큰 타일 시트를 2배로 키운 것. 한 칸 64px, 가로 13칸.
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
const FONT_LARGE := 48
const FONT_TITLE := 72


## 나무 버튼, 양피지 패널, 리본 배너, 갈무리 폰트를 묶은 테마.
static func build() -> Theme:
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
	var ribbon := _style(Rect2(RIBBON_COLUMN * UI_TILE, RIBBON_ROW * UI_TILE, UI_TILE * 3, UI_TILE), 0.0, 0.0)
	ribbon.texture_margin_left = 48
	ribbon.texture_margin_right = 48
	ribbon.texture_margin_top = 16
	ribbon.texture_margin_bottom = 24
	ribbon.content_margin_left = 64
	ribbon.content_margin_right = 64
	ribbon.content_margin_top = 12
	ribbon.content_margin_bottom = 24
	theme.set_stylebox("normal", "Banner", ribbon)

	theme.set_stylebox("panel", "PanelContainer", _style(_tile_rect(TILE_PARCHMENT), 20.0, 28.0))

	theme.set_stylebox("normal", "Button", _style(_tile_rect(TILE_WOOD), 16.0, 18.0))
	theme.set_stylebox("hover", "Button", _style(_tile_rect(TILE_WOOD_FANCY), 20.0, 18.0))
	theme.set_stylebox("pressed", "Button", _style(_tile_rect(TILE_WOOD), 16.0, 18.0, Color(0.75, 0.75, 0.75)))
	# 키보드로 고를 때도 어디에 있는지 보이게 장식 버튼 모양을 쓴다.
	theme.set_stylebox("focus", "Button", _style(_tile_rect(TILE_WOOD_FANCY), 20.0, 18.0, Color(1.15, 1.1, 1.0)))
	theme.set_color("font_color", "Button", TEXT_LIGHT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", TEXT_LIGHT)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_outline_color", "Button", TEXT_DARK)
	theme.set_constant("outline_size", "Button", 6)

	# 설정 화면의 켜기/끄기는 양피지 위에 바로 놓이므로 나무 배경을 빼고 글자를 어둡게 한다.
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		theme.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	theme.set_constant("outline_size", "CheckButton", 0)
	theme.set_color("font_color", "CheckButton", TEXT_DARK)
	theme.set_color("font_hover_color", "CheckButton", TEXT_DARK)
	theme.set_color("font_pressed_color", "CheckButton", TEXT_DARK)
	theme.set_color("font_focus_color", "CheckButton", TEXT_DARK)
	theme.set_color("font_hover_pressed_color", "CheckButton", TEXT_DARK)
	return theme


static func _tile_rect(index: int) -> Rect2:
	return Rect2((index % UI_COLUMNS) * UI_TILE, (index / UI_COLUMNS) * UI_TILE, UI_TILE, UI_TILE)


static func _style(region: Rect2, margin: float, content: float, tint := Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = UI_SHEET
	style.region_rect = region
	style.set_texture_margin_all(margin)
	style.set_content_margin_all(content)
	style.modulate_color = tint
	return style
