# 词鹿英语・App 图标源文件

当前上线图标：**小鹿脸（无吊牌・微笑版）**，iOS 与 macOS 均已使用。

## 一、这份图是怎么来的（说实话版）



* **不是矢量、不是手绘、也没有分层工程文件**。它是 AI 图像模型（豆包图像生成 / Seedream 5.5）按提示词生成的**位图**，一次出图 1536×1536。

* 流程是「文生图出候选 → 选定方向 → 以该图为参考做图生图微调」，每一步都基于上一张图，所以**同样的小鹿脸能保持住**。

* 因此 “原始文件”= `source/` 下的 **1536×1536 PNG 母版**（无损、未压过）。图标各尺寸都是从母版等比缩出来的，没有单独重绘。

如果你要的是能像设计稿那样拖锚点、改矢量路径的源文件，目前没有：要那种得再做一个 SVG/Figma 版本（见第四节）。

## 二、文件清单



```
design/app-icon/
├── source/                          ← 母版，改图从这里出发
│   ├── deer-final-1536.png          ★ 最终版（无吊牌 · 微笑）→ 当前 iOS/macOS 图标
│   ├── deer-nosmile-1536.png          上一版（无吊牌 · 原表情），想回到“呆一点”用它
│   └── w-mark-1536.png              鹿角 W 字标母版
├── backup-w-mark/                  ← 「鹿角 W」整套备份，随时可切回
│   ├── AppIcon.appiconset/            iOS 全套 13 个尺寸 + Contents.json
│   ├── AppIcon-macos.appiconset/      macOS 全套 7 个尺寸 + Contents.json
│   ├── w-mark-master-1536.png
│   └── worddeer-apple-icons.zip       当时交付的打包
├── tools/export-apple-icons.sh      ← 一键导出 iOS/macOS 各尺寸
```

## 三、生成提示词链（复现用）

**1）候选（一次性出 4 个方向）** —— 小鹿脸方向：

> 暖米色背景，扁平卡通小鹿脸，正面，浅棕鹿角，圆眼、腮红、白色菱形额斑、颈圈绒毛，粗圆描边，扁平无阴影无渐变，1:1 方形。

**2）吊牌版（图生图，参考 1）**

> 保持小鹿五官与配色，鹿角上挂两张白色小吊牌：左牌写 “Aa”，右牌画两条横线，扁平无阴影。

**3）小尺寸友好版（图生图，参考 2）**

> 吊牌贴在鹿角中段、不垂到耳朵，左牌只留一个粗笔画 A，右牌一条粗横线，主体占画幅 75%。

> 注：第 2、3 步的带吊牌图最终没有被采用，文件已删除，只保留提示词作为过程记录；需要复现可按上面两句重跑图生图。

**4）去掉吊牌（图生图，参考 3）**

> 去除鹿角上两张卡片和细绳，鹿角恢复干净完整，其余完全不变；画面不出现任何文字、字母、横线。

**5）微调表情（图生图，参考 4）→ 最终版**

> 只微调表情：下眼睑带笑意、眼珠高光略放大、眉毛轻抬、嘴角改成轻微上扬的浅笑、腮红更饱满；脸型 / 鹿角 / 耳朵 / 配色 / 描边 / 背景 / 构图完全不变。

**微调口诀**：永远写 “**只改 X，其余（列清单）完全不变**”。不列清单，模型会顺手重画脸、改耳朵比例、动背景色。

## 四、后期怎么改



| 想做的事              | 做法                                                                                                         |
| ----------------- | ---------------------------------------------------------------------------------------------------------- |
| 换小表情、去 / 加小元素、换底色 | 用 `source/deer-final-1536.png` 当参考做图生图，提示词按上面第 5 步的写法；改完存回 `source/`，再跑导出脚本                                |
| 回到 “无表情 / 呆一点”    | 直接用 `source/deer-nosmile-1536.png` 覆盖导出                                                                    |
| 切回鹿角 W            | 把 `backup-w-mark/` 里两个 `.appiconset` 覆盖到 `ios/Runner/Assets.xcassets/`、`macos/Runner/Assets.xcassets/`，重编译 |
| 要精确到像素级控制         | 需要重新做**矢量版**（Figma/Illustrator 重绘或描摹成 SVG），位图无法精修路径；弄好后可以再从 SVG 导出 PNG                                     |

## 五、导出与验证



```
# 默认用最终版母版，同时导 iOS + macOS
./design/app-icon/tools/export-apple-icons.sh

# 指定母版 / 只导某个平台
./design/app-icon/tools/export-apple-icons.sh design/app-icon/source/w-mark-1536.png ios

# Android：传统图标 5 个密度 + 自适应图标（108dp 前景 + 背景色）
"<python>" design/app-icon/tools/export-android-icons.py
"<python>" design/app-icon/tools/export-android-icons.py --preview   # 先看遮罩裁切效果

# 编译验证
flutter build ios --release        # 真机安装需签名，Team 45T7T52685 已配
flutter build macos --debug
flutter build apk --release
```

**Android 与 Apple 的区别**：自适应图标的前景画布是 108dp，系统只保证中间 72dp 的圆形安全区可见。
母版主体几乎顶到四边，直接铺满会被裁掉鹿耳，所以脚本把主体缩到 0.76 居中、四周填母版底色
（`#FEF0E3`，采自画面角落，遮罩边缘无接缝）。`--preview` 会输出 0.72/0.76/0.80 三档的圆形裁切对比图，
0.80 开始裁耳，这是上限。

**图标红线（Apple 要求）**



* 所有尺寸 **不能有 alpha 通道**，1024 商店图必须不透明

* 不预先切圆角，系统会自己做遮罩

* 内容占比约 75%，四周留白均匀，别贴边

* iOS 目录 `ios/Runner/Assets.xcassets/AppIcon.appiconset`，macOS 目录 `macos/Runner/Assets.xcassets/AppIcon.appiconset`（文件名是 Flutter 模板固定的，只换图不改 `Contents.json`）