# FloatShelf — 环境检测、技术调研与架构规划

> 状态：规划稿，等待批准后实施。本文所有"已验证"均指在本机（WeijiadeMacBook-Pro）实际执行过的命令结果；"未验证"项须在 Phase 0 用真实 GUI 操作确认。

---

## 1. 环境检测结果（2026-10-08，本机实测）

| 项目 | 结果 | 结论 |
|---|---|---|
| 硬件 | Apple M5 Pro，arm64 | — |
| macOS | 27.0（26A428） | — |
| Swift | Apple Swift 6.4（swiftlang-6.4.0.27.1），target arm64-apple-macosx27.0 | 支持 Swift 6 语言模式 |
| 开发者目录 | `/Library/Developer/CommandLineTools`（仅 CLT） | **无 Xcode**，`xcodebuild` 不可用 |
| SDK | `xcrun --show-sdk-path` → `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`，版本 27.0（同时存在 26.5 SDK） | — |
| SwiftPM 构建 AppKit + SwiftUI + Carbon + QuickLookThumbnailing | 临时包（tools-version 6.0，Swift 6 语言模式，含 NSPanel/NSStatusItem/NSHostingView/NSDraggingSource/CGEvent.tapCreate/os.Logger 代码）`swift build -c release` **编译、链接成功**，可执行文件能正常启动/退出 | ✅ 可只依赖 CLT 构建 |
| 默认构建系统 | SwiftPM 默认 `swiftbuild`（`--show-bin-path` → `.build/out/Products/Release`，`.build/release` 仍可访问）；链接时有 2 条无害 warning（`.../CommandLineTools/Developer/...` 搜索路径不存在） | 构建脚本用 `swift build --show-bin-path` 取路径 |
| Carbon `RegisterEventHotKey` | 编译通过；运行时注册 ⌃⌥S 返回 `noErr (0)`，**无需任何隐私权限** | ✅ 全局快捷键方案可行（实际触发需 GUI 验证） |
| `CGPreflightListenEventAccess()` / `AXIsProcessTrusted()` | 均可编译调用；从终端运行返回 `false/false`（未授权，符合预期） | 权限检测 API 可用 |
| `CGEvent.tapCreate` | 可编译（为避免弹出 TCC 提示，未实际创建） | 备选方案可用 |
| XCTest | **CLT 中不存在 XCTest.framework** | ❌ 不能用 XCTest |
| swift-testing | `Testing.framework` 位于 `/Library/Developer/CommandLineTools/Library/Developer/Frameworks` | ✅ 加 rpath + plugin-path 后稳定通过（见 §1.1） |
| codesign | ad-hoc 签名 `.app` 实测通过校验（见 §1.2） | ✅ |
| actool / ibtool | `/usr/bin` 下只是 shim，执行报 "requires Xcode" | ❌ 不使用 Asset Catalog / xib / storyboard |
| iconutil / plutil / sips | 均存在 | 图标用 `sips` + `iconutil` 生成 `.icns`；Info.plist 用 `plutil -lint` 校验 |
| git | 2.54.0；仓库 `main` 分支尚无提交；user.name=`Weijia Ren`、user.email=`gerryphedra@gmail.com`（来自全局 `~/.gitconfig`，仓库无本地覆盖） | 可直接提交 |
| 显示器 | 2 台：内建 Liquid Retina XDR 3024×1964 Retina（主屏）+ 外接 MT524 G1e 1920×1080 @75Hz（1x），非镜像 | 可实测多屏 + 混合缩放（2x/1x） |

### 1.1 swift-testing 在纯 CLT 下的已知问题与已验证的解决方式

1. 直接 `swift test`：测试 bundle 运行时 `dlopen` 失败，找不到 `@rpath/Testing.framework` 和 `@rpath/lib_TestingInterop.dylib`（CLT 没把它们放进默认 rpath）。
   - 解决：在测试 target 的 `linkerSettings` 里加两个 rpath：`/Library/Developer/CommandLineTools/Library/Developer/Frameworks` 和 `/Library/Developer/CommandLineTools/Library/Developer/usr/lib`（用 `unsafeFlags`，根包可以用）。
2. 默认的 `swiftbuild` 构建系统下，`@Test` 宏插件 `TestingMacros` **时有时无地找不到**（同一条命令连续跑，成功和失败交替出现）。
3. 已验证稳定的两种方式（都配合第 1 条的 rpath）：
   - **首选**：`swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`。清空 `.build` 后连续 4 次全部通过。
   - 备选：`swift test --build-system native -Xswiftc -F<Frameworks> -Xlinker -F<Frameworks>`。2 次全部通过，但 native 已标记 deprecated。
4. `scripts/test.sh` 封装首选命令。如果以后工具链变化导致失效，退路是写一个**不依赖宏**、自己做断言的测试可执行 target（`FloatShelfCoreChecks`）。

### 1.2 签名实测

- 链接器默认已经给可执行文件做了 ad-hoc 签名，`codesign --force --sign - --identifier ...` 会替换这个签名，结果是 `valid on disk`，并且 `satisfies its Designated Requirement`。
- `codesign -d -r-` 显示 `designated => cdhash H"..."`。这说明 ad-hoc 签名的 DR 绑定 cdhash，每次重新构建都会变（见 §2.4）。
- `.app` 组装（Info.plist + `plutil -lint` + 签名）流程已经用临时包走通。临时包和 `.scratch/` 已删除，项目目录恢复成只有 `.git`。

---

## 2. 关键 API 调研与技术判断

### 2.1 如何在系统范围内检测"正在拖文件"+"摇晃"

| 方案 | 权限 | 能否看到 Finder 拖拽中的鼠标移动 | 评价 |
|---|---|---|---|
| (a) `NSEvent.addGlobalMonitorForEvents(.leftMouseDragged / .leftMouseUp)` | Apple 文档：**仅键盘类事件**需要 Accessibility；鼠标事件不需要 Accessibility / Input Monitoring（文档 + 多个开发者报告） | 同类工具（Stash、Dropover 类应用的公开实现）用它检测 Finder 拖拽；**本机 macOS 27 上尚未实测** | **首选**。事件驱动、零轮询、无需授权；只读，不能修改/拦截事件，不会打断 Finder 拖拽 |
| (b) 只监听的 `CGEventTap`（`.cgSessionEventTap` + `.listenOnly`，mask = leftMouseDragged/Up） | Input Monitoring（`CGPreflightListenEventAccess` / `CGRequestListenEventAccess`）；ad-hoc 签名下 TCC 授权会随重建失效，且有报告称请求不一定把应用加入列表 | 能看到所有会话级鼠标事件 | **备选**。仅当 (a) 在 macOS 27 上收不到拖拽期间事件时启用 |
| (c) 无权限兜底：低频轮询 `NSEvent.pressedMouseButtons` + `NSPasteboard(name: .drag).changeCount`，检测到"左键按下且拖拽板变化"后，只在按键按住期间短时高频采样 `NSEvent.mouseLocation` | 无 | 不依赖事件投递 | **兜底**。有轮询成本（空闲时 ~4–5 Hz 检查，拖拽期间 ~60 Hz，松开即停） |

**区分"拖文件"与"拖窗口/选择文字"**：全局 `leftMouseDragged` 也会在拖窗口时触发，且 `.drag` 拖拽板会残留上一次的文件内容。已知规避（开发者反馈并经 DTS 确认为系统行为）：拖窗口不会让 `NSPasteboard(name: .drag).changeCount` 增加。因此判定规则为：
- `leftMouseDown`（或第一次 `leftMouseDragged`）记录 changeCount 基线；
- 拖动过程中 changeCount ≠ 基线 **且** 拖拽板类型包含 `.fileURL`（P1 再扩展到 URL/文本/图片）→ 进入 "文件拖拽中" 状态；
- `leftMouseUp` → 结束，重置手势检测。

**摇晃检测（纯算法，放在可测试 Core 中）**：
- 输入：带时间戳的全局坐标样本（AppKit 点坐标，与 Retina 缩放无关）。
- 计算 x 方向位移，忽略小于 `minSegment`（默认 ~30pt）的抖动；方向反转且相邻段幅度达标则计为一次"摆动"。
- 在 `window`（默认 ~600ms）内摆动次数 ≥ `requiredReversals`（默认 3–4）且 |Δy| 相对较小（过滤画圈/斜向移动）→ 触发。
- 触发后 `cooldown`（默认 ~800ms，单次拖拽内只触发一次）。
- 灵敏度 = 预设档位映射到 `minSegment / window / requiredReversals`；三者均可在设置中调整。

**选定方案**：(a) 为主，权限为零；启动时自检（若用户在拖拽中长时间收不到事件则在诊断日志中记录）。(b)/(c) 作为可在设置中切换的"检测引擎"，Phase 0 会把 (a) 与 (c) 都实现成可运行验证版本，(b) 视 (a) 实测结果决定是否实现。**结论以 Phase 0 实测为准，不预设成功。**

### 2.2 拖拽进行中弹出的 Shelf 如何接收 Finder 的拖放

- 系统拖拽会话在鼠标每次移动时重新对光标下的窗口做命中测试；新 `orderFront` 的窗口只要满足以下条件，就会作为目的地收到 `draggingEntered:`（Dropover/Yoink 类产品的核心行为依赖于此，**本机待 Phase 0 实测**）：
  - 窗口可见（`orderFrontRegardless()`，因为应用为 accessory/不激活）；
  - 窗口/视图已 `registerForDraggedTypes([.fileURL, ...])`；
  - `ignoresMouseEvents == false`；
  - 光标确实位于窗口内 → Shelf 出现位置需让光标落在 drop 区内（或者用户稍作移动即可进入）；
  - 窗口层级高于 Finder：`.floating`（必要时 `.statusBar`），`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient 或 .stationary]`，保证在全屏应用 Space 上也能出现。
- 使用 `NSPanel(styleMask: [.nonactivatingPanel, .borderless/.fullSizeContentView])`，`becomesKeyOnlyIfNeeded = true`，`hidesOnDeactivate = false`，`canBecomeKey` 默认 false（需要文字输入时再 override）——**不抢键盘焦点**，也不会让 Finder 失去前台，从而不打断原拖拽会话。
- 显示动画：仅用 `alphaValue`/`frame` 的短动画（≤150ms），窗口一出现就能接收拖放，不等待动画结束。
- 不使用 SwiftUI `onDrop/onDrag` 作为拖放主体：drop 目标是 AppKit `NSView`（实现 `NSDraggingDestination`），SwiftUI 仅用于内容展示（`NSHostingView` 嵌入）。

### 2.3 拖出（Drag Out）

- 拖出视图实现 `NSDraggingSource`，`mouseDragged:` 中调用 `beginDraggingSession(with: [NSDraggingItem], event:, source:)`；每个 `NSDraggingItem` 的 pasteboard writer 直接用 `NSURL`（实现了 `NSPasteboardWriting`，写出 `public.file-url`），拖全部时多个 item 一次性开始会话。
- `draggingSession(_:sourceOperationMaskFor:)`：`.outsideApplication` 返回 `[.copy, .move, .link, .generic]`（**不含 `.delete`**）；`.withinApplication` 返回 `[.copy, .generic]`（Shelf 之间复制引用）。
- 修饰键：系统按 Apple 文档过滤源掩码——Option → `.copy`，Command → `.generic`，Control → `.link`；不实现 `ignoreModifierKeysWhileDragging`，因此保留 Finder 原生语义（同卷默认移动、跨卷默认复制，Option 强制复制，带 "+" 光标）。
- `draggingSession(_:endedAt:operation:)`：
  - `.none`（取消/被拒）→ Shelf 内容保持不变；
  - `.move` → 由 Finder 执行实际移动；Shelf **仅在源 URL 已不存在时**才移除或更新该项（`FileManager.fileExists` 检查），不自行删除任何文件；
  - 其它 → 保留条目。
- 不模拟按键、不写系统剪贴板来伪造拖拽。
- 同名文件：模型以"标准化路径 + 文件资源标识（`URLResourceKey.fileResourceIdentifierKey`）"去重，而不是文件名；UI 显示文件名，tooltip/副标题显示所在目录区分同名。
- 被 Finder 移动后的追踪（可选增强）：保存 bookmark data（非安全作用域，非沙盒应用无需 security-scoped bookmark），`endedAt` 中可通过 bookmark 解析新位置更新引用。
- **注意**：把 Shelf 项拖到废纸篓，Finder 会把**真实文件**移入废纸篓——这是系统语义，会在 README 中明确说明。

### 2.4 应用形态与签名

- 非沙盒、ad-hoc 签名（`codesign --force --sign - --identifier com.weijiaren.FloatShelf`）。沙盒会限制读取他人拖入文件的长期访问，且对本需求无收益。
- `Info.plist`：`LSUIElement = YES`（无 Dock 图标）、`CFBundleIdentifier = com.weijiaren.FloatShelf`（固定不变）、`LSMinimumSystemVersion = 14.0`、`NSHighResolutionCapable`。
- **TCC 与 ad-hoc 签名**：ad-hoc 签名的指定要求（DR）是 cdhash，每次重建都会变化，已授予的 Accessibility / Input Monitoring 会"开关仍显示开启但实际失效"。对策：
  1. 选定的主路径（全局鼠标监听 + Carbon 热键）**本身不需要任何 TCC 权限**，因此该问题不影响 P0；
  2. 若启用 CGEventTap 引擎：README 提供 `tccutil reset ListenEvent com.weijiaren.FloatShelf` 后重新授权的步骤；
  3. 可选：用户自行在钥匙串创建本地自签名代码签名证书，`build.sh` 支持 `SIGN_IDENTITY="..."` 环境变量，使 DR 稳定（不由脚本自动创建证书、不修改钥匙串）。

### 2.5 多显示器坐标

- AppKit 全局坐标：原点在**主屏左下角**，y 向上；`NSEvent.mouseLocation`、`NSWindow.frame`、`NSScreen.frame` 均为此坐标系，单位为点（points）。
- CG / Quartz 全局坐标（CGEvent.location、CGDisplayBounds）：原点在主屏**左上角**，y 向下。换算：`y_appkit = NSScreen.screens[0].frame.maxY - y_cg`（仅在使用 CGEventTap 时需要）。
- Shelf 定位：用 `NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }` 找鼠标所在屏，在其 `visibleFrame`（排除菜单栏/Dock）内夹紧窗口 frame；左右/上下空间不足时翻转到光标另一侧；外接屏在主屏左侧/上方时坐标为负数，算法必须支持。
- Retina：所有计算用点坐标，`backingScaleFactor` 只用于缩略图像素尺寸（`QLThumbnailGenerator` 请求 `size × scale`）；混合 2x/1x 屏需在 `NSWindow.didChangeScreen` 时刷新缩略图。
- 定位数学是纯函数（输入：鼠标点、窗口尺寸、各屏 frame/visibleFrame），放在 Core 中单元测试。

### 2.6 全局快捷键

- Carbon `RegisterEventHotKey` + `InstallEventHandler(GetApplicationEventTarget(), kEventHotKeyPressed)`：默认 ⌃⌥S，无需任何权限（本机注册返回 noErr）。
- 不使用 `NSEvent` 全局 keyDown 监听（需要 Accessibility）。
- 设置中可录制新快捷键；注册冲突（`eventHotKeyExistsErr`）时提示用户。

### 2.7 菜单栏

- `NSStatusItem`（SF Symbol 模板图标），菜单：新建 Shelf、最近的 Shelf（P1）、设置…、权限与诊断…、**退出 FloatShelf（⌘Q）**。
- 状态栏按钮注册拖放类型：把文件拖到菜单栏图标 → 新建 Shelf 并放入（P1，可选）。

---

## 3. 模块架构

```
FloatShelf/
├── Package.swift                     # swift-tools-version 6.0，Swift 6 语言模式，macOS 14+
├── Sources/
│   ├── FloatShelfCore/               # 纯逻辑库，无 AppKit UI 依赖，可单元测试
│   │   ├── Gesture/ShakeDetector.swift        # 摇晃识别算法 + ShakeConfig（阈值/灵敏度/冷却）
│   │   ├── Geometry/ShelfPositioning.swift    # 多屏定位/夹紧/翻转纯函数
│   │   ├── Model/ShelfItem.swift              # 文件引用（URL、bookmark、resourceID、显示名）
│   │   ├── Model/ShelfStore.swift             # 增删、去重、排序、移动后校验
│   │   ├── Drag/DragSessionTracker.swift      # changeCount 基线 + 状态机（idle/pressed/fileDrag/ended）
│   │   └── Settings/SettingsModel.swift       # Codable 设置 + UserDefaults 键
│   └── FloatShelf/                   # 可执行 target（AppKit + SwiftUI）
│       ├── App/main.swift, AppDelegate.swift, StatusItemController.swift
│       ├── WindowManagement/ShelfPanel.swift, ShelfWindowController.swift, ShelfManager.swift
│       ├── DragCoordination/GlobalDragMonitor.swift   # NSEvent 全局监听（主）
│       │                    /PollingDragMonitor.swift  # 无权限轮询兜底
│       │                    /EventTapDragMonitor.swift # CGEventTap（可选）
│       ├── DropIn/ShelfDropView.swift                  # NSDraggingDestination
│       ├── DragOut/ShelfDragSource.swift               # NSDraggingSource / NSDraggingItem
│       ├── Views/ShelfContentView.swift, ItemCell.swift, Thumbnails.swift (QuickLookThumbnailing)
│       ├── Hotkey/HotkeyManager.swift                  # Carbon RegisterEventHotKey
│       ├── Permissions/PermissionCenter.swift          # AX / ListenEvent 检测 + 打开系统设置对应面板
│       ├── Settings/SettingsWindow.swift (SwiftUI)
│       └── Diagnostics/Log.swift                       # os.Logger，subsystem com.weijiaren.FloatShelf，分类 drag/shake/window/dragout/hotkey
├── Tests/FloatShelfCoreTests/        # swift-testing（或无宏断言 runner，见 §1.1）
├── Resources/Info.plist, AppIcon（sips+iconutil 生成，独立设计，不使用 Dropover 资源）
├── scripts/build.sh, run.sh, test.sh, make-icon.sh
├── docs/PLAN.md, docs/TESTING.md（手工 GUI 验收清单）
└── README.md
```

依赖方向：`FloatShelf (App)` → `FloatShelfCore`；Core 不依赖 AppKit 窗口类（可依赖 Foundation/CoreGraphics 类型）。并发：UI 与监听回调统一 `@MainActor`；Core 类型为 `Sendable` 值类型。

---

## 4. 构建方案（仅 CLT）

`scripts/build.sh`：
1. `swift build -c release --product FloatShelf`；`BIN=$(swift build -c release --show-bin-path)`。
2. 组装 `build/FloatShelf.app/Contents/{MacOS,Resources,Info.plist}`，复制可执行文件与 `AppIcon.icns`。
3. `plutil -lint` 校验 Info.plist。
4. 签名：`codesign --force --sign "${SIGN_IDENTITY:--}" --identifier com.weijiaren.FloatShelf build/FloatShelf.app`，再 `codesign --verify --verbose`。
5. 输出路径；`scripts/run.sh` 用 `open build/FloatShelf.app`（或直接执行二进制以便看日志）；`log stream --predicate 'subsystem == "com.weijiaren.FloatShelf"'` 查看诊断。
- 不写入 `/Applications`；是否复制到 `~/Applications` 由用户决定。
- `.build/`、`build/`、`.scratch/` 写入 `.gitignore`。

---

## 5. 分阶段计划

### Phase 0 — 技术可行性验证（最小可运行程序）
- 实现：菜单栏 + 退出；`GlobalDragMonitor` + `DragSessionTracker` + `ShakeDetector`；最简 `ShelfPanel`（非激活、浮动层）+ `ShelfDropView`（接收 fileURL）+ 列表显示文件名；`ShelfDragSource` 拖出单个/全部；诊断日志。
- 同时实现 `PollingDragMonitor`，菜单中可切换引擎，便于对比实测。
- 自动：`swift build`、Core 单元测试（摇晃算法、状态机）。
- **手工验收（需 Gerry 亲自操作）**：
  - A：Finder 拖住文件 → 摇晃 → Shelf 出现 → Finder 拖拽未中断 → 直接放入 Shelf 成功；
  - B：Finder → Shelf → 拖到 Finder 另一目录（默认/Option）→ 结果符合 Finder 语义，取消时条目保留。
- 若 A 失败：依次切换到轮询引擎 / CGEventTap 引擎，记录结论，向用户报告平台限制。
- 提交：`feat(poc): verify shake-to-open during Finder drag and native drag out`

### Phase 1 — 完整核心功能
- ⌃⌥S 全局快捷键、菜单栏新建 Shelf、Shelf 关闭/固定/清空、缩略图 + 文件名 + 数量 + 空状态、多文件/文件夹、拖全部、同名文件处理、`ShelfPositioning` 多屏夹紧、`build.sh` 产出可双击的 `FloatShelf.app`。
- 自动：定位数学、去重/同名、移动后校验逻辑单测。
- 提交：`feat(core): ...`、`build: add CLI app bundle script`

### Phase 2 — 体验与健壮性
- 动画、视觉（系统材质 `NSVisualEffectView`、圆角、阴影、SF Symbols、浅色/深色）、错误处理、多显示器/全屏 Space、权限说明面板、基础设置（灵敏度/阈值/冷却）。
- 提交：`feat(ui): ...`、`fix: ...`

### Phase 3 — P1 扩展（逐项，不破坏核心）
- 多个独立 Shelf、文本/URL/图片/剪贴板、Quick Look（`QLPreviewPanel`）、删除/重排/清空、透明度/尺寸/自动收起、SwiftUI Settings 完整版、位置记忆与最近 Shelf。
- 每项单独提交。

### 自动测试 vs 手工 GUI 验收

| 场景 | 类型 |
|---|---|
| 摇晃算法（正样本/普通移动/画圈/慢速/冷却） | 自动 |
| 拖拽状态机（changeCount 变化、窗口拖动不误判） | 自动 |
| 多屏定位/边界夹紧/负坐标/翻转 | 自动 |
| 模型去重、同名不同目录、移动后校验 | 自动 |
| 构建产物结构、Info.plist、签名校验 | 自动（脚本） |
| Finder → Shelf → Finder 其他目录 | 手工 |
| Finder → Shelf → 浏览器上传区域 | 手工 |
| 多文件 + 文件夹同时暂存 | 手工 |
| 拖拽中摇晃显示 Shelf | 手工 |
| 拖拽中切换应用（⌘Tab） | 手工 |
| 取消拖放后源文件无损 | 手工（可辅以脚本校验文件 hash） |
| 关闭 Shelf 后源文件仍在 | 手工 + 脚本校验 |
| 双屏（Retina 主屏 + 1080p 外接）及屏幕边缘 | 手工 |
| 权限未授予时的提示（仅 CGEventTap 引擎涉及） | 手工 |

未经实际验证的项目一律不标记为通过。

---

## 6. 已知风险与平台限制

1. **最高风险**：macOS 27 上全局鼠标监听在 Finder 拖拽会话期间能否持续收到 `leftMouseDragged`（未实测）。有 2 个备选引擎。
2. 拖拽中新出现窗口能否立即成为 drop 目标（行业产品证明可行，本机未实测）；若光标不在窗口内，需用户稍微移动。
3. `.drag` 拖拽板 changeCount 区分窗口拖动属于非文档化行为，可能随系统变化；状态机会结合 `.fileURL` 类型与按下时基线做判断。
4. 文件被拖出移动后的引用失效：靠 `endedAt` 存在性检查 + bookmark 解析处理。
5. 拖到废纸篓会真正删除（移入废纸篓）原文件——系统语义，需文档提醒。
6. ad-hoc 签名使 TCC 授权随重建失效（仅影响可选的 CGEventTap 引擎）。
7. 纯 CLT 下 swift-testing 要配 rpath，并显式指定宏 plugin-path，否则会间歇性失败（§1.1）。工具链升级后需要复查。
8. 无 Xcode：无 Asset Catalog、无 xib、无 Instruments/Xcode 调试器；调试依赖 `os.Logger` + `log stream` + `lldb`（CLT 自带，未验证）。
9. 外接屏为 1x，主屏 2x：缩略图与动画需在换屏时刷新。

---

## 7. 提交规范（Conventional Commits）

`<type>(<scope>): <subject>`，type ∈ `feat | fix | refactor | perf | test | docs | build | chore`；scope 示例：`poc, shake, drag, dragout, panel, hotkey, statusbar, settings, build`。
示例：
- `docs: add environment findings and architecture plan`
- `feat(poc): show shelf on shake during Finder drag`
- `feat(dragout): support dragging all items with native NSDraggingSession`
- `build: assemble FloatShelf.app with ad-hoc signing`
- `test(shake): cover false-positive movement patterns`
