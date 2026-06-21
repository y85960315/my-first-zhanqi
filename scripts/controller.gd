class_name Controller
extends Node

enum ActionType { ATTACK, DEFEND, WAIT }

# GameManager 初始化时注入
var battle_grid_data: BattleGridData

# 子类需要获取视野内敌人时注入
var _enemies: Array[Character] = []

# ---- 唯一对外接口 ----
# TurnManager 调用此方法启动角色行动
#   PlayerController: 激活输入监听，等待玩家操作
#   AIController:     内部完成全部决策 → 执行 → 发出 action_finished
func do_action(_character: Character) -> void:
	pass

# 行动完成信号 — 通知 TurnManager 该角色本回合结束
signal action_finished

# ---- 以下为兼容旧 GameManager 代码的接口（Step 2 后移除）----
signal move_decided(cell: Vector2i)
signal action_decided(action: ActionType, target: Character)


func set_enemies(enemies: Array[Character]) -> void:
	_enemies = enemies


func decide_move(_character: Character) -> Vector2i:
	return _character.grid_pos


func decide_action(_character: Character) -> ActionType:
	return ActionType.ATTACK


func decide_target(_character: Character, enemies: Array[Character]) -> Character:
	return enemies[0] if enemies.size() > 0 else null
