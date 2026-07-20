# 05：Inbox 人工归类实现记忆

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- 三条人工入口、共享 picker、领域 command 和 LLM 共用落地核心已经完成静态审计。
- 已修复 picker 打开期间 AI 建议、纯排序或同逻辑 CloudKit winner 替换导致人工选择被误拒绝的竞态。
- 正在补齐领域边界证据；下一阶段是 iPhone、iPad、macOS 普通路径与截图验收。

## 实现边界

- 人工入口必须覆盖归入 category、归入 task、作为 task checklist 三种目标。
- 选择目标前不修改数据；成功后 Inbox 条目只能被消费一次，失败时保留原条目。
- 排除不可用或会形成非法层级的目标，并处理目标在确认前被删除或归档的情况。
- iPhone 使用适合紧凑宽度的单一模态流程；iPadOS/macOS 保留上下文并支持指针、键盘选择。
- 不处理 `Docs/userfeedback.md` 中后续的选择器视觉统一、归档语义或详情编辑任务。

## 验收清单

- [x] 盘点模型关系、持久化约束、LLM 建议 command 与 Inbox UI
- [x] 建立人工归类 command 的领域测试和失败回滚测试
- [x] 实现三种人工归类入口并复用既有选择组件
- [ ] 验证 iPhone、iPad、macOS 普通交互路径并截图
- [ ] 运行 `CONFIGURATION=Release scripts/build_install_all.sh`
- [ ] 核验安装版本与签名，释放 owned 设备、进程和临时产物
- [ ] 只在 `Docs/userfeedback.md` 标记完成并移除活动软链接

## 依赖策略

- 优先使用 SwiftUI、SwiftData 与项目现有选择器/command。
- 如确需第三方库，先核对维护状态、许可证、平台兼容性和至少 1k GitHub stars；
  没有明确收益则不新增依赖。

## 子代理编排

- 已完成：领域审计确认三条人工路径与 LLM 复用 `createRouteDestination`，并定位逻辑 identity 竞态。
- 已完成：UI/HIG 审计确认继续使用行内 `Menu`、场景级单一 sheet 和两个现有共享 picker。
- 已完成：测试审计确认三路行为、重复消费、目标失效与原子回滚基础覆盖；补充分类 assignment 回滚和 picker 资格语义。

## Checkpoint 记录

- `41babb9`：修正 `parentEligibleTaskIDs` 的过期 UI 契约，单测 1/1。
- `a357333`：保留人工归类意图；新增 AI 落地、纯排序、逻辑 winner 替换三个竞态测试，manual-route suite 12/12。
