# 11：Checklist 完成动画与自动下沉实现记忆

> 本文件只保存实现、验证和子代理编排记忆，不是任务来源。范围与完成状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中唯一的 `[~]` 项。

## 当前阶段

- [~] 领取“勾选 checklist 加动画，完成内容自动移动到最下面”的反馈并建立活动链接。
- [ ] 审计所有 checklist 展示入口、完成命令、持久化排序与现有测试。
- [ ] 实现并验证完成/取消完成时的状态反馈和稳定排序。
- [ ] 在 owned 模拟器完成普通路径与 simulator-only 截图验收。
- [ ] 执行 Release 全设备安装、签名/版本核验与资源清理。
- [ ] 由 Codex 在唯一任务来源标记完成并移除活动链接。

## 反馈边界

- 点击 checklist 完成控件时提供短促、清晰且可取消的状态变化动画。
- 已完成条目自动显示在未完成条目之后；不臆造新的手动排序规则，先以现有持久化顺序语义为准。
- 覆盖现有 checklist 可见入口，不把同一数据在不同页面表现成互相矛盾的顺序。
- 只处理 `Docs/userfeedback.md` 当前 `[~]` 项，不领取后续反馈。

## 验收清单

- [ ] 定位 checklist 行、完成动作、排序字段与所有展示入口
- [ ] 明确完成、取消完成、连续快速点击及跨刷新后的顺序语义
- [ ] 使用原生 SwiftUI 动画与稳定 `ForEach` identity 完成实现
- [ ] 覆盖排序/持久化语义的单元或契约测试
- [ ] 在 owned iPhone/iPad 模拟器验证普通交互并适当截图
- [ ] 运行 `CONFIGURATION=Release scripts/build_install_all.sh`
- [ ] 核验安装版本与签名，清理 owned 设备、进程和临时产物
- [ ] 由 Codex 在 `Docs/userfeedback.md` 标记完成并移除活动链接

## 实现约束

- 采用 Apple HIG 的目的性、短促动作反馈；避免装饰性或阻塞式动画，并尊重系统 Reduce Motion 行为。
- 复用现有 checklist 控件、命令与排序服务；优先原生 SwiftUI `Button`、`withAnimation`、transition/符号效果，不新增重复组件。
- `ForEach` 必须保持持久稳定 identity；不能用数组索引或可变内容作为 identity。
- 不新增 Liquid Glass；保留正式 Apple Developer 签名。
- 所有验收截图仅来自 owned 模拟器；物理设备只执行规定的 Release 安装，不启动、不操作 UI、不截图。

## 子代理编排

- [ ] 数据模型、命令、持久化排序语义独立审计。
- [ ] SwiftUI checklist 展示入口、动画边界与跨平台一致性独立审计。
- [ ] 现有测试覆盖、可复用测试夹具与模拟器验收路径独立审计。

## 运行资源所有权

- 尚未创建 Task 11 owned 模拟器。
- 不触碰 `AnalyticsReview-iPhone17Pro` 或其他未由 Task 11 创建的设备/进程。

## Checkpoint 记录

- [~] 当前 checkpoint：领取反馈、建立实现记忆与活动链接。
