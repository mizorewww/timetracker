# 51：AI 大计划忠实渲染与清单上限实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“生成的计划含有过多分类/任务/清单项应忠实渲染;一个任务下生成150个checklist失败”反馈。
- [x] 审计计划数量上限(system contract 8分类/64任务/32清单每项/256总计)、验证失败路径与预览渲染截断。
- [x] 确定新上限(支持 150+ 清单项)与忠实渲染方案(大计划预览不截断不卡死)。
- [x] 实现并运行聚焦测试与模拟器截图验收。
- [x] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`(实体机安装失败不阻塞),标记完成并移除活动链接。

## 唯一反馈边界

- 大计划:上限调整 + 预览忠实渲染;150 清单项单任务必须可生成、可预览、可创建。
- 不领取 iCloud 冲突、token 显示或其他反馈。
- 以普通文字大小、正常交互路径、三平台系统约定为优先。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`;所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本。
- 实体机器不做测试;模拟器验收后 shutdown+delete 并清理 /tmp 产物。
- 优先复用现有组件;除用户建议外不引入 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务的已完成变更;保留用户在反馈文件中的其他内容。

## Checkpoint 编排

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [x] Checkpoint B：审计上限与渲染路径。
- [x] Checkpoint C：实现并补齐聚焦测试(含 150 清单项端到端)。
- [x] Checkpoint D：三平台模拟器验收与资源清理。
- [x] Checkpoint E：Release 构建安装、核验与收口。(2026-07-25:macOS Release 构建成功并装入 /Applications;iPad Pro M4 已安装;iPhone Air 安装失败(设备不可用),按惯例不阻塞)

## 资源所有权

- [~] 主代理：任务状态、编排、集成、所有 build/simulator/XCUITest/screenshot/Release 批次与清理。
- [x] 主代理(直接审计,无需子代理)：上限与渲染审计。

## 已提交 checkpoint

- [x] 已收口:userfeedback 勾选 [x],active link 已移除,任务关闭。


## 实现与验收记录

- 上限:8/64/32/256 → 16 分类/128 任务/256 清单每项/1024 清单总计;system contract 改为从常量插值,消除文本与常量漂移(任务43的暴露页同步生效)。
- 忠实渲染:预览的清单项原来全部塞在单个 List 行的 VStack(150 项≈6600pt 巨型行,布局/滚动崩溃),拆为独立 List 行(与任务43开关拆行一致),150 项可滚动渲染。
- 创建后 app 直接 `openTaskDetail(firstRootTaskID)` 打开新任务(本次反复调试的最终结论)。
- 测试:服务级 150 项 makeDraft 接受;协调者级 150 项原子创建(含 Chapter 150 与 150 个 visual);iPhone/iPad 端到端 UI(大 fixture:预览滚到 Chapter 150 → 创建 → 断言详情标题/分类);既有上限边界测试随常量自适应。
- macOS:该 UI 场景按既有惯例以模拟器验收,创建逻辑由 macOS 协调者单测覆盖。