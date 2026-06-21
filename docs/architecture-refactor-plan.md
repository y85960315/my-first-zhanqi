# 架构重构实施计划

> 基于 `docs/architecture.drawio` 目标架构，自底向上、逐步拆分 GameManager。

## 核心原则

- **每步可运行**：改完一步即可启动游戏验证，不积压 bug
- **小步提交**：每步一个 commit，出问题可精确回滚
- **只搬不写**：先从 GameManager 搬代码到新模块，再逐步重构新模块内部

---

## 第 0 步：Controller 接口统一（准备）

**目标**：Controller 基类暴露唯一的 `do_action()` 入口，消除 TurnManager 对内部决策步骤的依赖。

### 0.1 修改 `scripts/controller.gd`

- 现有方法：`decide_move()`, `decide_action()`, `decide_target()` — 保留但标记为内部方法
- 新增虚方法：`do_action(character: Character) -> void`
- 移除对外信号：`move_decided`, `action_decided`（改为内部信号）

```gdscript
# controller.gd 变更
class_name Controller
extends Node

enum ActionType { ATTACK, DEFEND, WAIT }

var battle_grid_data: BattleGridData
var _enemies: Array[Character] = []

func set_enemies(enemies: Array[Character]) -> void:
    _enemies = enemies

# 唯一对外接口 — TurnManager 只管调用这个方法
func do_action(_character: Character) -> void:
    pass  # 子类实现

# --- 内部方法（子类可覆盖）---
func _decide_move(_character: Character) -> Vector2i:
    return _character.grid_pos

func _decide_action(_character: Character) -> ActionType:
    return ActionType.ATTACK

func _decide_target(_character: Character, enemies: Array[Character]) -> Character:
    return enemies[0] if enemies.size() > 0 else null

# 动作完成信号 — 通知 TurnManager 该角色行动结束
signal action_finished
```

### 0.2 修改 `scripts/ai_controller.gd`

```gdscript
class_name AIController
extends Controller

# 实现 do_action：内部完成全部决策 + 执行
func do_action(character: Character) -> void:
    # 1. 决定移动位置
    var target_pos := _decide_move(character)
    if target_pos != character.grid_pos:
        var path := battle_grid_data.get_shortest_path(character.grid_pos, target_pos)
        character.walk_along_path(path)
        await character.walk_finished
    # 2. 决定行动
    var action := _decide_action(character)
    match action:
        ActionType.ATTACK:
            var enemies_alive := _get_alive_enemies()
            if not enemies_alive.is_empty():
                var target := _decide_target(character, enemies_alive)
                # 需要通过某种方式执行攻击...
        ActionType.DEFEND:
            # 需要通过某种方式执行防御...
    action_finished.emit()

# _decide_move / _decide_action / _decide_target 保持不变
# _get_alive_enemies / _pick_priority_target / _get_closest_to 保持不变
```

### 0.3 修改 `scripts/player_controller.gd`

```gdscript
class_name PlayerController
extends Controller

enum Phase { IDLE, MOVE, ACTION }

var phase: Phase = Phase.IDLE
var grid_renderer: GridRenderer
var _character: Character
var _move_options: Array[Vector2i] = []

# 玩家完成一次操作时触发
signal move_made(target_cell: Vector2i)
signal attack_made(target: Character)
signal action_done  # 等待/防御等

func setup(renderer: GridRenderer) -> void:
    grid_renderer = renderer

# do_action：激活输入监听，等待玩家操作
func do_action(character: Character) -> void:
    _character = character
    phase = Phase.MOVE
    _move_options = character.get_move_options()
    grid_renderer.highlight_cells(_move_options, GridRenderer.ATLAS_MOVE)

func handle_click(cell: Vector2i) -> bool:
    match phase:
        Phase.MOVE:
            if cell in _move_options:
                grid_renderer.clear_highlights()
                phase = Phase.IDLE
                move_made.emit(cell)
                return true
            return false
        _:
            return false

# 回合结束时的清理
func end_turn() -> void:
    phase = Phase.IDLE
    grid_renderer.clear_highlights()
```

### 验证

- 游戏启动不报错，能正常进入场景
- PlayerController.do_action() 被调用时显示蓝色高亮
- AIController.do_action() 能自动完成决策流程

---

## 第 1 步：拆分 UIManager（低风险）

**目标**：将 UI 创建逻辑从 GameManager 移到独立 UIManager 类。

### 1.1 新建 `scripts/ui/ui_manager.gd`

```gdscript
class_name UIManager
extends Node

var action_menu: ActionMenu
var info_panel: Control
var confirm_dialog: ConfirmationDialog
var hover_label: Label

# 信号转发 — 保持现有命名，减少 GameManager 改动
signal wait_pressed
signal skill_selected(skill_name: String)
signal end_turn_pressed
signal attack_pressed
signal undo_pressed


func setup(ui_layer: CanvasLayer) -> void:
    # 创建 ActionMenu
    action_menu = load("res://scenes/action_menu.tscn").instantiate()
    action_menu.name = "ActionMenu"
    ui_layer.add_child(action_menu)
    
    # 连接信号 → 转发
    action_menu.wait_pressed.connect(func(): wait_pressed.emit())
    action_menu.end_turn_pressed.connect(func(): end_turn_pressed.emit())
    action_menu.attack_pressed.connect(func(): attack_pressed.emit())
    action_menu.undo_pressed.connect(func(): undo_pressed.emit())
    action_menu.skill_selected.connect(func(name: String): skill_selected.emit(name))
    
    # 创建 InfoPanel
    info_panel = _create_info_panel()
    ui_layer.add_child(info_panel)
    
    # 创建 HoverLabel
    hover_label = _create_hover_label()
    ui_layer.add_child(hover_label)
    
    # 创建 ConfirmDialog
    confirm_dialog = ConfirmationDialog.new()
    confirm_dialog.size = Vector2(300, 120)
    confirm_dialog.title = "结束回合"
    ui_layer.add_child(confirm_dialog)


func update_info_panel(character: Character) -> void:
    if character == null:
        info_panel.visible = false
        return
    info_panel.visible = true
    # 更新 name / hp / status labels...


func update_hover(mouse_pos: Vector2, enemy: Character) -> void:
    # 悬停标签位置和内容...


func show_attack_button(show: bool) -> void:
    action_menu.show_attack_button(show)


func show_undo_button(show: bool) -> void:
    action_menu.show_undo_button(show)


# --- 内部 ---
func _create_info_panel() -> Control:
    # 从 GameManager._create_info_panel() 搬过来
    pass

func _create_hover_label() -> Label:
    # 从 GameManager._setup() 中搬过来
    pass
```

### 1.2 修改 `scripts/game_manager.gd`

删除项：
- `_create_info_panel()` 整个方法
- `_hover_label` 相关创建代码（在 `_setup()` 中）
- `_confirm_dialog` 创建代码
- `_info_panel / _name_label / _hp_label / _status_label` 变量
- `action_menu` 信号连接代码
- `_refresh_info_panel()` 改为调用 `ui_manager.update_info_panel()`
- `_process()` 中悬停逻辑改为调用 `ui_manager.update_hover()`

新增项：
- `var ui_manager: UIManager`
- `_setup()` 中创建 `UIManager` 并调用 `setup()`
- 连接 `ui_manager` 的转发信号

### 验证

- 所有 UI 元素正常显示（按钮、信息面板、悬停标签、确认弹窗）
- 按钮点击功能正常
- 悬停敌人仍然显示信息

---

## 第 2 步：拆分 TurnManager（核心）

**目标**：回合流转、行动者调度逻辑全部搬到 TurnManager。

### 2.1 新建 `scripts/turn_manager.gd`

```gdscript
class_name TurnManager
extends Node

# 依赖注入
var battle_grid_data: BattleGridData
var combat_system: CombatSystem
var grid_renderer: GridRenderer
var players: Array[Character] = []
var enemies: Array[Character] = []

# 回合状态
var round_number: int = 0
var pending_players: Array[Character] = []
var current_actor: Character = null
var has_moved: bool = false
var has_acted: bool = false
var attack_mode: bool = false
var move_from: Vector2i

# 信号
signal round_started(number: int)
signal player_phase_ended
signal enemy_phase_ended
signal actor_changed(character: Character)
signal action_completed(character: Character)


func start_round() -> void:
    round_number += 1
    print("========== 第 %d 回合 ==========" % round_number)
    for ch in players + enemies:
        ch.reset_defense()
        ch.modulate = Color.WHITE
    pending_players = _get_alive(players)
    current_actor = null
    has_moved = false
    has_acted = false
    attack_mode = false
    round_started.emit(round_number)


func select_player(ch: Character) -> void:
    # 从 GameManager._select_player() 搬过来
    # 处理角色切换、回滚等
    pass


func deselect() -> void:
    # 从 GameManager._deselect() 搬过来
    pass


func handle_move(target_cell: Vector2i) -> void:
    # 从 GameManager._on_move_cell_clicked() 搬过来
    # 移动角色 → 更新状态
    pass


func handle_attack(target: Character) -> void:
    # 从 GameManager._do_attack() 搬过来
    pass


func handle_wait() -> void:
    # 从 GameManager._on_wait() 搬过来
    pass


func end_actor() -> void:
    # 从 GameManager._end_actor() 搬过来
    # 标记当前角色完成 → 检查是否所有玩家完成
    pass


func check_end_player_phase() -> void:
    # 从 GameManager._check_end_round() 搬过来
    pass


func execute_enemy_phase() -> void:
    # 从 GameManager._execute_enemy_turns() + _step_enemy() 搬过来
    # 改为调用 controller.do_action()
    pass


# --- 内部辅助 ---
func _get_alive(pool: Array[Character]) -> Array[Character]:
    # 从 GameManager._get_alive() 搬过来
    pass

func _all_dead(pool: Array[Character]) -> bool:
    # 从 GameManager._all_dead() 搬过来
    pass
```

### 2.2 修改 `scripts/game_manager.gd`

删除项（移到 TurnManager 的）：
- `_pending_players`, `_current_actor`, `_has_moved`, `_has_acted`, `_attack_mode`, `_move_from`, `_round_number`
- `start_round()`, `_select_player()`, `_deselect()`
- `_on_move_cell_clicked()`, `_on_attack()`, `_do_attack()`
- `_on_wait()`, `_on_end_turn()`, `_on_undo()`, `_on_skill()`
- `_enter_attack_mode()`, `_cancel_attack_mode()`
- `_find_attack_position()`, `_is_in_attack_range()`
- `_end_actor()`, `_check_end_round()`
- `_on_confirm_end()`, `_on_cancel_end()`, `_do_end_player_phase()`
- `_execute_enemy_turns()`, `_step_enemy()`, `_enemy_index`
- `_on_enemy_clicked()`, `_rollback_move()`
- `check_win_condition()`
- `_get_alive()`, `_all_dead()`, `_manhattan()`
- `_refresh_attack_button()`
- `_pc()`
- `_unhandled_input()` 中大部分逻辑

保留项：
- `_setup()` — 初始化（创建 TurnManager 替代直接逻辑）
- `players[]`, `enemies[]` — 角色列表
- `battle_grid_data`, `grid_renderer`, `combat_system` — 系统引用
- `PLAYER_STATS` 等常量
- `create_character()` — 角色创建
- `_unhandled_input()` — 简化为转发给 TurnManager

### 验证

- 完整回合流程：选择角色 → 移动 → 攻击/等待 → 结束回合 → 敌人行动 → 新回合
- 切换角色自动回滚
- 撤销移动
- 防御技能
- 胜负判定

---

## 第 3 步：GameManager 瘦身收尾

**目标**：GameManager 只保留编排职责。

### 预期最终 GameManager 结构

```gdscript
class_name GameManager
extends Node

# 系统引用
var battle_grid_data: BattleGridData
var grid_renderer: GridRenderer
var combat_system: CombatSystem
var turn_manager: TurnManager
var ui_manager: UIManager

# 角色列表
var players: Array[Character] = []
var enemies: Array[Character] = []

# 角色模板
const PLAYER_STATS := { ... }
const HANLI_STATS := { ... }
const ENEMY1_STATS := { ... }
const ENEMY2_STATS := { ... }


func _ready() -> void:
    call_deferred("_setup")


func _setup() -> void:
    _init_battle_map()
    _init_systems()
    _init_ui()
    _init_characters()
    _connect_signals()
    turn_manager.start_round()


func _init_battle_map() -> void: ...
func _init_systems() -> void:
    # 创建 BattleGridData / GridRenderer / CombatSystem / TurnManager
    ...
func _init_ui() -> void:
    # 创建 UIManager
    ...
func _init_characters() -> void:
    # create_character() × 4
    ...
func _connect_signals() -> void:
    # 连接 TurnManager ↔ UIManager ↔ GameManager
    # turn_manager.round_ended → check_win_condition()
    ...


func create_character(stats: Dictionary, start_pos: Vector2i, texture: Texture2D, ctrl: Controller) -> Character:
    # 不变
    ...


func check_win_condition() -> void:
    # 从 TurnManager 搬回来 — 这属于游戏流程级别
    if _all_dead(enemies):
        print("胜利！")
    elif _all_dead(players):
        print("失败！")
    else:
        turn_manager.start_round()


# _unhandled_input → 简化转发
func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventMouseButton or not event.pressed:
        return
    var cell := grid_renderer.get_clicked_cell(event)
    # 右键取消
    if event.button_index == MOUSE_BUTTON_RIGHT:
        turn_manager.handle_right_click()
        return
    # 左键转发给 TurnManager
    if event.button_index == MOUSE_BUTTON_LEFT:
        turn_manager.handle_left_click(cell)
        return
```

### 验证

- 完整游戏流程正常
- GameManager 行数从 610 → ~80-100 行
- 每个新模块职责明确，可独立测试

---

## 文件变更汇总

| 步骤 | 文件 | 操作 |
|------|------|------|
| 0 | `scripts/controller.gd` | 修改：统一 `do_action()` 接口 |
| 0 | `scripts/ai_controller.gd` | 修改：实现 `do_action()` |
| 0 | `scripts/player_controller.gd` | 修改：实现 `do_action()` |
| 1 | `scripts/ui/ui_manager.gd` | **新建** |
| 1 | `scripts/game_manager.gd` | 修改：删除 UI 代码，改为调用 UIManager |
| 2 | `scripts/turn_manager.gd` | **新建** |
| 2 | `scripts/game_manager.gd` | 修改：删除回合逻辑，改为调用 TurnManager |
| 3 | `scripts/game_manager.gd` | 修改：清理残留，只保留编排逻辑 |
