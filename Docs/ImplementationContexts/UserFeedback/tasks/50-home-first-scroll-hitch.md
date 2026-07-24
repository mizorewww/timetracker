# 50：主页首次快速滑动卡顿实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取“主页在首次快速滑动的时候,有时会卡顿”反馈。
- [x] 审计主页(PhoneHomeView)首屏各 section 的加载/刷新链与懒加载策略,定位首次滚动卡顿根因。
- [x] 必要时用 Instruments(Time Profiler,模拟器)取证。
- [x] 实现最小修复并运行聚焦测试与模拟器验收。
- [ ] 执行 `CONFIGURATION=Release scripts/build_install_all.sh`(实体机安装失败不阻塞),标记完成并移除活动链接。

## 唯一反馈边界

- 只优化 Today 主页首次快速滑动的卡顿;不改视觉与语义。
- 不领取 AI 生成上限、iCloud 冲突或其他反馈。
- 以普通文字大小、正常交互路径、三平台系统约定为优先。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill`;所有 UI 导航、断言与截图只用 XCTest/XCUITest 脚本;Instruments 只读取进程数据。
- 实体机器不做测试;模拟器验收后 shutdown+delete 并清理 /tmp 产物。
- 优先复用 SwiftUI 性能模式(Lazy 容器、身份稳定、热路径瘦身);除用户建议外不引入 GitHub 少于 1k stars 的库。
- 每个 checkpoint 只暂存本任务的已完成变更;保留用户在反馈文件中的其他内容。

## Checkpoint 编排

- [x] Checkpoint A：领取任务、创建实现记忆与 active link。
- [x] Checkpoint B：审计首屏加载链与热路径,必要时录 trace。
- [x] Checkpoint C：实现修复并补齐聚焦测试。
- [x] Checkpoint D：模拟器验收与资源清理。
- [~] Checkpoint E：Release 构建安装、核验与收口。

## 资源所有权

- [~] 主代理：任务状态、编排、集成、所有 build/simulator/XCUITest/screenshot/Release 批次与清理。
- [x] `task50_home_perf_audit`(只读)：主页热路径审计。

## 已提交 checkpoint

- [~] 待提交：领取任务、实现记忆与 active link。


## 审计与实现记录(task50_home_perf_audit)

- 根因:① heatmap 全年快照在主线程同步计算(首次滚入/每分钟/每次 sync);② 重算期间 section 退成 ProgressView 造成行高抖动;③ 每图 371 个 cell 级无障碍元素(每格一次完整日期格式化)。
- 修复:快照服务异步化 + 重循环/逐任务 `Task.yield()` 协作让出(遵循项目"worker 不持有持久模型"约束,不走 detached 模型引用);section 重算期间保留旧快照(stale-while-revalidate);chart mark 级 `.accessibilityHidden(true)`(卡级已有摘要)。
- 未做(记录在案):timelineSnapshot 每次 body 评估对全历史 session 分组(section 与 chart 各算一次)与 TodayHomeContent 每次评估重建 —— 量级次之,留作后续。
- [x] heatmap 四个套件(Tests/Recurrence/Refresh/UIContract)全绿;iPhone/iPad/macOS heatmap 两项 UI 验收通过。
- [x] 未录 Instruments trace:静态证据已闭环(主线程同步调用点 + 行高抖动路径),修复不依赖计时断言。