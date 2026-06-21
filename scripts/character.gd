class_name Character
extends Node2D

enum Team { PLAYER, ENEMY }

# --- 属性 ---
var character_name: String
var team: Team
var max_hp: int
var current_hp: int
var attack_power: int
var defense_power: int
var attack_range: int
var move_range: int
var is_defending: bool = false

# --- 依赖注入 ---
var controller: Controller
var battle_grid_data: BattleGridData
var grid_renderer: GridRenderer

# --- 移动动画 ---
signal walk_finished
var is_moving: bool = false
var _path: Array[Vector2i] = []
var _path_step: int = 0

# --- 坐标（grid_pos 变化时自动同步世界坐标）---
var grid_pos: Vector2i:
	set(to):
		grid_pos = to
		if grid_renderer:
			position = grid_renderer.grid_to_world(to)


func setup(stats: Dictionary) -> void:
	max_hp = stats.max_hp
	current_hp = stats.max_hp
	attack_power = stats.attack_power
	defense_power = stats.defense_power
	attack_range = stats.attack_range
	move_range = stats.move_range
	character_name = stats.name
	team = stats.team
	if stats.has("start_pos"):
		grid_pos = stats.start_pos


func set_texture(tex: Texture2D) -> void:
	$Sprite2D.texture = tex


func setup_animation(idle: Array[Texture2D], walk: Array[Texture2D] = [],
		attack: Array[Texture2D] = [], defend: Array[Texture2D] = []) -> void:
	$Sprite2D.visible = false
	var anim := $AnimatedSprite2D
	anim.visible = true
	var sf := SpriteFrames.new()
	sf.add_animation("idle")
	sf.add_animation("walk")
	sf.add_animation("attack")
	sf.add_animation("defend")
	for f in idle:
		sf.add_frame("idle", f)
	for f in walk if walk.size() > 0 else idle:
		sf.add_frame("walk", f)
	for f in attack if attack.size() > 0 else idle:
		sf.add_frame("attack", f)
	for f in defend if defend.size() > 0 else idle:
		sf.add_frame("defend", f)
	sf.set_animation_speed("walk", 8.0)
	sf.set_animation_speed("attack", 10.0)
	anim.sprite_frames = sf
	anim.play("idle")


func play_anim(name: String) -> void:
	if $AnimatedSprite2D.visible:
		$AnimatedSprite2D.play(name)


func walk_along_path(path: Array[Vector2i]) -> void:
	if path.size() < 2:
		return
	is_moving = true
	if $AnimatedSprite2D.visible:
		$AnimatedSprite2D.play("walk")
	_path = path
	_path_step = 0
	_step_along_path()


func _step_along_path() -> void:
	_path_step += 1
	if _path_step >= _path.size():
		is_moving = false
		if $AnimatedSprite2D.visible:
			$AnimatedSprite2D.play("idle")
		walk_finished.emit()
		return

	var target_pos := grid_renderer.grid_to_world(_path[_path_step])
	var tween := create_tween()
	tween.tween_property(self, "position", target_pos, 0.12)
	tween.tween_callback(_on_step_done)


func _on_step_done() -> void:
	var from := _path[_path_step - 1]
	var to := _path[_path_step]
	battle_grid_data.move_character(from, to)
	_step_along_path()


func is_alive() -> bool:
	return current_hp > 0


signal died


func take_damage(damage: int) -> void:
	current_hp = maxi(0, current_hp - damage)
	if current_hp <= 0:
		visible = false
		battle_grid_data.remove_character(grid_pos)
		died.emit()


func defend() -> void:
	is_defending = true


func reset_defense() -> void:
	is_defending = false

# --- 委托给数据层 ---
func get_move_options() -> Array[Vector2i]:
	if battle_grid_data:
		return battle_grid_data.get_move_range(grid_pos, move_range)
	return []


func get_attack_targets() -> Array[Character]:
	if battle_grid_data:
		return battle_grid_data.get_characters_in_range(grid_pos, attack_range, team)
	return []
