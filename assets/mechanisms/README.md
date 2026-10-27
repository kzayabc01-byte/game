# 机关独立资产

这里保存从原始美术图中分割、紧裁切并缩放后的 Godot 可用资产。原始微信命名 PNG 已归档到 `assets/_source_originals/`，没有被覆盖或删除；该目录含 `.gdignore`，不会被 Godot 当成游戏资产导入。

## 目录

- `optics/`：凸透镜、凹透镜、三棱镜、玻璃板。
- `ice/`：冰川簇和四种冰晶外形。
- `props/`：石块、镜面板。
- `switches/`：圆环和圆盘的不同状态。
- `terrain/`：长条平台、斜坡和楔形地形。
- `textures/`：深色石材、浅色晶体和背景纹理。
- `_source/`：制作源文件和总览图；含 `.gdignore`，Godot 不会导入。
- `manifest.json`：生成文件、来源、用途和尺寸清单。

## 推荐映射

| 现有机关 | 推荐资产 | 说明 |
|---|---|---|
| `convex_lens` | `optics/convex_lens.png` | 已作为完整 Sprite 接入；碰撞与光路逻辑保持独立。 |
| `concave_lens` | `optics/concave_lens.png` | 已作为完整 Sprite 接入；碰撞与光路逻辑保持独立。 |
| `refract_surface` | `optics/glass_plate.png` | 当前碰撞体是横向 `96×8`，显示时需旋转 90° 或调整碰撞方向。 |
| `glacier` | `ice/glacier_cluster.png` 或 `ice/ice_crystal_*` | 先保留矩形碰撞；若改轮廓碰撞，需要同步融化时的禁用逻辑。 |
| `stone_block` | `props/stone_a.png`、`stone_b.png`、`stone_c.png` | 可随机选择外观，但继续使用原 `CharacterBody2D`。 |
| `mirror` | `props/mirror_panel_clean.png` | 已直接接入透明边缘清理版，薄片碰撞保持不变。 |
| `trigger_switch` | `switches/ring_neutral.png`、`switches/ring_cyan.png` | 分别作为未激活与激活状态。 |
| `pressure_sensor` | `switches/disc_orange.png`、`switches/disc_cyan.png` | 作为未按下与按下状态，具体颜色可互换。 |
| `light_source` | `switches/ring_orange.png` | 保留脚本绘制的方向箭头或另加 Overlay。 |
| `wall` / `opaque_wall` | `textures/dark_stone.png` | 已用重复纹理填充现有矩形碰撞轮廓。 |
| `dark_slope_*` | `textures/dark_stone.png` | 已建立短、长两种 `CollisionPolygon2D`，显示与碰撞共用轮廓。 |

`portal`、`light_source`、`trigger_switch` 和 `pressure_sensor` 继续用程序轮廓，只复用素材提取出的青色、橙色状态色。`cocoon` 和 `action_link` 在这批原始美术中没有明确的专属模型，不强行错配。

## Godot 使用方式

机关根节点、脚本和碰撞体继续保留，只增加显示节点：

```text
MechanismRoot
├── CollisionShape2D
└── Visual (Node2D)
    ├── Inactive (Sprite2D，可选)
    └── Active (Sprite2D，可选)
```

把对应 PNG 拖到 `Sprite2D.texture`，再按碰撞体尺寸设置 `scale`。状态机关切换两个 Sprite 的 `visible`，静态机关只需要一个 Sprite。

## 重新生成

```powershell
python tools/split_mechanism_assets.py
```

生成脚本从 `assets/_source_originals/` 读取原图，只覆盖 `assets/mechanisms/` 中由它维护的同名输出，不修改原始素材。
