@tool
class_name PortalBlock
extends Portal

## 传送门积木：薄壳，实现已并入 core/portal.gd（框架统一维护）。
## 语义：一对平面 —— 从 A 面射入，从 B 面对应位置、对应方向射出
## （切向保留、法向取反；mirror_out 时切向再取反）。
## 参数：pair_id（同编号配对，也是唯一会存进关卡文件的配对依据）、
##       mirror_out、one_way、energy_cost、length、thickness。
## 配对**与两扇门的距离无关**：没有编号就是未配对（吞光 + 红叉），
## 不会因为“离得近”被自动配到一起。
## 碰撞层 5 由基类自动设置。示例关卡：level_05_传送门。
