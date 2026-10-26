# 光学积木美术接入

`optics_reference.png` 是提供的四件光学素材原图，带透明背景，未重新绘制。当前只使用最左凸透镜和最右平面镜；凹透镜与三棱镜没有替换。

## 在 Godot 中查看和修改

1. 打开 `blocks/convex_lens/convex_lens.tscn` 或 `blocks/mirror/mirror.tscn`。场景树中的 `Art` 是新增的 `Sprite2D`，真正显示素材的就是这个节点。
2. 点 `Art` 的 `Texture` 资源，展开 `AtlasTexture`。`Atlas` 指向整张原图，`Region` 只取其中一件素材，不需要把 PNG 切成很多文件：
   - 凸透镜：`Rect2(163, 80, 222, 558)`。
   - 平面镜：`Rect2(1855, 104, 156, 516)`。
3. `Art` 挂的 `blocks/optical_art_sprite.gd` 是编辑器也会执行的贴图适配脚本。它按 `CollisionShape2D` 的矩形尺寸缩放图片，调整形状尺寸时美术会跟随。
4. 想调整视觉大小，修改 `Art` 的 `Size Multiplier`：凸镜为 `(1.1, 1.05)`；平面镜为 `(1.15, 0.9)`，略加长并收窄。直接调整积木根节点的缩放会连同碰撞一起变化，单纯改美术时请优先用此倍率。
5. 平面镜原素材为竖条，原有镜面碰撞为横条，所以 `Rotate Texture Quarter Turn` 开启，让贴图转过90°。凸镜保持竖向。

碰撞尺寸仍分别为24×96和64×8，聚光、反射、能量及关卡解法均沿用原逻辑。原脚本的 `_draw()` 占位外观在有 `Art` 贴图时不绘制；删除美术资源后仍保留占位回退。
