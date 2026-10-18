@tool
class_name PortalBlock
extends Portal

## 传送门积木：薄壳，实现已并入 core/portal.gd（框架统一维护，
## 含保角传送 / 镜像出射 / 自动互链）。碰撞层 5 由基类自动设置。
## 参数：linked_portal、mirror_out、energy_cost、auto_link。
## 示例关卡：level_05_传送门。
