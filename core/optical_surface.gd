@tool
class_name OpticalSurface
extends StaticBody2D

## 【光路接口契约 v1】所有“会改变光线方向”的积木的基类：
## 折射介质 / 凹透镜 / 冰川 / 传送门。
##
## 契约（框架组与积木组共同遵守；改签名必须升版本号并通知全员）：
##   1. 层号
##        层 4 = 折射体（RayCaster.LAYER_OPTIC = 8）
##        层 5 = 传送门（RayCaster.LAYER_PORTAL = 16）
##   2. 光线系统在光线命中本表面时调用 on_ray()
##   3. 返回 0..N 条出射光线：
##        { "origin": Vector2, "dir": Vector2（单位向量）, "energy": float }
##        可选 "color"（Color）：改变出射光颜色；缺省 = 继承入射颜色
##      返回空数组 = 这条光线被吞掉（吸收 / 没配对的门）
##   4. 能量语义：光源 1.0；镜面 1.0；折射 ×0.95；分束 ×0.6；传送 ×0.8；< 0.15 丢弃
##   5. 失败约定：返回非法数据（零向量 / 负能量 / 起点在自身形状内）由光线系统丢弃并警告，
##      积木不得抛错、不得卡死
##   6. 积木不得在 on_ray() 里做物理查询，也不得改动全局状态
##
## 新增光路积木的步骤：
##   1. extends 本类，实现 on_ray()，碰撞层设为层 4（传送门为层 5）
##   2. 用 @tool + _draw() 画占位外观
##   3. 照 tests/refract_test.tscn 写一个单测，跑 tools\dev.bat 40 通过
##   4. 跑 tools\dev.bat 50 检查积木

const CONTRACT_VERSION := 1


## 光线命中本表面（由光线系统调用，子类重写）
func on_ray(_in_dir: Vector2, _normal: Vector2, _hit_pos: Vector2, _energy: float) -> Array[Dictionary]:
	return []


## 统一构造出射光线（子类用这个，别手搓 Dictionary，容易漏字段）
## color 可选：传入不透明颜色 = 出射光变为该颜色；不传 = 继承入射颜色
static func make_ray(origin: Vector2, dir: Vector2, energy: float, color: Color = Color(0, 0, 0, 0)) -> Dictionary:
	var ray := {
		"origin": origin,
		"dir": dir.normalized(),
		"energy": energy,
	}
	if color.a > 0.0:
		ray["color"] = color
	return ray
