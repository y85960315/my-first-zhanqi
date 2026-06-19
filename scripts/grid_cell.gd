class_name GridCell
extends RefCounted

var pos: Vector2i            # 格子坐标
var is_walkable: bool        # 是否可行走
var terrain_type: int        # 地形类型（0=平地）
var occupant: Character      # 站在该格上的角色（null=空格）
