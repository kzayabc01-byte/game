extends Node
## 全局信号总线（Autoload，名字：GameEvents）。
## 跨场景通信统一走这里，避免场景之间互相拿节点。
## 组员可自行添加新信号，例如音效、统计等。

signal level_completed(level_name: String)

signal game_reset
