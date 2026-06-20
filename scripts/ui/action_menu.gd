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


func show_attack_button(show: bool) -> void:
	_attack_btn.visible = show


func show_undo_button(show: bool) -> void:
	_undo_btn.visible = show
