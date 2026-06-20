class_name PlayerController
extends Controller

enum Phase { IDLE, MOVE, ACTION, TARGET_SELECT }

var pending_move: Vector2i
var pending_action: ActionType
var pending_target: Character
var phase: Phase = Phase.IDLE

var grid_renderer: GridRenderer
var _move_options: Array[Vector2i] = []
var _character: Character


func setup(renderer: GridRenderer) -> void:
	grid_renderer = renderer


func start_move_phase(character: Character) -> void:
	_character = character
	phase = Phase.MOVE
	_move_options = character.get_move_options()
	grid_renderer.highlight_cells(_move_options, GridRenderer.ATLAS_MOVE)


func handle_click(cell: Vector2i) -> bool:
	match phase:
		Phase.MOVE:
			if cell in _move_options:
				pending_move = cell
				grid_renderer.clear_highlights()
				phase = Phase.IDLE
				move_decided.emit(cell)
				return true
			return false
		_:
			return false


func decide_move(_character: Character) -> Vector2i:
	return pending_move


func decide_action(_character: Character) -> ActionType:
	return pending_action


func decide_target(_character: Character, _enemies: Array[Character]) -> Character:
	return pending_target
