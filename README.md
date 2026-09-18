# Knight Errant

元气骑士式**俯视角双摇杆 Roguelike** 原型 · Godot 4.7.2 · 目标平台 Windows 11

完整技术路线见 **[docs/roadmap.md](docs/roadmap.md)**，
开源素材见 **[docs/open-source.md](docs/open-source.md)**。

## 快速开始

用 Godot 4.7 打开本目录并运行（F5）。默认操作：

| 键 | 动作 |
|---|---|
| `W A S D` | 移动 |
| **鼠标 / 右摇杆** | 瞄准（与移动方向独立） |
| **左键 / RT** | 射击 |
| `Space` / `Shift` / 手柄 A | 翻滚闪避（带无敌帧） |
| `Q` / `Tab` / 手柄 Y | 切换武器 |
| `E` / 手柄 X | 交互 |

调试与调参：`F2` 调参台 · `F3` 状态浮层 · `F4` 碰撞形状 · `F5` 恢复调参值 ·
`F6` 转储调参结果 · `F7` 无敌 · `F9` 重建当前层 · `F10` 作弊

**调参台（F2）** 是给"手感"用的：`[` `]` 选参数，`-` `=` 改值（`Shift` 加速），
`F6` 把改动转储到控制台/剪贴板。参数是反射自动发现的，Player、Health（护盾/生命）
和当前武器的数值型 `@export` 都会出现，**加新参数不用改调参台**。
按键刻意避开移动与射击，可以边跑边打边调。

## 目前已经跑通的内容

- **玩家**：八向移动、双摇杆瞄准、翻滚闪避（无敌帧）、双武器槽
- **武器**：6 把数据驱动武器（手枪/霰弹/冲锋枪/穿透枪/近战刀/敌人法杖），
  全局共享能量池，近战不耗能作为保底
- **敌人**：追逐型（带分离避免堆叠）、射击型（保持距离+环绕走位+攻击前摇）
- **关卡**：5×5 网格、**入口在正中心、出口在边缘**的程序生成楼层，四个方向都可能
  有新房间；房间**清怪后开门**，走进出口房间推进下一层；
  每层保证 2~3 场必经战斗（节奏是设计出来的，不由随机数决定）
- **小地图**：左上角画出本层房间图与门的连线，白框是你现在站的房间、金框是出口
- **战斗**：护盾先于血量吸收伤害，脱战 3.5 秒后**按速率逐点回复**（帧率无关）、
  击退、命中停顿、屏震、受击闪白
- **元进度**：单局状态与永久成长分离，宝石可在大厅购买永久升级
  （血量 / 护盾 / 移速，价格随等级上升）
- **存档**：3 槽位 JSON，原子写入 + 备份回滚
- **调参台**：游戏内实时调手感、武器与护盾数值，转储后可固化进代码
- **房间地形**：9 张手搭模板（固定 15/21/25 尺寸），带不变量自检
- **氛围**：压暗环境光 + 玩家随身灯 + 每房间 2~4 个火把 + 墙体实时投影；
  远离玩家的房间自动关灯（实测这个规模下灯光不是帧率瓶颈）
- **自动化测试**：2 套件 154 项断言，含"跨 60 个种子验证楼层必定可通关"、
  "场景切换入口不会黑屏"、"敌人不会生在墙里"

## 常用命令

```bash
GODOT=/d/Godot4/Godot_v4.7.2-stable_win64_console.exe

# 核心系统测试（70 项）
$GODOT --headless --path . res://tools/test_gameplay.tscn

# 整合测试：真实跑一局 + 场景切换 + 升级生效 + 调参台 + 房间模板 + 灯光 + 布局形状 + 小地图（84 项）
$GODOT --headless --path . res://tools/test_run.tscn

# 启动游戏
$GODOT --path .

# 重新生成配置 / 占位图 / 武器与场景
$GODOT --headless --path . --script res://tools/setup_project.gd
$GODOT --headless --path . --script res://tools/generate_placeholder_art.gd
$GODOT --headless --path . --script res://tools/build_scenes.gd

# 导出 Windows exe（单文件 109 MB，已验证可独立运行）
$GODOT --headless --path . --export-release "Windows Desktop" build/KnightErrant.exe
```

**改了 autoload 列表后必须先跑 `setup_project.gd`**，否则 `build_scenes.gd`
会因新 autoload 未注册而解析失败。

> **命令行下载注意**：curl 不读 Windows 系统代理，只认环境变量。
> 需要走代理时先 `export https_proxy=http://127.0.0.1:7897`（端口按你实际代理填）。

## 目录

```
scripts/autoload/   GameState(永久) · RunState(单局) · SaveManager · PlayerHost · SceneRouter
scripts/core/       DamageInfo · Hitbox · Hurtbox · Health(含护盾) · EnergyPool · Juice
scripts/player/     双摇杆玩家控制器
scripts/enemies/    追逐型 · 射击型
scripts/weapons/    WeaponData · Weapon · Projectile · WeaponRegistry
scripts/world/      Game · Level · Room · RoomTemplate + RoomTemplateLibrary · RoomDoor
                    DungeonLight · Chest · WeaponPickup · Pickup · CameraRig
scripts/ui/         HUD · 小地图 · 主菜单            （HUD 同时是 autoload）
scripts/debug/      状态浮层 · 调参台                （两者同时是 autoload）
resources/weapons/  6 把武器（.tres，加武器不用写代码）
tools/              生成器与测试（不参与导出）
docs/               roadmap.md（技术路线） · open-source.md（素材与许可证）
```

8 个 autoload 的权威清单是 `tools/setup_project.gd` 的 `AUTOLOADS`；
`HUD` / `DebugOverlay` / `TuningPanel` 按目录习惯住在 `ui/` 和 `debug/` 下。

## 注意事项

- `assets/placeholder/` 是程序生成的占位图，请整体替换。
  选素材认准 **top-down / 4-directional** 标签，横版素材套俯视角会很怪。
- 房间地形来自 `scripts/world/room_template_library.gd` 的 9 张 ASCII 模板。
  加一张模板只需往表里追加一条，但**必须保持外圈留空、内部全连通**——
  测试会校验这两条。
- 发布产物在 `build/KnightErrant.exe`（单文件内嵌 PCK，双击即玩，
  不需要装 Godot）。`tools/` 已被排除出导出包。
