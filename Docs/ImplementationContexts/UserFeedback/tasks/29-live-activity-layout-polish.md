# 29：Live Activity 时间尾部间距与排版优化实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [~] 领取反馈，定位 Live Activity 各 family 的尾部时间布局、现有 fixture 与自动化验收入口。
- [ ] 依据 Apple HIG 与 SwiftUI 布局规范确定信息层级、间距和最窄宽度契约。
- [ ] 实现最小修复，补齐单元/UI contract 与完全脚本化 XCUITest 几何/截图验收。
- [ ] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- 修复 Live Activity 最右侧时间附近异常空白/间距。
- 在不改变计时语义和交互能力的前提下，提高 Lock Screen / Dynamic Island 排版质量。
- 不领取主页统计图、Apple Health 或其他后续反馈。

## 强制约束

- 开始 UI/SwiftUI 工作前完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`，只读取其任务相关引用。
- 优先复用 ActivityKit、WidgetKit、SwiftUI 与仓库既有组件；若原生布局足够，不为装饰引入第三方依赖。
- 所有可重复验收写成 XCTest/XCUITest；macOS 如需窗口位置，由 `XCUICoordinate` 自动完成。只在自有模拟器截图；物理机仅最终 Release 安装与签名/版本只读核验，绝不启动、点击或截图。
- 每个 checkpoint 只暂存本任务变更，保护 `Docs/userfeedback.md` 中其他用户新增内容。

## Checkpoint 编排

- [~] Checkpoint A：布局根因、HIG 约束与自动化验收设计审计。
- [ ] Checkpoint B：实现、定向单元/UI contract 与脚本化视觉验收。
- [ ] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## 资源所有权

- 当前静态审计子 agent：只读，无文件、build、simulator 或设备所有权。
- 后续每个模拟器批次必须在此记录名称与 UDID；主代理负责终止 App、关机、删除，并核验无 runner/process 残留。
