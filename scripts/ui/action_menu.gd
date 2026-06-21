class_name ActionMenu
extends Control

# 子节点引用
@onready var _wait_btn: Button = $MainHBox/WaitBtn
@onready var _skill_btn: Button = $MainHBox/SkillBtn
@onready var _end_turn_btn: Button = $MainHBox/EndTurnBtn
@onready var _attack_btn: Button = $MainHBox/AttackBtn
@onready var _undo_btn: Button = $MainHBox/UndoBtn
@onready var _skill_popup: PopupMenu = $MainHBox/SkillPopup

# 信号
signal wait_pressed
signal skill_selected(skill_name: String)
signal end_turn_pressed
signal attack_pressed
signal undo_pressed


func _ready() -> void:
	# 常驻按钮
	_wait_btn.pressed.connect(func(): wait_pressed.emit())
	_end_turn_btn.pressed.connect(func(): end_turn_pressed.emit())

	# 技能按钮 → 弹出菜单
	_skill_btn.pressed.connect(func(): _skill_popup.popup())

	# 技能菜单项
	_skill_popup.add_item("🛡️ 防御")
	_skill_popup.index_pressed.connect(func(idx: int):
		skill_selected.emit(_skill_popup.get_item_text(idx))
	)

	# 条件按钮
	_attack_btn.pressed.connect(func(): attack_pressed.emit())
	_undo_btn.pressed.connect(func(): undo_pressed.emit())

	# === 按钮样式美化 ===
	_style_button(_wait_btn, Color(0.35, 0.45, 0.55))      # 蓝灰
	_style_button(_skill_btn, Color(0.25, 0.55, 0.35))      # 绿色
	_style_button(_end_turn_btn, Color(0.6, 0.45, 0.2))     # 橙黄
	_style_button(_attack_btn, Color(0.6, 0.2, 0.2))        # 红色
	_style_button(_undo_btn, Color(0.5, 0.4, 0.3))          # 灰棕


func _style_button(btn: Button, bg_color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	btn.add_theme_stylebox_override("normal", style)

	# hover 状态：稍微亮一点
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = bg_color.lightened(0.2)
	hover_style.set_corner_radius_all(6)
	hover_style.content_margin_left = 12
	hover_style.content_margin_right = 12
	btn.add_theme_stylebox_override("hover", hover_style)

	# pressed 状态：稍微暗一点
	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = bg_color.darkened(0.2)
	pressed_style.set_corner_radius_all(6)
	pressed_style.content_margin_left = 12
	pressed_style.content_margin_right = 12
	btn.add_theme_stylebox_override("pressed", pressed_style)

	# 白色文字
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 14)


func show_attack_button(show: bool) -> void:
	_attack_btn.visible = show


func show_undo_button(show: bool) -> void:
	_undo_btn.visible = show
