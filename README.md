# 《构造一个我》 — 生物机械构装解谜

使用 Godot 4 和 GDScript 开发的网格构装解谜游戏。玩家是从一群细胞中觉醒的意识，通过控制不同功能的细胞，在培养皿中连接身体、清除污染、回收目标，并搭建能够自主运行的结构。

游戏现名《构造一个我》。发布文件使用 `ConstructAMe` 作为 ASCII 文件名标识。为兼容已有进度、蓝图和设置，内部存档目录仍保留旧名称；Windows 下为 `%APPDATA%/Godot/app_userdata/格式塔 (Gestalt)/`，无需移动旧存档。

界面统一使用主菜单的实验室蓝色与细胞绿色：共享配色和按钮样式位于 `scripts/ui/UIStyle.gd`，选关与工坊复用主菜单的像素边框。博士对话采用浅蓝正文面板、深色文字和独立深蓝名牌。

研究员塔洛斯负责早期引导。随着玩家学会更多机制，她逐渐从教导转向观察和好奇，玩家也开始独立探索。

## 本地运行

1. 用 Godot 项目管理器导入仓库根目录的 `project.godot`。
2. 等待资源导入完成，按 **F5（运行项目）**进入主菜单。
3. 选择「开始游玩」，在章节地图点击关卡查看详情，再点击「进入关卡」。

当前 `project.godot` 声明 Godot **4.7**，近期本地验证使用 **4.7.2**。导出游戏还需要安装与引擎匹配的导出模板。

也可以从命令行运行（`godot` 替换为本机可执行文件路径）：

```bash
godot --path . --editor
godot --path .
```

## 教学与章节地图

目前有 **7 个教程、12 幕**。教程按顺序解锁，未解锁的教程不显示；已解锁关卡可重复体验。多幕教程会在完成第一幕后播放完成对白和幕间通讯，再通过运镜进入下一幕。

| 顺序 | 关卡名 | 学习内容 | 配置文件 |
| --- | --- | --- | --- |
| 01 | 初识 | 普通细胞连接；剪切移动、复制粘贴；镜头操作与手册入口 | `tutorial_00.json` |
| 02 | 清理 | 摧毁细胞的相邻攻击与朝向，单幕 | `tutorial_01.json` |
| 03 | 复制 | 复制器读取后方样本，串联生成新细胞 | `tutorial_03.json` |
| 04 | 转向 | 顺逆时针旋转；依次清理不同方向的污染 | `tutorial_04.json` |
| 05 | 推动 | 推进细胞推动自身与前方细胞 | `tutorial_02.json` |
| 06 | 编组 | 将相连细胞编为整体后协同移动，单幕 | `tutorial_06.json` |
| 07 | 沉默 | 解除障碍免疫；让失控细胞本回合行动等效于普通方块 | `tutorial_05.json` |

第一关第二幕禁用直接生成普通细胞：先将散落细胞移动到 `(0,1)`，再复制粘贴以连通晶胚。其他教程按各幕开放的器材练习，具体要求和提示显示在右侧。

正式关卡分为 **枪、获取、车、计数器**四章，共 **14 关**。章节路由和教程解锁逻辑位于 `scripts/core/Campaign.gd`；未编入章节的关卡显示在自由工坊。

选关节点采用文件夹图标：默认关闭，鼠标悬停时打开，移开后恢复。图标下保留关卡名和通关标记；点击节点显示目标、核心机制等详情。

## 操作速查

下表为默认操作。可配置快捷键以「系统设置」和游戏内 **F1 操作手册**显示为准；打开手册会暂停场景，关闭后恢复此前状态。

| 操作 | 默认输入 |
| --- | --- |
| 平移镜头 | W / A / S / D；中键拖动；选择模式下也可右键拖动 |
| 缩放 / 查看全景 | 鼠标滚轮 / Home |
| 选择方块工具 | 数字 1—6；Ctrl + 滚轮 |
| 放置 / 擦除 | 放置模式下左键 / 右键，支持按住拖动 |
| 退出放置工具 | Esc |
| 单选 / 多选 | 左键选中；空白处拖框；Shift 追加选择 |
| 复制 / 粘贴 | Ctrl+C / Ctrl+V，粘贴预览后左键确认；每次粘贴后再次按 Ctrl+V |
| 移动单块或多块 | 选中后 Ctrl+X，移动预览，再左键放下 |
| 旋转 | Q / E：逆时针 / 顺时针，适用于选区、预览或待放置方块 |
| 水平镜像 / 转向器模式 | F；放置转向器时切换顺逆时针模式 |
| 编组 / 解组 | G；多选不等于编组，相连细胞编组后才能作为整体运动 |
| 删除选中方块 | X；默认设置下也支持 Delete / Backspace |
| 撤销 / 重做 | Ctrl+Z / Ctrl+R |
| 开始或暂停 / 重置 | Space / R；单步使用界面按钮 |
| 对话展开与继续 | 点击文字、Enter 或 Space；Esc 结束通讯 |
| 操作手册 | F1 或界面中的手册按钮 |

剪切会立刻移除原件并进入移动预览，无需再按粘贴。取消预览不会自动恢复原件，需要撤销。复制、剪切和粘贴均支持框选后的批量操作。右键拖动镜头不是移动选中的细胞。

模拟暂停时只能观察，需要重置后再编辑；重置保留运行前的构装。「清空构装」删除自建细胞，「重来当前幕」恢复该幕初始状态。预设世界方块在游玩模式下不可直接编辑。触屏支持双指平移与缩放。

## 细胞与模拟规则

| 快捷键 | 类型 | 功能 |
| --- | --- | --- |
| 1 | 普通方块 / 普通细胞 | 连接身体与结构的基础单元 |
| 2 | 沉默器 / 沉默细胞 | 前方紧邻格有方块时，后方紧邻方块在本回合内行动等效于普通方块 |
| 3 | 推动器 / 推进细胞 | 推动自身及前方可移动实体；编组后可驱动整个相连结构 |
| 4 | 复制器 | 读取后方样本，在前方空格生成副本并保留朝向；副本不继承编组 |
| 5 | 摧毁器 / 摧毁细胞 | 攻击前方紧邻方块，受目标免疫性影响 |
| 6 | 转向器 / 转向细胞 | 将前方目标原地旋转 90°，支持顺时针和逆时针 |

编辑器还可放置坚硬方块、游荡怪物、宝藏、污染源与保护方块。坚硬方块被沉默后失去免疫；宝藏需要回收至建造区；保护方块不能损失。具体通关条件取决于关卡目标，第一关的晶胚连接使用专门的教学判定。

### 同时性与方向

模拟采用每步开始时的快照处理感知。理解这一点有助于判断结构为什么成功或失效：

- 摧毁器按**本步开始时的位置和朝向**确定相邻攻击目标，不能把本步刚转出的朝向当作本步的普通攻击方向。
- 复制器读取本步开始时后方样本及前方空位；新生成细胞从后续步开始参与作用。
- 推进是方向规则的例外：本步旋转后的朝向会立即用于推进；被推进的摧毁器可沿移动方向吞噬可摧毁障碍。
- 正交推进发生竞争时选择一个有效轴向，不会合成斜向位移。目标格竞争由伪随机仲裁处理。

例如，旋转教程第一幕需要先转向，再在下一步清除污染。第二幕参考解法为摧毁细胞初始朝上、左侧转向器朝右且设为顺时针，三步依次清除上、右、下方污染，避免开局误删转向器。

## 修改剧情、教程和图标

教学配置位于 `assets/levels/tutorial_*.json`。文件编号与教学顺序并非一一对应，请按上面的表定位。

| 字段 | 用途 |
| --- | --- |
| `level_name` / `description` | 关卡名 / 关卡目标描述 |
| `tutorial.act_title` / `title` | 幕名 / 引导面板标题 |
| `tutorial.speaker` / `dialogues` | 说话人 / 开场对白分页 |
| `dialogue_portraits` | 与开场对白逐页对应的立绘资源路径 |
| `success_dialogues` / `success_portraits` | 完成对白及逐页立绘 |
| `transition_dialogues` / `transition_portraits` | 幕间通讯及立绘；当前数据包含第一幕完成对白作为开头 |
| `intro` / `run_text` / `hints` | 侧栏介绍、当前目标与提示 |
| `followup` / `followup_offset_x` | 下一幕关卡数据 / 下一幕横向坐标偏移 |
| `equipment` / `reference` / `group_reference` | 器材配额 / 参考摆法 / 参考摆法是否编组 |
| `revision` | 教程版本；更新内容时递增，下一幕也有独立版本字段 |

上述未带前缀的教学字段均位于对应幕的 `tutorial` 对象中。单幕教程没有 `followup`。修改第一幕完成对白时，也应同步幕间通讯开头，避免两处文案不一致。较长台词拆成多页时，需同时补齐对应立绘条目。

立绘资源位于 `assets/portraits/`，当前包含 `normal`、`thinking`、`teaching`、`surprised`、`smile`、`shy` 六种表情。例如 `smile` 对应 `res://assets/portraits/doctor_smile.png`。JSON 保存的是完整资源路径，不是方括号标签。对白播放与表情切换由 `scripts/ui/TutorialDialogue.gd` 处理。

文件夹图标位于 `assets/textures/ui/level_folder_default.png` 和 `level_folder_open.png`，由 `scripts/ui/LevelSelect.gd` 切换。显示使用同一裁切区域；替换图片时应保持两张素材的画布和对齐一致，或同步调整脚本中的区域。

教程读取会比较资源与用户存档副本的 `revision`：同版本优先采用项目资源，更高版本的用户教程仍会保留。普通自制关卡保持用户副本优先。

## 验证

先在编辑器中完成资源导入。测试使用独立的用户数据目录，避免改变正常游玩的通关记录或关卡存档。

```bash
godot --headless --path . --script res://scripts/core/test_tutorials.gd
godot --headless --path . --script res://scripts/core/test_campaign.gd
godot --headless --path . --script res://scripts/core/test_simultaneity_t0.gd
```

图形交互回归不加 `--headless`，设置 `BLOCKBOUND_TEST_OUTPUT` 为截图目录：

```bash
BLOCKBOUND_TEST_OUTPUT=build/tutorial-tests godot --path . --script res://scripts/core/test_tutorial_ui.gd
```

教程测试覆盖单幕与双幕流程、对白立绘、运镜、操作练习和通关。截图仅在图形模式且指定输出目录时保存。

## Web 开发预览

以下脚本需要 Bash 环境、Godot 及对应导出模板；在 Windows 上请使用可用的 Bash 环境运行，或直接用 Godot 编辑器导出。

```bash
./start.sh                # 导出调试 Web 构建并启动 http://localhost:8060
./start.sh --release      # 使用发布模板导出后预览
./start.sh --no-export    # 跳过导出，仅启动服务器
```

调试流程支持将关卡编辑回写 `assets/levels/`；正式发布构建的编辑仅保存在用户目录。

## 正式版打包与发布

正式版统一使用发布模板（`--export-release`）构建，产物位于 `build/release/`。**正式版中玩家的关卡编辑只写入本机用户目录（`user://levels`），不会回写作者的 `assets/levels/`，也不会同步到调试服务器。**

### 桌面端 (Windows / Linux)

```bash
./build_release.sh                    # 同时构建 Windows 与 Linux 并打包
./build_release.sh linux              # 只构建 Linux
./build_release.sh windows            # 只构建 Windows
./build_release.sh all --no-package   # 只导出二进制，不打压缩包
GODOT_BIN=/path/to/godot ./build_release.sh
```

产物：

- `build/release/windows/ConstructAMe.exe` 与 `build/release/ConstructAMe-<版本>-windows-x86_64.zip`
- `build/release/linux/ConstructAMe.x86_64` 与 `build/release/ConstructAMe-<版本>-linux-x86_64.tar.gz`

### 网页端

```bash
./publish_web.sh              # 构建正式 Web 包并生成 zip
./publish_web.sh --serve      # 构建后启动本地预览 (http://localhost:8061)
./publish_web.sh --zip-only   # 仅用现有产物打包
```

产物：`build/web-release/` 与 `build/release/ConstructAMe-<版本>-web.zip`。上传到静态托管时需保留 COOP/COEP 隔离标头（`Cross-Origin-Opener-Policy: same-origin` 与 `Cross-Origin-Embedder-Policy: require-corp`）。

### 关卡导入 / 导出

在「创作工坊 / 关卡管理」左侧可「导出关卡 / 导入关卡」JSON 文件：桌面端使用系统文件对话框，网页端在浏览器中直接下载 / 选择文件。导入时若关卡标识与现有库冲突，会自动分配新的唯一标识，避免覆盖已有内容。

---

## 主要目录

```text
assets/levels/             内置关卡及教学 JSON
assets/portraits/          塔洛斯立绘差分
assets/textures/ui/        界面素材与选关文件夹图标
scenes/ui/                 主菜单、选关、游玩与编辑器场景
scripts/core/Campaign.gd   章节路由、教程顺序与通关记录
scripts/core/TutorialActs.gd   幕间关卡构建与坐标偏移
scripts/core/TutorialRules.gd  教学建造规则
scripts/core/SimulationEngine.gd  模拟规则
scripts/core/SaveManager.gd      关卡、图纸存储及导入导出
scripts/ui/LevelSelect.gd       章节地图与详情
scripts/ui/LevelPlayer.gd       游戏主流程与幕间切换
scripts/ui/TutorialDialogue.gd 博士对白与逐页立绘
scripts/ui/TutorialGuide.gd    侧栏引导与操作练习
scripts/ui/OperationManual.gd  F1 操作手册
```
