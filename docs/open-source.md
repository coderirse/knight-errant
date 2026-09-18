# 开源资源清单（俯视角 Roguelike）

> 原则：**能 CC0 就 CC0**（无需署名、无传染性）。其次 OFL/MIT。CC-BY 要放署名，
> GPL 不能静态链接进闭源商业游戏（作为独立工具使用没问题）。
>
> **链接状态**：本清单所有链接已于 **2026-09-18** 实测可访问（HTTP 200），
> 其中 Kenney 各包的 CC0 声明是在官网页面上直接核对到的。
> **但"能访问"≠"许可证没变"——商用前请逐个回官网复核。**

---

## 0. 本项目要替换的是什么

素材只有一处：**`assets/placeholder/`**，14 张 PNG，全部由
[tools/generate_placeholder_art.gd](../tools/generate_placeholder_art.gd) 程序生成。
节点结构与碰撞形状跟贴图解耦，所以替换是**纯美术改动**。

| 占位图 | 需要什么 | 去哪拿 |
|---|---|---|
| `player.png` | 俯视三头身角色，带行走动画 | §2.1 |
| `chaser.png` · `shooter.png` | 俯视敌人 | §2.1（怪物数量首选 DungeonTileset II） |
| `tile_ground.png` | 16×16 地形 **+ 墙体自动拼接的全套边缘瓦片** | §2.2 |
| `gun_pistol.png` · `gun_shotgun.png` · `sword.png` | 武器图标——**本项目最大的素材缺口**，见 §2.3 | §2.3 |
| `bullet.png` · `enemy_bullet.png` | 子弹 | 多数包自带；也可自绘（`bullet_tint` 已能调色） |
| `chest.png` · `portal.png` | 宝箱、传送门 | DungeonTileset II 直接就有 |
| `coin.png` · `heart.png` · `energy_orb.png` | HUD 图标 | ⚠️ HUD 现在全部用 `ColorRect` 纯色方块画，换成贴图是**另一件事**，不只是替换文件 |

> **替换时的省事做法**：保持文件名和路径不变、直接覆盖 PNG，则 `.tscn` / `.tres` 里
> 的 `texture = ExtResource(...)` 一行都不用改。
> **注意 `tools/generate_placeholder_art.gd` 会无警告覆盖这些 PNG——真素材进来后把它删掉。**

---

## 1. 选素材的两条规则

### 1.1 认准 top-down

元气骑士的观感来自**俯视角三头身**（从上往下看、头约等于身体大小）。
用横版素材硬套，一眼就会被看成"俯视的横版游戏"。搜素材时认准
**top-down / 4-directional / 8-directional** 标签。

### 1.2 数清楚有几个方向的动画（比 1.1 更容易踩）

"top-down"只保证**视角**对，不保证**方向数**对。这是两件独立的事：

- **0x72 DungeonTileset II** 的角色只有**上下左右四向**行走动画，**没有斜向**。
- 本项目的移动是**八向**的（`Input.get_axis` 两轴合力）。

所以换素材前必须先定一件事：**角色朝向跟"移动方向"还是跟"瞄准方向"？**

| 方案 | 朝向来源 | 需要几向动画 | 说明 |
|---|---|---|---|
| 元气骑士的做法 | 移动方向 | 4 向即可 | 武器独立旋转，角色只管走路 |
| 本项目现在的做法 | **瞄准方向**（`aim_direction`） | 8 向才够 | 当前 [player.gd](../scripts/player/player.gd) 只做了左右翻转，没有方向动画 |

现在代码是**纯左右翻转**，所以四向素材能直接接上、不会冲突。但如果你想让角色"转身朝鼠标"，
四向素材就不够了——**这是选素材前就要定的方向，不是拿到素材再补。**

---

## 2. 美术

### 2.1 角色 / 敌人

| 资源 | 链接 | 许可 |
|---|---|---|
| **Kenney `Top-down Shooter`** | <https://kenney.nl/assets/top-down-shooter> | **CC0**（官方页核实） |
| **0x72 `DungeonTileset II`** | <https://0x72.itch.io/dungeontileset-ii> | **CC0** |
| Kenney `Roguelike Characters` | <https://kenney.nl/assets/roguelike-characters> | **CC0** |
| Kenney `Tiny Dungeon` | <https://kenney.nl/assets/tiny-dungeon> | **CC0** |
| Kenney `Tiny Town` | <https://kenney.nl/assets/tiny-town> | **CC0** |
| Kenney `1-Bit Pack`（极简黑白，做原型够用） | <https://kenney.nl/assets/1-bit-pack> | **CC0** |
| Kenney 罗格列克相关包总览 | <https://kenney.nl/assets?search=roguelike> | **CC0** |
| itch.io 俯视角免费素材（逐个看许可） | <https://itch.io/game-assets/free/tag-top-down> | 逐个看 |
| LPC（Liberated Pixel Cup）合集 | <https://opengameart.org/> | CC-BY-SA / GPL ⚠️ |

**怎么选：**

- **`Top-down Shooter` 与本项目玩法同源**（俯视射击向，含角色与枪械），
  是唯一同时解决"俯视角色 + 枪"的 CC0 包 → **首选试这个**
- **`DungeonTileset II` 的怪物数量与动画质量更高**，但取向是**中世纪奇幻**（剑/弓/法杖）→ 做敌人和地形更好
- ⚠️ **LPC 合集**角色极多，但 **CC-BY-SA 有传染性**、GPL 不能静态链接进闭源商业游戏，**商业项目避开**

### 2.2 地形 / 场景

| 资源 | 链接 | 许可 | 备注 |
|---|---|---|---|
| **0x72 `DungeonTileset II`** | <https://0x72.itch.io/dungeontileset-ii> | **CC0** | **含墙体/地板自动拼接所需的全套边缘瓦片**，自己凑这套非常痛苦 |
| Kenney `Tiny Dungeon` | <https://kenney.nl/assets/tiny-dungeon> | **CC0** | 直接切进 Godot TileSet |
| Kenney `Roguelike Caves & Dungeons` | <https://kenney.nl/assets/roguelike-caves-dungeons> | **CC0** | 洞穴/地牢地形 |
| Kenney `Roguelike/RPG pack` | <https://kenney.nl/assets/roguelike-rpg-pack> | **CC0** | 家具、箱子、门 |
| Kenney `Micro Roguelike` | <https://kenney.nl/assets/micro-roguelike> | **CC0** | 更小尺寸 |

> 项目当前的 TileSet 在 `resources/tilesets/prototype_tileset.tres`，只有一个图集源
> （地面 / 地面变体 / 墙 / 墙碰撞）。换素材时这个文件的 `texture` 和瓦片坐标要同步改。

### 2.3 武器（枪械）—— 本项目最大的缺口 ⚠️

**为什么单列一节**：`docs/roadmap.md §6` 里 6 把武器里有 **4 把是枪**
（pistol / shotgun / smg / railgun），但**主流的 CC0 地牢素材包全是中世纪奇幻取向**——
剑、弓、法杖、盾，**没有枪**。搜"DungeonTileset II"找到枪是不现实的。

三条出路：

| 方案 | 做法 | 代价 |
|---|---|---|
| **A. 换素材源**（推荐） | 用 <https://kenney.nl/assets/top-down-shooter>（含枪械） | 美术调性偏现代军事 |
| **B. 改成奇幻皮** | 保留 DungeonTileset II，武器改名：手枪→法杖、霰弹→散射法杖、穿透枪→穿透光束 | **一行代码都不用改**（武器是 `.tres` 数据驱动），但失去枪械味 |
| **C. 自绘** | 16×16 的枪非常小，项目已有生成器模式（`generate_placeholder_art.gd`） | 要花时间，但风格最统一 |

> **另一个坑**：当前 **4 把武器共用同一张 `gun_pistol.png`**
> （见各 `.tres` 的 `icon` 字段）。换成真素材后它们会长得一模一样，
> 只能靠 `bullet_tint` 的弹道颜色区分。要区分就得给每把单独配图——
> 那只需改各自 `.tres` 里的一行 `icon`。

### 2.4 特效（弹道 / 爆炸 / 命中）

| 资源 | 链接 | 许可 |
|---|---|---|
| Kenney `Particle Pack` | <https://kenney.nl/assets/particle-pack> | **CC0** |
| itch.io 俯视射击向素材（逐个看许可） | <https://itch.io/game-assets/tag-top-down-shooter> | 逐个看 |
| OpenGameArt（高级搜索可勾 CC0） | <https://opengameart.org/> | 逐个看 |

> 命中闪光、屏震、受击闪白在项目里已由 [scripts/core/juice.gd](../scripts/core/juice.gd) 实现，
> **不需要素材**，别去外面找。

### 2.5 字体

| 资源 | 链接 | 许可 | 备注 |
|---|---|---|---|
| **霞鹜文楷 LXGW WenKai** | <https://github.com/lxgw/LxgwWenKai> | **OFL 1.1** | **中文首选**，可免费商用 |
| 思源黑体 / Source Han Sans | <https://github.com/adobe-fonts/source-han-sans> | OFL | 中文正文与 UI |
| Silkscreen / Press Start 2P | Google Fonts | OFL | 英文像素字体 |

> **坑**：像素英文字体几乎都没有中文字形。
>
> **本项目现状**：UI 文案**目前全是英文**，用的是 Godot 默认字体，**现在没问题**。
> 但一旦开始写中文 UI，默认字体不含汉字字形，会直接显示方块——
> 那时候把霞鹜文楷塞进 `project.godot` 的 `gui/theme/custom_font` 即可。
> **别等写完了才发现全是方块。**

---

## 3. 音频

### 3.1 音效

| 资源 | 链接 | 许可 |
|---|---|---|
| Kenney `Impact Sounds`（打击） | <https://kenney.nl/assets/impact-sounds> | **CC0** |
| Kenney `Interface Sounds`（UI） | <https://kenney.nl/assets/interface-sounds> | **CC0** |
| Kenney `UI Audio` | <https://kenney.nl/assets/ui-audio> | **CC0** |
| Kenney `RPG Audio` | <https://kenney.nl/assets/rpg-audio> | **CC0** |
| freesound.org（**筛 CC0**） | <https://freesound.org/> | 混合，务必筛 |
| BFXR（网页版生成 8-bit 音效） | <https://www.bfxr.net/> | 生成器 |
| OpenGameArt SFX | <https://opengameart.org/> | 逐个看 |

> 射击类项目最缺的是**开火/命中**音效。Kenney 的 Impact 系列够用，
> 但枪声建议用 BFXR 生成——**同一把枪要有微随机变体**，否则连射很快就听腻。

### 3.2 音乐

| 资源 | 链接 | 许可 | 备注 |
|---|---|---|---|
| Free Music Archive（**按 CC0 筛**） | <https://freemusicarchive.org/> | CC0 / CC-BY 混合 | 曲库大，有 CC0 的 chiptune 专辑 |
| OpenGameArt Music | <https://opengameart.org/> | 逐个看 | 勾 CC0 复选框 |
| incompetech（Kevin MacLeod） | <https://incompetech.com/> | **CC-BY** | 曲库大，**必须署名** |
| LMMS / Bosca Ceoil | <https://lmms.io/> | GPL / MIT | 自己写 BGM |

> ⚠️ **SoundImage.org 不是 CC0**，它要求署名。想零署名就别用。

---

## 4. 工具

| 类别 | 推荐 | 链接 | 许可 |
|---|---|---|---|
| 像素画 | **Pixelorama**（Godot 写的，同生态） | <https://github.com/Orama-Interactive/Pixelorama> | MIT |
| 像素画 | Aseprite（业界标准） | <https://www.aseprite.org/> | 商业（源码开放，可自编译） |
| 音效生成 | BFXR | <https://www.bfxr.net/> | 生成器 |
| 音频编辑 | Audacity | <https://www.audacityteam.org/> | GPL |
| 音乐制作 | LMMS | <https://lmms.io/> | GPL |

---

## 5. Godot 插件（均 MIT）

| 插件 | 用途 | 链接 | 什么时候引入 |
|---|---|---|---|
| **Phantom Camera** | 2D 相机：房间切换、死区、跟随组、震屏 | <https://github.com/ramokz/phantom-camera> | 相机需求变复杂时替换自写 `CameraRig` |
| **Beehave** | 行为树 | <https://github.com/bitbrain/beehave> | 敌人 AI 超过 3 个状态时 |
| **LimboAI** | 行为树 + 状态机（带可视化调试） | <https://github.com/limbonaut/limboai> | 做 BOSS 战更推荐 |
| **Dialogue Manager** | 对话系统，支持分支/条件 | <https://github.com/nathanhoad/godot_dialogue_manager> | 需要 NPC 时 |

> **现在都不需要装。** 项目当前零第三方插件，这是优点不是缺点——
> 引入插件会让导出和版本升级变复杂。按上表的"什么时候引入"触发，别提前。

---

## 6. 两个性价比远超换素材的观感提升

1. **2D 灯光**（`CanvasModulate` 压暗 + `PointLight2D` 自发光 +
   `LightOccluder2D` 墙体投影）。俯视角地牢的"高级感"主要来自灯光比对，
   **用现在的占位图也能出效果**。见 `docs/roadmap.md §10`，建议**在换素材之前做**。
2. **打击反馈**（命中停顿 + 屏震 + 受击闪白 + 击退）。同类游戏的"爽"有
   一大半来自这里，与素材精度无关。项目里 [scripts/core/juice.gd](../scripts/core/juice.gd) 已备好。

> **顺序建议**：先做灯光和打击反馈 → 再换素材。否则你会把"不够爽"误判成"素材不行"，
> 然后不停换图，问题却一直在别处。

---

## 7. 关于署名

- **CC0**：不用署名，商用也没问题。**本清单里 Kenney 与 0x72 的全部资源都是 CC0。**
- **CC-BY**：必须在游戏里（通常 Credits 页）注明作者与出处。
  **项目一开始就建 `scenes/ui/credits.tscn` 随手记录**，别等发布前翻仓库。
- **CC-BY-SA**：有传染性，衍生作品也要以 SA 发布 —— **商业项目避开**。
- **GPL**：不能静态链接进闭源商业游戏（作为独立工具使用没问题）。
- **OFL（字体）**：可自由使用与嵌入，但**不能单独售卖字体文件本身**。

**拿不准就换 CC0 的**，省掉一切后顾之忧。

> **一个可执行的建议**：现在就建 `CREDITS.md`，每引入一个非 CC0 资源就记一行
> （资源名 / 作者 / 许可 / 链接 / 用在哪）。等到发布前才回溯，一定会漏。

---

## 附：许可证速查

| 许可 | 可商用 | 需署名 | 有传染性 | 本项目态度 |
|---|---|---|---|---|
| **CC0** | ✅ | ❌ | ❌ | **首选** |
| **OFL** | ✅ | ❌（字体本身不可单独售卖） | ❌ | 字体用它 |
| **MIT** | ✅ | ✅ | ❌ | 插件用它 |
| **CC-BY** | ✅ | ✅ | ❌ | 可用，必须记 Credits |
| **CC-BY-SA** | ✅ | ✅ | ✅ | **避开** |
| **GPL** | ⚠️ 视链接方式 | ✅ | ✅ | 仅作独立工具 |
| **CC-BY-NC** | ❌ | ✅ | ❌ | **不能用** |
