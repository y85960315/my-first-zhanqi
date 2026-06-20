class_name GameManager
extends Node

# --- 注入的引用 ---
var battle_grid_data: BattleGridData
var grid_renderer: GridRenderer
var combat_system: CombatSystem
var players: Array[Character] = []
var enemies: Array[Character] = []

# --- Controller ---
var player_controller: PlayerController

# --- 初始数值 ---
const PLAYER_STATS := {
	name = "Player",
	team = Character.Team.PLAYER,
	max_hp = 100,
	attack_power = 15,
	defense_power = 5,
	attack_range = 1,
	move_range = 3,
}

const ENEMY1_STATS := {
	name = "Enemy1",
	team = Character.Team.ENEMY,
	max_hp = 60,
	attack_power = 10,
	defense_power = 3,
	attack_range = 1,
	move_range = 2,
}

const ENEMY2_STATS := {
	name = "Enemy2",
	team = Character.Team.ENEMY,
	max_hp = 80,
	attack_power = 12,
	defense_power = 4,
	attack_range = 1,
	move_range = 2,
}


func _ready() -> void:
	call_deferred("_setup")


func _setup() -> void:
	var battle_map = load("res://scenes/battle_map.tscn").instantiate()
	battle_map.name = "BattleMap"
	get_parent().add_child(battle_map)

	# 1. 数据层
	battle_grid_data = BattleGridData.new()
	battle_grid_data.init_from_tilemap(battle_map.get_node("ObstacleLayer"), 10, 8)

	# 2. 桥接层
	grid_renderer = GridRenderer.new()
	grid_renderer.name = "GridRenderer"
	grid_renderer.setup(battle_map.get_node("HighlightLayer"))
	get_parent().add_child(grid_renderer)

	# 3. 战斗系统
	combat_system = CombatSystem.new()

	# 4. 创建 Controller
	player_controller = PlayerController.new()
	player_controller.name = "PlayerController"
	player_controller.battle_grid_data = battle_grid_data
	player_controller.setup(grid_renderer)

	# 5. 创建角色
	var player := create_character(PLAYER_STATS, Vector2i(2, 4), load("res://assets/characters/player.png"), player_controller)
	players.append(player)

	var enemy1 := create_character(ENEMY1_STATS, Vector2i(5, 1), load("res://assets/characters/enemy1.png"), _create_ai_controller())
	enemies.append(enemy1)

	var enemy2 := create_character(ENEMY2_STATS, Vector2i(8, 1), load("res://assets/characters/enemy2.png"), _create_ai_controller())
	enemies.append(enemy2)

	# 6. 开始第一个回合
	start_round()


func _create_ai_controller() -> AIController:
	var ai := AIController.new()
	ai.battle_grid_data = battle_grid_data
	ai.set_enemies(players)
	return ai


func create_character(stats: Dictionary, start_pos: Vector2i, texture: Texture2D, ctrl: Controller) -> Character:
	var scene := load("res://scenes/character.tscn")
	var ch := scene.instantiate() as Character
	get_parent().add_child(ch)

	ch.battle_grid_data = battle_grid_data
	ch.grid_renderer = grid_renderer
	ch.controller = ctrl
	ch.add_child(ctrl)

	ch.setup(stats)
	ch.set_texture(texture)

	battle_grid_data.place_character(ch, start_pos)
	return ch


# ============================================================
#  回合流程
# ============================================================

var _pending_players: Array[Character] = []
var _turn_in_progress: bool = false


var _round_number: int = 0


func start_round() -> void:
	_round_number += 1
	print("========== 第 %d 回合 ==========" % _round_number)
	for ch in players + enemies:
		ch.reset_defense()
	_pending_players = _get_alive(players)
	_turn_in_progress = false


func _on_player_clicked(ch: Character) -> void:
	if _turn_in_progress:
		return
	if ch not in _pending_players:
		return
	_turn_in_progress = true
	print("[回合] %s 开始行动" % ch.character_name)

	await execute_move_phase(ch)
	await execute_action_phase(ch)

	_pending_players.erase(ch)
	_turn_in_progress = false

	if _pending_players.is_empty():
		await _execute_enemy_turns()
		check_win_condition()


func _execute_enemy_turns() -> void:
	print("--- 敌人回合 ---")
	for enemy in enemies:
		if not enemy.is_alive():
			continue
		print("[回合] %s 开始行动" % enemy.character_name)
		await execute_move_phase(enemy)
		await execute_action_phase(enemy)


func execute_move_phase(actor: Character) -> void:
	var ctrl := actor.controller
	var target_pos: Vector2i

	if ctrl is PlayerController:
		ctrl.start_move_phase(actor)
		target_pos = await ctrl.move_decided
	else:
		ctrl.set_enemies(players)
		target_pos = ctrl.decide_move(actor)

	if target_pos != actor.grid_pos:
		var path := battle_grid_data.get_shortest_path(actor.grid_pos, target_pos)
		actor.walk_along_path(path)
		await actor.walk_finished


func execute_action_phase(actor: Character) -> void:
	var enemies_alive := _get_alive_enemies(actor.team)
	if enemies_alive.is_empty():
		return

	var ctrl := actor.controller
	var action := ctrl.decide_action(actor)

	match action:
		Controller.ActionType.ATTACK:
			var target := ctrl.decide_target(actor, enemies_alive)
			if target:
				combat_system.execute_action(actor, target, action)
		Controller.ActionType.DEFEND:
			combat_system.execute_action(actor, null, action)


func check_win_condition() -> void:
	if _all_dead(enemies):
		print("胜利！所有敌人已消灭")
	elif _all_dead(players):
		print("失败！玩家已阵亡")
	else:
		start_round()


# ============================================================
#  输入（委托给 PlayerController）
# ============================================================

func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	var cell := grid_renderer.get_clicked_cell(event)

	# 移动阶段进行中 → 委托给 PlayerController
	if player_controller.phase != PlayerController.Phase.IDLE:
		player_controller.handle_click(cell)
		return

	# 点击玩家角色 → 开始该角色的回合
	var cell_data := battle_grid_data.get_cell(cell)
	if cell_data and cell_data.occupant and cell_data.occupant.team == Character.Team.PLAYER:
		_on_player_clicked(cell_data.occupant)


# ============================================================
#  内部辅助
# ============================================================

func _get_alive_enemies(team: Character.Team) -> Array[Character]:
	var result: Array[Character] = []
	var pool := enemies if team == Character.Team.PLAYER else players
	for ch in pool:
		if ch.is_alive():
			result.append(ch)
	return result


func _get_alive(pool: Array[Character]) -> Array[Character]:
	var result: Array[Character] = []
	for ch in pool:
		if ch.is_alive():
			result.append(ch)
	return result


func _all_dead(pool: Array[Character]) -> bool:
	for ch in pool:
		if ch.is_alive():
			return false
	return true
