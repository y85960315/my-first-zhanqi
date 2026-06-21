class_name UIManager
extends Node

# 依赖注入（用于悬停检测）
var grid_renderer: GridRenderer
var battle_grid_data: BattleGridData

# 子节点引用
var action_menu: ActionMenu
var info_panel: Control
var confirm_dialog: ConfirmationDialog
var hover_label: Label

# 内部
var _ui_layer: CanvasLayer
var _name_label: Label
var _hp_label: Label
var _status_label: Label

# 转发信号
signal wait_pressed
signal skill_selected(skill_name: String)
signal end_turn_pressed
signal attack_pressed
signal undo_pressed
signal end_turn_confirmed
signal end_turn_canceled


func setup(ui_layer: CanvasLayer) -> void:
	_ui_layer = ui_layer

	# ActionMenu
	action_menu = load("res://scenes/action_menu.tscn").instantiate()
	action_menu.name = "ActionMenu"
	ui_layer.add_child(action_menu)

	action_menu.wait_pressed.connect(func(): wait_pressed.emit())
	action_menu.end_turn_pressed.connect(func(): end_turn_pressed.emit())
	action_menu.attack_pressed.connect(func(): attack_pressed.emit())
	action_menu.undo_pressed.connect(func(): undo_pressed.emit())
	action_menu.skill_selected.connect(func(name: String): skill_selected.emit(name))

	# InfoPanel
	info_panel = _create_info_panel()
	ui_layer.add_child(info_panel)

	# HoverLabel
	hover_label = _create_hover_label()
	ui_layer.add_child(hover_label)

	# ConfirmDialog
	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.size = Vector2(300, 120)
	confirm_dialog.title = "结束回合"
	confirm_dialog.confirmed.connect(func(): end_turn_confirmed.emit())
	confirm_dialog.canceled.connect(func(): end_turn_canceled.emit())
	ui_layer.add_child(confirm_dialog)


func update_info_panel(character: Character) -> void:
	if character == null:
		info_panel.visible = false
		return
	info_panel.visible = true
	_name_label.text = character.character_name
	_hp_label.text = "HP: %d / %d" % [character.current_hp, character.max_hp]
	_status_label.text = "防御中" if character.is_defending else ""


func update_hover() -> void:
	if not is_inside_tree() or grid_renderer == null or battle_grid_data == null:
		hover_label.visible = false
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var cell := grid_renderer.get_cell_at_screen(mouse_pos)
	if not battle_grid_data.is_in_bounds(cell):
		hover_label.visible = false
		return
	var cell_data := battle_grid_data.get_cell(cell)
	if cell_data and cell_data.occupant and cell_data.occupant.team == Character.Team.ENEMY:
		var enemy := cell_data.occupant
		hover_label.text = "%s\nHP: %d/%d" % [enemy.character_name, enemy.current_hp, enemy.max_hp]
		hover_label.position = mouse_pos + Vector2(12, -20)
		hover_label.visible = true
	else:
		hover_label.visible = false


func show_attack_button(show: bool) -> void:
	action_menu.show_attack_button(show)


func show_undo_button(show: bool) -> void:
	action_menu.show_undo_button(show)


func popup_confirm(text: String) -> void:
	confirm_dialog.dialog_text = text
	confirm_dialog.popup_centered()


func show_game_over(text: String, color: Color) -> void:
	action_menu.visible = false
	info_panel.visible = false
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", color)
	label.anchor_left = 0.5
	label.anchor_top = 0.5
	label.position = Vector2(-200, -50)
	label.size = Vector2(400, 100)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ui_layer.add_child(label)


func _create_info_panel() -> Control:
	var panel := Panel.new()
	panel.position = Vector2(10, 10)
	panel.size = Vector2(220, 80)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.15, 0.85)
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 4
	panel_style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	panel.add_child(vbox)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 18)
	_name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	vbox.add_child(_name_label)

	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 16)
	_hp_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	vbox.add_child(_hp_label)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.modulate = Color(1.0, 0.8, 0.4)
	vbox.add_child(_status_label)

	panel.visible = false
	return panel


func _create_hover_label() -> Label:
	var label := Label.new()
	label.visible = false
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.WHITE)
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.05, 0.05, 0.1, 0.8)
	hover_style.set_corner_radius_all(4)
	hover_style.content_margin_left = 8
	hover_style.content_margin_right = 8
	hover_style.content_margin_top = 4
	hover_style.content_margin_bottom = 4
	label.add_theme_stylebox_override("normal", hover_style)
	return label
