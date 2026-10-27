# 机关材质系统

这里把视觉分成三种模式：`Matte` 哑光石材、`Glass` 透明光学件、`Ice` 浅蓝冰体。墙、遮光墙、石块和斜坡直接引用用户原素材中的 `dark_stone.png`；折射板和冰川直接引用 `light_crystal.png`。Shader 只改变颜色、纹理强度和透明度，不会再用新生成纹理替换原素材。

凸透镜、凹透镜和镜面分别直接使用 `convex_lens.png`、`concave_lens.png` 和 `mirror_panel_clean.png` 完整贴图。贴图节点只跟随碰撞尺寸，不参与光路计算；`Art` 节点另有一层默认不改色的 `adjustable_sprite.gdshader`，方便独立调节色彩浓度、饱和度、亮度、对比度与透明度。

## Inspector 参数

- `Material Mode`：`Matte / Glass / Ice` 三种显示逻辑。
- `Base Color`：材质本身的基础色。
- `Tint Color`：要叠加的目标颜色。
- `Color Concentration`：从基础色混合到目标色的浓度；`0` 只用基础色，`1` 完全使用目标色。
- `Saturation`：饱和度；`0` 为灰度，`1` 为原始值，`2` 为高饱和。
- `Brightness`：明暗。
- `Contrast`：纹理明暗反差。
- `Opacity`：整体透明度。
- `Emission Color / Strength`：发光颜色和强度。实际泛光效果还取决于关卡的 2D HDR/Glow 设置。
- `Texture Detail Strength`：原素材纹理显示强度；数值越高，石材颗粒或晶体切面越明显。
- `Texture Midpoint`：原纹理的平均亮度校准值；已经按石材 `0.234`、晶体 `0.839` 配好，一般不需要改。
- `Edge Highlight Color / Strength`：玻璃或冰的边缘亮色，不会生成内部花纹。
- `Tile Size Pixels`：纹理颗粒尺寸；数值越小，纹理重复越密。
- `Material Texture Scale / Offset`：纹理缩放和偏移，用于避免相邻机关纹理完全一致。

建议先调 `Tint Color` 和 `Color Concentration`，再用 `Saturation` 微调鲜艳程度。不要一开始同时拉高饱和度、对比度和发光，容易丢失材质细节。

## 程序机关状态色

`trigger_switch` 和 `pressure_sensor` 的根节点提供 `Inactive Color`、`Active Color`、`Color Concentration` 与 `Glow Strength`；默认橙色表示未激活或警告，青色表示激活。`light_source` 提供 `Accent Color`、`Color Concentration` 与 `Glow Strength`，光线自身颜色仍由 `Light Color` 独立控制。`portal` 提供 `Color Concentration` 与 `Glow Strength`，不会改变不同传送门配对色的识别逻辑。

默认青色 `#45C7BD`、橙色 `#FF8168` 来自用户圆盘/圆环素材，统一定义在 `mechanism_palette.gd`。这些参数只影响显示，不参与触发条件、光线颜色或碰撞。

## 在 Godot 里怎么调

1. 打开对应机关的 `.tscn` 场景。
2. 在场景树选中 `Visual` 子节点。
3. 在 Inspector 的 `颜色调节 / Color` 分组里修改参数，画面会立即更新。
4. 只改 `Visual`，不要为了颜色去改碰撞形状；机关逻辑和光路不会受影响。

如果是在关卡中的场景实例上单独改色，先对实例开启 `Editable Children`，再选中它内部的 `Visual`。每个 `Visual` 都会创建独立材质，修改一个实例不会串色到其他实例。

## 推荐范围

| 类型 | Color Concentration | Saturation | Brightness | Contrast | Opacity |
| --- | ---: | ---: | ---: | ---: | ---: |
| 墙 / 石块 | 0.05–0.35 | 0.55–0.95 | 0.75–1.10 | 0.80–1.10 | 1.00 |
| 透镜 / 折射面 | 0.05–0.30 | 0.35–0.80 | 0.85–1.10 | 0.80–1.20 | 0.25–0.50 |
| 冰川 | 0.20–0.45 | 0.50–0.85 | 0.85–1.10 | 0.75–1.00 | 0.60–0.82 |

发光强度建议先控制在 `0.00–0.15`；只有关卡需要明显魔法感时再提高。

## 文件

- `../mechanisms/textures/dark_stone.png`：墙体、遮光墙、石块、斜坡直接使用的用户原石材素材。
- `../mechanisms/textures/light_crystal.png`：折射片和冰川直接使用的用户原晶体素材。
- `../mechanisms/textures/light_background.png`：主页、关卡和编辑器共同使用的浅色纹理背景。
- `mechanism_palette.gd`：从圆盘、圆环素材提取的青色与橙色状态色。
- `textures/stone_matte_detail.png`、`textures/ice_frost_detail.png`：第二轮实验文件，保留作比较，当前机关场景没有引用。
- `_source/`：AI 生成的原始材质与平铺预览；有 `.gdignore`，不会进入 Godot 导入列表。
- `mechanism_material_shape_2d.gd`：可复用的多边形材质节点。
- `shaders/textured_shape.gdshader`：统一颜色调节 Shader。
- `shaders/adjustable_sprite.gdshader`：完整贴图专用调色 Shader，默认参数保持原图。
- `mechanism_material_preview.tscn/.png`：实际运行后的机关材质预览。
