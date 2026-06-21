class_name GameManager
extends Node

var battle_grid_data: BattleGridData
var grid_renderer: GridRenderer
var combat_system: CombatSystem
var turn_manager: TurnManager
var ui_manager: UIManager
var players: Array[Character] = []
var enemies: Array[Character] = []

const PLAYER_STATS := {
	name = "Player", team = Character.Team.PLAYER,
	max_hp = 100, attack_power = 15, defense_power = 5,
	attack_range = 1, move_range = 3,
}

const HANLI_STATS := {
	name = "韩立", team = Character.Team.PLAYER,
	max_hp = 80, attack_power = 12, defense_power = 4,
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

	ui_manager = UIManager.new()
	ui_manager.name = "UIManager"
	ui_manager.grid_renderer = grid_renderer
	ui_manager.battle_grid_data = battle_grid_data
	ui_manager.setup(ui_layer)

	turn_manager = TurnManager.new()
	turn_manager.battle_grid_data = battle_grid_data
	turn_manager.grid_renderer = grid_renderer
	turn_manager.combat_system = combat_system
	turn_manager.ui_manager = ui_manager
	turn_manager.players = players
	turn_manager.enemies = enemies

	var p1 := create_character(PLAYER_STATS, Vector2i(2, 4), load("res://assets/characters/player.png"), _create_player_controller())
	players.append(p1)

	var p2 := create_character(HANLI_STATS, Vector2i(7, 4), load("res://assets/characters/player.png"), _create_player_controller())
	players.append(p2)

	var enemy1 := create_character(ENEMY1_STATS, Vector2i(5, 1), load("res://assets/characters/enemy1.png"), _create_ai_controller())
	enemies.append(enemy1)

	var enemy2 := create_character(ENEMY2_STATS, Vector2i(8, 1), load("res://assets/characters/enemy2.png"), _create_ai_controller())
	enemies.append(enemy2)

	turn_manager.setup_signals()
	turn_manager.enemy_phase_ended.connect(_on_enemy_phase_ended)
	turn_manager.character_died.connect(check_win_condition)
	turn_manager.start_round()


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


func _create_player_controller() -> PlayerController:
	var pc := PlayerController.new()
	pc.battle_grid_data = battle_grid_data
	pc.setup(grid_renderer)
	return pc


func _process(_delta: float) -> void:
	if ui_manager:
		ui_manager.update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if turn_manager:
		turn_manager.handle_input(event)


func check_win_condition() -> void:
	if _all_dead(enemies):
		print("胜利！所有敌人已消灭")
	elif _all_dead(players):
		print("失败！玩家已阵亡")


func _on_enemy_phase_ended() -> void:
	check_win_condition()
	if _all_dead(enemies) or _all_dead(players):
		return
	turn_manager.start_round()


func _all_dead(pool: Array[Character]) -> bool:
	for ch in pool:
		if ch.is_alive():
			return false
	return true
