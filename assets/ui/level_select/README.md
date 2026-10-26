# 选关页美术资源

- `map_background.png`：使用内置 Imagegen 编辑用户提供的选关参考图，移除UI后得到的背景。它保留参考的几何构图，但属于重建背景，不是逐像素复印；文字、入口和路线由Godot节点显示。
- `ring*.svg`、`center*.svg`、`lock.svg`等：简单可缩放的矢量界面元素，实际由TextureRect/Sprite2D使用。
- `map_theme.tres`：本页与关卡入口共用的主题；引用`assets/fonts`中的外部字体。
- `title_font.tres`：标题粗体及额外字距。

背景生成使用的提示词：

> Use case: precise-object-edit. Edit target: provided 1672x941 wide game level-select artwork. Deliver ONLY a clean background texture for the same UI, 16:9 landscape. Remove ALL Chinese text, numbers 01-08, title, return label, chapter labels, every small circular level marker including locks and orange center marker, their grey connecting lines, short dark horizontal underlines and endpoint dots associated with UI. Inpaint removed areas seamlessly with the existing cream paper/grain underneath. Preserve the exact geometric background composition and texture: huge cropped peach circle top left, cropped teal circle upper right, muted mauve triangular field top, broad diagonally bounded cream empty middle, dark charcoal lower-left sloped band and teal accent, peach semicircle lower right, faceted translucent white crystal glacier corner bottom right, thin large WHITE decorative curves and white diagonals near edges. Do not erase the large white decorative edge curves. Do not move, recolor or redesign these major background shapes. Keep identical style, layout, rough paper grain, pastel palette, aspect ratio and visual boundaries. NO UI, NO lettering, NO digits, NO level rings, NO grey route lines anywhere. This background will be overlaid with actual Godot nodes for all UI. Exact background restoration, not a redesigned illustration.
