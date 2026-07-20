# 用户反馈修复总账

本目录是 `Docs/userfeedback.md` 的实现记忆与代理协作入口。反馈原文是完成状态的最终来源；这里只记录实现顺序、证据和当前上下文，避免上下文切换后重复工作。

## 状态约定

- `[ ]`：尚未开始或仍有已知缺口
- `[~]`：当前正在实现；必须在 `~active/` 下存在一个链接目录
- `[x]`：代码、相关测试、资源清理和要求的设备验收均完成；同时必须回写 `Docs/userfeedback.md`
- 每次只保留一个主产品任务为 `[~]`。并行子代理只能做边界清晰的审计、测试设计或互不冲突的实现。

## 实施纪律

- 每个小 checkpoint 单独验证和提交，主代理只暂存自己确认完成的文件。
- UI checkpoint 依据 Apple HIG 与仓库 SwiftUI 技能审查；按相关平台做普通文字大小、常规路径截图验收。
- 完整反馈任务完成后运行 `CONFIGURATION=Release scripts/build_install_all.sh`，保留付费开发者签名与 entitlement。
- 优先使用 Apple 原生框架和项目已有成熟依赖。新增第三方库前先联网核对维护状态、许可证、发行记录和 GitHub stars；除用户指定库外，少于 1,000 stars 的库不采用。
- 每个 checkpoint 报告：完成范围、使用的库/系统框架、验证、模拟器/进程/临时产物清理、累计进度与下一 checkpoint。

## 反馈任务

- [~] 01 同一任务小于一分钟的相邻计时段自动合并（[实现上下文](tasks/01-merge-nearby-segments.md)）
- [ ] 02 Today 增加本周累计时间柱状图
- [ ] 03 iPad 将正在计时卡片与概览合并成一行
- [ ] 04 接入 HealthKit 运动与睡眠并整合 Timeline、自动维护系统任务
- [ ] 05 Inbox 支持用户手动移动到任务、分类或 Checklist
- [ ] 06 统一任务选择器的计时状态指示
- [ ] 07 统一归档语义、移除删除路径并提供归档管理
- [ ] 08 合并任务详情与编辑、移除快速编辑、Markdown 备注
- [ ] 09 合并后的任务编辑自动保存
- [ ] 10 修复 Live Activity / Dynamic Island 不出现
- [ ] 11 任务详情顶部卡片复用 Stop，并把 Add Time 放到原编辑入口
- [ ] 12 Checklist 勾选动画及已完成项自动置底
- [ ] 13 Today 可配置 GitHub 风格 Heatmap
- [ ] 14 每个任务可选择追踪 Heatmap，默认关闭
- [ ] 15 每个任务独立 Heatmap 配色与阈值
- [ ] 16 任务量决定 Heatmap 深浅
- [ ] 17 创建重复任务与任务量任务
- [ ] 18 Quick Start 编辑页添加动画与固定列表交互
- [ ] 19 侧边栏计时图标对齐与任务间距
- [ ] 20 macOS 设置侧边栏固定展开并移除切换按钮
- [ ] 21 合并 Timeline 中不同类型的睡眠段
- [ ] 22 Quick Start 禁止启动 HealthKit 运动/睡眠同步任务
- [ ] 23 所有 AI 提示词均可编辑
- [ ] 24 Generate Task Plan 支持多任务并设计完整软件任务语义提示词
- [ ] 25 Apple Health 系统任务自动显示但不可手工计时
- [ ] 26 Inbox 完成状态可撤销
- [ ] 27 Timeline 短任务使用多轨布局并避免遮挡 elapsed 标记
- [ ] 28 Live Activity 时间尾部间距与整体排版

## 当前协作

- 主代理：维护总账、Git checkpoint、构建/安装、设备与模拟器资源所有权。
- `audit_timer_merge`：只读审计任务 01 的实现和测试。
- `audit_recent_feedback`：只读核对近期提交与仍未勾选反馈的差异。
- `inventory_project`：只读核对目标平台、scheme、依赖与全设备安装脚本。

## 资源所有权

- 当前无主代理或子代理持有的 Simulator、`xcodebuild`、`xctest`、UI runner 或 Instruments 进程。
