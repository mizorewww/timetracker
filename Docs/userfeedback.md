# Timetracker 交互问题

Note: 所有由codex完成的清单应该让codex自己勾选,如果有新的问题,直接在列表下面添加
Note: 鼓励使用模拟器等测试资源,但每次使用资源之后一定要释放
Note: `[~]` 表示 Codex 当前正在处理；本文件是任务内容和状态的唯一来源

- [x] Bug: 点击任务详情/Task Analysis,切换 day/week/month 会跳到页面顶部,预期:不应该移动,因为用户本意是停在这里查看相关数据
- [x] UI: Today/Now 的正在计时界面的排版很糟糕
  - [x] 1. 分割线层级不对,左右间隔应该一致
  - [x] 2. 我建议把时间放在较为左侧,应该是(icon)(较大的字体的任务名,下方较小字体的path)(时间,高度要等于前面的元素)(停止按钮) 2.1 如果path过长,建议改为/aaa/.../bbb/task这样的模式,如果还是过长,只显示首个字符
  - [x] 3. Today/Quick Start排版依旧很糟糕,建议复用Now里面的组件,Running标记不必出现,因为后面有start/stop按钮
- [x] UI: Tasks界面的Category的长度不对,右侧有奇怪的空白(或者说,它和卡片的右侧结束对不上)
- [x] UI: ipad 的标题应该自动出现在顶部,目前状态:和页面在一起,并且上滑也没有预期的标题出现在顶部
- [x] UI: ipad 侧边栏的任务有奇怪的缩进,我发现/下的任务前面还会有缩进,不应该有的
- [x] UI: Timeline 建议从中间开始排版,居中设计,这样看起来视觉更好.
- [x]  UI: 主页任务卡片的三点二级操作按钮,依旧排版的很奇怪,我认为没有和最右侧元素的结尾对其(实际上这是我第二次提到奇怪的spacing问题了)
- [x] UI: timeline实际上我没看到它显示开始时间,这不对
- [x] UI: 在任务编辑的color&icon选择器中,iphone上展开了键盘,就把icon选择器完全遮挡了,我建议你把color做成二级菜单而不是这样的完全展开,请参考 https://github.com/Lakr233/BlossomColorPicker/
- [x] UI:Inbox请做成原生卡片的模式,然后现在排版很混乱,ai建议的图标也看不见.同时,适当加一些动画.
- [x] feature:建议AI可以生成category,tasks和checklist,并且把提示词暴露在设置里允许用户编辑
- [x] UI: Live activity也很怪异,建议和第二条UI对齐(除了不必做停止指示)
- [x] feature: Apple watch端目前没有办法新建计时(似乎是我开了一个计时之后,我就没办法新建计时了).我的设想是这样的,apple watch是一个三页的app,第一页展示active timer,第二页展示quick start,第三页则是完整所有任务
- [x] UI: 灵动岛的live activity堆砌元素过多,建议只有icon,任务名称和时间,并且这三个在同一行,之前的排版很糟糕
- [x] features: 把status完全删掉,这不是这个软件需要的语义,需要完成的语义应该被转移到任务的checklist
- [x] UI: Tasks界面把任务名称/计时状态/checklist完成状态全都堆在一起,这不好,我建议的排版是icon|任务名称\n checklist |space|(右对齐)计时状态(只用放一个图标即可)|时间|点进去的指示. 如果任务名称过长,就将任务名称单独放在一行(允许换行),下一行再排版其他元素.
  - [x] 这里也包含任务选择器,过于怪异了,首先,对于这个软件所有地方都是的,有了running 标志就不必有stop标志,反之亦然,因为这两个明明意思是一样的.
  - [x] 然后排版也很诡异,请仔细看一下
- [x] UI&Bug: quick start 的开始按钮,图标没有居中.并且,点击进入任务详情界面,退出来居然是tasks界面而不是today,这不符合“从哪里进去就从哪里出来的预期”
- [x] feature: 如果同一个任务两个计时段间隔小于一分钟,自动合并为一段
- [x] UI: analytics里面既然把difinitions单独开一个卡片,那么,就不用加info icon了,并且这个卡片可以做的更加详细
- [x] UI:Today界面,现在开始和暂停,ios上暂停没有文字,开始却有文字,请你在iphone上全部去除文字,ipad上全部保留文字
- [x] UI: Toady 界面,可以放一个累积时间的,本周的柱状图
- [x] UI: ipad上,正在计时的卡片去拉长适应空间,相当诡异,建议将其和概览合并成一行
- [x] feature: 接入healthkit,接入运动数据和睡眠数据,将其整合在timeline上,并且自动创建运动category下面的任务和日常category的睡觉
- [x] UI: Inbox任务卡片的排版非常灾难.请单独checkcircle和任务文字是一行,然后Suggested: icon | task,然后是左右两边的dismiss | add to task 的icon(在iphone上建议简化为打勾和打叉符号) 请截图并仔细思考如何排版
- [x] feature: Inbox 不仅得是LLM可以建议移动到task下/category下/作为一个task的checklist,用户自己也要可以这样选择
- [x] UI: 任务选择器的状态指示依旧没有统一样式,start another timer的正在计时和没有被计时图标大小和位置不一
- [x] feature: 统一删除和归档的语义,现在任务不允许删除,只允许归档,在设置中添加一个归档的任务的菜单,允许解除归档.同时,把为了实现删除功能写的代码全部删掉,全面审核,让软件的语义更加简单.然后task页面左滑快捷操作也把删除替换成归档
- [x] feature: 把快速操作的编辑去掉,统一任务的详情和编辑页面,仔细考虑如何排版.同时,软件备注使用https://github.com/Lakr233/MarkdownView.
  - [x] feature: 合并之后,自动保存,不用手动点击save
  - [x] feature: markdown可以展开编辑
- [x] bug: 任务详情现在看不到任务名称了
- [x] bug: 我看不到liveactivity和灵动岛了,或许是liveactivity单纯坏了或者是有条件能让它失效
- [x] UI: 任务详情的stop应该放在最上面的任务卡片里呀,为何没有复用.然后鉴于上面提到我们要合并任务详情和edit,所以add time放在本来的edit按钮哪里
- [x] UI: 勾选checklist加动画,同时完成的内容要自动跑到最下面
- [x] feature: Today界面,用户可以在设置里加上github那样的Heatmap,用户可以在设置里加上要上heatmap的任务.heatmap颜色深浅的数据来源可以是子任务完成数量.
  - [x] feature: 是否追踪heatmap应该在任务详情页面可以被打开,默认关闭
  - [x] feature: 此处的产品语义是: 每个任务都有单独的heatmap和heatmap配色方案(复用blossomcolor组件,有一个主题色和从深到浅的配色,深到浅每个配色的阈值的数值由max(每日任务时常)来决定)
  - [x] feature: 任务量任务可以由任务量来决定深色还是浅色
- [x] feature: 用户可以创建重复任务,和简单任务量任务: 比如一个真实案例: 每天做50个俯卧撑,这个任务就是一个父任务,父任务可以自动生成每天的子任务,一个子任务是一个50个俯卧撑的任务量任务
- [x] UI: Inbox的任务正文应该和checkcircle居中对齐.Suggested应该和checkcircle同一垂直线左对齐
- [x] UI: Quickstart 编辑页面逻辑不对,点击添加应该是任务有一个动画,直接跑到固定列表里面,下面就不显示了(或者做拖动手势)
- [x] UI:侧边栏: 正在计时的icon应该和图标在同一水平线上,现在并不是,同时两个任务上下之间有奇怪的spacing
- [x] UI: MacOS设置侧边栏固定展开,删除侧边栏展开状态切换按钮
- [x] Bug: 时间线将不同类型的睡眠拆成了多段,睡眠时间实际上应该合并
- [x] feature: 不应该在quickstrat里允许开始workout,应该用apple的健身app开始workout,workout应该是仅同步的,睡眠也一样
- [x] feature: 配置AI的时候,不同的AI提示词应该都可以被编辑
- [x] feature/AI: Tasks/Generate task plan,应该可以一次性让AI生成多个任务.这里的AI提示词,需要详细向AI介绍软件中的各种任务类型.最终预期效果应该是: 输入: 帮我生成一个读书任务,checklist里有1-10章,每一章的checklist. 然后就可以自动生成到某个category
  - [x] 这部分值得好好设计,请单独写文档
  - [x] 编辑提示词采用markdownview
- [x] Bug: Apple Health 类任务,应该自动显示在task里(虽然他们是特殊任务,只能从apple health同步,不允许开始计时,也不能在计时任务选择器里被选择)
- [x] Bug: Inbox中将任务勾选完成后没办法将其切换为没有完成的状态
- [x] UI/Bug: 目前手机上的任务,如果时间太短,没办法容纳图标,会向上拓展而非预期的向下拓展,这导致两个任务之间的timeline ciew 没有预期的spacing(实际上,算法应该是,如果两个任务的结束时间和开始时间在图上画出来小于某个阈值,那么就换一条轨道显示),并且也会遮挡可能有的 xxx min elapsed
  - [x] UI/Bug: ipad上任务也会挡住 xxx min elapsed. 请尝试生成大量时间重叠,时间短的小任务来查看各个平台的timeline效果
  - [x] UI/Bug: iphone上 xxx min elapsed现在(在尝试修复重叠问题后)会互相遮挡了,请全平台测试,把这个视觉搞搞好
  - [x] UI: 在codex尝试修改之后这个图变的非常的奇怪,一条彩色条的宽度都不够容纳图标,居然还敢说视觉通过,很诡异,这个时间条至少要把图标抱住还有padding,否则看起来非常丑还不能传递信息.以及现在用圆点在下面文字标注,实际上应该显示图标的
  - [x] UI: 目前的省略xxx分钟,胶囊宽度是固定的,导致无法容纳所有文字,建议将其抱住
- [x]: Bug/Dev: 现在git commit的hook似乎不往上bump版本了,这让测试缺乏在用什么版本的提示,只能靠commit hash来确定,这不好,请每次git commit都bump版本
- [x] UI: live acitivty 时间最右边有奇怪的spacing,排版也不够美观UI Note: 真人安装了codex的commit后,我的live activity彻底看不到了,能看到的时候也是黑框框,原先蛮好的
  - [x] UI: 不知道为什么,codex反而劣化了liveactivity的设计,请回滚到原来的设计.现在不仅没有解决问题,反而让排版错乱更严重了
- [x] UI: 主页的统计图不要滥用渐变色,把标题移动到卡片外,说明文字说的明白一点,放在info的二级菜单
  - [x] 主页的各种说明文字都放在二级菜单
- [x] Bug: Apple Health 类型任务, task详情,summary没办法显示过去所有时长,统计也没法看过去所有时间线
- [x] Bug: Apple Helth 任务可以被改变categty
- [x] Bug: apple health 任务似乎无法查看过去累积时间和过去时间段
- [x] UI: 首页不要把heatmap和柱状图混在一起,每个元素请单独做卡片
  - [x] UI: heatmap和柱状图的风格和原生卡片不一致
  - [x] UI: heatmap和柱状图的标题与主页其他标题字体不一致,卡片左右间距也不一致.
    - [x] 请写主页设计规范
- [x] feature: category的展开和收起
- [x] feature: category的排序
- [x] feature: 设置中heatmap的默认时间段长度选择(比如显示这一个月)(也就是高度有几日,现在的方块在iphone上有些略小)
- [x] feature/Bug: 任务量任务的heatmap逻辑有问题,如果是可以重复的任务,父任务下面的子任务负责记录多少个(时间),父任务显示heatmap.
- [x] feature: 任务详情页面,点击图标应该跳转到图标编辑页面
  - [x] UI: 现在图标右侧有奇怪的空间
- [x] UI: Analytics 界面,切换 Day/Week/Month 的时候会闪烁
- [x] UI: 番茄钟页面的卡片是自己画的,要么切换成原生,要么圆角和原生同步
- [x] feature/test: AI的三个提示词为什么只有一个是允许markdownview来preview?AI真的可以稳定实现完成自动化生成任务吗,请测试.(代码库完全私有,不必考虑api泄漏问题 deepseek api: sk-66f353878d3042c0a12915630e9a46b1 模型 deepseek-v4-flash) 我认为你写的提示词完全不正确,甚至都没有指定输出格式,并且还是zero-shot.(这种较为死板的任务不要使用zeroshot)请妥善设计harness.(或者你没有把完整提示词暴露给用户).以及,我觉得把sfsymbol完成发给AI并不是一个很昂贵的选择,因为这是低频任务.(还有,支持deepseek的CoT,对deepseek设计支持思考预算)(测试提示词:帮我生成 category阅读，下放一个任务：人工智能：现代方法，生成checklist 1-28,现在这个提示词是可以work的).现在的实现其实已经足够稳定,我只是希望逻辑能多给用户暴露,防止疑惑
  - [x] UI: 生成的plan开关重叠在一起了,请复用task详情里的UI.
  - [x] Bug: 在保存ai提示词的时候卡死
  - [x] Bug: 依然没有解决AI给出超级大json的问题,不知道为什么要限制各个组件的长度.限制长度是一个很糟糕的设计
  - [x] Bug: 在利用Inbox页面的生成任务功能的时候,我发现AI似乎没有办法插入任务?因为我已经有一个‘a’ Category,我让AI在 ‘a’ Category 插入任务,却生成了一个新的 a Category. 请让AI得知完整上下文,并且支持增删改查. (Note: 增删改查请当作工具一样调用,不要担心AI上下文不够(也就是不要限制提示词大小,现代的LLM通常有 >= 256K 的上下文))
- [x] Bug: task详情子任务,勾选完成后,跑下去没有动画,会让用户很疑惑
  - [x] Bug: 勾选完成后取消勾选,没有办法跑到原来的位置
- [x] Feature: iOS shortcut支持&文档(这个请开一个文件夹讲shortcut设计)
- [x] feature: quickstart要可以被排序
- [x] UI: ipad/mac上的Now界面和overview请和iphone同步,没有必要做ipad/mac和iphone之间的差异化设计,同时,由于ipad/mac屏幕更加宽,所以把overview和now放在同一行(也就是Now|overview 而不是iphone上的 now \n overview)
- [x] UI: heatmap 在分析页面也放一份
- [x] code: inbox和task详情的checklist尽量复用
- [x] performance: 主页在首次快速滑动的时候,有时会卡顿
- [x] Bug: 提示生成的计划含有过多分类,任务或者清单项,软件应该忠实渲染,同时,我尝试在一个任务下面生成150个checklist然后失败了
- [x] Bug: 目前总是提示icloud冲突,可merge的应该优先merge,实在冲突再提示选择副本
- [x] UI: 生成任务展示模型目前输出了多少token,让用户知道是否卡死
- [x] UI/debug: AI生成任务界面可以查看CoT和原始输出
- [x] Bug: 现在启动MacOS 干净的 Release App 不知道为什么会让测试数据覆盖icloud(结合下一条) 让 release 构建不要混入测试数据, make build_install_all 也要默认release config
- [x] Bug: 可能是某次不小心把测试数据写进正式运行的app里了,inbox里老是出现莫名其妙的first,把这个删掉,同时搜索其他类似的测试数据,以后测试数据要放在一起,不可以干扰app运行
- [x] UI: 尽量少搞platform specific的ui，是否渲染iPhone界面根据宽度决定。建议全量审查一次代码，和平台相关的代码能删就删
- [x] Bug: 当你在停止一个任务的时候,的确停止了,但是主页上的timeline显示没有正确停止
- [x] Bug: 任务里的apple health显示消失了
- [x] UI: apple health任务在任务详情只留下摘要,任务分析和最近记录,其他都不要显示(其他都是给普通任务用的)
- [x] UI: ipad/macos上的today上面的heatmap和柱状图组件似乎无法自适应过宽的宽度
- [x] UI/Bug: 若主页上timeline第一个是apple health,第一个apple heath时间显示会和图表重叠
  - [x] Note: 此处建议apple heath和普通任务复用显示方案,否则老容易出bug
- [x] UI: iphone上timeline的时间标注在重叠任务较少的时候没有左对齐(可能是设计出来为了避让xxx min skipped,但是实际上应该左对齐)
- [x] UI: 在宽度较宽的设备上,现在和概览的开始高度不一致
- [x] UI: 宽度较宽的设备的主页排布浪费空间,建议自动排布
- [x] UI: Mac上的设置,图标没有居中.大小也不合适
- [x] Bug: 在设置了heatmap的range后,heatmap并没有自动变大来适应所有显示空间.实际上现在的heatmap单个瓷砖有点过于小了
- [x] UI: Gross Time 的柱状图配色很难看,其实可以是两个,一个gross一个wall
- [x] UI: Overview的gross 和wall time下方有奇怪的空间
- [x] UI: 侧边栏的分类图标和文字都太小了
- [x] UI: Mac App的各种字体都有些小
- [x] feature: apple health 软件维护单独的自己的数据库,可以被同步(但不能被修改).设置里的导出json也可以导出
- [x] UI: 分析页面复用主页的时间段编辑组件，否则没有办法删除和修改过去的时间段，任务详情页面同理
  - [x] 实际上时间段编辑应该单独做UI
- [x] AI: 目前timetracker的提示词不足，ai容易混淆子任务和checklist
- [x] UI: 多引入直接拖拽排序而不是排序按钮（现在任务子菜单不点击排序也可以拖拽排序了，所以排序代码属于冗余代码，删掉。
- [x] UI: 任务checklist删除图标变成二级菜单和左右滑动的操作
- [x] bug：因为任务的ai自动推荐机制，一次如果在变动任务的时候ai预测图标，输入会直接被打断，并且每次改变会让任务无限重复预测
- [x] UI: 任务checklist 的图标没有居中,并且不支持超长checklist,并且checklist文本显示应该从中间
- [x] UI/Bug: Mac上的Blossom Color Picker 出现在意外的位置
- [x] feature: Mac 在设置里加上快捷键设置,适当绑定快捷键
- [x] Bug: 总是提示 apple health returned a record that could not be stored safely






# 一、性能审查

## 1. P1：提交后的同步主线程管线过长

当前关键写路径为：

```text
用户命令
  → SwiftData 原子事务并提交
  → StoreRefreshPlanner
  → StoreRefreshCoordinator
  → 各领域读模型刷新
  → Live Activity / Widget / Watch 投影
  → 同步冲突快照捕获、fingerprint、状态文件保存
  → NotificationCenter 广播
  → 方法返回
```

`TimeTrackerStore` 是 `@MainActor @Observable`；`perform` 在事务完成后直接调用 `finishCommittedMutation`。后者依次执行刷新、`recordLocalSyncSnapshotIfNeeded` 和广播。`StoreRefreshCoordinator` 本身也是 `@MainActor`，会串行刷新任务、账本、番茄钟、偏好、清单、Inbox、Rollup，再执行系统投影。

同步快照路径还会：

* 获取新的 store context；
* 获取独占状态访问；
* 按领域捕获快照；
* 计算 fingerprint；
* 递增 generation；
* 保存同步状态文件。([GitHub][2])

### 影响

第一，用户点击 Start、Stop、编辑记录等操作的同步尾延迟，不只包含数据库提交，还包含刷新和同步保护工作。

第二，系统投影失败和业务提交失败没有真正隔离。当前设计正确地不会把“提交后刷新失败”误报成业务写入失败，但数据已经提交、同步 sidecar 快照尚未成功时，这条路径只设置 `errorMessage`。我没有在该路径看到一个与提交对应、可持久恢复的 pending-work 标记，因此不能证明失败一定会被后续事件补偿。

第三，所有刷新阶段在同一个 Actor 上串行化，局部 CPU 峰值会直接转化为 UI hitch。

### 建议

将提交后工作分成三层：

```text
A. 事务内
   数据写入 + 产生 MutationReceipt

B. UI 关键路径
   只更新当前可见的最小投影，例如 active/today/task row

C. 可恢复异步投影
   sync snapshot / analytics / widget / watch / live activity
```

`MutationReceipt` 至少应包含：

```swift
struct MutationReceipt: Sendable {
    let events: Set<DomainEventRecord>
    let affectedIDs: Set<UUID>
    let affectedRanges: [DateInterval]
    let generation: UInt64
}
```

可优先利用项目已经使用的 persistent history transaction/token 作为持久工作来源。后台投影处理器必须是幂等的，并在启动时恢复未处理 generation。只有当前可见读模型需要阻塞用户命令返回。

**相关但容易遗漏：** `StoreMutationBroadcaster` 使用进程内通知广播 mutation。多 Scene 环境下应检查接收方是否会在通知回调内立即同步刷新；否则一次用户操作可能叠加多个 Scene 的刷新成本。([GitHub][3])

---

## 2. P1：前台激活和远端导入仍走全量历史刷新

`refreshForForeground()` 首先调用 `refreshQuietly()`，后者调用无参数 `refresh()`；而无参数 `refresh()` 固定生成 `.fullSync` 计划。`.remoteImportCompleted` 同样直接映射为完整 refresh scope。([GitHub][4])

全量 Ledger refresh 会：

1. 查询 active segments；
2. 查询今天的 segments；
3. 调用 `allSegments()`；
4. 对所有 segment 排序；
5. 重建 ID、snapshot、array index、day、task、session 等索引；
6. 全量查询 sessions；
7. 触发 Rollup 全量重建。

远端变化虽然做了 350 ms 合并，但合并后仍发出 `.remoteImportCompleted`，所以它降低的是频率，不是单次成本。([GitHub][5])

### 静态复杂度

令：

* `S` 为历史 TimeSegment 数；
* `T` 为任务数；
* `C` 为清单项数。

一次 full refresh 至少包含：

```text
allSegments 去重、过滤、排序：O(S log S)
Ledger 多索引构建：          O(S)
Rollup 历史重建：            O(S + T + C)
内存：                       O(S + T + C)，但常数较高
```

内存常数较高是因为同一 segment 同时存在于：

* SwiftData model 数组；
* `segmentByID`；
* `segmentSnapshotByID`；
* `segmentArrayIndexByID`；
* day/task/session ID 集合；
* Rollup 的另一份 snapshot/index 结构。

这不一定在 50,000 条记录时立即出问题，但它会使前台恢复和 Cloud import 的峰值 CPU、分配量及内存带宽成为尾延迟上限。

### 测试覆盖的边界

仓库确实有 50,000 条记录性能测试，但文档明确说明，当前 `<0.25s` 的预算针对的是**单记录增量刷新**，只是测试环境中的回归告警，不是真机 SLA；文档也明确要求 Release 真机 Instruments 才能证明流畅性。它不能证明 foreground full refresh 或 remote full import 的性能。([GitHub][6])

### 建议

前台恢复改成三级决策：

```text
没有持久化 transaction 变化
  → 跳过持久层刷新，只推进时钟敏感状态

有可识别 transaction / affected IDs / affected ranges
  → scoped refresh

token 丢失、schema/calendar/topology 不可安全判定
  → full refresh
```

启动也应分阶段：

```text
第一阶段：active + today + 当前任务树，立即恢复交互
第二阶段：历史索引和 Rollup 在后台 actor 构建
第三阶段：Analytics、Widget、Watch 和同步保护投影
```

对于首次历史索引完成前的查询，可以直接回退到 repository range query，而不是阻塞整个 UI 等待历史全量 materialization。

**相关但容易遗漏：** 日历、时区变化确实可能要求重建 day index，但这应是独立 invalidation 原因，不应该和普通 foreground activation 使用同一个 `.fullSync` 入口。

---

## 3. P1：Ledger 增量数组更新最坏为 `O(kN)`

`replaceSegments` 对受影响 ID 逐个调用 `updateFlatSegment`。当记录被删除或 `startedAt` 变化时，后者会：

1. 从 `allSegments` 中删除；
2. 对删除位置之后的所有元素重新写 `segmentArrayIndexByID`；
3. 二分查找新位置；
4. 插入；
5. 再次重建插入位置之后的数组索引。([GitHub][7])

数组的二分搜索是 `O(log N)`，但删除、插入和后缀 reindex 均是 `O(N)`。如果一次远端导入或 range refresh 修改 `k` 条历史记录，最坏复杂度是：

```text
O(kN)
```

尤其是修改较早的历史记录时，几乎整个数组后缀都会被反复移动和重编号。

### 建议

为 `replaceSegments` 增加 batch 策略：

```text
少量变更且位置靠近尾部
  → 维持当前逐条更新

变更数超过阈值，或最早受影响位置较前
  → 一次性：
     1. 删除旧 ID
     2. 将新记录排序
     3. 与保留数组做线性 merge
     4. 一次重建 segmentArrayIndexByID
```

复杂度可从最坏 `O(kN)` 降到：

```text
O(N + k log k)
```

更进一步，可以让 `[UUID: SegmentRecord]` 成为主要事实索引，排序结构只保存 ID，避免同时在多个地方持有 SwiftData 对象引用。

---

## 4. P2：Analytics 的后台化不完整

项目已经意识到 SwiftData 对象不能跨 Actor，并为 Today visual snapshot 构造了值类型输入；这是正确方向。但只有 `.today` 的 visual 部分使用异步纯值计算。之后 `analyticsDomainStore.refreshSnapshot` 仍回到主 Store，继续执行 snapshot 构建。Week/Month 路径甚至没有对应的后台 visual 计算。([GitHub][8])

Analytics snapshot 会执行多轮：

* segment 去重；
* 时间范围过滤；
* daily breakdown；
* Pomodoro focus round 扫描；
* overview；
* task breakdown；
* previous-period comparison；
* rhythm；
* quality；
* root/category breakdown；
* overlap/insight 计算。

其中 comparison 和 Pomodoro round 还接收全部历史 segments。([GitHub][9])

缓存失效也较粗：一次 Analytics invalidation 会清空所有 range snapshots 和 task snapshots，只有 ledger day bucket 支持按区间失效。([GitHub][10])

此外，Ledger 的 day index 只索引最多 366 天；更长的区间会直接扫描全部 snapshot。([GitHub][11])

### 建议

建立完整的 `AnalyticsActor`：

```text
MainActor:
  从 LedgerStore 捕获 Sendable LedgerRecord / TaskRecord

AnalyticsActor:
  计算 Today / Week / Month / Task snapshots
  管理缓存和 revision

MainActor:
  只发布最终 immutable snapshot
```

缓存键不应只依赖全局 `analyticsRevision`，而应包含 revision vector：

```text
ledgerRevisionByDay
taskMetadataRevision
categoryRevision
pomodoroRevision
checklistRevisionByTask
calendarRevision
```

例如，修改 2024 年的一条记录不应使当前 Today snapshot 和所有无关 task snapshot 失效。

**相关但容易遗漏：** 超过 366 天的查询退化不是一定要删除的设计；可以保留 fallback，但应给“全历史 comparison”准备按月或按日的持久/内存聚合桶，避免每次冷缓存都扫描全部事实。

---

## 5. P2：部分“scoped refresh”实际上仍有全量读取

`TaskStore.refreshTaskScoped` 虽然只按 ID 获取任务，但仍然每次全量获取 categories 和 category assignments。更重要的是，quantity goal/entry 因为可能存在 malformed relational graph，明确选择了全量读取。([GitHub][12])

`refreshInboxDomain` 无论 affected inbox IDs 是否已知，都会先全量获取所有 Inbox item read model，并重建完整 dictionary 和 suggestion indexes；只有 suggestion 查询本身是 scoped 的。([GitHub][13])

这与项目自身的 Repository guardrail 存在偏差：文档要求普通用户操作不得执行 broad `all` 查询，除非 full sync 或没有可用范围的 history invalidation。([GitHub][14])

### 建议

**Quantity graph：**

* 写入和迁移时维护完整性状态；
* 将“发现 malformed graph”变成显式 dirty flag；
* graph clean 时执行 task-scoped query；
* 只有 dirty 时才走全量校验和 repair；
* repair 后清除 dirty flag。

不能让理论上的历史脏数据永久迫使所有正常任务更新全量扫描。

**Category：**

* 将 category 和 assignment 分成独立 revision；
* 普通标题或估时修改不重新查询 category；
* 只有 category ID 或根节点拓扑变化时更新 assignment projection。

**Inbox：**

* 为 item read model 增加按 ID fetch；
* 更新 `inboxItemReadModelByItemID` 的 affected bucket；
* 仅当排序字段或全局筛选条件改变时重建列表。

---

# 二、架构设计审查

## 1. 当前整体架构是合理的

项目不是“SwiftUI View 直接查 SwiftData”的简单结构。真实写路径已经形成：

```text
View
  → TimeTrackerStore facade
  → Command Handler
  → Repository
  → StoreDomainEvent
  → RefreshPlanner
  → RefreshCoordinator
  → Domain Stores
  → SwiftUI
```

读路径也有 Repository、domain snapshot 和 pure service 的分工；`TimeSegment` 是 canonical fact，统计、预测、图表和汇总都是可重建投影。

几个设计尤其值得保留：

* `StoreDomainEvent` 表达“发生了什么”，而不是直接耦合到某个 View。
* `StoreRefreshPlanner` 让 invalidation 策略可测试。
* `ModelContext.performAtomicMutation` 确保多步骤命令只保存一次，并在失败时整体 rollback。
* `TimerAdmissionPolicy` 是 `nonisolated`、纯值、确定性的策略对象，持久化和 side effect 被留给 coordinator。
* Rollup 已经有按变更记录、层级深度和 90 天窗口工作的增量索引。([GitHub][15])

这说明问题不是“需要重新设计整个应用”，而是继续把已有边界贯彻到底。

---

## 2. `TimeTrackerStore` 已成为状态、依赖和流程的集中枢纽

`TimeTrackerStore` 同时持有：

* 各种 repository；
* command handler 和 services；
* tasks、segments、sessions、checklist、inbox、preferences；
* Apple Health 状态；
* AI request 状态；
* sync/recovery 状态；
* navigation/selection 状态；
* analytics 和 rollup store；
* 多组手工索引与任务句柄。

维护者自己的重构文档也把 lifecycle 和 sync observer 的职责集中列为现存风险。

需要区分两件事：

* `@Observable` 具有按属性访问跟踪，因此不能仅凭对象大就断言每次修改都会重绘所有 View。
* 真正的问题是所有权、Actor 隔离和依赖方向：任何新功能很容易继续把状态或流程塞回 façade，最终形成单一刷新总线和单一故障域。

### 建议目标

保留 `TimeTrackerStore` 作为兼容 façade，但将其降为组合和路由层：

```text
TimeTrackerStore @MainActor
├── TodayFeatureStore
├── TaskFeatureStore
├── LedgerFeatureStore
├── AnalyticsFeatureStore
├── SyncPresentationStore
└── NavigationStore
```

同时把依赖装配移到独立 composition root：

```text
AppComposition
  ├── repositories
  ├── command coordinators
  ├── projection schedulers
  └── system surface adapters
```

这样 façade 可以继续提供旧 API，但不再直接拥有所有持久化和系统集成细节。

---

## 3. RefreshCoordinator 同时承担读模型刷新和外部系统投影

`StoreRefreshCoordinator.refresh` 把以下内容放在同一个同步 interval 内：

* primary domains；
* Rollup、Analytics invalidation；
* selection validation；
* Live Activity；
* Widget；
* Watch；
* 自动 AI suggestion 调度。

这使“保证 UI 一致”与“让所有外部投影最终一致”成为同一个事务后的同步阶段。

### 建议拆分

```text
ReadModelRefreshCoordinator
  只负责本 Scene 的 UI projection

SystemProjectionScheduler
  Live Activity / Widget / Watch

SuggestionScheduler
  Inbox / Checklist AI jobs

SyncProtectionScheduler
  conflict snapshot / fingerprint / state
```

不同 scheduler 共享同一个 `MutationReceipt`，但拥有独立重试、去重和错误状态。一个 Widget 写入失败不应延迟或污染当前 Scene 的任务状态。

---

## 4. Event 类型已经结构化，但语义仍然偏粗

当前映射包括：

* 任意 `taskChanged` 都刷新 tasks、rollups、analytics、live activities；
* 任意历史 ledger edit 都同步 live activities；
* 任意 checklist change 都使 Analytics snapshot 全失效。([GitHub][16])

部分行为是正确性所需，例如 checklist 会影响预测；但不是所有 task metadata 都会影响 Analytics 或 Live Activity。

### 建议

将事件扩展为 mutation fact，而不是继续增加 refresh scope：

```swift
struct TaskMutationFact {
    let taskID: UUID
    let changedFields: TaskChangedFields
    let affectedAncestorIDs: Set<UUID>
}

struct LedgerMutationFact {
    let segmentIDs: Set<UUID>
    let oldRanges: [DateInterval]
    let newRanges: [DateInterval]
    let affectsActiveSet: Bool
}
```

Planner 再根据字段依赖构造不同 projection 的计划：

```text
task.title       → tasks + widget/watch identity
task.parentID    → tasks + rollup topology + analytics grouping
task.estimate    → tasks + forecast
segment.note     → ledger row only
segment.interval → ledger + rollup + analytics
```

这会比继续扩大 `StoreRefreshScope` 更可控。

**相关但容易遗漏：** 主 target 配置了默认 `MainActor` 隔离，同时仍是 Swift 5 language mode。它降低了一部分并发错误风险，但也容易使未显式标注的纯计算默认落到主 Actor。建议先启用更严格的并发警告，再逐步将纯算法标为 `nonisolated` 或移入专用 Actor，而不是直接进行一次性 Swift 6 迁移。

---

# 三、代码抽象审查

## 1. Repository 协议过宽，违反能力隔离

`TaskRepository` 同时包含：

* hierarchy repair；
* task 查询；
* category 查询与写入；
* recurrence 查询；
* quantity 查询；
* task/category mutation。

`TimeTrackingRepository` 也同时承担查询和命令写入。([GitHub][17])

这会导致：

* 测试 fake 必须模拟大量无关能力；
* 调用方难以表达只读依赖；
* 新实现可以在不知情的情况下使用高成本默认路径；
* repository 逐渐变成领域 API 总表。

### 建议拆分

```swift
protocol TaskQuerying {
    func tasks(ids: Set<UUID>) throws -> [TaskRecord]
}

protocol TaskHierarchyQuerying {
    func children(of parentID: UUID?) throws -> [TaskRecord]
}

protocol TaskMutating {
    func execute(_ command: TaskCommand) throws -> TaskMutationResult
}

protocol RecurrenceQuerying { ... }
protocol QuantityProgressQuerying { ... }

protocol LedgerQuerying { ... }
protocol LedgerMutating { ... }
```

Command Handler 依赖 mutation capability，Domain Store 只依赖 query capability。

---

## 2. 默认空实现和全量 fallback 会隐藏错误

协议扩展中：

* recurrence/quantity 默认返回空数组；
* `repairInvalidHierarchy` 默认什么也不做；
* `segments(ids:)` 默认调用 `allSegments()` 后在内存过滤；
* scoped recurrence/quantity 默认先调用全量方法再过滤。([GitHub][17])

这些默认实现对简单 fake 很方便，但对生产抽象有两个问题。

### 正确性风险

一个新的 Repository 实现可以在完全编译通过的情况下，静默“不支持” recurrence 或 quantity，调用方看到的只是空数据，而不是 capability missing。

### 性能风险

调用者看到的是 `segments(ids:)`，可能以为复杂度与 ID 数量相关，实际却可能是全表 materialization。

### 建议

* 删除业务能力的默认空实现。
* 测试 fake 显式实现它需要支持的协议。
* 如确需可选能力，使用独立 capability 协议或明确的 `.unsupported` error。
* 禁止在协议默认实现中做 broad query fallback。
* 为 query 增加复杂度语义，例如 `fetchSegments(ids:)` 必须有后端 predicate。

---

## 3. Repository 直接暴露 SwiftData 模型

Repository 返回 `[TaskNode]`、`[TimeSegment]`、`[TimeSession]` 等持久化模型。Analytics 代码本身已经明确指出，SwiftData 对象不能跨越 main-actor boundary，因此需要手工构造值输入。([GitHub][17])

这意味着：

* domain/read model 被 SwiftData 生命周期和 Actor 约束污染；
* 后台计算必须临时复制；
* 单元测试更依赖持久层对象；
* Repository 很难被其他存储实现替换；
* 对象引用相同性等 SwiftData 特性会渗透到索引代码中。

### 建议

读取侧返回 immutable、`Sendable` 的 record：

```swift
struct LedgerRecord: Sendable, Hashable {
    let id: UUID
    let taskID: UUID
    let sessionID: UUID
    let startedAt: Date
    let endedAt: Date?
    let deletedAt: Date?
}
```

SwiftData model 只存在于：

```text
SwiftData Repository / Actor-owned ModelContext
```

UI、Analytics、Rollup、Watch/Widget projection 使用值类型。这会同时解决代码抽象、并发边界和一部分内存不可控问题。

---

## 4. 原子事务实现正确，但依赖隐藏的 ambient state

`performAtomicMutation` 使用一个以 `ObjectIdentifier(ModelContext)` 为 key 的全局静态 dictionary 记录嵌套深度。Repository 调用 `saveAfterMutationStep()` 时，会读取这个隐藏状态来决定是否延迟 save。([GitHub][15])

优点是现有命令无需大规模修改，就能实现 outer transaction save-once。

缺点是：

* 事务状态不在类型系统中；
* Repository 是否正确遵守事务取决于它是否调用指定 helper；
* 新写入路径直接调用 `context.save()` 就能绕过该机制；
* 代码阅读时无法从方法签名判断自己处于事务内；
* 全局状态目前依赖 MainActor 串行性。

### 建议

逐步改成显式 Unit of Work：

```swift
protocol MutationUnitOfWork {
    func execute<Result>(
        _ operation: (MutationContext) throws -> Result
    ) throws -> Result
}
```

Repository mutation 接收 `MutationContext`，只有 Unit of Work 能最终 commit。短期至少可以增加测试或静态规则，禁止 Repository 直接调用 `ModelContext.save()`。

---

## 5. 错误层次存在轻微反向依赖

`TaskRepositoryError` 直接通过 `AppStrings.localized(...)` 生成用户文案。([GitHub][17])

这使 infrastructure/domain 层依赖 presentation localization。更清晰的方式是：

```text
RepositoryError.invalidMove
  → PresentationErrorMapper
  → localized string
```

这不是高优先级问题，但在未来增加日志、遥测、App Intent 或 Watch 错误表现时，会减少重复判断。

**相关但容易遗漏：** `TimerAdmissionPolicy` 是本项目中较好的抽象范例：纯值输入、确定性输出、无持久化、无 UI 文案、显式 `nonisolated`。新的业务规则应尽量按这个形态设计，而不是继续扩展 façade helper。([GitHub][18])

---

# 四、测试、可观测性与交付门禁

## 优点

测试文档覆盖面很强，包括：

* DST、未来时间和半开区间；
* 增量结果与全量重建一致；
* task cycle 和 hierarchy repair；
* recurrence/quantity graph；
* sync LWW、tombstone、快照恢复、损坏文件隔离；
* 原子写入；
* Widget/Watch payload 限制；
* UI、Dynamic Type 和 accessibility；
* 50,000 条 ledger 性能告警；
* Release Instruments 与真机验证。

源码中也已经广泛使用 `PerformanceSignpost.interval`，因此具备继续做调用链归因的基础。

## 缺口

Makefile 提供了 macOS 单元测试、iOS/macOS build、格式化、本地化和真实 LLM 测试入口，但默认 `make test` 只运行 macOS `timetrackerTests`，没有一个公开可见的单一 mandatory verification target。([GitHub][19])

公开的 GitHub Actions 页面只显示“开始使用 Actions”的介绍内容，仓库根目录也没有 `.github/workflows`。因此，当前公开仓库没有可见的 GitHub Actions CI。不能排除维护者使用其他私有或外部 CI，但它未在仓库中形成可审计的合并门禁。([GitHub][20])

### 建议的 CI 分层

每次提交：

```text
format-check
localization-check
macOS unit tests
generic iOS build
generic macOS build
```

PR 或主分支：

```text
CorePerformanceBudgetTests
migration/snapshot suites
sync failure-injection suites
```

定时或 release：

```text
UI tests
real-provider LLM tests
signed archive
real-device profiling/manual acceptance
```

需要把前两层设为 branch protection required checks。真实 LLM 和真机测试不适合每次提交执行，但其最后一次证据应绑定到具体 commit。

---

# 五、推荐的改造顺序

## 第一阶段：建立可量化基线，工作量 S

先不要立即重写架构。补充以下 signpost：

```text
mutation.transaction
mutation.visibleProjection
mutation.syncSnapshot
mutation.systemProjections
foreground.changeDetection
foreground.visibleRefresh
foreground.historyRefresh
ledger.batchIndexUpdate
analytics.valueCapture
analytics.compute
analytics.publish
```

同时增加公开 CI，确保后续重构有可重复回归门禁。

验收重点：能把一次 Start/Stop 的数据库提交、可见状态更新、同步快照、Widget/Watch 各阶段单独量出来。

## 第二阶段：缩短提交后关键路径，工作量 M

* `finishCommittedMutation` 只同步执行可见读模型刷新。
* Sync、Widget、Watch、Live Activity 进入独立 scheduler。
* 每个 scheduler 支持 generation、去重、取消和重试。
* 失败状态按 projection 分类，不再全部写入一个 `errorMessage`。

这是收益最大、风险相对可控的一步。

## 第三阶段：修复 Ledger batch update 和 foreground full refresh，工作量 M/L

* 为 `replaceSegments` 增加 batch merge。
* 使用 persistent history token 检测 foreground 是否真的有变化。
* 远端导入尽可能携带实体 ID/range，而不是无条件 `.remoteImportCompleted → full`。
* 启动只同步加载 active/today，历史索引延迟完成。

## 第四阶段：建立 Sendable DTO 和后台计算边界，工作量 L

优先迁移：

1. Ledger Analytics 输入；
2. Rollup segment snapshot；
3. Task/category read model；
4. Inbox read model。

不必一次性改掉所有 Repository；可以从新的 `LedgerQueryingV2` 开始，旧 façade 做适配。

## 第五阶段：收紧协议和缓存失效，工作量 M

* 拆分 Repository capabilities。
* 删除默认空实现和全量 fallback。
* 引入 revision vector。
* 将 category、quantity、inbox 的 scoped refresh 做到真正 scoped。
* 最后再缩减 `TimeTrackerStore` 属性和依赖。

---

# 六、可复现的性能验证方案

先执行仓库现有基线：

```bash
make format-check
make localization-check
make test
CONFIGURATION=Release make build-ios
CONFIGURATION=Release make build-macos
```

这些命令来自仓库的 Makefile 和 Testing policy。

随后建立以下数据集：

```text
Tasks:           5,000
Segments:       50,000
Sessions:       25,000
ChecklistItems: 20,000
InboxItems:      5,000
```

重点场景：

| 场景                             | 检查目标                                    |
| ------------------------------ | --------------------------------------- |
| 无数据库变化时 foreground             | 应跳过历史重建                                 |
| 只新增今天一条记录后 foreground          | 只更新 visible/range projection            |
| 编辑最早的一条历史记录                    | 暴露数组后缀 reindex 成本                       |
| 一次导入 100、1,000 条历史记录           | 验证 `O(kN)` 是否出现                         |
| 开启 iCloud 后 Start/Stop         | 分离 commit、snapshot、system projection 延迟 |
| 同时打开 3 个 Scene                 | 检查广播是否引发重复刷新                            |
| 冷打开 Today/Week/Month Analytics | 检查主线程 CPU 和缓存失效                         |
| 查询 365 天与 367 天                | 验证 day-index fallback 的性能断点             |
| 时区切换与系统时间回拨                    | 保证优化不破坏正确性                              |

建议把以下数字作为**拟定验收目标**，而不是当前性能结论：

```text
命令提交到可见状态 p95：      < 100 ms
单段连续 MainActor CPU：      尽量 < 8–16 ms
无变化 foreground：           < 20 ms 且不读取全历史
任何主线程阻塞：              不出现 > 50 ms 长任务
后台历史/系统投影：            不阻塞交互，可取消且可恢复
增量结果：                    必须与 fresh full rebuild 完全一致
```

真机至少使用：

* Time Profiler；
* Animation Hitches 或 Core Animation；
* Allocations；
* SwiftUI Instrument；
* 现有 `PerformanceSignpost` points of interest。

仓库测试文档也明确要求在 Release 和真实 iPhone/iPad/macOS 上验证，单元性能测试不能替代设备 SLA。([GitHub][6])

---

# 最终优先级

按收益、风险和依赖关系排序：

1. [~] **P1：把 sync snapshot、Widget、Watch、Live Activity 从同步提交后路径移出。**
2. [ ] **P1：foreground/remote import 使用 persistent-history delta，避免无条件 full refresh。**
3.  [ ]**P1：将 Ledger 多记录更新改为 batch merge，消除最坏 `O(kN)`。**
4.  [ ]**P2：Analytics 使用完整的 Sendable value pipeline 和后台 Actor。**
5.  [ ]**P2：拆分 Repository capability，删除空实现和全量 fallback。**
6. [ ] **P2：修正 Task quantity、category、Inbox 的伪 scoped refresh。**
7. [ ] **P2：增加公开 CI 和 required checks。**
8.  [ ] **P3：将 ambient transaction state 逐步替换为显式 Unit of Work。**
