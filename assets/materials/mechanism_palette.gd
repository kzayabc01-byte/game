class_name MechanismPalette
extends RefCounted
## 从用户机关素材中提取的统一状态色；程序绘制机关只取色，不复用原图轮廓。

const CYAN_GLOW := Color("45c7bd")
const ORANGE_GLOW := Color("ff8168")
const DARK_SURFACE := Color("20252b")
const LIGHT_EDGE := Color("e7f1ef")
const MUTED_SURFACE := Color("3c444d")


static func concentrate(neutral: Color, target: Color, amount: float) -> Color:
	return neutral.lerp(target, clampf(amount, 0.0, 1.0))
