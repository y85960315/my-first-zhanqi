class_name BattleGridData
extends Resource

var width: int
var height: int
var cells: Array[Array] = []


# ============================================================
#  公开接口（外部调用）
# ============================================================

# 从 ObstacleLayer 读取障碍物数据，生成 cells 二维数组
# obstacle_layer: 障碍物层，有 tile 的位置 is_walkable=false
# map_width, map_height: 地图尺寸
func init_from_tilemap(obstacle_layer: TileMapLayer, map_width: int, map_height: int) -> void:
	width = map_width
	height = map_height
	cells.clear()
	for y in height:
		var row: Array = []
		for x in width:
			var cell := GridCell.new()
			cell.pos = Vector2i(x, y)
			cell.terrain_type = 0
			cell.is_walkable = obstacle_layer.get_cell_source_id(Vector2i(x, y)) == -1
			row.append(cell)
		cells.append(row)


# 获取指定坐标的格子，越界返回 null
func get_cell(pos: Vector2i) -> GridCell:
	if not is_in_bounds(pos):
		return null
	return cells[pos.y][pos.x]


# 判断坐标是否在地图范围内
func is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height


# 判断坐标是否可行走（在界内 + 不是障碍物 + 无人占据）
func is_walkable(pos: Vector2i) -> bool:
	if not is_in_bounds(pos):
		return false
	var cell := get_cell(pos)
	return cell.is_walkable and cell.occupant == null


# BFS 回溯出从 from 到 to 的最短路径（含 from 和 to），无路径返回空数组
func get_shortest_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if from == to:
		return [from]
	var visited: Dictionary = {}
	var parent: Dictionary = {}
	var queue: Array = [from]
	visited[from] = true

	while queue.size() > 0:
		var cur = queue.pop_front()
		for neighbor in _get_neighbors(cur):
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			parent[neighbor] = cur
			if neighbor == to:
				var path: Array[Vector2i] = []
				var pos = to
				while pos != from:
					path.push_front(pos)
					pos = parent[pos]
				path.push_front(from)
				return path
			queue.push_back(neighbor)
	return []


# BFS 寻路：计算从 origin 出发 move_limit 步内可达的所有格子
func get_move_range(origin: Vector2i, move_limit: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var visited: Dictionary = {}
	var queue: Array = [{pos = origin, dist = 0}]
	visited[origin] = true

	while queue.size() > 0:
		var cur = queue.pop_front()
		for neighbor in _get_neighbors(cur.pos):
			if visited.has(neighbor):
				continue
			if cur.dist < move_limit:
				visited[neighbor] = true
				queue.push_back({pos = neighbor, dist = cur.dist + 1})
				result.append(neighbor)
	return result


# 获取 origin 的曼哈顿距离 ≤ range_limit 的所有格子坐标
func get_attack_range(origin: Vector2i, range_limit: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in height:
		for x in width:
			var pos := Vector2i(x, y)
			if pos == origin:
				continue
			if not is_in_bounds(pos):
				continue
			if _manhattan_distance(origin, pos) <= range_limit:
				result.append(pos)
	return result


# 将角色放置到指定格子上（GameManager 初始化时调用）
func place_character(character: Character, pos: Vector2i) -> void:
	var cell := get_cell(pos)
	if cell:
		cell.occupant = character
		character.grid_pos = pos


# 将角色从 from_pos 移动到 to_pos（清旧格 + 占新格）
func move_character(from_pos: Vector2i, to_pos: Vector2i) -> void:
	var from_cell := get_cell(from_pos)
	var to_cell := get_cell(to_pos)
	if from_cell and to_cell and from_cell.occupant:
		var mover := from_cell.occupant
		from_cell.occupant = null
		to_cell.occupant = mover
		mover.grid_pos = to_pos


# 清除角色在 pos 的占位（角色死亡时调用）
func remove_character(pos: Vector2i) -> void:
	var cell := get_cell(pos)
	if cell:
		cell.occupant = null


# 获取 origin 范围内所有敌对阵营的存活角色
# team: 调用者的阵营，返回所有 team != 调用者阵营的角色
func get_characters_in_range(origin: Vector2i, range_limit: int, team: Character.Team) -> Array[Character]:
	var result: Array[Character] = []
	for y in height:
		for x in width:
			var pos := Vector2i(x, y)
			var cell := get_cell(pos)
			if cell.occupant and cell.occupant.team != team and _manhattan_distance(origin, pos) <= range_limit:
				result.append(cell.occupant)
	return result


# ============================================================
#  内部方法
# ============================================================

# 获取 pos 的四方向可行走邻居（BFS 内部使用）
func _get_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var next: Vector2i = pos + dir
		if is_walkable(next):
			result.append(next)
	return result


func _manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)
