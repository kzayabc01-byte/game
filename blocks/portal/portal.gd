@tool
class_name PortalBlock
extends Portal

## 传送门积木：薄壳，实现已并入 core/portal.gd（框架统一维护）。
## 语义：一对平面 —— 从 A 面射入，从 B 面对应位置、对应方向射出
## （切向保留、法向取反；mirror_out 时切向再取反）。
## 参数：linked_portal（显式配对）或 pair_id（同 id 自动配对）、
##       mirror_out、one_way、energy_cost、auto_link。
## 碰撞层 5 由基类自动设置。示例关卡：level_05_传送门。
