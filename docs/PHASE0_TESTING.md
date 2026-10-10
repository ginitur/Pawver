# FloatShelf Phase 0：验证说明、自动验证结果与手工验收步骤

> 原则：**编译通过或应用能启动，不能证明跨应用拖拽可用。** 本文把"已自动验证"和"需要 Gerry 亲手做的 GUI 验收"严格分开。所有 GUI 项在用户实测之前都标为 **待用户验证**。
> 所有拖拽测试只使用 `scripts/make-test-files.sh` 生成的专用测试文件（`TestFixtures/`，已被 git 忽略），不要用真实文件。

---

## 1. Phase 0 交付物

| 交付物 | 路径 |
|---|---|
| 可双击运行的应用（ad-hoc 签名，LSUIElement，无 Dock 图标） | `dist/FloatShelf.app` |
| 构建 / 启动 / 测试脚本 | `scripts/build.sh`、`scripts/run.sh`、`scripts/test.sh` |
| 测试文件生成与校验 | `scripts/make-test-files.sh`、`scripts/verify-test-files.sh` |
| 规划（已按官方文档修订 §2.1、§2.3） | `docs/PLAN.md` |
| 本文件 | `docs/PHASE0_TESTING.md` |

Phase 0 功能范围：
- 菜单栏图标，菜单项依次为：新建 Shelf、拖拽检测引擎（全局监听 / 轮询）、摇晃灵敏度、仅在 changeCount 变化时触发、拖出时允许移动（实验，默认关）、详细诊断日志、记录屏幕信息、权限状态、**退出 FloatShelf**。
- 摇晃检测：在确认为文件拖拽时打开 Shelf。
- 非激活浮动 Shelf：接收文件拖入，只保存引用。
- 拖出：单项或"拖动全部"，默认**只提供复制**。
- 快捷键 ⌃⌥S（Carbon）。
- 诊断日志。

---

## 2. 自动验证结果（2026-10-08，在本机实际执行）

| 检查 | 命令 | 结果 |
|---|---|---|
| Debug 全量构建 | `swift build`（清空 `.build` 后） | ✅ `Build complete!`，**0 个编译 warning**（只有工具链自带的 2 条无害链接器 "search path not found"） |
| 单元测试 | `scripts/test.sh` | ✅ `Test run with 46 tests in 4 suites passed` |
| Release 构建并组装 .app | `scripts/build.sh` | ✅ `Build complete!` |
| Info.plist 校验 | `plutil -lint`（build.sh 内） | ✅ `OK`；`LSUIElement => true`，`CFBundleIdentifier => com.weijiaren.FloatShelf` |
| 签名校验 | `codesign --verify --strict --verbose=2` | ✅ `valid on disk` / `satisfies its Designated Requirement`；`Signature=adhoc`，arm64 |
| 启动冒烟测试 | `scripts/run.sh`（经 `open` 启动），约 10 秒后 `kill -TERM` 结束 | ✅ 进程存活（`pgrep` 找到 FloatShelf，RSS 约 64 MB），统一日志和 `logs/*.log` 中都有启动日志，见下 |
| 测试文件脚本 | `make-test-files.sh` → `verify-test-files.sh` | ✅ 9 个文件、14 个条目、`RESULT: PASS`；重复运行未带 `--force` 会拒绝覆盖（exit 1） |
| 校验脚本负向测试 | 故意改动一个文件、改名一个文件、往目的地复制文件 | ✅ 检出 `notes.md: FAILED`、缺失 `pixel.png`、目录树差异，并报 `RESULT: FAIL`；目的地中的文件正确识别为 "== copy of source/…"。之后已用 `--force` 重建为干净状态 |

单元测试覆盖范围：
- `ShakeDetector`（17 项）：快速摇晃触发且只触发一次；慢速来回、单次摆动、直线、小幅抖动不触发；斜向来回和快速画圈被拒绝；轻微竖直晃动仍触发；冷却期；停顿后重新计数；requiredReversals、minSwingDistance、timeWindow 三个参数；预设灵敏度的顺序；reset。
- `ShelfPositioning`（13 项）：居中；菜单栏、右边缘、左下角夹紧；负坐标屏（左侧）、上方屏、下方屏（含 Dock）；**本机实际布局**（外接屏在右侧且 y 偏移 −98）；屏幕交界与顶边归属；屏间空隙取最近屏；2x/1x 像素对齐；窗口超出可见区时缩小；无屏幕。
- `ShelfStore`（8 项）：标准化路径去重（含 `.`、`..`、目录末尾斜杠）；不同目录的同名文件保持独立且显示名可区分；父目录名也相同时显示完整路径；拒绝非文件 URL；保持顺序与删除；拖出后移除规则的真值表。
- `DragSessionTracker`（8 项）：changeCount 变化且有 fileURL 时判为确认；残留 fileURL 判为 stale；只有文本时判为 nonFile；基线前移；mouseDown 前已变化的情况；漏掉 mouseDown 的隐式按下；自身拖出后重置基线；只在需要时读取 types。

启动日志（冒烟测试实际输出，节选）：
```
NOTE  [app] FloatShelf starting: version=0.1.0 build=1 pid=56872 bundle=/Users/weijiaren/Projects/FloatShelf/dist/FloatShelf.app bundleID=com.weijiaren.FloatShelf ...
INFO  [permissions] startup permission snapshot (read-only, nothing requested): Accessibility(AXIsProcessTrusted)=false InputMonitoring(CGPreflightListenEventAccess)=false
INFO  [drag] global monitor installed (leftMouseDown/Dragged/Up)
INFO  [hotkey] registered global hot key ⌃⌥S (Carbon RegisterEventHotKey, status=noErr)
INFO  [app] screen#0 (primary) '内建视网膜显示器' frame=(0.0, 0.0, 1512.0×982.0) visibleFrame=(0.0, 0.0, 1512.0×949.0) scale=2.0
INFO  [app] screen#1 'MT524 G1e' frame=(1512.0, -98.0, 1920.0×1080.0) visibleFrame=(1512.0, -98.0, 1920.0×1050.0) scale=1.0
NOTE  [app] startup complete: engine=globalMonitor sensitivity=medium requireChange=true allowMoveOnDragOut=false verbose=false
```

观察到的权限状态：辅助功能和输入监控**都未授权**。安装全局鼠标监听返回了非 nil，Carbon 热键注册也成功，整个过程没有出现系统授权弹窗。但"未授权时拖拽中能否收到鼠标事件、热键能否真正触发"属于 GUI 行为，**待用户验证**。

冒烟测试的副作用：没有生成 `~/Library/Preferences/com.weijiaren.FloatShelf.plist`（启动前后都检查过；只有在菜单里改设置时才会写入）。`open` 启动会让 LaunchServices 登记这个 .app，这是任何可双击应用都会有的行为。统一日志写入系统日志。冒烟测试结束后 FloatShelf **没有在运行**。

**以上任何一项都不能证明 Finder 跨应用拖拽可用。**

---

## 3. 手工验收准备

```bash
cd /Users/weijiaren/Projects/FloatShelf
scripts/build.sh                 # 生成 dist/FloatShelf.app
scripts/make-test-files.sh       # 若已存在：scripts/make-test-files.sh --force
scripts/run.sh                   # 启动，并把日志另写一份到 logs/floatshelf-<时间>.log
```

也可以直接在 Finder 里双击 `dist/FloatShelf.app`，但这样只有系统日志，没有 `logs/` 文件。

**实时查看日志**（另开一个终端窗口）。注意 zsh 里 `log` 是内建命令，必须写 `/usr/bin/log`：
```bash
/usr/bin/log stream --level debug --style compact --predicate 'subsystem == "com.weijiaren.FloatShelf"'
```
事后导出：
```bash
/usr/bin/log show --last 30m --info --debug --style compact --predicate 'subsystem == "com.weijiaren.FloatShelf"' > logs/phase0-unified.log
```
建议在菜单栏图标菜单里勾选 **"详细诊断日志"**，这样会额外记录每次按下的细节和原始 URL。

测试文件结构（`TestFixtures/`）：
```
source/A/report.txt              ← 与 B/report.txt 同名不同内容
source/A/notes.md
source/A/中文 文件.txt
source/A/random-256k.bin
source/A/Folder With Spaces/      ← 文件夹（含 inner-1.txt、inner-2.txt、nested/deep.txt）
source/B/report.txt
source/B/pixel.png
destination/                      ← 空目的地 1
destination-2/                    ← 空目的地 2
```
每做完一组测试，运行一次 `scripts/verify-test-files.sh`。它会确认 source 下的所有文件和目录结构未变，并列出两个目的地里的文件是否与某个源文件逐字节相同。

---

## 4. 手工 GUI 验收步骤（全部 **待用户验证**）

在每一项后记录：通过 / 失败、现象，以及对应的日志行（在 `logs/` 中搜索关键字即可）。

### T0 启动与菜单栏
1. `scripts/run.sh` 启动。
2. 预期：菜单栏出现托盘图标（`tray.full`），Dock 中**没有**图标。点开菜单，能看到上面列出的各项，最后一项是 **"退出 FloatShelf"**。
3. 如果菜单栏图标被刘海或拥挤的菜单栏挡住：按 ⌃⌥S 仍可打开 Shelf；用 `pgrep -lx FloatShelf` 确认进程在运行。

### T1 热键打开，不抢焦点
1. 在 Finder 中点一下某个窗口，让 Finder 处于前台；也可以在 Finder 窗口的搜索框里输入几个字符。
2. 按 **⌃⌥S**。
3. 预期：Shelf 出现在光标附近，显示"空 Shelf"和"把文件拖到这里"。Finder 仍是前台应用，继续输入的字符还进入 Finder 搜索框。
4. 日志关键字：`hot key ⌃⌥S fired`、`shelf shown (reason=hot key`，同一行里应有 `appActive=false panelIsKey=false frontmostApp=com.apple.finder`。

### T2 拖入（不摇晃）：Finder → 已打开的 Shelf
1. 用 ⌃⌥S 打开 Shelf。
2. 在 Finder 中同时选中 `source/A/report.txt`、`source/B/report.txt`、`source/A/Folder With Spaces`，拖进 Shelf 后松开。
3. 预期：拖入过程中 Shelf 边框高亮。松开后出现 3 行，两个 report.txt 分别显示为 "report.txt — A" 和 "report.txt — B"，文件夹显示文件夹图标，计数为"3 个项目"。Finder 中原文件**原地不动**。
4. 再拖一次同样的文件：计数不变，日志显示 duplicate。
5. 日志：`draggingEntered seq=… sourceMask=…`（**请记录 Finder 作为拖拽源提供的掩码**）、`performDragOperation … stored 3 reference(s) … Files were NOT copied or moved`。
6. 运行 `scripts/verify-test-files.sh`，应为 `PASS`，两个目的地为空。

### T3 核心验收 A：拖拽中摇晃唤出 Shelf，并直接放入
1. 先关闭 Shelf（点左上角 ⊗）。
2. 在 Finder 中选中 `source/A` 里的 2–3 个文件，**按住鼠标开始拖动，不要松开**。
3. 按住状态下快速左右晃动鼠标 3–4 次，每次幅度约 3–5 cm。
4. 预期：
   - a. Shelf 立即出现在光标附近；
   - b. Finder 的拖拽**没有中断**：拖拽图像仍然跟着光标；
   - c. 继续把文件移到 Shelf 上，边框高亮后松开，文件出现在 Shelf 中；
   - d. Finder 中原文件**原地不动**。
5. 日志中应依次出现：
   - `global monitor received its first leftMouseDragged`（只在本次运行第一次拖动时出现）
   - `classification → confirmedFileDrag | changeCount=… change seen at drag event #N (… after press) | types=[…public.file-url…]`
   - `SHAKE → open shelf at …`
   - `shelf shown (reason=shake …) … cursorInsidePanel=true appActive=false panelIsKey=false`
   - `draggingEntered seq=… NNNms after shelf shown`
   - `performDragOperation … stored …`
   - 松开后：`SUMMARY classification=confirmedFileDrag … shakeTriggered=true`
6. 如果 Shelf **没有出现**，请记录日志里缺了哪一行，然后按顺序排查：
   - **没有任何 `[global]` 日志**：说明全局监听在 Finder 拖拽期间没收到事件。在菜单中切换"拖拽检测引擎 → 轮询"，重做一遍，看日志中是否出现 `[polling]` 的分类和 `SHAKE`。
   - **有 `shake recognised but NOT opening: classification=staleFileURL`**：说明 changeCount 没有按预期变化。记录 SUMMARY 行，可以临时取消勾选"仅在拖拽板 changeCount 变化时触发"后重试，以作对比。
   - **有 SUMMARY 但没有 SHAKE**：可能是摇晃幅度或速度不够。把"摇晃灵敏度"调到"高"再试。
   - **Shelf 出现了，但放不进去**（没有 `draggingEntered`）：这是平台限制方面的关键证据，请记录。
7. 分别在两个引擎下各做一次，并记录结果。

### T4 changeCount 可靠性证据（非文件拖拽不应弹出）
在"全局监听"引擎和"详细诊断日志"打开的状态下，分别执行以下操作，并且每种操作都**按住鼠标摇晃**：
1. 拖动 Finder 窗口的标题栏；
2. 在桌面上拖出框选矩形；
3. 在任意文本中拖选一段文字（例如在 Finder 文件名的重命名状态下）；
4. 作为对照：先做一次 T3 的文件拖拽，再拖窗口。

预期：Shelf **不出现**，日志有 `shake recognised but NOT opening: classification=nonFileDrag 或 staleFileURL`。
请把每次的 `SUMMARY` 行附到结果里（含 changeCount 的 idle/press/end 值、`changeSeenAtEvent`、`fileURL`）。这些就是"窗口拖动和文字选择是否改变 changeCount、改变发生在按下后多久"的实测证据。

### T5 核心验收 B：拖出 = 复制到 Finder 另一目录
1. Shelf 中放入 `source/A/notes.md`（T2 或 T3 的方式均可）。
2. 用鼠标按住 Shelf 中 notes.md 这一行，拖到 Finder 中打开的 `TestFixtures/destination/` 后松开。
3. 预期：`destination/notes.md` 出现；`source/A/notes.md` 仍在；Shelf 中仍保留该项。
4. 日志：`drag-out session #… began … offered outside-app mask=copy`，以及 `ended … operation=copy → destination performed COPY`，后面跟 `sourceExists=true removeFromShelf=false`。
5. `scripts/verify-test-files.sh` 应显示 `destination/notes.md == copy of source/A/notes.md`，并且 `RESULT: PASS`。

### T6 拖动全部（多文件、文件夹、同名文件）
1. Shelf 中放入两个 report.txt、`Folder With Spaces`、`pixel.png`。
2. 按住标题栏右侧的"拖动全部"图标（叠层图标），拖到 `destination-2/`。
3. 预期：两个同名 report.txt 进入同一个目录时，Finder 应弹出同名冲突对话框，这是 Finder 自己的行为（选"保留两者"或"停止"都可以，请记录 Finder 的表现）。文件夹整体被复制。Shelf 内容不变。
4. 验证：`verify-test-files.sh` 应为 `PASS`，并且 `destination-2` 中每个文件都显示为某个源文件的副本。

### T7 修饰键（实测，不预设结果）
Phase 0 默认只提供 copy。分别做以下三次拖出，每次在**松开前**按住对应修饰键：
1. **Option**：预期仍为复制（待验证）；
2. **Command**：只允许复制时可能被拒（显示禁止符号，`operation=none`），也可能仍为复制（待验证）；
3. **Control**：待验证。

每次记录光标形状（是否有 "+"）以及日志 `ended … operation=… modifiers at end=…`。

### T8 取消拖出不丢东西
1. 从 Shelf 拖出一项，途中按 **Esc**。
2. 从 Shelf 拖出一项，放回 Shelf 自身（Phase 0 中自己拖回自己不构成操作），或放到菜单栏空白处等不接受文件的位置。
3. 预期：拖拽图像弹回，`operation=none → cancelled/rejected … shelf unchanged`，Shelf 中该项仍在，源文件仍在。
4. 从 Finder 拖文件进 Shelf 的途中按 Esc：Shelf 不增加条目，Finder 原文件不动。
5. `verify-test-files.sh` 应为 `PASS`。

### T9 跨应用：Shelf → 浏览器上传区域
1. 在浏览器中打开一个你信任、带有拖放上传区域的页面。**只用测试文件，不要点"提交"或"上传"**；也可以把文件拖到浏览器窗口中，确认浏览器能打开或识别该文件。
2. 从 Shelf 把 `pixel.png` 或 `notes.md` 拖到上传区域。
3. 预期：页面识别到文件（显示文件名或预览），日志 `operation=copy`（具体值由浏览器决定，请记录），源文件和 Shelf 都不受影响。

### T10 拖拽中切换应用，以及 Shelf 持续悬浮
1. 从 Finder 拖住文件，不松开，按 ⌘Tab 切换到其他应用，再摇晃。记录 Shelf 是否出现、能否放入。
2. Shelf 打开时切换到其他应用、点击其他窗口：Shelf 应始终浮在普通窗口之上，并且不抢焦点。
3. 如果条件允许，在全屏应用的 Space 中按 ⌃⌥S，Shelf 应能出现（`fullScreenAuxiliary`）。

### T11 多显示器（内建 Retina 2x 主屏 + 右侧 1080p 1x 外接屏）
本机实际布局（来自日志）：外接屏在主屏**右侧**，frame 为 (1512, −98, 1920×1080)。
1. 光标分别放在以下位置，按 ⌃⌥S（或在该处拖文件摇晃）：
   - a. 外接屏右上角（菜单栏下方）；
   - b. 外接屏左下角（靠近两屏交界，y 为负数的区域）；
   - c. 主屏右上角；
   - d. 主屏底部（Dock 附近）。
2. 预期：Shelf 每次都完整显示在**光标所在的屏幕**内，不跨屏、不被菜单栏或 Dock 遮挡。日志中 `screen#` 与实际屏幕一致，并检查 `cursorInsidePanel` 的值。
3. 在 1x 外接屏上，Shelf 中的图标和文字应清晰，不发虚。
4. 在两块屏幕上各做一次 T3（拖拽中摇晃）和 T5（拖出复制）。

### T12 关闭 Shelf 后源文件仍存在
1. Shelf 中放入多个文件和文件夹，点左上角 ⊗ 关闭。
2. 预期：日志 `shelf closed … released N reference(s); no file was touched`；`verify-test-files.sh` 为 `PASS`。

### T13 权限提示
1. 菜单 → "权限状态…"：预期两项都显示"未授权"，同时说明主路径不需要这两项权限。
2. 关键结论要靠 T3 和 T1 判断：在两项都未授权时，如果摇晃唤出和热键都能工作，就说明 Phase 0 主路径确实不需要这些权限。如果全局监听不工作而轮询可以，请记录，后续据此决定是否引入 Input Monitoring 引导。
3. FloatShelf **不会**主动弹出系统授权请求。

### T14（可选，最后做，会改变测试文件）移动语义评估
只有在 T5–T8 的复制测试都通过之后再做。
1. 菜单中勾选"拖出时允许“移动”（实验）"。
2. 从 Shelf 把 `source/B/pixel.png` 拖到 `destination/`。分别试不按修饰键和按住 Command，记录 Finder 选择了复制还是移动。
3. 如果 Finder 执行了移动：`source/B/pixel.png` 消失（这是 Finder 移动的，不是 FloatShelf），日志 `operation=move`，`sourceExists=false removeFromShelf=true`，Shelf 中该项被移除。此时 `verify-test-files.sh` **会报告 FAIL，这是预期的**。
4. 测试完成后取消勾选，并运行 `scripts/make-test-files.sh --force` 重建测试文件。

---

## 5. 结果记录表（待用户填写）

| 项 | 全局监听引擎 | 轮询引擎 | 关键日志 / 备注 |
|---|---|---|---|
| T0 启动 / 菜单 / 退出 | 待用户验证 | — | |
| T1 热键、不抢焦点 | 待用户验证 | — | |
| T2 拖入、去重、同名 | 待用户验证 | — | Finder 提供的 sourceMask： |
| T3 拖拽中摇晃 + 直接放入 | 待用户验证 | 待用户验证 | |
| T4 非文件拖拽不弹出 + changeCount 证据 | 待用户验证 | 待用户验证 | SUMMARY 行： |
| T5 拖出复制到 Finder | 待用户验证 | — | |
| T6 拖动全部 / 文件夹 / 同名 | 待用户验证 | — | |
| T7 修饰键 | 待用户验证 | — | |
| T8 取消不丢失 | 待用户验证 | — | |
| T9 浏览器上传区 | 待用户验证 | — | |
| T10 拖拽中切换应用 / 悬浮 | 待用户验证 | 待用户验证 | |
| T11 多显示器 | 待用户验证 | 待用户验证 | |
| T12 关闭后源文件仍在 | 待用户验证 | — | |
| T13 权限 | 待用户验证 | — | |
| T14 移动（可选） | 待用户验证 | — | |

---

## 6. 已知问题与限制（Phase 0）

1. **核心风险尚未验证**：macOS 27 上，全局鼠标监听在 Finder 拖拽期间是否持续收到事件、拖拽中新出现的面板能否立即成为放置目标，都要靠 T3 证实。
2. 只有一个 Shelf；关闭即清空（只释放引用）。多 Shelf、最近 Shelf 属于 P1。
3. 只接受文件 URL（`public.file-url`）；文本、URL、图片和剪贴板属于 P1。
4. 不能删除单项或重新排序，没有 Quick Look，不能调整尺寸或透明度，没有设置窗口（只有菜单开关）。
5. 拖出默认只提供 copy；move 在实验开关后面，`.generic` 和 `.link` 尚未提供，修饰键的实际效果待 T7 实测。
6. Shelf 拖回自身返回 `[]`（不构成操作）。
7. 没有应用图标（Phase 2 用 `sips` + `iconutil` 制作）。菜单栏使用 SF Symbol。
8. 轮询引擎空闲时 5 Hz，检测到按下最多延迟约 200 ms。它也会把 FloatShelf 自身窗口里的点击算作按下，但会被拖拽板判断过滤。
9. Finder 拖拽板上的 file reference URL（`file:///.file/id=…`）会转换为路径 URL。代码已处理，但真实 Finder 拖拽是否提供这种 URL，需开启详细日志查看 `raw dropped URLs`。
10. ad-hoc 签名每次构建 cdhash 都会变；只有将来启用需要 TCC 权限的引擎时才有影响，Phase 0 主路径不需要权限。
11. zsh 中 `log` 是内建命令，查看日志必须写 `/usr/bin/log`。
12. 冒烟测试用 `kill -TERM` 结束进程，所以那次运行没有记录 `FloatShelf terminating`。用户从菜单退出时会记录。
13. ⌃⌥S 若已被其他应用占用，注册会失败，日志会提示 `eventHotKeyExistsErr`。
14. 测试只能在 Command Line Tools 下用 Swift Testing，并依赖 `scripts/test.sh` 中的 plugin-path 绕过（见 PLAN §1.1）。

---

## 6.1 第一轮用户实测结果（2026-10-08 至 10-10，日志 logs/floatshelf-20261008-160404.log）

- ✅ **拖拽中摇晃唤出**：真实 Finder 拖拽中触发 5 次（`shakeTriggered=true`，全局监听引擎，两项权限均未授权）。Shelf 出现后 27–290 ms 内收到 `draggingEntered`，`performDragOperation` 成功保存引用。
- ✅ **拖出复制**：会话 #352（2026-10-10 10:41:24）记录为 `operation=copy → destination performed COPY`，`sourceExists=true`，Shelf 保留该项。此前 5 次 `operation=none` 是用户有意没有在可接受的位置松开，属于正常的取消。
- ⚠️ **⌃⌥S 热键**：只在 2026-10-08 16:05:24 触发过 1 次，之后用户按下时没有任何反应，日志中也没有再出现 fired。
  - **已确认**：代码中除了退出以外，没有任何地方注销热键或移除 handler；"Shelf 已经打开"也不会导致没有日志（fired 日志写在打开 Shelf 之前）。因此之后的按键事件根本没有送达本进程。
  - **怀疑（未证实）**：根据开发者报告，Carbon 热键只有在前台应用或输入法没有先消费按键时才会派发。可能的情况有：中文输入法对 Option+字母的处理、终端或自绘编辑器吞掉按键、其他应用注册了相同组合。
  - **本次修改**：
    - 记录每一个 Carbon 热键事件（pressed 和 released），附带当时的前台应用；
    - 菜单显示注册状态和触发次数，并新增"重新注册快捷键"；
    - 唤醒、会话重新激活时自动重新注册；
    - 仅当辅助功能**已经**授权时，额外安装 NSEvent keyDown 后备（FloatShelf 不会主动请求该权限）。
  - **复测时请记录**：按键时的前台应用、当前输入法，以及日志中是否出现 `carbon hot-key event`。

## 7. 实际项目结构（Phase 0）

```
Package.swift                         # Swift 6 语言模式，macOS 14+；Core 库 + 可执行 + 测试
Sources/FloatShelfCore/               # 纯逻辑，可单元测试
  ShakeDetector.swift                 # 摇晃识别 + ShakeConfig/预设
  ShelfPositioning.swift              # 多屏定位、夹紧、像素对齐
  ShelfStore.swift                    # ShelfItem（只存引用）、去重、显示名、拖出后移除规则
  DragSessionTracker.swift            # changeCount + fileURL 多信号分类
Sources/FloatShelf/                   # AppKit 应用
  main.swift, AppDelegate.swift, StatusItemController.swift, AppSettings.swift
  DragEngines.swift                   # 全局监听引擎 + 轮询引擎
  DragSignalProcessor.swift           # 信号融合、摇晃触发、证据日志
  ShelfPanel.swift                    # NSPanel(nonactivating) + ShelfDropView(NSDraggingDestination)
  ShelfController.swift               # Shelf 窗口、列表、拖入处理
  ShelfItemViews.swift                # 行视图与"拖动全部"手柄（拖出起点）
  DragOutController.swift             # NSDraggingSource
  HotkeyManager.swift                 # Carbon 热键 ⌃⌥S
  Permissions.swift                   # 只读权限探测
  Diagnostics.swift                   # os.Logger + 可选日志文件
Tests/FloatShelfCoreTests/            # Swift Testing，46 项
Resources/Info.plist
scripts/                              # build / run / test / make-test-files / verify-test-files
```
