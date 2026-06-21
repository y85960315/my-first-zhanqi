class_name TurnManager
extends Node

# 依赖注入
var battle_grid_data: BattleGridData
var grid_renderer: GridRenderer
var combat_system: CombatSystem
var ui_manager: UIManager
var players: Array[Character] = []
var enemies: Array[Character] = []

# 回合状态
var _pending_players: Array[Character] = []
var _round_number: int = 0
var _current_actor: Character = null
var _has_moved: bool = false
var _has_acted: bool = false
var _move_from: Vector2i
var _attack_mode: bool = false
var _enemy_index: int = 0

# 信号
signal enemy_phase_ended
signal character_died


# 在角色全部创建后调用，连接各模块信号
func setup_signals() -> void:
	# UI 信号
	ui_manager.wait_pressed.connect(_on_wait)
	ui_manager.end_turn_pressed.connect(_on_end_turn)
	ui_manager.attack_pressed.connect(_on_attack)
	ui_manager.undo_pressed.connect(_on_undo)
	ui_manager.skill_selected.connect(_on_skill)
	ui_manager.end_turn_confirmed.connect(_on_confirm_end)
	ui_manager.end_turn_canceled.connect(_on_cancel_end)

	# PlayerController 信号
	for p in players:
		(p.controller as PlayerController).move_decided.connect(_on_move_cell_clicked)

	# 角色死亡信号
	for ch in players + enemies:
		ch.died.connect(_on_character_died)


func _on_character_died() -> void:
	character_died.emit()


func start_round() -> void:
	_round_number += 1
	print("========== 第 %d 回合 ==========" % _round_number)
	for ch in players + enemies:
		ch.reset_defense()
		ch.modulate = Color.WHITE
	_pending_players = _get_alive(players)
	_current_actor = null
	_has_moved = false
	_has_acted = false
	_attack_mode = false
	_move_from = Vector2i.ZERO
	ui_manager.update_info_panel(null)


# 处理输入转发
func handle_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
		return
	var cell := grid_renderer.get_clicked_cell(event)

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

	# 角色操作中 → 点敌人或移动
	if _current_actor != null and _pc().phase == PlayerController.Phase.MOVE:
		if _current_actor.is_moving:
			return
		if cell_data and cell_data.occupant and cell_data.occupant.team == Character.Team.ENEMY:
			_on_enemy_clicked(cell_data.occupant)
			return
		if _pc().handle_click(cell):
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


# ================================================================
#  内部
# ================================================================

func _pc() -> PlayerController:
	return _current_actor.controller as PlayerController


func _refresh_info_panel() -> void:
	ui_manager.update_info_panel(_current_actor)


func _refresh_attack_button() -> void:
	if _current_actor == null or _has_acted:
		ui_manager.show_attack_button(false)
		return
	var can_attack := _current_actor.get_attack_targets().size() > 0
	ui_manager.show_attack_button(can_attack)


func _check_end_round() -> void:
	if _pending_players.is_empty():
		ui_manager.popup_confirm("所有玩家已完成操作，是否结束回合？")


func _on_confirm_end() -> void:
	_do_end_player_phase()


func _on_cancel_end() -> void:
	pass


func _do_end_player_phase() -> void:
	print("[回合] 结束玩家回合")
	_execute_enemy_turns()


# ---- 玩家动作 ----

func _on_wait() -> void:
	if _current_actor == null:
		return
	print("[回合] %s 等待" % _current_actor.character_name)
	_end_actor()
	_check_end_round()


func _on_end_turn() -> void:
	if _pending_players.is_empty():
		_do_end_player_phase()
	else:
		ui_manager.popup_confirm("还有 %d 个角色未行动，确定结束回合？" % _pending_players.size())


func _on_attack() -> void:
	if _current_actor == null or _has_acted:
		return
	_enter_attack_mode()


func _do_attack(target: Character) -> void:
	_has_acted = true
	_current_actor.play_anim("attack")
	combat_system.execute_action(_current_actor, target, Controller.ActionType.ATTACK)
	grid_renderer.clear_highlights()
	ui_manager.show_attack_button(false)
	if _has_moved:
		ui_manager.show_undo_button(false)
	_attack_mode = false
	print("[回合] %s 攻击完成，回合自动结束" % _current_actor.character_name)
	_end_actor()
	_check_end_round()


func _on_undo() -> void:
	if _current_actor == null or not _has_moved or _current_actor.is_moving:
		return
	ui_manager.show_undo_button(false)
	_attack_mode = false
	grid_renderer.clear_highlights()
	await _rollback_move()
	_pc().start_move_phase(_current_actor)
	_refresh_attack_button()
	_refresh_info_panel()


func _on_skill(skill_name: String) -> void:
	if _current_actor == null:
		return
	match skill_name:
		"🛡️ 防御":
			_current_actor.play_anim("defend")
			combat_system.execute_action(_current_actor, null, Controller.ActionType.DEFEND)
			_has_acted = true
			print("[回合] %s 使用防御，回合自动结束" % _current_actor.character_name)
			_end_actor()
	_check_end_round()


func _on_move_cell_clicked(target_cell: Vector2i) -> void:
	if _current_actor == null or _has_moved:
		return
	if target_cell == _current_actor.grid_pos:
		return
	_move_from = _current_actor.grid_pos
	_has_moved = true
	ui_manager.show_undo_button(true)
	var path := battle_grid_data.get_shortest_path(_current_actor.grid_pos, target_cell)
	_current_actor.walk_along_path(path)
	await _current_actor.walk_finished
	if _current_actor != null:
		_pc().phase = PlayerController.Phase.MOVE
	_refresh_attack_button()


# ---- 攻击模式 ----

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

	if _attack_mode:
		if _is_in_attack_range(_current_actor, enemy):
			_do_attack(enemy)
		return

	if _has_moved:
		if _is_in_attack_range(_current_actor, enemy):
			_enter_attack_mode()
		return

	var attack_pos := _find_attack_position(_current_actor, enemy)
	if attack_pos == Vector2i(-1, -1):
		return
	if attack_pos != _current_actor.grid_pos:
		_move_from = _current_actor.grid_pos
		_has_moved = true
		ui_manager.show_undo_button(true)
		var path := battle_grid_data.get_shortest_path(_current_actor.grid_pos, attack_pos)
		_current_actor.walk_along_path(path)
		await _current_actor.walk_finished
	_enter_attack_mode()


func _is_in_attack_range(actor: Character, target: Character) -> bool:
	return _manhattan(actor.grid_pos, target.grid_pos) <= actor.attack_range


func _enter_attack_mode() -> void:
	_attack_mode = true
	ui_manager.show_attack_button(false)
	grid_renderer.clear_highlights()
	var attack_cells := battle_grid_data.get_attack_range(_current_actor.grid_pos, _current_actor.attack_range)
	grid_renderer.highlight_cells(attack_cells, GridRenderer.ATLAS_ATTACK)


func _cancel_attack_mode() -> void:
	grid_renderer.clear_highlights()
	_attack_mode = false
	if _current_actor != null:
		_pc().phase = PlayerController.Phase.MOVE
	_refresh_attack_button()


# ---- 角色管理 ----

func _end_actor() -> void:
	if _current_actor == null:
		return
	_current_actor.modulate = Color.GRAY
	var ctrl := _current_actor.controller as PlayerController
	_pending_players.erase(_current_actor)
	_current_actor = null
	_has_moved = false
	_has_acted = false
	_attack_mode = false
	ui_manager.update_info_panel(null)
	grid_renderer.clear_highlights()
	ui_manager.show_attack_button(false)
	ui_manager.show_undo_button(false)
	ctrl.phase = PlayerController.Phase.IDLE


func _select_player(ch: Character) -> void:
	if ch == _current_actor:
		if not _has_moved:
			_pc().start_move_phase(ch)
		_refresh_info_panel()
		_refresh_attack_button()
		return
	if ch.is_moving:
		return
	if _current_actor != null and _current_actor != ch:
		if _attack_mode:
			_cancel_attack_mode()
		if _has_moved and not _has_acted:
			await _rollback_move()
		_deselect()
	_current_actor = ch
	ch.modulate = Color.WHITE
	_has_moved = false
	_has_acted = false
	_attack_mode = false
	print("[回合] %s 开始行动" % ch.character_name)
	_pc().start_move_phase(ch)
	_refresh_info_panel()
	_refresh_attack_button()


func _deselect() -> void:
	if _attack_mode:
		_cancel_attack_mode()
	grid_renderer.clear_highlights()
	_pc().phase = PlayerController.Phase.IDLE
	ui_manager.update_info_panel(null)
	ui_manager.show_attack_button(false)
	ui_manager.show_undo_button(false)


func _rollback_move() -> void:
	if _current_actor == null:
		return
	ui_manager.show_undo_button(false)
	var path := battle_grid_data.get_shortest_path(_current_actor.grid_pos, _move_from)
	if path.size() >= 2:
		_current_actor.walk_along_path(path)
		await _current_actor.walk_finished
	_has_moved = false


# ---- 敌人 AI ----

func _execute_enemy_turns() -> void:
	print("--- 敌人回合 ---")
	_enemy_index = 0
	_step_enemy()


func _step_enemy() -> void:
	if _enemy_index >= enemies.size():
		enemy_phase_ended.emit()
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


# ---- 工具 ----

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


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)
