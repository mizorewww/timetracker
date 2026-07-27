# 75：侧边栏分类图标与文字可读性 实现记忆

状态：2026-07-27 实现中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 认领的反馈条目

- iPad / macOS 侧边栏中的分类图标和文字过小，普通字号下扫描与辨识困难。

## 预期行为

- 侧边栏分组、目的地和任务行形成清晰且符合平台习惯的字号层级；当前目的地、
  badge、展开控件和任务身份不会互相竞争。
- 分类图标具有稳定、易辨识的视觉尺寸和对齐，不通过放大整行 hit frame 制造
  假图标尺寸，也不裁切 SF Symbol。
- iPad 与 macOS 使用同一语义组件；只有系统平台控件自身的自然差异，不复制
  两套分类 row。
- iPhone 的 tab/紧凑导航不因宽屏侧边栏修复而改变。

## UI 验收清单

- 先保留正常字号下 iPad 横屏与 macOS 的确定性侧边栏截图，并定位字号、symbol
  frame、row height 与系统 sidebar style 的实际 owner。
- 用可访问性标识和真实 UI frame/文字属性建立先失败的验收，不使用源码字符串
  扫描或像素颜色扫描。
- 检查长分类名、badge、展开箭头、选中态和至少一层任务树；图标与文字基线、
  行间距和点击区域保持稳定。
- iPhone 紧凑根导航回归，确保没有把 tab 图标或正文一并放大。
- SwiftFormat、相关单元/XCUITest、默认 `make test` 和 Release
  `make build-install-all` 通过，并释放所有 owned 资源。

## Checkpoint 编排

- [ ] A：领取反馈、建立活动实现记忆并定位侧边栏 row owner。
- [ ] B：补充先失败的可读性 / 几何 UI 契约。
- [ ] C：实现最小共享组件修复并更新相关文档。
- [ ] D：完成格式、跨平台截图、全量测试、Release 全设备安装与收口。

## 库策略

- 优先使用 SwiftUI `Label`、动态系统文字样式、SF Symbols 和现有
  `TaskSummaryRow`；不为字号或 symbol frame 引入组件库。
- 参考 Apple HIG 对 sidebar hierarchy、typography、SF Symbols 与 selection 的
  规范。只有现有原生组件无法满足明确行为时，才评估维护活跃、成熟且一般不少于
  1k stars 的第三方库。

## 进度记录

- 2026-07-27：认领任务并建立 `~75` 活动实现记忆。
