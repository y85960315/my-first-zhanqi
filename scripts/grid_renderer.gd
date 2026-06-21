class_name GridRenderer
extends Node

const CFG = preload("res://scripts/constants.gd")

var highlight_layer: TileMapLayer

const ATLAS_ATTACK = Vector2i(0, 0)
const ATLAS_MOVE   = Vector2i(1, 0)


# 注入 HighlightLayer 引用（GameManager 初始化时调用）
func setup(layer: TileMapLayer) -> void:
	highlight_layer = layer


# 格子坐标 → 世界坐标（用于设置角色的 position）
func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return highlight_layer.map_to_local(grid_pos)


# 世界坐标 → 格子坐标
func world_to_grid(world_pos: Vector2) -> Vector2i:
	return highlight_layer.local_to_map(world_pos)


# 鼠标点击 → 格子坐标（InputEventMouseButton.position → 格子）
func get_clicked_cell(event: InputEventMouseButton) -> Vector2i:
	var local_pos: Vector2 = highlight_layer.to_local(event.position)
	return highlight_layer.local_to_map(local_pos)


# 将指定格子着色（移动蓝 / 攻击红）
# coords: 要着色的格子坐标数组
# atlas_pos: ATLAS_MOVE 或 ATLAS_ATTACK，决定颜色
func highlight_cells(coords: Array[Vector2i], atlas_pos: Vector2i) -> void:
	for cell in coords:
		highlight_layer.set_cell(cell, CFG.HIGHLIGHT_SOURCE_ID, atlas_pos)


# 清除所有高亮
func clear_highlights() -> void:
	highlight_layer.clear()


# 屏幕坐标 → 格子坐标（用于鼠标悬停检测）
func get_cell_at_screen(screen_pos: Vector2) -> Vector2i:
	var local_pos: Vector2 = highlight_layer.to_local(screen_pos)
	return highlight_layer.local_to_map(local_pos)
