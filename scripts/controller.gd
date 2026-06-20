class_name Controller
extends Node

enum ActionType { ATTACK, DEFEND, WAIT }

# GameManager 初始化时注入
var battle_grid_data: BattleGridData

# 玩家用信号通知 GameManager 输入已完成
signal move_decided(cell: Vector2i)
signal action_decided(action: ActionType, target: Character)

# 子类需要获取视野内敌人时注入
var _enemies: Array[Character] = []


func set_enemies(enemies: Array[Character]) -> void:
	_enemies = enemies


func decide_move(_character: Character) -> Vector2i:
	return _character.grid_pos


func decide_action(_character: Character) -> ActionType:
	return ActionType.ATTACK


func decide_target(_character: Character, enemies: Array[Character]) -> Character:
	return enemies[0] if enemies.size() > 0 else null
