class_name LevelHudView
extends RefCounted

## 只负责关卡提示与货币控件，不判定奖励资格、不写存档。

signal upgrade_requested

var _win_label: Label
var _coins_label: Label
var _upgrade_button: Button
var _top_scrim: ColorRect


func configure(hud: CanvasLayer, official: bool) -> void:
	_win_label = hud.get_node("WinLabel") as Label
	_coins_label = hud.get_node("CoinsLabel") as Label
	_upgrade_button = hud.get_node("UpgradeButton") as Button
	_top_scrim = hud.get_node_or_null("TopScrim") as ColorRect
	_win_label.hide()
	_coins_label.visible = official
	_upgrade_button.visible = official
	if _top_scrim != null:
		_top_scrim.visible = official
	_upgrade_button.pressed.connect(func() -> void: upgrade_requested.emit())
	if not official:
		var hint: Label = hud.get_node("HintLabel") as Label
		hint.text = "玩家预览（不记进度/金币） · 鼠标瞄准 · 空格发射 · Esc 暂停"


func reset() -> void:
	if is_instance_valid(_win_label):
		_win_label.hide()


func show_progress(coins: int, hint_length: float, maxed: bool, cost: int, increment: float) -> void:
	_coins_label.text = "金币 %d  ·  虚线 %d" % [coins, roundi(hint_length)]
	_upgrade_button.disabled = maxed or coins < cost
	_upgrade_button.text = "瞄准提示已满级" if maxed else "升级虚线 +%d  ·  %d 金币" % [
		roundi(increment), cost]
