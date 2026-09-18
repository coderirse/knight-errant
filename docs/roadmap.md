# 元气骑士式俯视角 Roguelike — 技术路线

> 目标平台：Windows 11 原生 exe · 引擎：Godot 4.7.2 stable · 美术：优先开源资源
> **本文档对应仓库里已经跑通的代码**，不是纸上规划。所有关键结论都有
> `tools/test_*.gd` 的自动化测试背书（两套共 211 项断言，全绿）。

---

## 0. 方向变更说明

本项目**最初按横版类空洞骑士搭过一版骨架**，后按需求改为**俯视角双摇杆
Roguelike（元气骑士式）**。这不是转个相机那么简单，差异是结构性的：

| | 横版空洞骑士 | 俯视角元气骑士 |
|---|---|---|
| 视角 | 侧视，有重力 | 俯视/三头身，**无重力** |
| 战斗 | 近战挥砍为主 | 双摇杆射击为主，武器是核心资源 |
| 移动 | 跳跃/二段跳/墙滑/下劈 | 八向移动 + 双摇杆瞄准 + 翻滚闪避 |
| 关卡 | 手工设计的大地图 | **程序生成**的房间序列 + 单局制 |
| 存档 | 存世界进度 | 存**单局外的永久成长**（宝石/解锁） |
| 房间 | 一房间一 `.tscn`，逐个加载 | 一层 = 一个场景，所有房间同时存在 |
| 生命周期 | 死亡回长椅 | 死亡结束本局，回大厅 |

**可以保留的**：Hitbox/Hurtbox/Health 战斗三件套、碰撞层思想、相机屏震、
调试浮层、headless 测试方法学、`tools/` 生成器模式。
**必须重写的**：玩家控制器、关卡/房间系统、相机、HUD、存档模型。

---

## 1. 关键设计决策

| 决策项 | 选择 | 理由 |
|---|---|---|
| 渲染器 | Forward+ | 2D 灯光质量最好（俯视角地牢很吃灯光） |
| 逻辑分辨率 | 480×270 整数缩放 | 三头身角色约 20px，双摇杆需要同时看到多个敌人和弹幕 |
| 世界结构 | **一层 = 一个场景**，所有房间同时实例化 | 过门只是传送 + 相机移动，无加载、无卡顿、无状态需要序列化 |
| 玩家归属 | **autoload `PlayerHost` 持有** | 玩家要跨"楼层重建"存活（换层不重置武器/血量） |
| 存档模型 | **永久成长（GameState）与单局状态（RunState）分离** | 死了必须清掉本局，保留元进度。混在一起就会出现"死亡丢失永久升级"的 bug |
| 关卡生成 | 网格图 + 链式主干 + 分支 | 主干保证可通关，分支给可选奖励 |
| 武器 | `.tres` 数据驱动 | 加一把武器是写一个资源文件，不是写代码 |
| 子弹碰撞 | **双方各自 mask 对方 Hurtbox 层** | 共用一个 mask 会导致一方子弹永远打不中（见 §11.4） |

---

## 2. 目录结构

```
knight-errant/
├─ project.godot                  # 由 tools/setup_project.gd 生成
├─ assets/placeholder/            # 程序生成的俯视角占位图（可整体替换）
├─ resources/
│  ├─ tilesets/prototype_tileset.tres
│  └─ weapons/*.tres              # 6 把武器（pistol/shotgun/smg/railgun/sword/enemy_pistol）
├─ scenes/
│  ├─ player/player.tscn
│  ├─ enemies/{chaser,shooter}.tscn
│  ├─ weapons/projectile.tscn
│  ├─ world/{game,level,room,chest,weapon_pickup}.tscn
│  └─ ui/main_menu.tscn
├─ scripts/
│  ├─ autoload/   game_state(永久) · run_state(单局) · save_manager · player_host · scene_router
│  ├─ core/       DamageInfo · Hitbox · Hurtbox · Health(护盾) · EnergyPool · Juice
│  ├─ player/     player.gd
│  ├─ enemies/    chaser.gd · shooter.gd
│  ├─ weapons/    weapon_data.gd · weapon.gd · projectile.gd · weapon_registry.gd
│  ├─ world/      game.gd · level.gd · room.gd · room_template.gd · room_template_library.gd
│  │              room_door.gd · dungeon_light.gd · chest.gd · weapon_pickup.gd
│  │              pickup.gd · camera_rig.gd
│  ├─ ui/         hud.gd · minimap.gd · main_menu.gd
│  └─ debug/      debug_overlay.gd · tuning_panel.gd
└─ tools/         setup_project · build_scenes · test_gameplay · test_run
```

**autoload 一共 8 个，权威清单是 `tools/setup_project.gd` 的 `AUTOLOADS`**（顺序即注册
顺序，`HUD` / `DebugOverlay` / `TuningPanel` 因历史原因住在 `ui/` 和 `debug/` 下，
不在 `autoload/` 目录里）。改这个清单**必须先跑 `setup_project.gd`**，理由见
[AGENTS.md §4](../AGENTS.md)。

---

## 3. 架构分层

```
      ┌──────────── Autoload（永久）────────────┐
      │ GameState   永久成长：宝石/升级/解锁/纪录  │  ← 存盘
      │ RunState    单局：层数/金币/武器/种子      │  ← 不存盘，死亡即清
      │ SaveManager JSON 原子写入 + .bak 回滚     │
      │ PlayerHost  持有玩家实例，跨层复用        │
      │ SceneRouter 大厅 ⇄ 游戏 的淡入淡出切换     │
      │ HUD / DebugOverlay / TuningPanel         │
      └─────────────────────────────────────────┘
                          ▲ 信号
      ┌───────────────────┴──────────────────────┐
      │ Game (Node2D)                            │
      │  ├─ LevelHolder/                         │
      │  │   ├─ Level  生成楼层：房间图 + 门 + 落位 │
      │  │   │   ├─ Room0 (Terrain/Actors/门)     │
      │  │   │   ├─ Room1 ...                     │
      │  │   └─ Player（跨层存活）                 │
      │  └─ CameraRig  跟随 + 朝向预瞄 + 屏震      │
      └──────────────────────────────────────────┘
```

**铁律：永久与单局状态绝不混放。** 任何"死了应该丢掉"的东西写 RunState，
"死了也该留着"的写 GameState。

---

## 4. 碰撞层表

| Bit | 层值 | 用途 | mask 指向 |
|---|---|---|---|
| 1 | `1` | World（墙体瓦片） | — |
| 2 | `2` | Player body | 1 |
| 3 | `4` | Player Hurtbox | 0（靠子弹主动找它） |
| 4 | `8` | Enemy body | 1 |
| 5 | `16` | Enemy Hurtbox | 0 |
| 6 | `32` | Player 近战 Hitbox | 16 |
| 7 | `64` | Enemy 接触 Hitbox | 4 |
| 8 | `128` | Hazard（预留） | 4 |
| 9 | `256` | Interactable（门/宝箱/掉落） | 2 |
| 11 | `1024` | Projectile | **按阵营取 4 或 16** |

**子弹的 mask 必须按阵营区分**（`Projectile._ready()` 里设置）：
玩家子弹找敌方 Hurtbox（16），敌人子弹找玩家 Hurtbox（4）。
早期版本两边共用 mask=16，结果是**敌人子弹永远打不中玩家**，而且完全不报错。

---

## 5. 玩家手感参数（`scripts/player/player.gd` 顶部 `@export`）

| 组 | 参数 | 默认 | 作用 |
|---|---|---|---|
| Movement | `max_speed` | 132 | 移速。俯视角比横版慢，否则难以瞄准 |
| | `acceleration` / `friction` | 1300 / 1500 | 有惯性但不飘 |
| Dodge | `dodge_time` | 0.20 | 翻滚时长（固定动量，是**承诺**不是加速） |
| | `dodge_cooldown` | 0.42 | 冷却 |
| | `dodge_invincibility_bonus` | 0.10 | 翻滚末尾多给的无敌帧，补偿输入延迟 |
| Combat | `max_weapons` | 2 | 双武器槽（元气骑士式） |

**设计要点：**

1. **瞄准方向永不被移动方向覆盖。** 后退射击（backpedal）是这类游戏的核心技巧，
   一旦让移动方向决定朝向，这个技巧就没了。
2. **翻滚是固定动量**，不做减速。承诺感来自"不能中途取消"。
3. **无敌帧比翻滚略长**，否则有延迟的输入会感觉"我明明滚了却挨打"。
4. 手柄右摇杆有输入时**优先于鼠标**，插着手柄玩不会被鼠标抢朝向。

---

## 6. 武器系统

一把武器 = 一个 `WeaponData` 资源 + 一个通用 `Weapon` 节点。加新武器只写 `.tres`。

| 武器 | 伤害 | 射速 | 弹数/散布 | 能量/发 | 定位 |
|---|---|---|---|---|---|
| pistol | 2 | 4.0/s | 1 / 3° | 1 | 起始武器，省能量 |
| shotgun | 2 | 1.3/s | 5 / 34° | 8 | 近距离高僵直 |
| smg | 1 | 11/s | 1 / 11° | 1.5 | 弹幕压制，耗能快 |
| railgun | 4 | 1.1/s | 1 / 0°，穿透 4 | 12 | 直线穿透，重击 |
| sword | 3 | 2.2/s | 近战扇区 | **0** | 无弹药，能量见底时的保底 |
| enemy_pistol | 1 | 1.0/s | 1 / 4° | 0 | 敌人专用 |

**能量池是全局共享的**（`EnergyPool`）。这让"带什么枪"变成资源决策而不是冷却
计时：霰弹枪 8 点一发，就得和 1 点一发的冲锋枪权衡。**近战不耗能**，所以它天然
是弹尽粮绝时的退路——这是刻意的设计，不要"平衡"掉。

**子弹打墙用射线检测**（`Projectile._physics_process`），不是 Area2D 重叠：
高速子弹一帧走的距离比墙厚，重叠检测会**穿墙**。

---

## 7. 关卡生成

- **一层 = 一个 `Level` 场景**，所有房间同时实例化并物理相邻。
  过门 = 传送到邻居房间 + 相机移动，**没有场景加载**，也就没有卡顿。
- **布局**：房间排在 **5×5 网格**上，入口在**正中心**，出口落在**边缘**
  （对标元气骑士，见 RESEARCH §2.2）。主干**只走正交步**；额外房间作为分支
  挂出去，且只允许挂在唯一一个格子上（死路）。
- **房间类型**：`START`（空）、`COMBAT`（清怪开门）、`TREASURE`（宝箱）、`BOSS`。
- **门**：相邻房间共享墙处挖门。清怪前 `locked`，锁住时玩家撞上去只反馈不通过。
- **过关条件**：**玩家走进已清空的出口房间**才推进下一层，
  而不是"出口房间被清空"。原因见 §11.7。
- **种子**：`(level_seed, room_index)` 决定房间内容，同种子完全可复现。
- **方向提示 = 左上角小地图**（`scripts/ui/minimap.gd`）：画整层房间格 + 门连线，
  白框是当前房、金框是出口。中心入口换来了空间感、也拿走了"往右就是前进"这个
  默认答案，小地图是补这一笔的。**刻意不是箭头**——箭头会把"选哪个方向"还给系统，
  而那次重构要的就是这个选择。由 `Level.room_changed` 信号驱动，不轮询。

### 为什么主干只走正交步（重要）

早期版本允许斜向步进（`(1,1)`），而门只能在**物理相邻**的房间之间挖。
结果：主干上连续两个房间在网格里是斜对角，它们没有共享墙 →
挖不出门 → **通关路径断裂**。

200 个种子压力测试的结果：**141 个种子生成了无法通关的楼层**。
改成只走正交步 + 落位改成"按行对齐"后，300 个种子全部连通、零重叠。
这个属性现在由 `tools/test_run.gd` 的 §12 守着（跨 60 个种子验证：
无重叠、全可达、门数足够）。

### 为什么主干必须是一棵树（同样重要）

中心入口带来一个链式布局没有的新问题：**"这一层要打几架"不再由主干长度自动决定**。

`_carve_doors()` 在**所有**正交相邻的房间之间挖门，不是只在主干步之间。所以只要
主干拐了个弯贴到自己早先的格子（比如 `S→a→b→c` 里 `c` 恰好与 `a` 相邻），那里就会
多开一道门——而那道门是一条**绕过战斗的捷径**。玩家照最短路线走，`required_enemies`
就白定了，而且**楼层还变得更短更简单，没有任何报错**。

实测这个数字：把"新格子不得触碰主干上任何非前驱格"这条规则去掉，
**30 个种子里 6 个**出现绕过战斗的捷径，入口到出口的平均房间数从 4.5 掉到 4.2。

所以 `_free_neighbours()` 要求候选格**只与前驱相邻**，`_plan_layout()` 的分支还要求
**只与母房间相邻**。两条一起把门图压成一棵树：主干 + 挂死的叶子。于是
"玩家实际会走的那条路"与"生成器规划的那条路"是同一件事，
`path.size() - 2 >= required_enemies` 才真正等于节奏被保证。

`test_run` §20 跨 30 个种子、两种楼层奇偶，断言的就是**走出来的最短路线**上的战斗数
（不是 `_path` 的长度）—— 测错对象的话这条性质就白保了。

**另一个坑（同一次改动里踩的）**：`Array.shuffle()` 用的是**引擎全局随机**，不是
生成器传进来的 `rng`。用它打乱主干候选，同一个种子就重建不出同一张图，
`test_run` §11 立刻报红。要打乱就自己写 Fisher-Yates 吃 `rng`。

### 7.1 房间模板库

房间地形不再由代码画矩形，而是从**手搭模板**里取：

```
scripts/world/room_template.gd          单个模板：解析、查询、自检
scripts/world/room_template_library.gd  目录：9 张模板 + 按尺寸挑选
```

**尺寸固定为 15 / 21 / 25（正方形），对标元气骑士的 15/21/25。**
不再用随机尺寸，因为门的对齐依赖两间房墙面的重叠量：尺寸集合已知时
`Level._connect()` 的重叠计算是精确的。代价是房间外形变化变少，
换来的是一整类"门开不出来"的 bug 消失。

**模板是 ASCII，`.` 可走 / `#` 实心**，只描述**内部**，不含外墙环。
两条不变量由 `RoomTemplate.problems()` 强制，而不是靠人自觉：

| 不变量 | 为什么 |
|---|---|
| **外圈必须留空** | `Level` 会在墙环任意位置挖门，模板外圈若是实心就会堵死门 |
| **内部必须全连通** | 封死的口袋会把敌人困住 → 房间永远清不掉 → **楼层无法通关** |

**这个自检很关键。** 上面两条出错都是**静默的**：游戏照跑、不报错，
只是某些种子下不可通关。`test_gameplay` §9 直接校验目录；
`test_run` §17 校验"贴出来的瓦片和模板一致"（抓坐标偏移一格），
§18 跨 24 个种子校验"没有敌人/宝箱生在墙里"。

**敌人生成必须用模板的可走格**，不能再用"房间矩形内随机取点"：
柱子出现后随机点会落进墙里 → 敌人卡住打不死 → 房间清不掉。
而且要求距边界 ≥2 格 —— 门就在边界上，敌人堵门会秒杀刚进门的玩家。

**挑模板是确定性的**（种子决定），所以同一层可复现。

**当前局限**：模板还是 ASCII 数据，不是 TileMap 场景。等布局定型后应转成
编辑器里手搭的 `.tscn`，那时才方便做视觉调整（地面材质变化、装饰物、
光照锚点）。ASCII 只适合现在还在一起迭代的阶段。

### 7.2 瓦片坐标约定（改动前必读）

这是**最容易静默出错的地方**，曾经整层偏了一格：

| 空间 | 约定 |
|---|---|
| 房间局部坐标 | `(0,0)` 是外墙环左上角；`interior_rect()` 从 `(16,16)` 开始 |
| `world_size()` | `(interior + 2) × TILE`，含外墙环 |
| **瓦片层坐标** | 墙环占 layer `0` 与 `interior+1`；地面占 `1..interior` |
| **模板坐标** | 相对内部左上角，即 layer 坐标减 1 |

门开在**墙环**的中心（如右侧门 `local.x = world_size.x - TILE/2`）。
门的触发框做成 2 格长、跨墙与地板各一格 —— 正好嵌在墙里的小方框只会与
玩家**相切**，重叠判断不可靠，表现是"门时灵时不灵"。

**改这里之后必须跑 `test_run` §17**：它逐格比对"贴出来的瓦片 vs 模板"，
坐标偏移一格会立刻报出来（这次就是它抓到的，355 处不匹配）。

---

## 8. 存档模型

`SaveManager` 写 `user://saves/slot_XX.json`，**只存永久成长**：

- 宝石、永久升级等级、已解锁角色、最高层数、总局数、总击杀、游戏时长。
- **不存单局进度**——这是 roguelike，死亡本来就该损失本局。
- 原子写入：先写 `.tmp`，旧档改名 `.bak`，再 rename 覆盖。中途崩溃不会毁档。
- 带 `version` 字段，`load_game()` 里预留迁移分支。
- `slot_summary()` 给 UI 用。

若将来要做"中断续跑"，把 `RunState.to_dict()` 也加进去即可——
**但必须同时存 `level_seed`**，否则无法重建同一层。

---

## 9. 开源资源清单

> 许可证以官网为准，**商用前逐个复核**。详见 [开源资源清单.md](./open-source.md)。

| 类别 | 推荐 | 许可 |
|---|---|---|
| 俯视角角色/敌人 | 0x72 `DungeonTileset II` | **CC0** |
| 俯视角地形 | Kenney `Tiny Dungeon` / `Tiny Town`、`1-Bit Pack` | **CC0** |
| 俯视角角色（另一套） | Kenney `Tiny Dungeon` 附带的 4 向角色 | **CC0** |
| 音效 | Kenney `Audio` 系列 | **CC0** |
| 音乐 | incompetech、Free Music Archive | CC-BY |
| 中文像素字体 | **霞鹜文楷 LXGW WenKai**、思源黑体 | OFL |
| 像素画工具 | **Pixelorama**（Godot 生态）、Aseprite | MIT / 商业 |
| 音效生成 | jfxr / BFXR | CC0 |
| Godot 插件 | Phantom Camera（相机）、Beehave/LimboAI（敌人 AI） | MIT |

**注意**：元气骑士的观感一半来自**俯视角三头身比例**（头约等于身体大小、
从上往下看）。用横版素材硬套会被看成"俯视的横版游戏"。
选素材时认准 **top-down / 4-directional** 标签。

**中文项目坑**：像素英文字体几乎没有中文字形。中文 UI 用霞鹜文楷或思源黑体。

---

## 10. 开发里程碑

| 阶段 | 目标 | 验收 |
|---|---|---|
| **M0 骨架** ✅ | 双摇杆、武器、敌人、程序生成、HUD、存档、测试 | `test_gameplay` + `test_run` 全绿（交付时 96 项；当前 211 项） |
| **M1 手感** | 只调玩家/武器参数，不加内容 | 拿手枪连打 10 分钟不烦躁；翻滚能稳定躲弹幕 |
| **M2 一层的完整循环** | 出生→清房间→宝箱换枪→BOSS→下一层 | 从进游戏到打完 3 层不用重启 |
| **M3 内容** | 敌人 6~8 种、BOSS 3 个、武器 15 把、5 层 | 每层有新敌人组合，武器有取舍 |
| **M4 元进度** | 大厅、宝石消费、角色解锁 | 死一次能感到"我变强了" |
| **M5 视听** | 换素材、加音效/BGM、2D 灯光 | 有地牢氛围（见下） |
| **M6 发布** | 导出 Win11 exe | 见 §13 |

**M1 不要跳。** 双摇杆的手感（移速/瞄准/翻滚帧数）决定了后面所有敌人该怎么设计，
参数定不下来就铺内容，改一次要重调所有敌人。

> 本表是**粗粒度阶段规划**，不跟随每次交付更新。M0 之后实际做掉的步骤
> （里程碑 1：修 P0/P2 + 清死代码 + 调参台；里程碑 2：房间模板库）按日期记在
> [RESEARCH.md §1 与 §7](../RESEARCH.md)。**不要在这里再抄一份进度**，
> 那正是 §11.0-B 说的"定义分散两地必然分叉"。

### 氛围（已做，2026-09-18）

俯视角地牢的"高级感"主要来自**灯光对比**，不是素材精度。已落地：

| 件 | 位置 | 值 |
|---|---|---|
| `CanvasModulate` 压暗全局 | `Level/Ambience`，一层一个，随层释放 | `(0.14, 0.16, 0.24)` |
| 玩家随身灯 | `Player._build_light()`，`light_energy` / `light_scale` 是 `@export` + setter，F2 可直接调 | 1.1 / 1.7 |
| 每房间火把 | `Room/Lighting`，按尺寸 2 / 3 / 4 个，落在最靠近四角的可走格 | `1.9` 能量、暖橙 |
| 墙体投影 | 同 `Lighting` 持有者，合并后的矩形各一个节点 | 见下 |

两个**实测**结论记在 [RESEARCH.md §3.11](../RESEARCH.md)：Godot 4.7 的
`TileMapLayer` **完全没有 per-tile 遮挡物**，只能自己发 `LightOccluder2D` 节点，
所以做了"横条合并成矩形"（一层 5 房共 **41 个**，按格生成会是 400+）；
以及**灯光不是帧率瓶颈**（邻近开关 169.8 FPS vs 全开 166.4）。
开关仍然保留——它让成本不随楼层大小增长，而不是为了现在的几帧。

---

## 11. 踩过的坑（真实记录）

### 11.0 三个最贵的教训（元层面，比单个 bug 值钱）

**A. "对象存在"不等于"路径可用"。** 两套测试都完整跑通了，仍然漏掉一个
P0 级致命故障：主菜单按「开始」黑屏卡死。因为测试只断言
`SceneRouter != null`，从没调用过真实入口 `start_new_run()`。
**新增任何跨系统流程，都要问一句：这条路径有测试真的走过吗？**
现在 `test_run.gd` §14 守着这条路径。

**B. 定义分散在两地，就一定会分叉。** 永久升级"卖什么"写在 `main_menu.gd`、
"应用什么"写在 `game.gd`，结果 `speed` 被卖出去却从没生效，玩家白花宝石，
**全程不报错**。凡是"定义在 A、消费在 B"的成对逻辑，都该收拢成单一数据源
（现在升级全在 `GameState.UPGRADES` 表；调参台用反射自动发现而不是手写清单，
是同一个思路）。

**C. 参数被认真地设置了，不代表有人读它。**（B 的第三种形态，2026-09-18）
`armor_regen_rate` 有 `@export`、注释写着"每秒恢复点数"、`player.tscn` 和测试里
都赋了值 —— **消费者数量是 0**，实际实现是每帧 `+1`，于是 5 点护盾 0.021 秒回满、
且速度随帧率变化。守卫它的断言 `armor >= 1` 在错误实现下恒成立，所以 138 项测试
绿了很久也没人发现。
**推论**：加一个可调参数，要同时问两句——**"谁读它"（`grep -rn 名字`）和
"测试能不能区分它被读和没被读"**。这次的解法是一条**比较式断言**：两个只差 rate 的
护盾跑同一段时间，慢的必须回得更少；这种断言不依赖绝对时序（所以不会 flaky），
而且**在 bug 存在时必然是红的**（已反向验证）。

### 11.1 俯视角相关

1. **`motion_mode` 必须是 `FLOATING`**（枚举值 1），且 `floor_snap_length = 0`。
   默认的 GROUNDED 模式会去寻找"地面"，俯视角下没有任何东西是地面。
2. **项目重力要设成 0**（`physics/2d/default_gravity`）。任何未来加入的
   `RigidBody2D` 杂物都会往下掉出屏幕。
3. **`_ready()` 里查玩家会拿到 null**。房间在 `generate()` 期间生成敌人，
   而玩家是之后才创建的。所有敌人都必须**按需重查**玩家引用
   （`_resolve_player()`），否则敌人永远不动、也不开火。
4. **子弹 mask 必须按阵营区分**。两边共用一个 mask=16 时，玩家子弹正常、
   敌人子弹永远打不中玩家，且**完全不报错**。

### 11.2 关卡生成
5. **主干只能用正交步**（§7）。斜向步会挖不出门，200 个种子里 141 个无法通关。
6. **落位要按行/列对齐**（`_plan_origins`）。按列堆叠高度会让同一行的两个
   相邻房间 y 坐标错开，门依然挖不出来。
7. **"房间被清空"≠"可以过关"**。宝箱房没有敌人，生成时就已"清空"，
   早期版本因此在生成瞬间就把整层判成通关。过关条件必须是
   **玩家走进**已清空的出口房间。
8. **瓦片层坐标与房间局部坐标必须差一格对齐**。墙环占 layer 的 `0` 和
   `interior+1`，地面占 `1..interior`；房间局部坐标里 `interior_rect()`
   从 `(16,16)` 开始、`world_size()` 是 `interior+2` 格宽。
   **早期版本把墙环画在 layer `-1` 和 `interior+1`**，于是每个瓦片都比
   其余代码认为的位置偏了一格：生成点落在错误的格子上，**门被开在地板而不是墙上**。
   这个 off-by-one **逻辑测试完全看不出来**——两套测试当时全绿——
   只有把几何量出来（`used_rect` vs `world_size`）才暴露。
   教训：**格子坐标差一格是静默的，几何断言要直接量，不要靠推理。**
9. **门的触发框要比门洞大，并向房内探进**。修好坐标后门正好嵌在墙里，
   玩家撞墙时身体边缘只与门**相切**，重叠不可靠（会时灵时不灵）。
   现在触发框是 2 格长、跨墙与地板各一格。
10. **带障碍的房间不能再用随机点放敌人**。模板出现柱子后，"房间矩形内随机取点"
    会把敌人放进墙里 → 卡住、打不死 → **房间永远清不掉 → 楼层无法通关**，
    而且看起来像关卡生成 bug 而不是模板 bug。改用模板的可走格，并要求
    距离边界 ≥2 格（门就在边界上，敌人堵门会秒杀刚进门的玩家）。
    现在由 `test_run` §18 跨 24 个种子守着。

### 11.3 节点与场景
11. **`PackedScene.pack()` 需要 `owner`**。子节点不设 `owner`，导出的场景是空的，
   而且不报错。生成器必须递归设 `owner`。
12. **`.tscn` 里 `script=` 必须写在自定义属性之前**。Godot 按文件顺序应用属性，
   写在 script 之前的自定义属性会被静默丢弃（`maximum_armor = 5` 就这么丢过一次）。
13. **敌人挂在 `Room/Actors` 下**，所以敌人里 `get_parent()` 拿到的是 `Actors`
    而不是 `Room`。需要 Room 引用时由 Room 显式注入（`enemy.set("room", self)`），
    否则房间永远不会被判为已清空。
14. **`_despawn()` 里不能直接改 `monitoring`**。从 `area_entered` 信号里调用时
    Godot 禁止修改，必须 `set_deferred("monitoring", false)`。

### 11.4 引擎/测试环境
15. **`--script` 模式不加载 autoload**，也不注册 `class_name`。
    所以测试写成 `.tscn` 场景，不能用 `--script`。
16. **`--check-only` 不注册 autoload**，会对所有引用 autoload 的脚本报**假错**。
    判断脚本正确性只能实际运行。
17. **`ChangeSceneToPacked` 是延迟换场景**，按帧数等待是抛硬币，
    要等"新场景已成为 current_scene"这个可观测条件。
18. **`set_current_scene()` 要求节点是 root 的直接子节点**，否则报
    `Condition "p_scene && p_scene->get_parent() != root" is true`。
19. **PNG 必须先让编辑器导入**（`--editor --quit`）才能被 `load()` 加载。
20. 退出时的 `Unreferenced static string` / `RID allocations` /
    `ObjectDB instances were leaked` 是 Godot 关闭期噪音，不是 bug。
21. **测试里不要跨帧持有会 `queue_free` 的节点引用**——敌人死亡后会自我释放，
    循环里持有 `Health` 引用会解引用到已释放对象。
22. **退出码不是可靠判据**：`quit(1)` 会传出 1，但**脚本中途抛错返回 0**。
    判定必须读 stdout。
23. **探针/测试挂在 `current_scene` 槽位上会被自己释放**。
    `change_scene_to_packed()` 释放旧的 `current_scene`，正在 `await` 的协程随之死亡
    （表现：只打印第一条日志就没了）。要先 `get_tree().current_scene = null`，
    让探针作为 root 的普通子节点存活。
24. **`DisplayServer.clipboard_set()` 在 headless 下会报错**，
    用 `DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)` 先判断。
25. **`ProjectSettings.get_property_list()` 里的 `input/*` 包含 90+ 个引擎内置
    `ui_*` 动作**。按"删除所有不在我表里的 input 动作"来清理，会把它们一起删掉。
    实测**无害**（引擎启动时恢复默认绑定），但会让 `project.godot` 内容不可预测，
    并静默丢弃用户在编辑器里手动做的绑定。清理要用**显式退役清单**。
26. **`String(int)` 不是合法的 GDScript 构造**，数字转字符串要用格式化
    （`"%d" % value`）。
27. **新加的 `class_name` 脚本要先让编辑器扫一遍才认得。** 实测：新增
    `scripts/world/dungeon_light.gd`（`class_name DungeonLight`）后直接跑游戏，
    所有引用它的脚本**一起**编译失败，报 `Identifier "DungeonLight" not declared`，
    连带 Room 建不出来（探针打出 `rooms=0`）。跑一次 `--editor --quit` 重建
    `.godot/global_script_class_cache.cfg` 即可。与第 19 条"PNG 要先导入"同源：
    **`.godot/` 里的缓存是编辑器产物，命令行模式不会替你重建。**
28. **`TileMapLayer` 没有 per-tile 遮挡物。** 4.7 实测：没有 `occluders_enabled`，
    没有 `set_cell_occluders_enabled`，`TileSet` / `TileSetAtlasSource` 上也找不到
    任何 occluder 接口。所以瓦片墙的投影只能自己发 `LightOccluder2D` 节点；
    按格发一层 5 房要 400+ 个，故 `Room._solid_rects()` 先把实心格并成矩形（41 个）。
    别照着 3.x 时代 `TileMap.occluders_enabled` 的印象写。
29. **`Array.shuffle()` 用的是引擎全局随机，不吃你传进去的 `rng`。** 在种子化的
    生成器里用它打乱候选，同一个种子就重建出不同的结果——"同种子同楼层"直接失效
    （实测被 `test_run` §11 抓到）。要确定性打乱就自己写吃 `rng` 的 Fisher-Yates。
    同理注意 `randomize()` / `randi()` 这类全局函数都会污染可复现性。

---

## 12. 测试与命令

两套共 **211 项**，判定标准是 stdout 最后一行 `ALL NN CHECKS PASSED`。

```bash
GODOT=/d/Godot4/Godot_v4.7.2-stable_win64_console.exe

# 核心系统：伤害/护盾/能量/武器/弹匣/散射/伤害类型/子弹变体/存档/房间模板目录（90 项）
$GODOT --headless --path . res://tools/test_gameplay.tscn

# 整合：真实跑一局——生成楼层、真物理打死敌人、清房间、过门、换层、
#       场景切换入口（P0 回归）、永久升级生效、调参台、模板空间校验、灯光、布局形状、小地图、
#       三层完整循环、对局内装填与扔枪（121 项）
$GODOT --headless --path . res://tools/test_run.tscn

# 启动游戏
$GODOT --path .

# 重新生成配置 / 武器与场景
$GODOT --headless --path . --script res://tools/setup_project.gd
$GODOT --headless --path . --script res://tools/build_scenes.gd
```

**注意执行顺序**：改了 autoload 列表后必须先跑 `setup_project.gd`，
否则 `build_scenes.gd` 会因为新 autoload 未注册而解析失败。

**关于退出码**（实测）：`quit(1)` 确实传出 1，所以断言失败能被 shell 检出；
但**脚本中途抛错、没走到 `quit()` 时返回 0**。因此判定必须读
stdout 的 `ALL NN CHECKS PASSED`，不能只看退出码。

### 调参台（F2）

手感必须由人玩出来，所以参数调整做成了游戏内实时调，不用改文件 + 重启。

| 键 | 作用 |
|---|---|
| `F2` | 开关调参台 |
| `[` `]` | 选参数 |
| `-` `=` | 减 / 加（`Shift` 加速：粗调 2%，细调 0.2%） |
| `F5` | 恢复本次启动时的值 |
| `F6` | 转储改动到控制台 + 剪贴板 |

参数靠**反射**从 Player、Health 与当前武器的数值型 `@export` 自动发现，加新参数无需改面板。
（`Health` 是玩家的子节点，所以要显式指一次收集源——`test_run` §16 有断言守着这条接线。）
按键避开移动与射击，可边跑边打边调。

调好后把数值手工写回，**写回位置取决于参数住在哪个文件**：
`player.gd` 的 `@export` 默认值（移动/翻滚）、`WEAPONS` 表 + 重跑生成器（武器）、
**`scenes/player/player.tscn` 的 `Health` 节点**（血量/护盾/回复）。
写错地方是**静默的**：`.tscn` 里的属性会覆盖脚本默认值，所以往 `health.gd`
里写护盾数值等于什么都没改。
**调参台故意不保存 `.tres`**——那些文件由 `build_scenes.gd` 生成，两边同时写会分叉。

### 调试快捷键

| 键 | 功能 |
|---|---|
| `F2` | 调参台 |
| `F3` | 状态浮层（楼层/房间/敌人/武器/无敌帧/子弹数） |
| `F4` | 显示碰撞形状 |
| `F5` | 调参：恢复启动值 |
| `F6` | 调参：转储改动 |
| `F7` | 无敌 |
| `F9` | 原地重建当前层（测生成用） |
| `F10` | 作弊：满能量满血 + 全部武器 |

### 默认操作

`WASD` 移动 · **鼠标瞄准 + 左键射击** · `Space`/`Shift` 翻滚闪避 ·
`Q`/`Tab` 换武器 · `E` 交互。手柄：左摇杆移动、右摇杆瞄准、RT/RB 射击、
A/B 翻滚、X 交互、Y 换武器。

---

## 13. 导出 Windows 11 exe

**状态：已打通。** 导出模板已安装到
`%APPDATA%\Godot\export_templates\4.7.2.stable\`，`export_presets.cfg` 已就位，
产出 `build/KnightErrant.exe`（约 109 MB，内嵌 PCK 单文件，双击即玩）。

```bash
$GODOT --headless --path . --export-release "Windows Desktop" build/KnightErrant.exe
```

已实测：导出的 exe 独立启动、D3D12/Forward+ 正常渲染、`tools/` 未被打进包
（预设里 `exclude_filter="tools/*"`，测试不该发布给玩家）。

### 装模板的正确姿势（踩过坑）

**走系统代理。** 这台机器 Windows 系统代理是 `127.0.0.1:7897`，
但 **curl 不读 Windows 注册表代理**，只认 `http_proxy` / `https_proxy` 环境变量。
直连 GitHub 只有 ~240 KB/s 且反复断流（下 1.2 GB 要 85 分钟，还会中途卡死）；
设上环境变量后 **23 MB/s，74 秒下完，快 95 倍**：

```bash
export https_proxy="http://127.0.0.1:7897" http_proxy="http://127.0.0.1:7897"
curl -L -o tpl.tpz "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
```

注意下载地址在 **`godot-builds`** 仓库（`godotengine/godot-builds`），
不是 `godotengine/godot`；官方镜像 `downloads.godotengine.org` 在国内反而更慢。

`.tpz` 就是个 ZIP，顶层是 `templates/` 目录。**Godot 要的是该目录的*内容*，
直接放进版本号命名的文件夹**，层级套错会报"找不到模板"：

```
%APPDATA%\Godot\export_templates\4.7.2.stable\
    windows_release_x86_64.exe     ← 不要多套一层 templates/
    windows_debug_x86_64.exe
    version.txt                    ← 内容必须是 4.7.2.stable，与引擎严格一致
```

**版本必须严格匹配**（`4.7.2.stable`）。README 里写的 "4.7" 只是 major.minor，
真正校验的是 `version.txt` 的完整字符串。

其他关键预设项：`Binary Format = Embedded PCK`（单 exe，方便分发）、
架构 `x86_64`。`export_presets.cfg` 可进版本库；
`.godot/`、`build/`、`*.exe` 已在 `.gitignore` 里。

---

## 14. 下一步

> **排序的权威在 [RESEARCH.md §1](../RESEARCH.md)**（"上面的没答案之前，不要做下面的"）。
> 本节只保留各件事**具体怎么做**的技术要点，不要在这里维护优先级——
> 曾经两份清单并存，结果 RESEARCH 已记里程碑 2 完成，本节还把它列为待做。

1. **M1 手感**：只调 `player.gd` 和 `resources/weapons/*.tres` 的数值。
   武器参数全在 `tools/build_scenes.gd` 顶部的 `WEAPONS` 表里，改完重跑生成器即可。
2. **装 2D 灯光**（`CanvasModulate` + `PointLight2D` + `LightOccluder2D`），
   性价比最高的观感提升。
3. **换素材**：从 §9 挑 CC0 俯视角素材替换 `assets/placeholder/`，
   同步改 `.tscn` 里的 `texture` 引用（节点结构和碰撞形状不用动）。
4. **BOSS**：`AnimationTree` + `AnimationNodeStateMachine`，
   每个阶段一个状态，攻击靠 `Hitbox.activate()/deactivate()` 打帧；
   血条走 HUD 的 banner 接口。
5. **敌人变多后**引入 Beehave 或 LimboAI 行为树，替换手写的 `_steer()`。
6. ~~**房间变复杂后**把 `Room._build_tiles()` 换成手搭模板库，生成时随机抽取模板
   而不是每次画矩形。~~ ✅ **已完成**（里程碑 2，见 §7.1）。**剩下的那半**是
   把 ASCII 模板转成编辑器里手搭的 `.tscn`，以便做视觉调整——但**要等布局定型**，
   现在转等于把还在改的东西固化。
