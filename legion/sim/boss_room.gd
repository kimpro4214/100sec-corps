extends RefCounted
## 넓은 필드에서 보스 방으로 넘어가는 흐름.
## boss_at초에 포탈이 열리고, 플레이어가 들어가거나 round_seconds초가 되면 보스 방으로 옮겨진다.
## 보스 방은 필드 오른쪽에 떨어진 작은 공간이고, 들어가는 순간 필드의 적과 아이템은 사라진다.

const Loot := preload("res://legion/sim/loot.gd")


static func field_rect(data: Dictionary) -> Rect2:
	return Rect2(0.0, 0.0, float(data.arena.w), float(data.arena.h))


static func room_rect(data: Dictionary) -> Rect2:
	var room: Dictionary = data.boss_room
	return Rect2(float(data.arena.w) + float(room.gap), 0.0, float(room.w), float(room.h))


static func update(sim) -> void:
	if sim.in_boss_room:
		return
	var open_at := float(sim.data.boss_at)
	if not sim.boss_warned and sim.round_time >= open_at - float(sim.data.boss.warning_seconds):
		sim.boss_warned = true
		sim.emit_event({"type": "boss_warning"})
	if not sim.portal_open and sim.round_time >= open_at:
		_open_portal(sim)
	if not sim.portal_open:
		return
	var reach := float(sim.data.boss_room.portal_radius) + float(sim.data.player.radius)
	if sim.player_pos.distance_to(sim.portal_pos) <= reach:
		_enter(sim, false)
	elif sim.round_time >= float(sim.data.round_seconds):
		_enter(sim, true)


static func _open_portal(sim) -> void:
	sim.portal_open = true
	var margin := 120.0
	var field := field_rect(sim.data).grow(-margin)
	var angle: float = sim.rng.randf() * TAU
	var pos: Vector2 = sim.player_pos + Vector2.from_angle(angle) * float(sim.data.boss_room.portal_distance)
	sim.portal_pos = pos.clamp(field.position, field.end)
	sim.emit_event({"type": "portal", "pos": sim.portal_pos})


## 필드에 남은 보석과 금화는 바로 받고, 나머지는 치운 뒤 보스 방 아래쪽에 선다.
static func _enter(sim, forced: bool) -> void:
	for gem in sim.gems:
		Loot.take_gem(sim, gem)
	# 타입이 정해진 배열이라 새 배열을 넣지 않고 비운다.
	sim.gems.clear()
	sim.enemies.clear()
	sim.projectiles.clear()
	sim.strikes.clear()
	sim.zones.clear()
	sim.pickups.clear()
	sim.in_boss_room = true
	sim.area = room_rect(sim.data)
	sim.player_pos = sim.area.position + Vector2(sim.area.size.x * 0.5, sim.area.size.y * 0.75)
	sim.player_prev = sim.player_pos
	sim.emit_event({"type": "boss_room", "forced": forced})
