# 93：侧边栏任务切换需要二次点击 实现记忆

状态：2026-07-28 进行中

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的状态条目。

## 认领范围

- 复现侧边栏已高亮任务 A 时，单击任务 B 先跳到 Tasks 根页、第二次才选中 B 的问题。
- 统一 sidebar selection、Tasks route 与 Task Detail replacement 的单次导航事务。
- 保留脏草稿导航保护、侧边栏自动展开和紧凑宽度 tab 导航语义。

## 验收条件

- [ ] 先建立 A → B 单击切换的失败行为测试或 UI acceptance。
- [ ] 一次点击同时更新高亮和详情，不暴露中间 Tasks 根页。
- [ ] 脏草稿仍需确认；取消确认时保持 A，确认后才原子切到 B。
- [ ] iPad 与 macOS 正常字号侧边栏行为、选中态和截图验收通过。
- [ ] `make test`、格式、本地化门禁通过，实现提交后完成 `make build-install-all`。

## 子代理编排

- 子代理 A：只读追踪 sidebar selection、route 和 detail replacement 状态流。
- 子代理 B：只读梳理现有 sidebar/navigation 行为与 UI 测试缺口。
- 主代理：复现、测试、最小修复、平台 UI 验收、提交和设备安装。

## 约束

- Apple HIG：sidebar 选择应直接呈现所选目标，选中高亮与 detail 内容保持一致。
- SwiftUI skill：导航状态只有一个事实来源；避免多个 `onChange`/binding setter 互相写回。
- 优先使用 SwiftUI `NavigationSplitView`、selection binding 和现有 typed route，不新增导航库。

## 进度记录

- 2026-07-28：认领侧边栏双击切换 bug；下一步先锁定 A → B 的中间状态写回来源。
