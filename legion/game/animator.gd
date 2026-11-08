extends RefCounted
## 스프라이트 한 장짜리 캐릭터에 움직임을 주는 절차적 애니메이션.
## 게임 시간과 상태만 받아 자세(띄움, 찌그러짐, 흔들림, 색)를 계산한다. 그리는 일은 WorldRenderer가 한다.

const NEUTRAL := {"lift": 0.0, "squash": Vector2.ONE, "offset": Vector2.ZERO, "tint": Color.WHITE}

# 종류별 걸음: 초당 위상 속도, 뜨는 높이(px), 착지할 때 찌그러지는 정도.
const HOP := {
	"grunt": {"rate": 9.0, "height": 4.0, "squash": 0.12},
	"runner": {"rate": 15.0, "height": 3.0, "squash": 0.1},
	"brute": {"rate": 5.0, "height": 6.0, "squash": 0.2},
	"player": {"rate": 12.0, "height": 4.0, "squash": 0.12},
}


## 통통 튀는 걸음. 땅에 닿는 순간 옆으로 퍼지고, 공중에서는 살짝 길어진다.
static func hop(kind: String, t: float, seed: float) -> Dictionary:
	var cfg: Dictionary = HOP[kind]
	var height := absf(sin(t * cfg.rate + seed))
	var landing: float = pow(1.0 - height, 6.0) * cfg.squash
	var stretch := 0.05 * height
	return {
		"lift": height * cfg.height,
		"squash": Vector2(1.0 + landing - stretch, 1.0 - landing + stretch),
		"offset": Vector2.ZERO, "tint": Color.WHITE,
	}


## 제자리에서 숨 쉬듯 위아래로 늘었다 줄었다 한다.
static func breathe(t: float, seed: float) -> Dictionary:
	var s := sin(t * 3.0 + seed) * 0.04
	return {"lift": 0.0, "squash": Vector2(1.0 - s * 0.5, 1.0 + s), "offset": Vector2.ZERO, "tint": Color.WHITE}


## 날갯짓: 위아래로 떠다니며 옆으로 펄럭인다.
static func flap(t: float, seed: float) -> Dictionary:
	var beat := sin(t * 22.0 + seed)
	return {
		"lift": 6.0 + sin(t * 4.0 + seed) * 3.0,
		"squash": Vector2(1.0 + beat * 0.12, 1.0 - beat * 0.06),
		"offset": Vector2.ZERO, "tint": Color.WHITE,
	}


## 과거의 나: 땅에 닿지 않고 천천히 떠다니며 깜빡인다.
static func float_ghost(t: float, seed: float) -> Dictionary:
	return {
		"lift": 8.0 + sin(t * 2.6 + seed) * 4.0,
		"squash": Vector2(1.0, 1.0 + sin(t * 2.6 + seed) * 0.03),
		"offset": Vector2.ZERO,
		"tint": Color(1, 1, 1, 0.85 + 0.15 * sin(t * 9.0 + seed)),
	}


## 군단장: 평소엔 묵직하게 쿵쿵 걷고, 패턴 준비 때는 웅크리며 붉게 떨고, 돌진 때는 앞으로 늘어난다.
static func boss(state: String, timer: float, pattern: Dictionary, t: float) -> Dictionary:
	match state:
		"windup":
			var windup := maxf(float(pattern.get("windup", 1.0)), 0.01)
			var p := clampf(1.0 - timer / windup, 0.0, 1.0)
			var pulse := 0.5 + 0.5 * sin(t * 30.0)
			return {
				"lift": 0.0,
				"squash": Vector2(1.0 + 0.2 * p, 1.0 - 0.2 * p),
				"offset": Vector2(sin(t * 70.0) * 4.0 * p, 0.0),
				"tint": Color.WHITE.lerp(Color(1.8, 0.5, 0.5), p * pulse),
			}
		"charge":
			return {
				"lift": 2.0,
				"squash": Vector2(1.28, 0.8),
				"offset": Vector2.ZERO,
				"tint": Color(1.4, 0.9, 0.9),
			}
	var height := absf(sin(t * 4.0))
	var landing := pow(1.0 - height, 8.0) * 0.18
	return {
		"lift": height * 7.0,
		"squash": Vector2(1.0 + landing - 0.04 * height, 1.0 - landing + 0.04 * height),
		"offset": Vector2.ZERO, "tint": Color.WHITE,
	}


## 맞은 순간 한 번 부풀었다 돌아온다.
static func with_hit(pose: Dictionary, flash: float) -> Dictionary:
	if flash <= 0.0:
		return pose
	var hit := pose.duplicate()
	hit.squash = pose.squash * Vector2(1.12, 0.9)
	return hit
