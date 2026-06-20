class_name GameManager
extends Node

# --- 注入的引用 ---
var battle_grid_data: BattleGridData
var grid_renderer: GridRenderer
var players: Array[Character] = []
var enemies: Array[Character] = []

# --- 移动状态 ---
var selected_character: Character = null
var move_options: Array[Vector2i] = []

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

func create_battle_map():
	print("=== 环境诊断 ===")
	print("当前场景根节点: ", get_tree().current_scene.name)
	
	# 1. 检查所有兄弟节点
	var siblings = get_parent().get_children()
	print("\n兄弟节点列表:")
	for node in siblings:
		var info = "  名称: %s, 类型: %s" % [node.name, node.get_class()]
		if node is Node2D:
			info += ", z_index: %d, visible: %s" % [node.z_index, node.visible]
			info += ", pos: %s, global_pos: %s" % [node.position, node.global_position]
		print(info)
	
	# 2. 检查相机
	var camera = get_viewport().get_camera_2d()
	if camera:
		print("\n当前相机: ", camera.name)
		print("  全局位置: ", camera.global_position)
		print("  缩放: ", camera.zoom)
	
	# 3. 加载地图
	var battle_map = load("res://scenes/battle_map.tscn").instantiate()
	battle_map.name = "DynamicBattleMap"
	
	# 4. 设置地图属性（关键！）
	if battle_map is Node2D:
		battle_map.global_position = Vector2.ZERO  # 用全局位置
		battle_map.z_index = -10  # 临时设为很低，看是不是被遮挡
		
		# 递归设置所有子节点可见
		for child in battle_map.get_children():
			if child is CanvasItem:
				child.visible = true
				child.modulate = Color.WHITE
	
	# 5. 添加到场景
	get_parent().add_child(battle_map)
	
	print("\n添加后的地图信息:")
	print("  局部位置: ", battle_map.position)
	print("  全局位置: ", battle_map.global_position)
	print("  可见: ", battle_map.visible)
	print("  z_index: ", battle_map.z_index)
	
	# 6. 移动地图节点到最前面（在场景树中）
	get_parent().move_child(battle_map, get_parent().get_child_count() - 1)

func _setup() -> void:
	print("[GM] _ready 开始")
	# var battle_map := $"../BattleMap"
	var battle_map = load("res://scenes/battle_map.tscn").instantiate()
	print("[GM] battle_map=%s, is_inside_tree=%s" % [battle_map, battle_map.is_inside_tree()])
	print("[GM] 添加前子节点数: %d" % get_parent().get_child_count())
	get_parent().add_child(battle_map)
	print("[GM] add_child 添加后子节点数=%d, is_inside_tree=%s" % [get_parent().get_child_count(), battle_map.is_inside_tree()])
	print("[GM] 父节点: %s (%s)" % [get_parent().name, get_parent().get_class()])
	#create_battle_map()

	# 1. 数据层：从 ObstacleLayer 初始化地图
	battle_grid_data = BattleGridData.new()
	battle_grid_data.init_from_tilemap(battle_map.get_node("ObstacleLayer"), 10, 8)
	print("[GM] 网格初始化完成 %dx%d" % [battle_grid_data.width, battle_grid_data.height])

	# 2. 桥接层：创建 GridRenderer 并注入 HighlightLayer
	grid_renderer = GridRenderer.new()
	grid_renderer.name = "GridRenderer"
	var hl = battle_map.get_node("HighlightLayer")
	print("[GM] HighlightLayer=%s" % hl)
	grid_renderer.setup(hl)
	get_parent().add_child(grid_renderer)
	print("[GM] GridRenderer 创建完成")

	# 3. 创建角色（挂 MainScene 下，与 BattleMap 同级，解耦）
	#    纹理运行时动态加载，character.tscn 保持通用
	var tex = load("res://assets/characters/player.png")
	print("[GM] player texture=%s" % tex)
	var test_pos = grid_renderer.grid_to_world(Vector2i(2, 4))
	print("[GM] grid_to_world(2,4)=%s" % test_pos)
	var player := create_character(PLAYER_STATS, Vector2i(2, 4), tex)
	print("[GM] player name=%s pos=%s grid_pos=%s texture=%s" % [player.name, player.position, player.grid_pos, player.get_node("Sprite2D").texture])
	players.append(player)

	var enemy1 := create_character(ENEMY1_STATS, Vector2i(5, 1), load("res://assets/characters/enemy1.png"))
	enemies.append(enemy1)

	var enemy2 := create_character(ENEMY2_STATS, Vector2i(8, 1), load("res://assets/characters/enemy2.png"))
	enemies.append(enemy2)

func _ready() -> void:
	call_deferred("_setup")


func create_character(stats: Dictionary, start_pos: Vector2i, texture: Texture2D) -> Character:
	var scene := load("res://scenes/character.tscn")
	var ch := scene.instantiate() as Character
	get_parent().add_child(ch)

	# 先注入依赖，再设坐标（grid_pos setter 依赖 grid_renderer）
	ch.battle_grid_data = battle_grid_data
	ch.grid_renderer = grid_renderer
	ch.setup(stats)
	ch.set_texture(texture)
	#ch.z_index = 10

	# 数据层注册占位
	battle_grid_data.place_character(ch, start_pos)
	return ch


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	var cell := grid_renderer.get_clicked_cell(event)
	var cell_data := battle_grid_data.get_cell(cell)

	if selected_character == null:
		# 阶段 A：选中玩家角色
		if cell_data and cell_data.occupant and cell_data.occupant.team == Character.Team.PLAYER:
			selected_character = cell_data.occupant
			move_options = selected_character.get_move_options()
			grid_renderer.highlight_cells(move_options, GridRenderer.ATLAS_MOVE)
	else:
		# 阶段 B：点击移动目标
		if cell in move_options:
			var old_pos := selected_character.grid_pos
			battle_grid_data.move_character(old_pos, cell)
			grid_renderer.clear_highlights()
			selected_character = null
			move_options.clear()
		else:
			# 点击无效格 → 取消选中
			grid_renderer.clear_highlights()
			selected_character = null
			move_options.clear()
