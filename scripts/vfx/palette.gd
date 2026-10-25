## Neon Arcade palette (see the visual design spec). Colors pushed above 1.0
## with hdr() cross the WorldEnvironment glow threshold and bloom.
extends RefCounted

const BG := Color("07070f")
const GRID := Color(0.2, 0.2, 0.5, 0.6)
const P1 := Color("00e5ff")
const P2 := Color("ff2bd6")
const BALL := Color.WHITE
const WALL := Color(0.9, 0.9, 1.0)
const NET := Color(0.9, 0.9, 1.0, 0.35)
const SCORE := Color(0.9, 0.9, 1.0, 0.2)
const ACCENT := Color("ffe14d")
const UI_TEXT := Color("e6e6ff")
const UI_MUTED := Color("8c8cb4")
const UI_PANEL := Color(0.06, 0.06, 0.12, 0.92)
const UI_LINE := Color("26264a")

const GLOW := 2.0 # paddles, ball
const GLOW_SOFT := 1.3 # walls, sparks


static func side_color(side: int) -> Color:
	return P1 if side == 0 else P2


static func hdr(c: Color, k: float = GLOW) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)
