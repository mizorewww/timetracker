# 30：主页统计图与说明层级实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [~] 领取反馈，审计主页统计图、渐变、标题位置与全部说明文字入口。
- [ ] 依据 Apple HIG、SwiftUI 规范与成熟系统组件制定信息层级和自动化验收契约。
- [ ] 实现统计卡片与 info 二级菜单，补齐定向测试和完全脚本化截图验收。
- [ ] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- 主页统计图避免滥用渐变色。
- 把统计图标题移到卡片外。
- 将说明文字改得清楚，并把主页的各类说明统一放到 info 二级菜单。
- 不领取 Apple Health、首页 heatmap/柱状图拆卡或其他后续反馈。

## 强制约束

- 完整遵循仓库本地 `apple-hig` 与 `swiftui-expert-skill` 已读取规则；优先使用 Apple SwiftUI、Swift Charts 与系统菜单/弹出层。
- 如评估第三方库，必须先核验维护质量与 GitHub stars；除用户建议外不采用少于 1k stars 的库。
- 所有交互与截图验收写成 XCTest/XCUITest；只使用有明确所有权的模拟器，不手动调整窗口，不在物理设备启动、点击或截图。
- 每个 checkpoint 只暂存本任务变更，保护 `Docs/userfeedback.md` 中其他用户新增内容。

## Checkpoint 编排

- [~] Checkpoint A：范围领取、现状/依赖/HIG 审计与自动化验收设计。
- [ ] Checkpoint B：最小实现、定向单元/UI contract 与脚本化视觉验收。
- [ ] Checkpoint C：Release 全设备安装、签名/版本只读核验与收口。

## 资源所有权

- 当前无 simulator、build、TestManager 或 Instruments 批次；后续每个批次在此记录名称和 UDID，并在 checkpoint 前完成终止、关机、删除与进程核验。

## 编排记录

- 待填写：相关视图、重复说明来源、Swift Charts 现状、系统二级菜单方案与测试入口。
