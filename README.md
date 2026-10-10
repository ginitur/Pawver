# Pawver

> 原名 FloatShelf（2026-10-10 更名；仓库目录仍为 `~/Projects/FloatShelf`）。

原生 macOS 悬浮文件暂存工具（Swift 6 + AppKit），交互参考 Dropover，独立实现。当前处于 **Phase 0：技术可行性验证**。

## 构建与运行（只需 Command Line Tools，不需要 Xcode）

```bash
scripts/build.sh        # → dist/Pawver.app（ad-hoc 签名，LSUIElement，无 Dock 图标）
scripts/run.sh          # 启动，并把日志另写一份到 logs/
scripts/test.sh         # 单元测试（Swift Testing）
```

也可以直接在 Finder 中双击 `dist/Pawver.app`。退出：菜单栏图标 → **退出 Pawver**。

## 使用（Phase 0）

- 在 Finder 中拖住文件不松开，左右快速摇晃鼠标 → Shelf 出现在光标附近，直接把文件放进去即可。
- 快捷键 **⌃⌥S**，或菜单栏图标 → 新建 Shelf。
- 从 Shelf 拖出单个文件，或用右上角"拖动全部"图标一次拖出全部，放到 Finder 或浏览器等应用。Phase 0 默认**只复制**。
- Pawver 只保存文件引用，**从不复制、移动或删除源文件**。

## 菜单与设置

菜单栏菜单只保留基本项：**新建 Shelf ⌃⌥S**、**设置… ⌘,**、**隐藏菜单栏图标**、**退出 Pawver ⌘Q**。Shelf 右上角“…”按钮弹出同一个菜单。

“设置…”窗口（所有选项保存在 UserDefaults，域 `com.weijiaren.Pawver`）：
- 通用：显示菜单栏图标
- 摇晃检测：灵敏度（低/中/高）、检测引擎（全局事件监听 / 轮询）、仅在确认是文件拖拽时触发
- 快捷键：⌃⌥S 注册状态与触发次数、重新注册
- 高级与诊断：拖出时允许“移动”（实验）、详细诊断日志、权限状态（只读）、记录屏幕信息、在 Finder 中显示日志

## 菜单栏图标（可隐藏）

- 菜单栏图标是 SF Symbol `pawprint`（单色模板图，随深浅色自动变化）；App 图标由 `scripts/make-icon.sh` 从 `Resources/Brand/pawver-source.png` 生成（build.sh 会自动调用）。
- 隐藏：菜单 → **隐藏菜单栏图标**，或按住 ⌘ 把图标拖出菜单栏。两种方式都会记录到 UserDefaults（`statusItemHidden`）。
- 找回（Pawver 仍在运行时）：
  1. 再次双击 `dist/Pawver.app`（触发 reopen，图标立即恢复）；
  2. 或按 **⌃⌥S** 打开 Shelf，点右上角 **“…”** 按钮 → **显示菜单栏图标**。这个菜单和菜单栏菜单相同，**退出 Pawver** 也在里面。
- 重新启动 Pawver 时总是显示图标（启动即表示想用它，同时保证“退出”可见）。
- 如果 Finder 仍显示旧图标或通用图标：`touch dist/Pawver.app`（build.sh 已自动执行），必要时重新打开 Finder 窗口。

## 权限

Phase 0 的主路径（全局鼠标事件监听 + Carbon 快捷键）按 Apple 文档不需要辅助功能或输入监控权限，Pawver 也不会主动请求。可以在 设置… → 高级与诊断 中查看当前状态。

## 日志

```bash
/usr/bin/log stream --level debug --style compact --predicate 'subsystem == "com.weijiaren.Pawver"'
```
（zsh 中 `log` 是内建命令，请写完整路径。）

## 文档

- `docs/PLAN.md`：环境检测、API 调研、架构与阶段计划
- `docs/PHASE0_TESTING.md`：自动验证结果、手工验收步骤、已知问题
