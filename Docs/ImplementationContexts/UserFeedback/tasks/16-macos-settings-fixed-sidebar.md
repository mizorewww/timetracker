# 16：macOS 设置侧边栏固定展开实现记忆

> 本文件仅作为主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 读取唯一反馈、Apple HIG 与 SwiftUI 强制技能并建立 active link。
- [ ] 审计 macOS Settings 的 scene、导航容器、column visibility 与 toolbar/sidebar toggle 来源。
- [ ] 实现 macOS 设置侧边栏固定展开并移除展开状态切换按钮。
- [ ] 完成定向测试、owned macOS 普通路径截图验收与资源清理。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh` 并由 Codex 标记完成。

## 唯一反馈边界

- 仅在 macOS 设置界面让侧边栏固定保持展开。
- 删除该设置界面的侧边栏展开/收起状态切换按钮。
- 不领取或实现本条之后的睡眠合并等反馈。

## 强制设计与实现约束

- Apple HIG：macOS Settings 导航应稳定、可预测；当前仓库使用侧边栏的前提下，本任务按用户明确要求
  固定展开，不提供一个不会再有有效状态变化的伪切换按钮。
- SwiftUI：优先使用 `NavigationSplitView` / scene 原生 column-visibility 与 toolbar API，避免 AppKit
  window 遍历、视图坐标 hack 或重复导航容器；不顺手迁移无关软弃用 API。
- 保留 Command-Comma、最后选择的设置 pane、键盘导航、窗口尺寸与非 macOS 平台行为。
- UI 操作与截图仅使用 owned macOS App/测试会话或 owned 模拟器；物理 iPhone/iPad 只用于最终 Release
  安装，不启动、不操作、不截图。
- 每个小 checkpoint 完成验证并提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中用户新增内容。

## 初始审计问题

- 当前设置入口是否为 SwiftUI `Settings` scene，侧边栏是否由 `NavigationSplitView`、`List` selection 或
  自定义 split view 提供。
- 展开状态切换按钮来自系统自动 toolbar item、显式 `toggleSidebar:`、自定义 Button，还是 window toolbar。
- macOS 窗口变窄/重开 Settings 时，如何在不产生状态反复写入的前提下维持 sidebar 可见。
- iOS/iPadOS 是否复用同一 Settings view；修复必须用条件编译或平台封装避免改变移动端导航。

## 依赖与互联网库审计

- 待查询 Apple 官方 SwiftUI 文档与成熟候选库。原生 Settings/NavigationSplitView 能完整覆盖时不新增依赖；
  非用户指定 GitHub 库一般必须达到 1k stars 且仍需证明它优于原生 API。

## 验证与资源所有权

- 待为本任务记录 owned 会话/模拟器标识、截图路径、结果包与清理结果。
- 最终必须记录 exact Release 命令、签名、两台连接设备的只读安装版本、embedded Watch 与 macOS 安装。
