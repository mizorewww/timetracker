# 85：macOS 快捷键设置实现记忆

Status: Complete

状态：2026-07-28 已完成

> 本文件是主代理与子代理的实现、验证和编排记忆；唯一任务来源仍是
> [`Docs/userfeedback.md`](../../../../userfeedback.md) 中对应的 `[x]` 条目。

## 认领的反馈条目

- macOS 设置中增加快捷键设置。
- 为适合键盘操作的常用时间管理动作绑定快捷键。

## 初始范围

- 审计现有 macOS `Commands`、菜单动作、设置结构、焦点/场景路由和偏好持久化边界。
- 依据 Apple HIG 选择少量高频、可发现、无冲突的动作；系统保留快捷键不可覆盖。
- 评估原生 SwiftUI/AppKit 能力与成熟快捷键录制库，优先复用可靠方案。
- 保持 iPhone、iPad、Watch 行为不变。

## UI 验收清单

- [x] macOS 设置提供清晰的快捷键分区和录制/重置交互。
- [x] 菜单中显示当前生效快捷键，设置变更无需重启即可生效。
- [x] 重复、系统保留或无效组合有明确且本地化的反馈。
- [x] 默认快捷键覆盖最有价值的常用动作，不抢占标准编辑和系统快捷键。
- [x] 普通字号下完成 macOS 自动化断言与截图验收。

## 测试优先清单

- [x] 先为快捷键默认值、持久化、冲突规则和命令触发边界补失败测试。
- [x] 实现后跑定向测试、完整 `make test`、格式与本地化门禁。
- [x] macOS UI 自动化和截图验收。
- [x] 清理自有资源。
- [x] `make build-install-all` 安装最终任务版本。

## Checkpoint 编排

- [x] A：完成现有架构、HIG、库与测试边界审计。
- [x] B：新增先失败的快捷键策略和命令边界测试。
- [x] C：实现设置、持久化与动态菜单绑定。
- [x] D：完成 UI、全量、截图、Release 全设备安装与关闭。

## 库策略

- 首先核对 SwiftUI `Commands` / `keyboardShortcut` 与 AppKit 菜单 API 是否足以支持动态
  用户配置。
- 如果需要可靠的快捷键录制、校验和持久化，优先评估维护活跃且超过 1k stars 的成熟库；
  不为录制器、键码映射或菜单同步重复造轮子。
- 任何新增依赖都记录版本、维护状态、stars、许可证和选择理由。

### 审计结论

- 继续使用 SwiftUI 原生 `Commands` / `keyboardShortcut` 作为应用内触发与菜单可发现性
  边界，只把录制、键码转换和冲突检查交给成熟库。
- `Command-N` 继续作为标准“新建”菜单快捷键，不开放改作其他用途；开放四个时间管理
  动作：添加时间、开始选中任务、开始番茄钟、刷新数据。`Command-1...5` 导航与
  `Command-,` 设置同样保持固定。
- 快捷键属于设备与键盘布局偏好，写入设备本地 `UserDefaults`，不进入 SwiftData /
  CloudKit 同步模型。
- 选择 Sindre Sorhus 的 `KeyboardShortcuts 3.0.1`：
  - GitHub 约 2.7k stars，172 commits，审计时 1 个 issue / 0 个 PR；
  - MIT 许可证，支持沙盒与 Mac App Store；
  - 精确锁定 `3.0.1` / `49c3fc04ea827f816df67843bfcc57286b47ff06`；
  - 提供绑定式 `Recorder`、SwiftUI 快捷键转换、菜单/系统冲突策略和中英文资源。
- 本项目的应用 target 同时构建 macOS 与 iOS。Xcode 的 framework 平台过滤仍会把远程
  包放入 iOS 依赖图，因此用本地 `MacKeyboardShortcuts` Swift Package 适配层表达
  SwiftPM 官方 `.when(platforms: [.macOS])` 条件；适配层不实现录制或键码逻辑。
- 库的命名录制模式固定写 `UserDefaults.standard`，不满足测试 host 隔离，所以设置界面
  使用库提供的 binding 型 `Recorder`；项目只负责通过 `AppDefaults.shared` 保存一个
  4 KiB 上限的原子 Codable blob。
- blob 中缺少动作表示继承默认、`disabled` 表示显式清空、`custom` 表示覆盖；未知动作
  前向兼容地忽略，未知 schema、损坏、超限、不可表示、重复或撞固定组合则整体安全回退
  默认，并且读取路径不回写。

### 验证边界

- 命令边界测试：默认值、显式清空、覆盖持久化、重置、损坏数据回退、重复冲突。
- macOS UI 测试：设置分类、录制器、重置、菜单实时显示与动作触发，普通字号截图。
- 多平台回归：macOS 与 iOS 签名构建；任务关闭前跑完整 `make test` 与
  `make build-install-all`。

## 子代理编排

- 主代理负责范围、活动记忆、集成、测试、设备安装和提交。
- 子代理只在有独立审计价值时参与；不得并发运行 Xcode 构建或修改主代理正在编辑的文件。

## 进度记录

- 2026-07-28：按反馈顺序认领任务，建立 `~85` 活动实现记忆并进入 Checkpoint A。
- 2026-07-28：完成 HIG、SwiftUI、现有命令/设置/偏好架构和第三方库审计；精确锁定
  `KeyboardShortcuts 3.0.1`。直接链接时 iOS 构建按预期失败，加入仅声明平台条件的
  本地 Swift Package 适配层后，`make build-ios` 与 `make build-macos` 均成功。
- 2026-07-28：Checkpoint B 先看到新增 suite 因实现类型不存在而失败，再完成设备本地
  命令边界与原子偏好存储。定向 suite 覆盖四项默认、显式清空、跨实例加载、重置、
  损坏/超限回退、动作重复、固定组合和无修饰字母拒绝；标准 `Command-N` 按 HIG 固定。
- 2026-07-28：Checkpoint C 完成 macOS Settings 分类、四个 binding recorder、三语文案、
  恢复默认和 SwiftUI `Commands` 动态绑定；应用根向主场景、Settings 和 Commands 注入同一
  设置实例，revision 变化立即重建菜单。普通字号 XCUITest 1/1 通过，`runtimeWarnings`
  为空；Settings 与 File 菜单截图目视复核通过，实际 `Shift-Command-M` 成功打开添加时间。
  库的原生 `NSSearchField` recorder 不把内部清除按钮独立暴露给 XCUITest，合成按键也不会
  进入其本地 `NSEvent` monitor，因此自动化不伪造录制测试后门：自定义/清空/重置和冲突由
  9 个真实命令边界测试覆盖，UI 冒烟负责 recorder、菜单可发现性和真实 focused-scene 触发。
- 2026-07-28：最终格式门禁 0/849、本地化 9/9、完整 `make test` 1456 tests /
  163 suites、`make build-ios` 与 `make build-macos` 全部通过；实现 checkpoint
  `d87f10be` 已提交并自动提升到 `1.1.301 (356)`。
- 2026-07-28：Release `make build-install-all` 通过。iOS 主 App 与嵌入 Watch companion
  签名有效，已安装到实体 iPhone Air 和 iPad Pro M4；当前没有独立可见的实体 Apple Watch，
  companion 由 iPhone 的 Automatic App Install 管理。通用架构 macOS App 已签名、复制到
  `/Applications/timetracker.app` 并通过 designated requirement 校验。测试 App 已终止，
  未创建模拟器；任务关闭时移除 `~85` 活动链接。
