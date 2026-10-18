@tool
class_name RefractSurfaceBlock
extends RefractSurface

## 折射介质积木：薄壳，实现已并入 core/refract_surface.gd（框架统一维护，
## 含 FIXED/SNELL 两种模式与分光/变色扩展）。碰撞层 4 由基类自动设置。
## 参数：mode、bend_degrees（正 = 顺时针）、ior、attenuation、split、recolor、output_color。
## 示例关卡：level_02_折射入门。
