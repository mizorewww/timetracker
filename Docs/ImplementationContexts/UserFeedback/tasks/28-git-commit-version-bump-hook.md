# 28：每次 Git commit 自动递增版本实现记忆

> 本文件只用于主代理与子代理的实现、验证和编排记忆，不是任务来源。唯一范围与状态必须重新读取
> [`Docs/userfeedback.md`](../../../userfeedback.md) 中对应的 `[~]` 条目。

## 当前阶段

- [x] 领取反馈，审计现有 hook、版本字段、安装包版本展示与失效根因。
- [x] 确定不会递归提交、不会丢失用户变更且能在每个成功 commit 中生效的版本递增契约。
- [x] 实现 hook 与自动化回归，在隔离仓库中证明连续 commit 连续递增。
- [x] 精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`，标记反馈完成并移除活动链接。

## 唯一反馈边界

- 每次 `git commit` 都必须自动递增 App 版本，让测试包能直接辨认具体构建版本，不能只依赖 commit hash。
- 不领取 Live Activity、主页统计图、Apple Health 或后续任何反馈。

## 强制约束

- 先审计仓库已有 hook 安装机制、版本源与 Xcode build settings；不建立第二套互相竞争的版本系统。
- hook 必须适用于普通提交与本代理的小 checkpoint，不得形成递归 commit，不得暂存或改写无关用户文件。
- 验证必须在隔离的临时 Git 仓库/工作树完成，不污染真实历史；验证后删除全部临时资源。
- 每个小 checkpoint 验证后提交；只暂存本任务状态差异，保护 `Docs/userfeedback.md` 中其他用户新增内容。

## Checkpoint 编排

- [x] Checkpoint A：现有 hook、安装入口、版本字段与失败模式审计。
- [x] Checkpoint B：修复实现与隔离连续提交回归。
- [x] Checkpoint C：Release 全设备安装、版本只读核验与收口。

## Checkpoint A 审计结论

- 直接根因不是递增算法损坏，而是当前 clone 从未设置 `core.hooksPath`；Git 实际寻找不存在的 `.git/hooks/pre-commit`，`git hook run/list pre-commit` 均证明没有可执行 hook。最近多次真实提交因此一直停在 `1.1.52 (107)`。
- 仓库中的 `.githooks/pre-commit` 与 `scripts/bump_marketing_version.sh` 均存在、可执行且语法正确；唯一安装说明要求每个 clone 手动运行 `git config core.hooksPath .githooks`，没有可重复的 installer/check 入口。
- 旧 hook 直接 `git add` 整个 `project.pbxproj`，会把该文件的未暂存用户修改一并带入 commit；若 hook 已 bump 后 commit-msg 等后续步骤失败，重试还会再次递增。
- App、Widget、Live Activity 与 Watch 的 12 组 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 均来自同一 Xcode project，Settings/About 和所有安装包都消费这些字段；不需要第二套版本源。
- 外部成熟工具审计：Lefthook 约 8.5k stars 且活跃，是未来多 hook 场景的首选；pre-commit 约 15.3k stars 但会引入 Python 环境及“修改文件则本次失败”的流程；Husky 约 35.2k stars 但会给纯 Swift 仓库强加 Node/package.json。三者仍需每个 clone 安装一次，无法消除 Git 的信任边界。
- 本任务不新增第三方依赖，复用 Git 官方 `core.hooksPath` 与仓库已有 shell hook。Apple `agvtool` 需要迁移到 `apple-generic` 且当前工程的生成式 Info.plist 只读检查异常，不在本反馈内扩大迁移风险。

## Checkpoint B 实现与验证

- 新增幂等 `scripts/install_git_hooks.sh`：当前 clone 已安装并通过 `--check`；`core.hooksPath=.githooks`、resolved pre-commit 与 `git hook list --show-scope` 均确认 Git 会执行 tracked hook。`AGENTS.md` 要求每个新 clone 在首个 checkpoint 前安装并复核。
- pre-commit 改由 `scripts/stage_commit_version.sh` 处理版本。下一版本始终从 `HEAD` 计算，因此同一次失败 commit 多次重跑得到同一目标版本，不会连续虚增。
- 脚本从当前 index blob 保留所有已暂存 Xcode 工程修改，只替换版本字段后用 `hash-object` / `update-index` 更新 index；工作树仅同步版本字段，所以其他未暂存工程修改既不会丢失，也不会泄漏进 commit。
- `scripts/test_versioning_hooks.sh` 在隔离 HOME 的临时 Git 仓库中安装真实 hook，验证两个普通 commit、`--allow-empty`、真实 commit-msg 失败后重试、project 已暂存/未暂存混合修改、12 组配置一致与 `--amend`；正常版本从 `1.1.52 (107)` 连续到 `1.1.58 (113)`。
- 旧的 `SKIP_VERSION_BUMP` 逃生口已删除，符合“每次 `git commit`”的反馈；Git 自身仍允许显式 `--no-verify` 绕过客户端 hook，因此最终 Release 必须核对 bundle 版本。
- index 与工作树版本只允许处于 `HEAD` 或已准备的 `HEAD+1` 状态；手工分叉或字段不一致会在修改用户文件前失败，隔离回归确认拒绝后 `9.9.99 (999)` 原样保留。
- 第一轮测试唯一失败是 diff 上下文行被误判为脏版本字段；改为直接比较 HEAD/index/working tree 后全量重跑通过。临时仓库已自动删除，无测试目录、设备、simulator 或进程残留。
- 新增脚本均通过 `bash -n`，仓库 diff 通过 whitespace check；本机未安装 ShellCheck，未把该项误报为已执行。下一次真实 checkpoint commit 本身将作为当前 clone 的端到端 hook 验证，并应从 `1.1.52 (107)` 递增到 `1.1.53 (108)`。

## Checkpoint C Release 与收口

- 实现 checkpoint `f71164d` 的真实 commit 已由安装后的 hook 自动从 `1.1.52 (107)` 递增到 `1.1.53 (108)`，证明当前 clone 的普通提交链路会执行 tracked hook。
- 为保证最终收口 commit 与已安装测试包版本完全一致，先通过 `git hook run pre-commit` 幂等预备 `1.1.54 (109)`，再精确执行 `CONFIGURATION=Release scripts/build_install_all.sh`；脚本成功完成 iOS Release（包含 Watch companion）、物理 iPhone 安装、macOS universal Release 构建与 `/Applications/timetracker.app` 安装。
- iOS App、嵌入式 Watch App 与 macOS App 的 Info.plist 均只读确认为 `1.1.54 (109)`；三者 `codesign --verify --deep --strict` 均通过，标识符分别为 `me.mezorewww.timetracker`、`me.mezorewww.timetracker.watchkitapp`、`me.mezorewww.timetracker`，TeamIdentifier 均为 `LT98S43NKA`。
- macOS 主二进制经 `lipo -archs` 确认为 `x86_64 arm64`；物理 iPhone 通过 `devicectl device info apps` 只读确认为已安装 `1.1.54 (109)`。未启动、点击或截图物理机 App；当前没有可直接安装的物理 Watch，故仅验证签名有效的嵌入式 Watch companion，并保留系统配对自动安装路径。
- Release 产物核验后删除 `build/Install`，并确认无本批次 `xcodebuild`、`xctest`、UI runner、Instruments/trace 进程及 Booted simulator 残留。最终 commit 的 pre-commit 对已预备版本保持幂等，不会额外跳到下一版。
- 本任务没有新增第三方库：继续使用 Git 官方 hooks / `core.hooksPath`、Xcode build settings 与仓库 shell 自动化；外部工具仅作为方案审计，没有引入依赖。
