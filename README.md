# app_worddeer · 词鹿英语

英语单词学习 App（Flutter / Android）。词库来自 tooldeer.com 的 6 个英语小工具，A1–C1 共 7201 词。

## 目录结构

```
app_worddeer/
├─ design/            ← ★ HTML 原型文件夹（做功能前先在这里出效果）
│  ├─ demo.html       主原型：首页 + 学习会话（5对5配对）+ 词典 + 结算
│  ├─ demo1.html      闯关首页参考原型（级别→单元→关卡链、会员锁、付费墙）
│  ├─ shots/          原型截图存档
│  └─ README.md       原型工作流 + 已定稿规则（务必先读）
├─ lib/
│  ├─ main.dart       入口，4 tab 壳（学习/复习/词典/我的）
│  ├─ bank.dart       词库加载（assets/words.json + words.db）
│  ├─ progress.dart   SRS 间隔重复（7 档，10 分钟→30 天，box≥5 掌握）
│  ├─ curriculum.dart 课程进度（级别/12 关/12 主题/今日目标，独立持久化）
│  ├─ audio.dart      发音（默认 https://tooldeer.com，--dart-define=AUDIO_BASE 可覆盖）
│  ├─ confetti.dart   配对成功的纸屑粒子（Canvas + Ticker，固定 1/60 步长）
│  ├─ ui.dart         主题/配色
│  ├─ preview.dart    无需首页直达各玩法（--dart-define 或路由 ?q=flash|choice|spell|listen）
│  ├─ match_probe.dart 配对棋盘截图入口（跑自动演示并导出帧，仅开发用）
│  └─ pages/          home / match（5对5配对棋盘）/ session / review / dict / me
├─ windows/           桌面预览工程（430x900 手机比例窗口，仅用于快速看 UI）
├─ assets/            words.json（7201 词）、words.db（SQLite 索引）
├─ tools/asset_build/ 词库再生成脚本（build_db.py + TSV 源）
└─ test/              冒烟测试 + 配对游戏回归（变绿停留 / 只 2 张红 / 整局到结算 / 补位换位）
```

## 已移植：5 对 5 配对棋盘（`lib/pages/match.dart`）

首页点任意关卡进入。原稿是 `design/game-a-desk.html`（方案 A 经典版），逻辑、配色、时间轴逐项对齐。

**规则**
- 左列英文、右列中文，两列各自打乱 —— 配对的两张通常不在同一行，靠词义找，不靠位置。
- 一对卡消失后，**空位会和邻近的格子换个位置再补新词**（只搬一张卡、最多挪两格，不是整列重排），
  所以补位位置不固定；并且新词的两半**绝不会补在同一行** —— 否则那一行就是现成的一对，
  用户闭着眼一直点同一行就能连对。开局也做同样的修正（两列各自打乱后，偶然同行同词的会被换开）。
- 点左边英文再点右边中文：判定正确 → 变绿 → 停 680ms 让人再看一眼词形（答对可能是猜的）→ 蹦一下 → 炸成纸屑 → 淡出 → 新卡补位。
- 判错：只有**被点的那两张**变红上下颠（420ms），颠完**红标撤掉、恢复白卡**。
  卡片**不退场、不换词、不挪位** —— 点错不该被打断：一换牌桌面就跳一下，注意力被拉走，
  而且这两个词被洗到别处后，用户反而记不住「我刚才错在哪」。红卡恢复后原地继续选，直到配对正确。
  同一个词的另一半**不做任何视觉变化**（不变色、不变虚线、不淡出、不抖）——
  原来的「虚线灰卡」等于把正确答案指给用户，已去掉。
- 桌面清空且队列空 → 结算（正确数 / 一次选对率 / 最高连击 / 配错词）。

**动效时间轴**（`_T` 常量，微调节奏只改这一处）

| 时刻 | 发生什么 |
| --- | --- |
| 220ms | 判定：两卡变绿 + 绿色柔光，**轻轻抬 10px**、再微弹一下停在 -3.5px 的悬浮位（0.28s，全程不下沉） |
| 220–900ms | 绿卡悬在原位停住 —— 给用户「再确认一眼词形」的窗口 |
| 900ms | 起爆：20 片纸屑（两张卡各 10 片）+ 卡片 0.8s 慢速化掉 |
| 1600ms / 1770ms | 残影散尽 → 新卡补位 → 解锁 |

**配错**不走上面这条时间轴：点下第二张卡的 220ms 后判定，2 张卡变红抖动 420ms，
520ms（`_T.wrongClear`）时红标撤掉、解锁，牌面完全没动。

补位那一下的「换位置」（`_nudgeHoles` / `_refill`）：
- 消失的两格先和邻近的格子换内容（`CardFx.slide`：朝原位方向偏 14px、300ms 回位），
  空位挪一格最多两格，新词就补在挪过去的那格 —— 位置不再能靠记忆锚定。
- 位移只有 14px，**不按整格滑**：整格滑动的卡会压住相邻行的卡，用户点下去会点到别人的格子。
- 每列的空位配对是整体找「错排」的（打乱后撞行就整串循环移位），不是填一个算一个 ——
  逐个挑会死在「最后只剩同一行」，那个词就只能同行补位，又变成白送格。

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
- 设计原型中已定稿的规则（每关 50 词、5 对 5、错词回流、每 5 关复习、主题每级只开第一个…）见 `design/README.md`
