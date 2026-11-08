# design/ — HTML 原型文件夹（功能先行）

> 规则：**做一个功能前，先在这里用 HTML 做出来、看得过去，再移植到 Flutter。**
> 不直接改 Dart 攒 UI —— Dart 改 UI 成本高，HTML 改一遍只要几秒刷新。

## 文件说明

| 文件 | 内容 |
|---|---|
| `demo.html` | 主原型：首页（级别选择 / 学习进度卡 / 模式小 pill / 关卡树 / 主题锁）+ 学习会话（5对5 配对）+ 词典 + 结算。词库内联在文件里（A1 452 词） |
| `demo1.html` | 闯关首页参考原型：级别 tab → 单元卡 → 关卡链，付费墙、访客/会员锁 |
| `game-pick.html` | **游戏界面三方案对比页**（iframe 并排缩略 + 要点对比），选型用 |
| `game-a-desk.html` | 游戏界面方案 A · 卡片桌（经典左右分栏，卡牌有厚度） |
| `game-b-link.html` | 游戏界面方案 B · 连线（极简白底，配对画贝塞尔曲线） |
| `game-c-merge.html` | 游戏界面方案 C · 消消乐混排（深紫底、打乱混排、粒子动效） |
| `shots/` | 每次改版的整页截图（无头 Chrome 出图） |

## 工作流（每个新功能照这个顺序）

1. **原型**：在 `design/` 里新建或改现有 `demo*.html`，浏览器打开就能点。
   - 单文件、无构建、词库数据内联或 `<script src>` 引 json
   - 交互要真实可点（配对、锁、toast、结算都做出来）
2. **定稿**：无头 Chrome 截图留档到 `design/shots/`：
   ```
   "C:\Program Files\Google\Chrome\Application\chrome.exe" --headless=new --no-proxy-server ^
     --force-prefers-reduced-motion --hide-scrollbars --virtual-time-budget=4000 ^
     --user-data-dir=<临时目录> --window-size=1400,980 ^
     --screenshot="design\shots\xx.png" "file:///D:/phpstudy_pro/WWW/go/app_worddeer/design/demo.html#锚点"
   ```
   深链锚点：`#theme` `#free` `#session` `#done` `#dict` `#lv-B1` `#theme-lv-A2`（可组合）
3. **移植**：原型确认后，把交互规则翻译成 Dart（会话引擎在 `lib/pages/session.dart`，页面在 `lib/pages/`）。
4. **记录**：每张原型卡片的规则（每关 50 词、错词隔 2~3 次配对重现、每 5 关复习…）写进本文件下方「已定稿规则」。

## 已定稿规则（原型确认过的）

- **一关 50 词**，一屏 5 对 5；配对成功即时消失、从词池补位
- **错词回流**：配错进重试队列，隔 2~3 次成功配对后重现，直到配对正确才计过关
- **每 5 关一个复习关**（U6、U12…），复习前 5 关全部词
- **三种模式**（小 pill，不抢焦点）：关卡 / 主题 / 自由；同一套会话引擎
- **首页结构**：问候+进度副行 → A1–C1 级别卡（带 mini 进度条）→ 今日目标条 → 模式 pill → **学习进度卡（紫底、圆环 32/50、点击续学）** → 列表
- **主题模式**：每个级别只免费开放第一个主题，其余金锁（会员）；关卡树的灰锁 = 进度未到，两种锁严格区分
- **卡片信息**：英文卡=单词+音标，中文卡=释义+词性；辅助行小 5px、透明度 50%
- 中途退出也记进度（`state.part`），进度卡圆环显示"学到一半"，重做只取更大值不倒退

## 游戏界面三方案（2026-10-31，待选型）

三份都是**可玩的完整实现**，同一套引擎规则，只在界面语言上分叉。三份都支持深链
`#mid`（进行中，带选中态与连击）和 `#done`（结算页），便于截图评审。

| | A 卡片桌 | B 连线 | C 消消乐混排 |
|---|---|---|---|
| 排版 | 左右分栏固定（左英右中） | 左右分栏 + 中间 64px 通道 | 10 张卡打乱混排 |
| 卡片 | 白底 + 底部实阴影（卡牌厚度） | 无边框浅灰块，左卡右对齐、右卡左对齐 | 白卡 + 淡青卡，右上角喇叭／"中" 标记 |
| 配对反馈 | 变绿 → 跳起 → 炸成纸屑+碎片 → 淡出补位 | 画紫→绿贝塞尔曲线，端点圆点 | 卡放大发绿光 + 8 粒粒子 + 飘字 `en = zh` |
| 选中引导 | 卡片抬起 3px | 卡片竖条 + 指向中缝的虚线牵引 | 黄色描边 + 抬起 |
| 背景 | 浅紫灰 | 纯白（极简） | 深紫渐变 + 光斑 |
| 情绪强度 | 中 | 低（安静、专注） | 高（游戏感） |
| Flutter 移植成本 | 最低（与 demo.html 同构） | 中（连线要 CustomPainter） | 中（粒子 + 混合布局） |
| 建议人群 | 成人 / 正式学习 | 高年级 / 工具型 | 青少年 / 追留存 |

**共同实现**：5 对 5 同屏、点两张判定、配对成功即补位、配错延迟 2 次重现直到配对正确、
连击计数、计时、顶部进度（演示 `x/20`，正式每关 50）、结算（正确数 / 一次选对率 / 最高连击 / 错词回顾）。

## 玩法定稿：A 卡片桌 + 打击感动效（2026-10-31）

已选定 A。动效时间轴（`game-a-desk.html`，常量在 `const T = { judge:220, burst:680, gone:700, wipe:170 }`）：

| 时刻 | 发生什么 |
| --- | --- |
| 0ms | 点第二张卡 → **220ms 判定缓冲**（防误触） |
| 220ms | 配对正确：两卡变绿（`ok`）+ **跳起 18px 后停在 -5px 悬浮位**（`hop` 0.4s，收尾不回落到 0）+ 底部 `✓ en = zh` |
| 220–900ms | **绿卡原地停住 680ms** —— 答对不等于记住（可能是猜的），这段是留给用户再看一眼词形的确认窗口 |
| 900ms | 起爆：Canvas 粒子（见下），**没有冲击环**（试过绿色圆圈，太像 UI 控件，已删） |
| 900ms 起 | 卡片 **0.8s 慢速化掉**到 12% 并微缩至 .965，纸屑飞时字仍辨得清 |
| 1600ms | 残影散尽 → 170ms 后空白位被新卡顶上来（`pop`） |
| 1770ms | 解锁，可以点下一对（整段比初版慢约一倍） |

### 纸屑：Canvas 粒子（照 `tooldeer_com/views/home/tools/e/engmatch.html` 的 fireConfetti 改）

原来用 CSS 给每个 `.paper` 元素套 keyframes，最多只能做出“抛物线飞出去”的观感。
参考 engmatch 的彩纸后换成 canvas 逐帧积分，纸屑才像真纸片：

- 每片是**实心色块**（`fillRect`，无阴影无描边），四成细长条 3~5px × 12~19px、六成小方块 5.5~11px × 7~14px，10 色；
- 物理：`vy += .062`（重力）+ `vx *= .993`（空气阻力）+ `Math.sin(life * .055 + ph) * sway`（左右飘）+ 自转；
- 寿命 2.7~4.2 秒，**前 60% 保持实心、后 40% 才淡出**，所以看得见它飘，而不是一闪就没；
- 固定 1/60s 物理步长（`CF_STEP`，累加器驱动），掉帧或 120Hz 屏上飘落速度都一致；
- 炸点**不是单个中点**：中英两列各自打乱，配对的两张卡常常不在同一行，取中点会在中缝“空爆”。
  现在沿两卡连线布 3 个爆发点（16 + 14 + 16 片）= 两张卡各自碎掉 + 中间一道纸屑带。

纸屑要够猛但不能脏：canvas 单层铺满 `.frame`，靠 `.top / .cols / .foot` 的 `z-index:7` 让纸屑从 HUD **身后**飞过，标题、`12/20` 计数、连击、底部提示始终清晰。
（canvas 改尺寸会清空画布，`sizeFx()` 里补了重绘，否则窗口一变纸屑就凭空消失。）

### 配错：只动 2 张，不连带整桌

配错时被点的 2 张**上下颠 4 下**（-8 → +7 → -5 → +4 → -2，0.42s）。但错配要作废的其实是 **2 对**——
这两个词的另一半留在桌上会变成配不上对的孤卡，所以必须一起退场。处理办法：

- 另外 2 张“连坐卡”加 `.void`：实底浅灰 + 虚线边 + 文字变淡，**不抖、不弹、不可点**，一眼读作“这半张也作废了”；
- 900ms 后 4 张同一帧换牌，新卡用 `.fade`（纯 opacity 淡入，**没有缩放和位移**）并以 80/120ms **错峰**浮现；
- 于是屏幕上永远只有 2 张在“动”，不再是 4 张卡一起抽搐。

（用实底浅灰而不是整体 `opacity`，是为了不让桌面中缝的竖虚线透过卡片。）

音效：`ok`（880+1320Hz 双音）+ `paper`（1250→2340Hz 四连短“唰”）+ 震动 26ms/16ms；配错是 180Hz 低鸣 + `[40,60,40]` 震动。

**看效果**：
- 直接打开 `game-a-desk.html` 点卡片（真实时序）
- 静态帧深链：`#burst:600`（绿卡确认停留帧）、`#burst:1000`（起爆中）、`#burst:1300`（纸雨飘落）、`#wrong:80`（配错抖动）；数字=点第二张卡后第几毫秒
- 动图：`shots/g-a-burst-slow.gif`（0–2000ms 逐 100ms 一帧）、封面 `shots/g-a-burst-slow.png`、逐帧 `shots/g-a-burst-frames.png`
- 配错动图：`shots/g-a-wrong-slow.gif` + `shots/g-a-wrong-slow.png` + 逐帧 `shots/g-a-wrong-frames.png`（用 `#autow` 真实点击 + `--virtual-time-budget` 逐帧截）
- 深链静态帧：牌面用 `seedRnd` 固定，纸屑则是**把物理循环直接推进到第 N 帧再停住**（`burstPair(a,b,frames)`，不走 rAF），所以每帧可重复出图

**回归验证**：三份都注入脚本跑过「正确配对 → 补位 → 错误配对 → 再补位」，
结果一致为 `done=1 / en_tiles=5 / blanks=0`，无空白位、无重复卡。
A 另加了两条无头回归深链（把断言写进 `document.title`，`--dump-dom | grep title` 即可读）：
- `#auto` → `AUTO done=1 en=5 zh=5 blank=0 lock=0`
- `#autow` → `AUTOW bad=2 void=2 | final en=5 zh=5 blank=0 bad=0 void=0 lock=0`（抖动期恰好 2 红 + 2 灰，补位后无残留态）

## 已移植到 Flutter（2026-10-31）

首页已按 `demo.html` 定稿实现到 `lib/pages/home.dart`，对照关系：

| 原型 | Flutter |
| --- | --- |
| `.greet` + `.levels` + `.goal` | `_header` / `_levels` / `_goal` |
| `.segrow` 模式小 pill | `_modeBar` + `_modePill`（0=关卡 1=主题 2=自由） |
| `#lvHero` `.pcard` 圆环进度卡 | `_heroCard` + `_ring`（CircularProgressIndicator） |
| `.tree` / `.lvl` 关卡树 | `_tree` + `_unitRow`（虚线用 `_DashPainter`） |
| `.themes` / `.tcard` 主题网格 | `_themePanel` + `_themeCard` |
| 数据 `state.levels/part/themes` | `lib/curriculum.dart`（`Curriculum.I`，键 `A1:U3`） |

已在模拟器（Medium_Phone_API_37.0）实测三模式首页无溢出，截图见 `docs/home-0*.png`。

### 游戏界面 A 已移植（2026-10-31）

`game-a-desk.html` → `lib/pages/match.dart`（首页点关卡进入），粒子 → `lib/confetti.dart`。

| 原型 | Flutter |
| --- | --- |
| `S.enSlots / S.zhSlots`（5 对） | `_en` / `_zh`（`List<_Card>`） |
| `.card` 的 `sel/ok/bad/blasting/gone/blank` | `_Card` 的 `sel/ok/bad/blasting/opacity` + `CardFx` |
| `hop` / `shake` 关键帧 | `_CardView` 里按 `_t` 逐段算 translateY 与 scale |
| `pop` / `fade` 入场 + 错峰 `animationDelay` | `CardFx.pop/fade` + `fxDelay`（`Timer` 后再 forward） |
| `burstPair()` + `<canvas>` 粒子 | `ConfettiField.burstBetween()` + `ConfettiOverlay`（CustomPaint + Ticker） |
| `T = {judge:220, burst:680, gone:700, wipe:170}` | `class _T` 同名常量 |
| `brief(w)` 释义缩略 | 顶层函数 `_brief()`（同算法） |
| `#auto` / `#autow` 无头回归 | `test/match_test.dart` 三条 + 首页跳转一条 |

差异（有意为之）：Flutter 用 `HapticFeedback` 替代 WebAudio 合成音效（音效资源待补）；
浏览器 `:active` 的按下反馈换成 `InkWell` 水波；
**配错时同一个词的另一半不再变灰**（原型里的 `.void` 虚线灰卡等于把正确答案指出来）；
**配错的卡不退场**——原型判错后 2 对牌一起换掉，Flutter 版只让被点的那两张红 420ms，
520ms 后恢复白卡、原地继续选，牌面不动；
起爆纸片从 40 片减到 20 片；
**答对的卡只是「轻轻一抬」**——原型 hop 抬 18px / 0.4s 且收尾会压到 +3px / scale .976（像凹进桌面），
Flutter 版抬 10px / 0.28s，收尾停在 -3.5px / scale 1.018，配一层拉远的投影做出轻微悬浮；
**补位位置会挪动**——原型是原位补位（消失哪格就填哪格），位置固定，用户闭眼点同一行就能连对；
Flutter 版把空位和邻近格子换个位置再补（`CardFx.slide`，14px 微位移），并保证新词的两半不补在同一行，
开局也做同样的错位修正。

回归：`flutter test` 覆盖「变绿停留时词还在 → 补位后换掉且同列不重复」、
「配错恰好 2 红、另一半不变色、牌面一字不动且能重新点」、
「整局 10 对能打到结算」、「首页点关卡能进棋盘」、
「补位换了格子且整桌没有一行同词」、「固定点同一行 6 次不会连对」。


## 待定稿 / 未做

- 复习关 250 词偏长（建议错词 + 随机补满 50，或每关抽 10 词）
- 会员购买弹层（demo1 有，demo.html 还只有 toast）
- 音频源授权（现为第三方转发，`lib/audio.dart` 的 `kAudioBase` 可用 `--dart-define=AUDIO_BASE` 覆盖）
