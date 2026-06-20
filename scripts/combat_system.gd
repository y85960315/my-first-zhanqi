class_name CombatSystem
extends RefCounted


func is_in_range(attacker: Character, target: Character) -> bool:
	return _manhattan(attacker.grid_pos, target.grid_pos) <= attacker.attack_range


func calculate_damage(attacker: Character, defender: Character) -> int:
	var raw := attacker.attack_power - defender.defense_power
	if defender.is_defending:
		raw = maxi(1, raw / 2)
	return maxi(1, raw)


func execute_action(actor: Character, target: Character, action: Controller.ActionType) -> void:
	match action:
		Controller.ActionType.ATTACK:
			if not is_in_range(actor, target):
				return
			var damage := calculate_damage(actor, target)
			target.take_damage(damage)
		Controller.ActionType.DEFEND:
			actor.defend()


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)
