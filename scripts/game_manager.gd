class_name GameManager
extends Node

# --- 注入的引用 ---
var battle_grid_data: BattleGridData
var grid_renderer: GridRenderer
var players: Array[Character] = []
var enemies: Array[Character] = []

# --- Controller ---
var player_controller: PlayerController

# --- 移动状态 ---
var selected_character: Character = null

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

	# 3. 创建 Controller
	player_controller = PlayerController.new()
	player_controller.name = "PlayerController"
	player_controller.battle_grid_data = battle_grid_data
	player_controller.setup(grid_renderer)
	player_controller.move_decided.connect(_on_player_move_decided)

	# 4. 创建角色
	var player := create_character(PLAYER_STATS, Vector2i(2, 4), load("res://assets/characters/player.png"), player_controller)
	players.append(player)

	var enemy1 := create_character(ENEMY1_STATS, Vector2i(5, 1), load("res://assets/characters/enemy1.png"), _create_ai_controller())
	enemies.append(enemy1)

	var enemy2 := create_character(ENEMY2_STATS, Vector2i(8, 1), load("res://assets/characters/enemy2.png"), _create_ai_controller())
	enemies.append(enemy2)


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


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	var cell := grid_renderer.get_clicked_cell(event)

	# 如果 PlayerController 在等待输入，委托给它
	if player_controller.phase != PlayerController.Phase.IDLE:
		player_controller.handle_click(cell)
		return

	# 否则检测点击玩家角色
	var cell_data := battle_grid_data.get_cell(cell)
	if cell_data and cell_data.occupant and cell_data.occupant.team == Character.Team.PLAYER:
		var ch := cell_data.occupant
		if ch.is_moving:
			return
		selected_character = ch
		player_controller.start_move_phase(ch)


func _on_player_move_decided(_cell: Vector2i) -> void:
	var path := battle_grid_data.get_shortest_path(selected_character.grid_pos, _cell)
	selected_character.walk_along_path(path)
	selected_character = null
