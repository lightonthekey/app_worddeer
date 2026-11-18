# app_worddeer · 词鹿英语

英语单词学习 App（Flutter / Android）。词库来自 tooldeer.com 的 6 个英语小工具，A1–C1 共 7201 词。

## 目录结构

```
app_worddeer/
├─ design/            ← ★ HTML 原型文件夹（做功能前先在这里出效果）
│  ├─ game-v2.html    可玩原型：配对棋盘 v2（巩固台 + 4 行棋盘 + 结算）
│  ├─ demo1.html      闯关首页参考原型（级别→单元→关卡链、会员锁、付费墙）
│  ├─ shots/          原型截图存档
│  └─ README.md       原型工作流 + 已定稿规则（务必先读）
├─ lib/
│  ├─ main.dart       入口，4 tab 壳（学习/复习/词典/我的）
│  ├─ bank.dart       词库加载（assets/words.json + words.db）
│  ├─ progress.dart   SRS 间隔重复（7 档，10 分钟→30 天，box≥5 掌握）
│  ├─ curriculum.dart 课程进度（级别 / 每关 20 词 / 每 5 关复习 / 主题 / 今日目标）
│  ├─ backend.dart    后台地址单点 + 统一 JSON 请求（{code,message,data}）
│  ├─ auth.dart       账号（登录/注册/会话恢复/登出）
│  ├─ content_sync.dart 词库内容包同步（改词不发版）
│  ├─ progress_sync.dart 学习进度云同步（本地优先 + 异步增量）
│  ├─ entitlement.dart 会员权益（付费墙唯一数据源）
│  ├─ pay.dart        支付（下单/凭证校验/恢复购买/删号，沙箱 mock 占位扣款）
│  ├─ audio.dart      发音（默认 https://tooldeer.com，--dart-define=AUDIO_BASE 可覆盖）
│  ├─ confetti.dart   配对成功的纸屑粒子（Canvas + Ticker，固定 1/60 步长）
│  ├─ ui.dart         主题/配色
│  ├─ preview.dart    无需首页直达各玩法（--dart-define 或路由 ?q=flash|choice|spell|listen）
│  ├─ match_probe.dart 配对棋盘截图入口（跑自动演示并导出帧，仅开发用）
│  └─ pages/          home / match（配对棋盘 v2 + 巩固台）/ session / review / dict / me / login / paywall / checkin
├─ windows/           桌面预览工程（430x900 手机比例窗口，仅用于快速看 UI）
├─ assets/            words.json（7201 词）、words.db（SQLite 索引）
├─ tools/asset_build/ 词库再生成脚本（build_db.py + TSV 源）
└─ test/              冒烟测试 + 配对游戏回归（4 行首屏 / 巩固台左移 / 配错不换位 / 整局结算）
```

## 购买与删号（第 5 项）

- `pages/paywall.dart` 点开通：`Pay.createOrder` →（扣款占位）→ `Pay.verify` →
  服务端校验凭证 → 事务内发权益 → `Ent.refresh`。全程服务端判定，客户端拿不到凭证就开通不了
- **扣款占位**：沙箱联调用 `mock:txid:original:product_id` 凭证（服务端 `pay.sandbox: true`
  才接受）；接真实 IAP 只改 `Pay.purchase`，换成 StoreKit 调起支付并返回 JWS
- **恢复购买**：verify 成功的凭证留存在 prefs，换机/重装后 `Pay.restore` 批量上交补录；
  同一交易号跨账号会被服务端唯一约束拒绝（防薅）
- **删除账号**：我的页底部红色入口（Apple 审核硬性要求），服务端硬删账号/进度/权益，
  订单匿名保留（财务凭证 + 防收据重放）

## 会员与付费墙（第 4 项）

**App 里没有任何 `if (vip)` 的业务判断**，也没有硬编码"免费几关/几个主题"。
锁不锁只问 `Ent`：`canLevel(lv)` / `canUnit(index)` / `canTheme(index)`，
答案来自后台 `GET /api/v1/worddeer/entitlement` 的 `limits`（后台「会员套餐」页可改，不发版）。

- 拉取时机：启动、登录/登出、打开付费墙前；失败沿用上次缓存
- 离线兜底：没有缓存用内置保守免费档（A1/A2、每级 2 关、每级 1 个主题）
- 缓存里记着到期时间的，本地判定已过期立即按免费算，不等服务器
- 免费额度学完后，首页主卡片变成开通引导，而不是卡在第 3 关反复点
- `pages/paywall.dart`：套餐对比 + 权益列表 + 开通/恢复购买占位；**第 5 项**接 IAP 时只改 `_buy`

## 已移植：首页 / 主题 / 打卡（对照 `design/home-pick.html`）

原稿：`design/home-v3-terrace.html`（首页台地地图）、`theme-v2-ladder.html`（主题阶梯）、
`checkin.html`（连胜日历）。

**首页**（`lib/pages/home.dart`）
- 三种模式共用顶栏：左上角级别胶囊 → **从顶栏下方滑出**的下拉面板（级别 / 本级别进度 /
  今日目标 / 已掌握·待复习·易错 / 换主题·去复习·打卡）；右上角火焰直连打卡页。
- 关卡沿一条正弦曲线向下（一个周期 5 关，幅度 ±68 且随屏宽收窄），
  每 5 个学习关 + 1 个复习关裹进一块交替色带（台地），色块本身就是进度条。
- 走过的段画实线、没走的画圆点虚线；当前关带柔光圈 + 🚩 + 侧面的「继续 · U9」标签。
- 打开首页自动滚到当前关（`_autoScrolled` 记已滚过的目标，重建不会把人拽回去）。
- 当前关的标签放在**节点侧面**而不是正下方：正下方会和下一关撞在一起（下一关常往那侧偏）。

**关卡表**（`lib/curriculum.dart`）
- `perUnit = 20`，`learnPerReview = 5`；关数**按词库算**（`ceil(词数/20)` 个学习关，
  每 5 个之后插一关复习，复习关 = 这 5 关的 100 词）。A1 现在是 53 + 10 = 63 关。
- 界面上的「x / y 关」「已学 x / y 词」全部走 `unitCountOf()` / `wordCountOf()`，不再有 12。

**主题**（同一文件 `_themeBody`）
- 卡牌左右交错（奇数张缩进 46）+ 卡间直角折线（`_LadderPainter`，几何确定，不依赖布局回调）。
- 每张卡带 44dp 主题图标；四种状态：已学完 / 当前（紫卡 + 卡内进度条）/ 未开始 / 会员金锁。
- 底部常驻「继续 · 主题名」，指向第一个没学完的主题。

**打卡**（`lib/pages/checkin.dart` + `lib/checkin.dart`）
- 数据源是 `Progress.days`（`Set<String>` 按天存），不再用计数器：
  跨天/改系统时间都不会漂移，而且画得出历史。日历与「最长连胜」都从这一份算。
- 学完任意一关就算打卡：`Curriculum.addToday()` → `Progress.markCheckin()`。
- 算法（`MonthGrid` / `runsIn` / `longestRun` / `countInWeek`）单独放 `lib/checkin.dart`，
  不依赖 Flutter，`test/checkin_test.dart` 直接测，不用起整棵树。

## 已移植：配对棋盘 v2（`lib/pages/match.dart`）

首页点关卡或主题进入 —— 两种模式共用同一套棋盘（只有一种展示方式：左列英文、右列中文），
仅结算文案按场景区分（「本关完成」/「主题完成」）。自由练习仍走 `session.dart` 的四选一·拼写·听音混排。
原稿是 `design/game-v2.html`（可玩原型），逻辑、配色、时间轴逐项对齐。

**布局**（自上而下）：标题栏 + 计时 → 进度条 → **巩固台** → 4 行棋盘 → 底部提示。

**规则**
- 左列英文、右列中文，**4 行**。开局两列各自打乱，配对的两张通常不在同一行，靠词义找，不靠位置。
- **英文列位置固定**：哪格消失就补哪格，位置永远不动，当「锚点」用。
- **中文列每次配对后整列重排**，且保证没有任何一行左右是同一个词 ——
  只换一格的话位置固定下来，用户闭眼点同一行就能连对；整列洗开就没有这个漏洞。
- 点左边英文再点右边中文：判定正确 → 两张变绿轻轻一抬 → **合拢飞向巩固台** → 棋盘原地补新词。
- 判错：只有被点的两张变红上下颠（420ms），颠完恢复白卡。**不退场、不换词、不挪位**，
  同一个词的另一半也不做任何标记（变了就等于把答案指出来）。
- 桌面清空且队列空 → 结算（配对 / 一次选对 / 最高连击）。

**巩固台**（顶部那条 76dp 的区域）
- 最多留 3 个词对，**左旧右新**，位置本身就是时间顺序。
- 新词落位时绿框 + 放大字号高亮 2 秒；台子满 3 个时**整条向左平移一格**（300ms）：
  最旧的滑出左边、新词从右边缘滑入，中间两个只平移、文字不变。
- 不做「固定三格换字」：一次换三张画面整体闪一下；也不做「1-2-3 轮流替换」：
  位置轮流变就看不出谁最新，巩固台也就失去了「刚配对的是哪个」的意义。

**中文释义**：中文卡主行是 `zh`，副行是 `detail`（完整释义，最多 2 行，超出用省略号截断）。
自己玩的时候会看释义，所以不复用旧的「缩略成 2 条义项」那套（`_brief` 已删）。

**动效时间轴**（`_T` 常量，微调节奏只改这一处）

| 时刻 | 发生什么 |
| --- | --- |
| 0–140ms | 判定缓冲（太短会看不清点了哪两张） |
| 140ms | 两卡变绿 + 轻抬（停在 -3.5px 的悬浮位）；底部显示 `✓ milk = 牛奶`；**立即解锁** |
| 140–620ms | 绿卡原地停留，用户已可点下一组 |
| 620ms | 两张卡藏起来，两个克隆「合拢」飞向巩固台（340ms） |
| 740ms | 棋盘原位补新词（英文格不动，中文列重排） |
| 960ms | 落到巩固台；若已满 3 个，整条左移一格（300ms） |

**关键**：从 140ms 起就不再锁操作。飞行、补位、巩固台左移全是背景动画，手快可以一路配下去。

配错不走上面这条：判定 140ms 后 2 张卡变红抖动 420ms，520ms（`_T.wrong`）时红标撤掉、解锁，牌面完全没动。

实现上两个坑值得记着：
- 巩固台左移用 `AnimationController` + `Transform.translate`，**落位串行化**（`_shelfChain`）：
  左移动画没走完不插下一张，否则第二张会算错位置。
- 卡片坐标要从 `GlobalKey` 的 RenderBox 换算到页面 Stack 坐标系（`_rectOf`），
  飞行的起点是两张卡的中心、终点是目标槽位的中心 —— 位移过程中槽位必须还没开始平移。

纸屑是 Canvas 粒子（`lib/confetti.dart`）：实心色块，重力 `.062/frame²` + 阻力 + 左右摆动 + 自转，寿命 2.7–4.2 秒，前 60% 实心后 40% 淡出；固定 1/60 物理步长，掉帧设备上飘落速度也一致。

三条约束保证纸片「向四周散开」而不是「从中间竖着掉下来压住学习区」：

- **只在两张卡上炸**（各 10 片，合计 20 片；早先各 20 片纸太满，会糊住旁边的牌面），不在两卡连线的中点单开爆点 —— 中点在屏幕中缝，那里的纸片很容易贴着中线往下走。
- **横向速度有下限**（`kMinVx = 1.6`，衰减到底也不低于 1.2）：`vx ≈ 0` 时后半程只剩重力，纸片会变成一条竖线直直落下。
- **下落 260~350px 就开始淡、再掉 90px 彻底消失**（`kFallFadeStart` / `kFallFadeWidth`，每片起始值随机，错开退场），不让长尾穿过下半屏牌面。

回归用例在 `test/confetti_test.dart`：断言「不存在 `vy > 2 && |vx| < 1.2` 且压在中缝的可见纸片」和「下落深度不超过阈值」。

> 粒子层的 Ticker 必须**整个 State 只创建一次**，用 `start()` / `stop()` 控制。
> 早期写成「粒子清空就 stop 并置 null、下次爆炸再 `createTicker`」，
> 但 `SingleTickerProviderStateMixin` 内部也持有 ticker，只允许创建一次，
> 第二次会抛 `multiple tickers were created`，新纸屑没人推进 —— 表现为碎片停在爆点不动、越玩累积越多。
> 回归用例：`test/confetti_test.dart`（连打三轮）、`test/match_test.dart`（连打两对）。
> 想肉眼复现/验证：`flutter run -t lib/match_probe.dart -d windows --dart-define=DEMO=3`，
> 连打三对、每对结束截一张 `flutter-soak-N.png` 并打印 `particles=0`。

> 卡片动画的「重播」判据要用 State 自己记的序号，**不能拿 `old.card.fxNonce` 比**：
> `_CardView` 的 `card` 是一个**可变对象**，`old.card` 和 `widget.card` 指向同一个 `_Card`，
> 所以 `old.card.fxNonce != widget.card.fxNonce` 恒为 false —— 动画只在 `initState` 播过一次，
> 之后 hop / shake / 补位 fade 全都不播，`_t` 停在 1，卡片直接跳到终点姿态
> （用户看到的就是「跳了一下就定格 / 凹进去」）。现在用 `_seen` 字段记住上一版序号来触发。
> 回归用例：`test/match_test.dart` 的「答对的卡只是「轻轻一抬」」，逐 50ms 采样 Transform，
> 断言 hop 全程 `dy ≤ 0`（不许压进桌面）、抬升不超过 12px，且收尾停在 `-3.5px`。

> 补位位置的回归：`test/match_test.dart` 的「补位不再固定在原位」（连打 6 对，检查新词
> 换了格子、且整桌没有一行左右同词）和「一直点同一行不会连对」（模拟用户不动脑，
> 固定点第 2 行 6 次，全程断言那一行左右不是同一对）。

**看效果**

```bash
# 真机/桌面交互（首页 → 关卡）
flutter run -d windows

# 自动演示并导出关键帧到 design/shots/
#   DEMO=1 正确  2 配错  3 连打三对查纸屑残留  4 答对后悬浮态（4 张）  5 密集连拍（做 GIF）
flutter run -t lib/match_probe.dart -d windows --dart-define=DEMO=1
```

## 工作流（重要）

**做一个功能前，先在 `design/` 用 HTML 实现并确认，再移植到 Flutter。**

1. 改/建 `design/demo*.html`（单文件、无构建、可直接点）
2. 无头 Chrome 截图存档到 `design/shots/`（命令见 design/README.md）
3. 交互规则定稿后翻译成 Dart
4. `flutter analyze && flutter test` 通过再提交

## 常用命令

```bash
flutter pub get                 # 拉依赖
flutter analyze                 # 静态检查
flutter test                    # 冒烟测试（注意先清掉代理环境变量）
flutter run -d windows          # 桌面预览（快，改 UI 用这个）
flutter run -d emulator-5554    # 安卓模拟器
flutter build apk --release     # 出包（build/app/outputs/flutter-apk/）
```

**最省事：双击脚本**
- `run-win.bat` → 在 **Windows 桌面**跑（430x900 手机比例窗口），改 UI 最快，不用等模拟器
- `run.bat` → 在 **Android 模拟器**跑（emulator-5554）

两个脚本都会清代理变量再 `flutter run`（改完代码在终端按 `r` 热重载，`q` 退出）。

Android Studio 里想用绿色 ▶ 运行，需要先装 Flutter 插件：
`File → Settings → Plugins → Marketplace → 搜 Flutter → Install（会连带装 Dart）→ 重启`，
然后 `Settings → Languages & Frameworks → Flutter → Flutter SDK path` 填 `D://flutter`；
重启后右上角 Select Device 选 `Medium_Phone_API_37.0`，Run 配置选 Flutter、Dart entrypoint 选 `lib/main.dart`。

> 本机注意：`flutter test` 需要清空 http_proxy/https_proxy，否则 flutter_tester 的 WebSocket 连不上。
> Gradle 已设 `kotlin.incremental=false`（增量缓存在这台机器上会崩）。

## 已知事项

- 发音源为第三方转发，正式上线前需换授权音频
- C2 级词库为空；主题覆盖目前只有 A1 的 12 个主题
- **真实内购尚未接入**：`Pay.purchase` 只在 debug 包造 mock 凭证；
  release 包会直接抛「内购暂未开放」，避免服务端 sandbox 开着时被白拿会员。
  接 IAP 时只改 `Pay.purchase`，把 App 返回的凭证交给 `Pay.verify`，其余流程不变。
- **正式签名未配置**：把上传密钥放到 `android/key.properties`（四行：
  `storeFile` / `storePassword` / `keyAlias` / `keyPassword`），
  `app/build.gradle.kts` 会自动启用 `release` 签名；没有该文件时 release 包
  退回 debug 签名并在构建日志里警告 —— 这种包不能上架。
- 设计原型中已定稿的规则（每关 20 词、4 对 4、错词回流、每 5 关复习、主题每级只开第一个…）见 `design/README.md`

## 健壮性约定（改动时别破坏）

| 位置 | 约定 |
|---|---|
| `main.dart` `_boot()` | 每个模块单独 try/catch。以前串行 await，词库包结构不对就永久白屏 |
| `bank.dart` `applyRaw` | 逐行容错 + 跳过坏行；一条有效词都没有时**保留现有词库** |
| `bank.dart` `load()` | 远程包读不出来 / 解析不出词条，都要回退内置 `assets/words.json` |
| `auth.dart` `UserInfo` | 昵称是选填的，界面一律用 `displayName` / `initial`，不要直接 `.characters.first` |
| `progress_sync.dart` | 同步收尾只清「本轮确实推成功」的脏标记（按 `last` 快照比对），同步期间的新进度必须留下 |
| `curriculum.dart` | debug 演示数据只留内存（`_demo`），用户真开始学时要 `_endDemo()` 清掉并落盘 |
| `curriculum.dart` `unitsOf` | 关数按词库算，别写死；复习关取「最近 5 个学习关」，且整个级别学完不再补复习关 |
| `progress.dart` `days` | 打卡按天存 `Set`，别改回计数器（跨天/改时间会漂移，且画不出日历） |
| `entitlement.dart` `canUnit` | 会员直接放行：后台 `units_per_level` 还是「每级 12 关」时代的旧值，会把人挡在 U13 |
| 界面文案 | 词数 / 主题数 / 版本号一律从 `bankSummary()` / `themeCount()` / `kAppVersion` 取，不写死 |

