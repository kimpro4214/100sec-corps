extends RefCounted
## 100초 군단 화면에서 함께 쓰는 색.

const BG := Color("15171f")
const PLAYER := Color("5ad1ff")
const GHOST := Color("c77dff")
const GRUNT := Color("e0604c")
const RUNNER := Color("f2a541")
const GEM := Color("7ee081")
const HOSTILE := Color("ff5d8f")
const BOSS := Color("d7263d")
const SWARMLING := Color("ffb3a7")
const BRUTE := Color("a4243b")
const POTION := Color("ff8fab")
const MAGNET := Color("8ecbff")
const AWAKEN := Color("ffe066")


static func enemy_color(kind: String) -> Color:
	match kind:
		"runner":
			return RUNNER
		"swarmling":
			return SWARMLING
		"brute":
			return BRUTE
		"ghost":
			return GHOST
		"boss":
			return BOSS
	return GRUNT
