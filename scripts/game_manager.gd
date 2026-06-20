class_name GameManager
extends Node

var battle_grid_data: BattleGridData
var grid_renderer: GridRenderer
var combat_system: CombatSystem
var players: Array[Character] = []
var enemies: Array[Character] = []
var player_controller: PlayerController
var action_menu: ActionMenu
var _info_panel: Control

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

	# InfoPanel — 选中角色状态
	_info_panel = _create_info_panel()
	ui_layer.add_child(_info_panel)

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


# 本回合尚未行动的玩家角色，点击时从中选取
var _pending_players: Array[Character] = []
# 当前回合编号（仅打印用）
var _round_number: int = 0
# 当前正在操作的玩家角色（null=未选中）
var _current_actor: Character = null
# 当前角色本回合是否已移动（限1次）
var _has_moved: bool = false
# 当前角色本回合是否已攻击/技能（限1次，触发后自动结束该角色）
var _has_acted: bool = false
# 移动前的格子坐标，撤销时回到此处
var _move_from: Vector2i
# 是否处于攻击模式（红高亮攻击范围，等待点敌人）
var _attack_mode: bool = false



var _name_label: Label
var _hp_label: Label
var _status_label: Label


func _create_info_panel() -> Control:
	var panel := Panel.new()
	panel.position = Vector2(10, 10)
	panel.size = Vector2(220, 80)

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	panel.add_child(vbox)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_name_label)

	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_hp_label)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.modulate = Color(1.0, 0.8, 0.4)
	vbox.add_child(_status_label)

	panel.visible = false
	return panel


func _refresh_info_panel() -> void:
	if _current_actor == null:
		_info_panel.visible = false
		return
	_info_panel.visible = true
	_name_label.text = _current_actor.character_name
	_hp_label.text = 'HP: %d / %d' % [_current_actor.current_hp, _current_actor.max_hp]
	_status_label.text = '防御中' if _current_actor.is_defending else ''

func start_round() -> void:
	_round_number += 1
	print("========== 第 %d 回合 ==========" % _round_number)
	for ch in players + enemies:
		ch.reset_defense()
	_pending_players = _get_alive(players)


func _refresh_attack_button() -> void:
	if _current_actor == null or _has_acted:
		action_menu.show_attack_button(false)
		return
	var can_attack := _current_actor.get_attack_targets().size() > 0
	action_menu.show_attack_button(can_attack)


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
	if _current_actor == null or _has_acted:
		return

	# 进入攻击模式：红色高亮攻击范围
	_enter_attack_mode()


func _do_attack(target: Character) -> void:
	_has_acted = true
	combat_system.execute_action(_current_actor, target, Controller.ActionType.ATTACK)
	grid_renderer.clear_highlights()
	action_menu.show_attack_button(false)
	if _has_moved:
		action_menu.show_undo_button(false)
	_attack_mode = false
	print("[回合] %s 攻击完成，回合自动结束" % _current_actor.character_name)
	_end_actor()
	_refresh_info_panel()


func _on_undo() -> void:
	if _current_actor == null or not _has_moved or _current_actor.is_moving:
		return
	action_menu.show_undo_button(false)
	_attack_mode = false
	grid_renderer.clear_highlights()
	var path := battle_grid_data.get_shortest_path(_current_actor.grid_pos, _move_from)
	if path.size() >= 2:
		_current_actor.walk_along_path(path)
		await _current_actor.walk_finished
	_has_moved = false
	player_controller.start_move_phase(_current_actor)
	_refresh_attack_button()
	_refresh_info_panel()


func _on_skill(skill_name: String) -> void:
	if _current_actor == null:
		return
	match skill_name:
		"🛡️ 防御":
			combat_system.execute_action(_current_actor, null, Controller.ActionType.DEFEND)
			_has_acted = true
			print("[回合] %s 使用防御，回合自动结束" % _current_actor.character_name)
			_end_actor()
	_refresh_info_panel()


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
	if _current_actor != null:
		player_controller.phase = PlayerController.Phase.MOVE
	_refresh_attack_button()


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

	# 攻击模式：直接选敌人 → 攻击
	if _attack_mode:
		if _is_in_attack_range(_current_actor, enemy):
			_do_attack(enemy)
		return

	# 已移动：若敌人在攻击范围内则直接进入攻击模式
	if _has_moved:
		if _is_in_attack_range(_current_actor, enemy):
			_enter_attack_mode()
		return

	# 未移动：自动走到最近攻击位
	var attack_pos := _find_attack_position(_current_actor, enemy)
	if attack_pos == Vector2i(-1, -1):
		return
	if attack_pos != _current_actor.grid_pos:
		_move_from = _current_actor.grid_pos
		_has_moved = true
		action_menu.show_undo_button(true)
		var path := battle_grid_data.get_shortest_path(_current_actor.grid_pos, attack_pos)
		_current_actor.walk_along_path(path)
		await _current_actor.walk_finished
	_enter_attack_mode()


func _is_in_attack_range(actor: Character, target: Character) -> bool:
	return _manhattan(actor.grid_pos, target.grid_pos) <= actor.attack_range


# 进入攻击模式：红色高亮攻击范围
func _enter_attack_mode() -> void:
	_attack_mode = true
	action_menu.show_attack_button(false)
	grid_renderer.clear_highlights()
	var attack_cells := battle_grid_data.get_attack_range(_current_actor.grid_pos, _current_actor.attack_range)
	grid_renderer.highlight_cells(attack_cells, GridRenderer.ATLAS_ATTACK)

# 取消攻击模式，若未移动则恢复蓝色高亮
func _cancel_attack_mode() -> void:
	grid_renderer.clear_highlights()
	_attack_mode = false
	if _current_actor != null:
		player_controller.phase = PlayerController.Phase.MOVE
	_refresh_attack_button()

func _end_actor() -> void:
	if _current_actor == null:
		return
	_pending_players.erase(_current_actor)
	_current_actor = null
	_has_moved = false
	_has_acted = false
	_attack_mode = false
	_info_panel.visible = false
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
	if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
		return
	var cell := grid_renderer.get_clicked_cell(event)
	# 右键 → 取消攻击模式 或 撤销移动
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if _attack_mode:
			_cancel_attack_mode()
		elif _has_moved and not _has_acted:
			_on_undo()
		elif _current_actor != null:
			_deselect()
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var cell_data := battle_grid_data.get_cell(cell)

	# 攻击模式：点敌人攻击，点空地取消
	if _attack_mode:
		if cell_data and cell_data.occupant and cell_data.occupant.team == Character.Team.ENEMY:
			_on_enemy_clicked(cell_data.occupant)
		else:
			_cancel_attack_mode()
		return

	# 角色操作中 → 敌人物或移动
	if _current_actor != null and player_controller.phase == PlayerController.Phase.MOVE:
		if _current_actor.is_moving:
			return
		if cell_data and cell_data.occupant and cell_data.occupant.team == Character.Team.ENEMY:
			_on_enemy_clicked(cell_data.occupant)
			return
		if player_controller.handle_click(cell):
			return

	# 点击待行动玩家
	if cell_data and cell_data.occupant and cell_data.occupant.team == Character.Team.PLAYER:
		var ch := cell_data.occupant
		if ch in _pending_players:
			_select_player(ch)
			return

	# 点空地或不可交互 → 取消选中
	if _current_actor != null:
		_deselect()


func _deselect() -> void:
	if _attack_mode:
		_cancel_attack_mode()
	# 保留 _current_actor 不置空，避免重新选中时丢失 _has_moved 等状态
	grid_renderer.clear_highlights()
	player_controller.phase = PlayerController.Phase.IDLE
	_info_panel.visible = false
	action_menu.show_attack_button(false)
	action_menu.show_undo_button(false)


func _select_player(ch: Character) -> void:
	if ch == _current_actor:
		player_controller.start_move_phase(ch)
		_refresh_info_panel()
		_refresh_attack_button()
		return
	if ch.is_moving:
		return
	_current_actor = ch
	_has_moved = false
	_has_acted = false
	_attack_mode = false
	print("[回合] %s 开始行动" % ch.character_name)
	player_controller.start_move_phase(ch)
	_refresh_info_panel()
	_refresh_attack_button()


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
