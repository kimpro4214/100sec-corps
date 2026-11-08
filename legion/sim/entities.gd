extends RefCounted
## 100초 군단 sim이 다루는 개체 데이터. 행동 규칙은 각 시스템 파일에 있다.


class Enemy:
	var kind := ""
	var label := ""
	var pos := Vector2.ZERO
	var prev := Vector2.ZERO
	var hp := 1.0
	var max_hp := 1.0
	var speed := 0.0
	var radius := 1.0
	var contact := 0.0
	var xp := 1
	var build := {}
	var timers := {}
	var flash := 0.0
	var damage_mult := 1.0
	var keep_distance := 0.0
	var born := 0.0
	var slow_time := 0.0
	var slow_amount := 0.0

	func current_speed() -> float:
		if slow_time > 0.0:
			return speed * maxf(0.2, 1.0 - slow_amount)
		return speed


class Projectile:
	var pos := Vector2.ZERO
	var prev := Vector2.ZERO
	var vel := Vector2.ZERO
	var damage := 0.0
	var radius := 1.0
	var life := 1.0
	var hostile := false
	var source := ""
	var pierce := 0
	var hit_list: Array = []
	var splash_radius := 0.0
	var splash_mult := 0.0


class Strike:
	var pos := Vector2.ZERO
	var delay := 0.0
	var damage := 0.0
	var radius := 1.0
	var source := ""
	var hostile := true


class Gem:
	var pos := Vector2.ZERO
	var value := 1
	var attracted := false
	var gold := false # true면 경험치 대신 금화


## 필드에 놓인 상호작용 오브젝트(보물상자, 룰렛, 제단). 위에 서 있으면 progress가 차고, 다 차면 작동한다.
class Interactable:
	var kind := ""
	var pos := Vector2.ZERO
	var used := false
	var progress := 0.0
	var last_reward := ""


class Pickup:
	var kind := ""
	var pos := Vector2.ZERO
	var life := 0.0
