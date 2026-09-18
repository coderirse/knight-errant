# AGENTS.md — AI 编码代理工作指南

> 本文件面向**在本仓库里改代码的自动化代理**（Claude Code、Cursor、Kilo、Copilot 等）。
> 人类读者请从 [README.md](README.md) 开始；设计取舍与踩坑全记录在 [docs/roadmap.md](docs/roadmap.md)。
>
> **改动代码前请读完第 1、2 节。** 第 2 节的铁律一旦违反，产生的是**不报错的静默 bug**，
> 测试也未必抓得住。

---

## 0. 一句话

Godot 4.7.2 的**俯视角双摇杆 Roguelike**（元气骑士式）原型，目标平台 Windows 11。

- 纯 GDScript，**无第三方插件**
- 渲染 Forward+，逻辑分辨率 480×270、整数缩放
- 场景与武器资源由 `tools/` 下的生成器脚本产出，**不是手写 `.tscn`**
- 当前进度：M0 骨架完成，里程碑 1~5（修 P0/P2 + 调参台、模板库、2D 灯光、
  5×5 中心入口、小地图）与 M2 完整循环（每层 BOSS 战）已完成，
  Windows 导出链路已打通
  （见 [docs/roadmap.md §10](docs/roadmap.md) · [§13](docs/roadmap.md)）。
  **逐条交付进度只记在 [RESEARCH.md §7](RESEARCH.md)，本节不维护第二份清单。**

---

## 1. 环境与验证闭环

### 引擎路径

```bash
GODOT=/d/Godot4/Godot_v4.7.2-stable_win64_console.exe
```

版本必须与 `project.godot` 的 `config/features` 一致（`"4.7"`）。用别的版本打开会触发全量重新导入。

### 改完代码必须跑的两套测试

```bash
# 核心系统（90 项）：伤害/护盾/能量/武器/弹匣/散射/伤害类型/子弹变体/存档/模板目录
$GODOT --headless --path . res://tools/test_gameplay.tscn

# 整合（121 项）：真实生成楼层、真物理打死敌人、清房间、过门、换层、
#                场景切换入口、永久升级生效、调参台、模板空间校验、灯光、
#                布局形状、小地图、三层完整循环（清房→BOSS→过层）、
#                对局内装填与扔枪
$GODOT --headless --path . res://tools/test_run.tscn
```

**判定标准是最后一行 `ALL NN CHECKS PASSED`。**

### 关于退出码（实测，勿依赖单一判据）

| 情形 | 退出码 |
|---|---|
| 断言失败 → 走到 `quit(1)` | **1** ✅ |
| 脚本中途报错、没走到 `quit()` | **0** ❌ |

所以**必须读 stdout**——理由不是"断言失败也返回 0"（那不对），
而是**脚本中途崩溃会返回 0**。P0 那种故障恰好属于后一类：既不报红、也不改退出码。

两套全绿 = **211 项**，与 README 一致。数量对不上说明测试被改动了。

### 生成器与执行顺序

```bash
$GODOT --headless --path . --script res://tools/setup_project.gd
$GODOT --headless --path . --script res://tools/build_scenes.gd
```

**顺序不可颠倒。** `setup_project.gd` 负责把 autoload 写进 `project.godot`；而
`build_scenes.gd` 在组装场景时会解析脚本，**autoload 没注册就会解析失败**。

> 只要你碰了 autoload 列表（新增 / 改名 / 删除），**必须先跑 `setup_project.gd`**。

### 新增 `class_name` 脚本要扫一次

新加一个带 `class_name` 的脚本之后，**先跑一次编辑器再跑测试**：

```bash
$GODOT --headless --path . --editor --quit
```

否则所有引用它的脚本会**一起**编译失败，报
`Identifier "DungeonLight" not declared in the current scope`（实测踩过：当时探针
直接打出 `rooms=0`，因为 Room 根本建不出来）。原因和 PNG 必须先导入一样——
`.godot/` 里那份 `global_script_class_cache.cfg` 是**编辑器产物**，
命令行模式不会替你重建。

### 导出 Windows exe

```bash
$GODOT --headless --path . --export-release "Windows Desktop" build/KnightErrant.exe
```

模板已安装，链路**已验证可用**（产物约 109 MB，内嵌 PCK 单文件，双击即玩）。
预设里 `exclude_filter="tools/*"` —— **测试与生成器不会被打进发布包**，这是故意的。

> **联网下载时注意**：`curl` **不读 Windows 系统代理**，只认 `http_proxy` / `https_proxy`
> 环境变量。这台机器的系统代理是 `127.0.0.1:7897`，设上环境变量后从 GitHub 下载
> 快约 95 倍。细节见 [docs/roadmap.md §13](docs/roadmap.md)。

### ⚠️ 生成器会静默覆盖手工改动

`build_scenes.gd` 无条件 `ResourceSaver.save()` 到：

| 被覆盖的文件 |
|---|
| `resources/tilesets/prototype_tileset.tres` |
| `resources/weapons/*.tres`（全部 6 把） |
| `scenes/world/{room,level,game}.tscn` |
| `scenes/ui/main_menu.tscn` |

在编辑器里手改过上面任何一个，再跑这个脚本改动就没了，**且没有任何警告**。

生成器是脚手架。一旦开始手工搭房间，就该按它头部注释说的**把脚本删掉、转为手改场景**。
（占位图生成器 `generate_placeholder_art.gd` 已在 2026-09-18 素材替换后删除。）

### 手改 `.tscn` 的坑

Godot **按文件顺序应用属性**：`script =` 必须写在自定义属性之前，
否则写在它前面的自定义属性会被**静默丢弃**（项目里 `maximum_armor = 5` 就这么丢过一次）。

---

## 2. 铁律

每一条都对应一个真实发生过的静默 bug。违反它们不会让测试变红，只会让游戏行为不对。

### 2.1 永久状态与单局状态绝不混放

| 归属 | autoload | 存盘 | 放什么 |
|---|---|---|---|
| 永久 | `GameState` | ✅ | 宝石、永久升级、解锁角色、最高层、总局数 |
| 单局 | `RunState` | ❌ | 层数、金币、击杀、本局武器、`level_seed` |

判断标准一句话：**"死了应该丢掉吗？"** 是 → `RunState`；否 → `GameState`。

`SaveManager` **只序列化 `GameState`**。不要往里加 `RunState`，除非同时存 `level_seed`
——否则读档无法重建同一层。

### 2.2 一层 = 一个场景

`Level` 生成后所有 `Room` 同时实例化并物理相邻。过门 = 传送玩家 + 移相机，
**不是加载场景**。不要在房间级别引入 `change_scene`；`SceneRouter` 只处理菜单 ⇄ 游戏这类粗粒度切换。

### 2.3 子弹的 mask 必须按阵营区分

| 层 | 值 | 用途 |
|---|---|---|
| 4 | `4` | Player Hurtbox |
| 16 | `16` | Enemy Hurtbox |

玩家子弹 mask 指向 **16**，敌人子弹 mask 指向 **4**。两边共用同一个 mask 时，
**敌人子弹永远打不中玩家，且完全不报错**。完整碰撞层表见 [docs/roadmap.md §4](docs/roadmap.md)。

### 2.4 玩家归 `PlayerHost` 所有，不属于任何场景

玩家实例挂在 autoload `PlayerHost` 下，场景只是 `adopt()` 它——这样换层（重建 `Level`）时
武器/血量/能量才能存活。

- `Game._clear_level()` **故意跳过玩家**，只清关卡几何
- 回主菜单要 `PlayerHost.despawn()`，否则下一局继承上一个死人的状态
- 切场景前要 `PlayerHost.detach()`，否则玩家会随旧场景被一起释放

### 2.5 敌人必须按需重查玩家引用

`Room._ready()` 在关卡生成期就 spawn 敌人，而玩家是**之后**才由 `Game` 创建的。
`_ready()` 里查玩家会拿到 `null` 并缓存 → 敌人永远不动、不开火。

模式是 `_resolve_player()`，每次需要时重查。见 [scripts/enemies/chaser.gd](scripts/enemies/chaser.gd)。

### 2.6 敌人的 `room` 引用靠注入，不能 `get_parent()`

敌人挂在 `Room/Actors` 下，`get_parent()` 拿到的是 `Actors` 而不是 `Room`。
`Room._spawn_enemy()` 显式注入 `enemy.set("room", self)`。
拿不到 room 引用 → 房间永远不会被判为已清空 → **门永远不开**。

### 2.7 关卡主干只能走正交步

门只能在**物理相邻**的房间之间挖。主干上连续两个房间若在网格里是斜对角，
它们没有共享墙 → 挖不出门 → **通关路径断裂**。

历史数据：允许斜向步进时，200 个种子里 **141 个**生成了无法通关的楼层。
落位也必须按行/列对齐（`_plan_origins`），理由同上。

这个属性现在由 `tools/test_run.gd` §12 守着（跨 60 个种子验证）。

### 2.8 "房间被清空" ≠ "可以过关"

宝箱房没有敌人，生成瞬间就已"清空"。过关条件必须是
**玩家走进**已清空的出口房间（`Level._try_complete_floor` 同时检查
`is_cleared` 和 `_current_room_index`）。

### 2.9 高速子弹用射线检测，不用 Area2D 重叠

一帧走的距离可能超过墙厚，重叠检测会**穿墙**。见 `Projectile._physics_process`。

### 2.10 房间的瓦片层坐标必须差一格对齐

| 空间 | 约定 |
|---|---|
| 房间局部坐标 | `(0,0)` = 外墙环左上角；`interior_rect()` 从 `(16,16)` 起 |
| `world_size()` | `(interior + 2) × 16`，含外墙环 |
| **瓦片层坐标** | 墙环占 layer `0` 与 `interior+1`；地面占 `1..interior` |
| **模板坐标** | 相对内部左上角 = layer 坐标减 1 |

**这条曾经整体错了一格**，而且**两套测试当时全绿**——因为它们断言的是
"门存在且指向正确房间"、"玩家在房间矩形内"，这些在偏一格时依然成立。
结果门被开在**地板**上而不是墙上。只有直接量几何才暴露。

**改了房间/门/瓦片坐标后，必须确认 `test_run` §17
「stamped tiles match their template」通过**，它逐格比对贴图与模板。

**涉及空间的断言要直接量几何**（`used_rect`、世界坐标、格子索引），
不要只断言结构关系——关系在偏一格时往往依然自洽。

细节见 [docs/roadmap.md §7.2](docs/roadmap.md)。

### 2.11 敌人与宝箱不能生成在实心格里

模板有柱子之后，"房间矩形内随机取点"会把敌人放进墙里 →
卡住打不死 → **房间永远清不掉 → 楼层无法通关**，
而且看起来像关卡生成 bug 而不是模板 bug。

用 `Room._spawn_tiles()`（来自模板的可走格，距边界 ≥2 格以避开门口）。
由 `test_run` §18 跨 24 个种子守着。

### 2.12 门图必须是一棵树：主干不许自触，分支只许挂一个格子

门开在**所有**正交相邻的房间之间，不只是主干步之间。所以：

- 主干拐回来贴到自己早先的格子 → 那里多开一道门 → **一条绕过必经战斗的捷径**，
  楼层悄悄变短变简单，不报错（实测去掉规则后 30 个种子里 6 个中招）。
- 分支若与第二个格子相邻 → 它成了通路而不是死路，同样绕路。

`_free_neighbours()` 要求候选格只与前驱相邻，`_plan_layout()` 的分支要求只与母房间
相邻。两条一起才让"`required_enemies` 个战斗房"这句话真的成立。

由 `test_run` §20 守着，且它断言的是**用门 BFS 走出来的最短路线**而不是 `_path`
的长度——测错对象等于没测。

---

## 3. 代码地图：改什么去哪里

| 我想改… | 去这里 |
|---|---|
| 玩家手感（移速/加速/翻滚帧数） | [scripts/player/player.gd](scripts/player/player.gd) 顶部 `@export` |
| 武器数值 | [tools/build_scenes.gd](tools/build_scenes.gd) 顶部 `WEAPONS` 表 → 重跑生成器 |
| 敌人行为 | [scripts/enemies/chaser.gd](scripts/enemies/chaser.gd) · `shooter.gd` · `boss.gd`（两阶段，数值全走 F2） |
| 关卡布局 / 房间数 / 分支 | `Level._plan_layout()` |
| 房间地形（模板） | `scripts/world/room_template_library.gd` 的 `TEMPLATES` 表 |
| 地形贴图逻辑 / 坐标约定 | `Room._build_tiles()`，改前读技术路线 §7.2 |
| 灯光观感（暗度 / 火把 / 玩家灯） | `Level.AMBIENT_COLOR` · `Room.TORCH_*` · `Player.light_*` |
| 墙体投影怎么来的 | `Room._solid_rects()` + `_make_occluder()`，改前读技术路线 §11.4 第 28 条 |
| 哪些房间的灯亮着 | `Level._apply_light_scope()`（当前房间 + 有门的邻居） |
| 小地图 / 方向提示 | [scripts/ui/minimap.gd](scripts/ui/minimap.gd)，由 `Level.room_changed` 信号驱动；房间图的唯一来源是 `Level.cell_of()` / `neighbors_of()`，别在 UI 里再算一份 |
| 房间内容（敌人数量/种类） | `Room._spawn_encounter()` / `Room._default_budget()` |
| 掉落 / 宝箱 | [scripts/world/chest.gd](scripts/world/chest.gd) · `pickup.gd` · `weapon_pickup.gd` |
| HUD 布局 | [scripts/ui/hud.gd](scripts/ui/hud.gd) |
| 调参台快捷键 / 显示 | [scripts/debug/tuning_panel.gd](scripts/debug/tuning_panel.gd) |
| 调试快捷键 / 浮层 | [scripts/debug/debug_overlay.gd](scripts/debug/debug_overlay.gd) |
| 永久升级（卖什么/多少钱/应用什么） | `GameState.UPGRADES` 表 |
| 存档字段 | `GameState.to_dict()` / `apply_dict()`（记得同步升 `SAVE_VERSION`） |
| 开局/换层流程 | [scripts/world/game.gd](scripts/world/game.gd) |
| 场景切换与淡入淡出 | [scripts/autoload/scene_router.gd](scripts/autoload/scene_router.gd) |
| 输入映射 | [tools/setup_project.gd](tools/setup_project.gd) 的 `KEY_ACTIONS`/`JOY_ACTIONS`/`AXIS_ACTIONS` |

---

## 4. 常见任务的正确做法

### 加一把武器

**不用写代码。** 改 `tools/build_scenes.gd` 的 `WEAPONS` 表加一条，重跑
`setup_project.gd`（如涉及 autoload）→ `build_scenes.gd`。
它只读 `WeaponData` 字段，加完自动出现在 `WeaponRegistry` 里。

武器参数含义见 [scripts/weapons/weapon_data.gd](scripts/weapons/weapon_data.gd)。

### 加一种敌人

1. 复制 `scripts/enemies/chaser.gd`，改行为
2. 在 `tools/build_scenes.gd` 里加场景定义（或手写 `.tscn`）
3. 在 `Room._spawn_enemy()` 里加入选择逻辑

记住 §2.5（按需重查玩家）和 §2.6（`room` 靠注入）。

### 加一个 autoload

1. 加进 `tools/setup_project.gd` 的 `AUTOLOADS`
2. **先**跑 `setup_project.gd`
3. 再跑 `build_scenes.gd`

顺序反了会解析失败。改完 autoload 列表**必须重跑两套测试**。

### 改输入动作

`tools/setup_project.gd` 的 `KEY_ACTIONS` / `JOY_ACTIONS` / `AXIS_ACTIONS` /
`MOUSE_ACTIONS` 是**权威表**，改完重跑 `setup_project.gd`。

删掉一个动作时要把它加进 `RETIRED_ACTIONS`，否则它会一直留在
`project.godot` 里（看着像还有人用）。**不要**改成"删除所有不在表里的动作"，
那会连带删掉 Godot 内置的 `ui_*`（见 §6）。

⚠️ 同一个动作名**不要同时出现在 `RETIRED_ACTIONS` 和某个 live 表里** ——
`_report_table_conflicts()` 会报错。这个 bug 真发生过：`pause` 在
`JOY_ACTIONS` 里（手柄 Start 键），同时在 `RETIRED_ACTIONS` 里，
prune 删掉又被写回。现在 prune 是**最后**执行的，退役清单无条件胜出。

### 改手感数值

**优先用游戏内的调参台（F2），不要靠改文件 + 重启。**

```bash
$GODOT --path .     # 开局后按 F2 打开
```

| 键 | 作用 |
|---|---|
| `F2` | 开关调参台 |
| `[` `]` | 选上一个 / 下一个参数 |
| `-` `=` | 减 / 加（`Shift` 加速：粗调 2%，细调 0.2%） |
| `F5` | 全部恢复本次启动时的值 |
| `F6` | 打印改动到控制台并复制到剪贴板 |

调参台的参数是**反射自动发现**的 —— Player、Health 和当前武器的每个数值型
`@export` 都会出现，**加新参数不用改调参台**。非数值类型（Texture/Color/
StringName/数组）会被跳过。

按键刻意选在 `[` `]` `-` `=`，**不占用移动和射击**，所以可以边跑边打边调。

调好之后 `F6` 转储 → 把数值**手工写回**，位置取决于参数住在哪个文件：

| 参数 | 写回哪里 |
|---|---|
| 移动 / 翻滚（`max_speed` 等） | `player.gd` 的 `@export` 默认值 |
| 武器数值 | `build_scenes.gd` 的 `WEAPONS` 表 → 重跑生成器 |
| 血量 / 护盾 / 回复速率 | **`scenes/player/player.tscn` 的 `Health` 节点** |

⚠️ 写错地方是**静默的**：`.tscn` 里的属性覆盖脚本 `@export` 默认值，
所以把护盾数值写进 `health.gd` 等于什么都没改。

> ⚠️ **调参台故意不保存 `.tres`**。`resources/weapons/*.tres` 由
> `build_scenes.gd` 生成，从调参台保存会让两边内容分叉。
> 转储是给人看的，写回代码才是持久化。

技术路线 §10 明确要求 **M1 手感阶段不铺内容**——参数定不下来就加敌人，
后面改一次要重调所有敌人。

### 加测试

写进 `tools/test_gameplay.gd`（核心系统）或 `tools/test_run.gd`（整合），
用现成的 `_check(condition, label)`。

⚠️ **测试必须写成 `.tscn` 场景，不能用 `--script`。**
`--script` 模式不实例化 autoload，`GameState`/`RunState`/`PlayerHost` 会全部缺失。
新测试套件照抄 `tools/test_gameplay.tscn` 的形式。

---

## 5. 引擎级陷阱速查

| 症状 | 原因 |
|---|---|
| 俯视角人物会"找地面"、行为怪异 | `motion_mode` 必须是 `FLOATING`，且 `floor_snap_length = 0` |
| 未来的 `RigidBody2D` 往下掉 | 项目重力必须是 0（`physics/2d/default_gravity`） |
| `--check-only` 报一堆假错 | 它**不注册 autoload**，引用 autoload 的脚本必然报错。判断正确性只能实际运行 |
| 导出的场景是空的，还不报错 | `PackedScene.pack()` 需要递归设 `owner`，漏设的子节点会消失 |
| 从信号回调里改 `monitoring` 报错 | 必须 `set_deferred("monitoring", false)` |
| 按帧数等待换场景，偶尔失败 | `change_scene_to_packed()` 是延迟的。要等"新场景已成为 `current_scene`"这个可观测条件 |
| `set_current_scene()` 报 `p_scene->get_parent() != root` | 该节点必须是 tree root 的**直接子节点** |
| png 加载不到 | 必须先让编辑器导入一次（`--editor --quit`）才能被 `load()` |
| 退出时 `RID allocations` / `ObjectDB leaked` | Godot 关闭期噪音，**不是 bug** |
| 测试里持有已 `queue_free` 的对象 | 敌人死后自我释放，循环里持有 `Health` 引用会解引用到已释放对象 |

---

## 6. 当前未完成 / 已知故障

> 这一节会过时。改完一处就更新一处，别让它烂掉。

### 🟢 P0 — 已修复：主菜单按「开始」黑屏卡死

**原因**：`SceneRouter.go_to_scene()` 读写了一个不存在的属性
`GameState.current_scene_path`（该字段在从横版改为俯视角时被删掉了）。
异常发生在**淡出到全黑、`paused = true` 之后**，协程死掉 →
`_busy` / `paused` / `input_locked` 永久为 `true` → 黑屏且后续所有切换被拒绝。

**修法**（不只是补字段，而是消除整类故障）：
所有**可能失败的操作**（路径校验、`ResourceLoader.load`）全部前置到
修改全局状态**之前**；全局状态的恢复收拢到**唯一**的 `_release()`，
成功与失败路径共用，两者不可能再分叉。

**回归测试**：`test_run.gd` §14 驱动真实入口 `start_new_run()`，
断言 `is_busy` / `paused` / `input_locked` 全部复位，并做第二次切换验证路由没卡死。
真实渲染下也验证过（开局 → Game 场景 → 100 FPS → 回菜单，零脚本错误）。

> 教训（RESEARCH.md §5.4）：**"对象存在"不等于"路径可用"。**
> 以前两套测试只 `_check(SceneRouter != null)`，从没调用过入口函数。

### 🟢 P2 — 已修复：「速度」永久升级买了没用

**原因**：升级的定义分散在两处 —— `main_menu.gd` 定义卖什么，
`game.gd` 定义应用什么，`speed` 只在前者里。

**修法**：定义收拢到 `GameState.UPGRADES` 一处表格，购买价与分级上限也从表里读。
`Player.apply_meta_upgrades()` 按表应用，`main_menu` 按表出售。
卖一个不存在的升级已经不可能。

**回归测试**：`test_run.gd` §15 断言**每一项**升级都真的改变了对应属性
（`max_speed` / `max_masks` / `max_armor`），且价格随等级上升、满级后拒绝购买。

### 🟢 P3 — 死代码已清理

以下已在 2026-09-18 清掉：

- 6 个无引用的输入动作（`jump` / `attack` / `dash` / `focus` / `pause` /
  `debug_unlock_all`）—— 由 `setup_project.gd` 的 `RETIRED_ACTIONS` 显式退役。
  **注意**：不要改成"删除所有不在表里的动作"，那条更宽的规则会把 Godot 内置的
  90+ 个 `ui_*` 导航动作一起删掉（实测无害，引擎会恢复默认值，但会让文件内容
  不可预测，并静默丢弃用户在编辑器里手动加的绑定）。
- `Player.acquire_into_room()`（空函数）
- `PlayerHost.park()` / `unpark()`（无调用者）

### 🟢 P4 — 已修复：`armor_regen_rate` 是死参数，护盾曾经几乎瞬间回满

`scripts/core/health.gd:25` 导出 `armor_regen_rate`，注释写着 "Armour points restored
per second"，`scenes/player/player.tscn:40` 把它设成 `1.0`，`test_gameplay.gd:90`
也设成 `1.0` —— **但全仓库没有任何一处读取它**（`grep -rn armor_regen_rate` 只有声明
和赋值）。`Health._process()` 里是 `armor = mini(armor + 1, maximum_armor)`，
即**安静期一过就每帧 +1**。

- **实测**（探针，已删）：`delay=0, rate=1.0, 5 点护甲` → 逐帧 `[1,2,3,4,5]`，
  **5 帧 / 0.021 秒回满，折合每秒 238 点**；注释承诺的是 5 秒。
- **后果**：玩家实配 `armor_regen_delay = 3.5` + 5 点护甲，实战表现是"躲开 3.5 秒
  然后护盾啪一下全回来"。护盾的设计意图是奖励**拉开距离**（见 roadmap §6），
  现在它奖励的是"找掩体站 3.5 秒"。而且回复速度**取决于帧率**，高刷屏上更快。
- **为什么一直没被发现**：`test_gameplay` §4 只断言 `armor >= 1`，在每帧 +1 下恒成立。
  属于 §11.0-B 同一类："定义在 A、消费在 B"，参数被认真地设置了，就是没人用。
- **修法（已做）**：`Health` 加了独立的 `_regen_progress`，安静期过后按
  `armor_regen_rate * delta` 攒小数、满 1 点才 +1，所以回复与帧率无关。
  两个边界都处理了：盾满时累加器清零（否则攒下的进度会在被打掉一点后瞬间爆发），
  `apply_damage` 里连同 `_quiet_time` 一起清零（否则被打前跑的那半秒白发）。
- **玩家起始值**：`armor_regen_delay = 3.5` + `armor_regen_rate = 2.0` →
  盾 5 点 = 3.5 秒延迟 + 2.5 秒回满。**比修复前弱得多，这是 2026-09-18 用户
  拍板的设计决定**（逐点回复奖励 hit-and-run，而非找掩体站 3.5 秒）。
  五个 `Health` 数值参数已接进 F2 调参台，手感阶段可以随时改。
- **回归测试**：`test_gameplay` §4 用两个**只差 rate** 的护盾（0.5 与 4.0）跑同一段
  时间，断言慢的那个 0 点、快的满 3 点。旧实现下两者都是 3 点，断言必红——
  **已做反向验证**：临时把实现改回每帧 +1，测试报
  `regen speed comes from the rate, not the frame count (slow 3 / fast 3)`。
  `test_run` §16 另有一条断言调参台能收集到 `armor_regen_rate`，防这条接线静默断掉。

### 其它

- **本目录已于 2026-09-18 `git init`**，分支 `main`，尚无远程仓库。`.gitignore`
  排除 `.godot/`、`build/`、`*.exe`、`*.pck`、`export_credentials.cfg`——
  导出产物有 109 MB，**不要让它进库**。
- **`docs/` 下的文件名一律用 ASCII**。原来叫 `docs/技术路线.md` 和
  `docs/开源资源清单.md`，已改名为 `docs/roadmap.md` 和 `docs/open-source.md`
  （文档内部标题仍用中文）。原因：Windows 的 GBK 代码页会让 Git 按错误编码记录
  中文文件名，**未被修改的文件会彻底躲过 `git status`**，改了也不知道；
  改名之后还会留下一条假的 delete。本机已另外设 `core.fsmonitor=true` 兜底，
  但新加文件请直接用 ASCII 名，别依赖它。
- [ ] 提交前过第 8 节清单。两套测试共 211 项，最后一行必须分别是 `ALL 90 CHECKS PASSED`（核心）与
  `ALL 121 CHECKS PASSED`（整合）。

---

## 7. 文档地图

| 文档 | 作用 | 什么时候更新 |
|---|---|---|
| [README.md](README.md) | 给人看的门面：玩法、操作、已完成内容 | 玩家可见的行为变化时 |
| [AGENTS.md](AGENTS.md) | 本文件：代理工作指南 | 命令 / 铁律 / 已知故障变化时 |
| [RESEARCH.md](RESEARCH.md) | 研究笔记：设计问题、对标拆解、待验证项 | 得出新结论或提出新问题时 |
| [docs/roadmap.md](docs/roadmap.md) | **权威设计文档**：架构、参数、决策理由、踩坑全记录 | 架构或关键参数变化时 |
| [docs/open-source.md](docs/open-source.md) | 素材/工具/插件与许可证 | 引入新素材时 |

**冲突时的优先级**：代码 > `docs/roadmap.md` > 其它。
发现文档与代码不符，**先改文档**，除非能确认代码是错的。

---

## 8. 提交前清单

- [ ] `test_gameplay` 与 `test_run` 都输出 `ALL NN CHECKS PASSED`（共 211 项）
- [ ] 碰过 autoload 列表 → 已重跑 `setup_project.gd`
- [ ] 新增了 `class_name` 脚本 → 已跑一次 `--editor --quit` 注册它（见 §1）
- [ ] 碰过 `WEAPONS` 表或场景生成器 → 已重跑 `build_scenes.gd`
- [ ] 没有把"死了该丢"的东西写进 `GameState`
- [ ] 没有把永久升级的定义写散到多处（一律进 `GameState.UPGRADES` 表）
- [ ] 新增的 `@export` 数值参数有真实的**读取方**，不是只被赋值（P4 教训：
      `grep -rn 参数名` 只出现声明与赋值 = 死参数）
- [ ] 新增的子弹/碰撞体 mask 分对了阵营
- [ ] 涉及全局状态（`paused` / `input_locked` / `_busy`）的改动 → 恢复逻辑仍收拢在 `_release()`
- [ ] 新增测试写在 `.tscn` 里，不是 `--script`
- [ ] 新增"跨系统流程" → `test_run` 里有一条驱动**真实入口**的断言（见 §2 教训）
- [ ] 碰过房间/门/瓦片坐标 → `test_run` §17「stamped tiles match their template」通过
- [ ] 碰过关卡布局 → `test_run` §20 通过（入口在正中 / 出口在边缘 / 必经战斗数）
- [ ] 在种子化生成器里打乱数组 → 用吃 `rng` 的 Fisher-Yates，不是 `Array.shuffle()`
- [ ] 新增模板 → 外圈留空、内部连通（`test_gameplay` §9 会校验）
- [ ] 本文档第 6 节已同步
