extends Node2D
## 다른 객체의 그리기 함수를 대신 호출하는 레이어. 그리는 순서를 노드 순서로 정하려고 쓴다.
## additive가 true면 더하기 혼합이라 빛 효과가 겹칠수록 밝아진다.

var draw_fn: Callable
var additive := false


func _ready() -> void:
	if additive:
		var blend := CanvasItemMaterial.new()
		blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = blend
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func _draw() -> void:
	if draw_fn.is_valid():
		draw_fn.call(self)
