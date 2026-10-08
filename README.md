# FloatShelf

原生 macOS 悬浮文件暂存工具（Swift 6 + AppKit），交互参考 Dropover，独立实现。当前处于 **Phase 0：技术可行性验证**。

## 构建与运行（只需 Command Line Tools，不需要 Xcode）

```bash
scripts/build.sh        # → dist/FloatShelf.app（ad-hoc 签名，LSUIElement，无 Dock 图标）
scripts/run.sh          # 启动，并把日志另写一份到 logs/
scripts/test.sh         # 单元测试（Swift Testing）
```

也可以直接在 Finder 中双击 `dist/FloatShelf.app`。退出：菜单栏图标 → **退出 FloatShelf**。

## 使用（Phase 0）

- 在 Finder 中拖住文件不松开，左右快速摇晃鼠标 → Shelf 出现在光标附近，直接把文件放进去即可。
- 快捷键 **⌃⌥S**，或菜单栏图标 → 新建 Shelf。
- 从 Shelf 拖出单个文件，或用右上角"拖动全部"图标一次拖出全部，放到 Finder 或浏览器等应用。Phase 0 默认**只复制**。
- FloatShelf 只保存文件引用，**从不复制、移动或删除源文件**。

## 权限

Phase 0 的主路径（全局鼠标事件监听 + Carbon 快捷键）按 Apple 文档不需要辅助功能或输入监控权限，FloatShelf 也不会主动请求。可以在菜单 → "权限状态…" 查看当前状态。

## 日志

```bash
/usr/bin/log stream --level debug --style compact --predicate 'subsystem == "com.weijiaren.FloatShelf"'
```
（zsh 中 `log` 是内建命令，请写完整路径。）

## 文档

- `docs/PLAN.md`：环境检测、API 调研、架构与阶段计划
- `docs/PHASE0_TESTING.md`：自动验证结果、手工验收步骤、已知问题
