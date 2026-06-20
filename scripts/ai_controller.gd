class_name AIController
extends Controller


func decide_move(character: Character) -> Vector2i:
	var options := character.get_move_options()
	var alive := _get_alive_enemies()
	if alive.is_empty():
		return character.grid_pos
	var target := _pick_priority_target(alive)
	return _get_closest_to(options, target.grid_pos)


func decide_action(character: Character) -> ActionType:
	if character.get_attack_targets().size() > 0:
		return ActionType.ATTACK
	return ActionType.ATTACK if randf() < 0.7 else ActionType.DEFEND


func decide_target(_character: Character, enemies: Array[Character]) -> Character:
	return _pick_priority_target(enemies)


func _get_alive_enemies() -> Array[Character]:
	var result: Array[Character] = []
	for enemy in _enemies:
		if enemy.is_alive():
			result.append(enemy)
	return result


func _pick_priority_target(enemies: Array[Character]) -> Character:
	if enemies.is_empty():
		return null
	var best := enemies[0]
	for enemy in enemies:
		if enemy.current_hp < best.current_hp:
			best = enemy
	return best


func _get_closest_to(options: Array[Vector2i], target: Vector2i) -> Vector2i:
	if options.is_empty():
		return target
	var best_pos := options[0]
	var best_dist := _manhattan(best_pos, target)
	for pos in options:
		var dist := _manhattan(pos, target)
		if dist < best_dist:
			best_dist = dist
			best_pos = pos
	return best_pos


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)
