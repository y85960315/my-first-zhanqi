class_name GameManager
extends Node

var battle_grid_data: BattleGridData
var grid_renderer: GridRenderer
var combat_system: CombatSystem
var players: Array[Character] = []
var enemies: Array[Character] = []
var player_controller: PlayerController
var action_menu: ActionMenu

const PLAYER_STATS := {
	name = "Player", team = Character.Team.PLAYER,
	max_hp = 100, attack_power = 15, defense_power = 5,
	attack_range = 1, move_range = 3,
}

const ENEMY1_STATS := {
	name = "Enemy1", team = Character.Team.ENEMY,
	max_hp = 60, attack_power = 10, defense_power = 3,
	attack_range = 1, move_range = 2,
}

const ENEMY2_STATS := {
	name = "Enemy2", team = Character.Team.ENEMY,
	max_hp = 80, attack_power = 12, defense_power = 4,
	attack_range = 1, move_range = 2,
}


func _ready() -> void:
	call_deferred("_setup")


func _setup() -> void:
	var battle_map = load("res://scenes/battle_map.tscn").instantiate()
	battle_map.name = "BattleMap"
	get_parent().add_child(battle_map)

	battle_grid_data = BattleGridData.new()
	battle_grid_data.init_from_tilemap(battle_map.get_node("ObstacleLayer"), 10, 8)

	grid_renderer = GridRenderer.new()
	grid_renderer.name = "GridRenderer"
	grid_renderer.setup(battle_map.get_node("HighlightLayer"))
	get_parent().add_child(grid_renderer)

	combat_system = CombatSystem.new()

	var ui_layer := CanvasLayer.new()
	ui_layer.name = "UILayer"
	get_parent().add_child(ui_layer)

	action_menu = load("res://scenes/action_menu.tscn").instantiate()
	action_menu.name = "ActionMenu"
	ui_layer.add_child(action_menu)

	action_menu.wait_pressed.connect(_on_wait)
	action_menu.end_turn_pressed.connect(_on_end_turn)
	action_menu.attack_pressed.connect(_on_attack)
	action_menu.undo_pressed.connect(_on_undo)
	action_menu.skill_selected.connect(_on_skill)

	player_controller = PlayerController.new()
	player_controller.name = "PlayerController"
	player_controller.battle_grid_data = battle_grid_data
	player_controller.setup(grid_renderer)
	player_controller.move_decided.connect(_on_move_cell_clicked)

	var player := create_character(PLAYER_STATS, Vector2i(2, 4), load("res://assets/characters/player.png"), player_controller)
	players.append(player)

	var enemy1 := create_character(ENEMY1_STATS, Vector2i(5, 1), load("res://assets/characters/enemy1.png"), _create_ai_controller())
	enemies.append(enemy1)

	var enemy2 := create_character(ENEMY2_STATS, Vector2i(8, 1), load("res://assets/characters/enemy2.png"), _create_ai_controller())
	enemies.append(enemy2)

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


var _pending_players: Array[Character] = []
var _round_number: int = 0
var _current_actor: Character = null
var _has_moved: bool = false
var _has_acted: bool = false
var _move_from: Vector2i
var _pending_attack_target: Character = null


func start_round() -> void:
	_round_number += 1
	print("========== 第 %d 回合 ==========" % _round_number)
	for ch in players + enemies:
		ch.reset_defense()
	_pending_players = _get_alive(players)


func _on_wait() -> void:
	if _current_actor == null:
		return
	print("[回合] %s 等待" % _current_actor.character_name)
	_end_actor()


func _on_end_turn() -> void:
	_end_actor()
	_pending_players.clear()
	print("[回合] 结束玩家回合")
	_execute_enemy_turns()


func _on_attack() -> void:
	if _current_actor == null or not _pending_attack_target:
		return
	_has_acted = true
	combat_system.execute_action(_current_actor, _pending_attack_target, Controller.ActionType.ATTACK)
	grid_renderer.clear_highlights()
	action_menu.show_attack_button(false)
	if _has_moved:
		action_menu.show_undo_button(false)
	print("[回合] %s 攻击完成，回合自动结束" % _current_actor.character_name)
	_end_actor()


func _on_undo() -> void:
	if _current_actor == null or not _has_moved:
		return
	action_menu.show_undo_button(false)
	var path := battle_grid_data.get_shortest_path(_current_actor.grid_pos, _move_from)
	if path.size() >= 2:
		_current_actor.walk_along_path(path)
		await _current_actor.walk_finished
	_has_moved = false
	grid_renderer.clear_highlights()
	player_controller.start_move_phase(_current_actor)


func _on_skill(skill_name: String) -> void:
	if _current_actor == null:
		return
	match skill_name:
		"🛡️ 防御":
			combat_system.execute_action(_current_actor, null, Controller.ActionType.DEFEND)
			_has_acted = true
			print("[回合] %s 使用防御，回合自动结束" % _current_actor.character_name)
			_end_actor()


func _on_move_cell_clicked(target_cell: Vector2i) -> void:
	if _current_actor == null or _has_moved:
		return
	if target_cell == _current_actor.grid_pos:
		return
	_move_from = _current_actor.grid_pos
	_has_moved = true
	action_menu.show_undo_button(true)
	var path := battle_grid_data.get_shortest_path(_current_actor.grid_pos, target_cell)
	_current_actor.walk_along_path(path)
	await _current_actor.walk_finished
	grid_renderer.clear_highlights()


func _find_attack_position(actor: Character, target: Character) -> Vector2i:
	var options := actor.get_move_options()
	options.append(actor.grid_pos)
	var best := Vector2i(-1, -1)
	var best_dist := 9999
	for pos in options:
		var d := _manhattan(pos, target.grid_pos)
		if d <= actor.attack_range:
			var dist_to_me := _manhattan(pos, actor.grid_pos)
			if dist_to_me < best_dist:
				best_dist = dist_to_me
				best = pos
	return best


func _on_enemy_clicked(enemy: Character) -> void:
	if _current_actor == null:
		return
	var attack_pos := _find_attack_position(_current_actor, enemy)
	if attack_pos == Vector2i(-1, -1):
		return
	if attack_pos != _current_actor.grid_pos and not _has_moved:
		_move_from = _current_actor.grid_pos
		_has_moved = true
		action_menu.show_undo_button(true)
		var path := battle_grid_data.get_shortest_path(_current_actor.grid_pos, attack_pos)
		_current_actor.walk_along_path(path)
		await _current_actor.walk_finished
	_pending_attack_target = enemy
	grid_renderer.clear_highlights()
	grid_renderer.highlight_cells([enemy.grid_pos], GridRenderer.ATLAS_ATTACK)
	action_menu.show_attack_button(true)


func _end_actor() -> void:
	if _current_actor == null:
		return
	_pending_players.erase(_current_actor)
	_current_actor = null
	_has_moved = false
	_has_acted = false
	_pending_attack_target = null
	grid_renderer.clear_highlights()
	action_menu.show_attack_button(false)
	action_menu.show_undo_button(false)
	player_controller.phase = PlayerController.Phase.IDLE


func _execute_enemy_turns() -> void:
	print("--- 敌人回合 ---")
	_enemy_index = 0
	_step_enemy()


var _enemy_index: int = 0


func _step_enemy() -> void:
	if _enemy_index >= enemies.size():
		check_win_condition()
		return
	var enemy := enemies[_enemy_index]
	_enemy_index += 1
	if not enemy.is_alive():
		_step_enemy()
		return
	print("[回合] %s 开始行动" % enemy.character_name)
	var ctrl := enemy.controller as AIController
	ctrl.set_enemies(players)
	var target_pos := ctrl.decide_move(enemy)
	if target_pos != enemy.grid_pos:
		var path := battle_grid_data.get_shortest_path(enemy.grid_pos, target_pos)
		enemy.walk_along_path(path)
		await enemy.walk_finished
	var enemies_alive := _get_alive_enemies(enemy.team)
	if not enemies_alive.is_empty():
		var action := ctrl.decide_action(enemy)
		match action:
			Controller.ActionType.ATTACK:
				var target := ctrl.decide_target(enemy, enemies_alive)
				if target:
					combat_system.execute_action(enemy, target, action)
			Controller.ActionType.DEFEND:
				combat_system.execute_action(enemy, null, action)
	_step_enemy()


func check_win_condition() -> void:
	if _all_dead(enemies):
		print("胜利！所有敌人已消灭")
	elif _all_dead(players):
		print("失败！玩家已阵亡")
	else:
		start_round()


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var cell := grid_renderer.get_clicked_cell(event)
	var cell_data := battle_grid_data.get_cell(cell)
	if _current_actor != null and player_controller.phase == PlayerController.Phase.MOVE:
		if _current_actor.is_moving:
			return
		if cell_data and cell_data.occupant and cell_data.occupant.team == Character.Team.ENEMY:
			_on_enemy_clicked(cell_data.occupant)
			return
		player_controller.handle_click(cell)
		return
	if cell_data and cell_data.occupant and cell_data.occupant.team == Character.Team.PLAYER:
		var ch := cell_data.occupant
		if ch in _pending_players:
			_select_player(ch)


func _select_player(ch: Character) -> void:
	if ch == _current_actor:
		return
	if ch.is_moving:
		return
	_current_actor = ch
	_has_moved = false
	_has_acted = false
	_pending_attack_target = null
	print("[回合] %s 开始行动" % ch.character_name)
	player_controller.start_move_phase(ch)


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


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)
