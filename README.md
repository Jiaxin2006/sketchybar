# SketchyBar · Focus & Mood

macOS SketchyBar 配置：正计时、25 分钟番茄钟、科研 / 课程 / 社工分类，以及当天、本周统计。保留 CPU、内存、电量、音量、应用菜单、网络和心情记录等状态栏组件。

A minimal macOS status bar with a categorized stopwatch, Pomodoro timer, daily/weekly focus totals, and a one-click mood logger. Category labels: **Research · Study · Service · Other**. All history stays on your Mac; the timer uses Python's standard library and SQLite.

## 计时和分类

点击计时器旁的类别（例如 `Research ▾`），选择 **Research（科研）、Study（课程）、Service（社工）、Other（未分类）**。新安装默认科研，之后记住选择。切换桌面、显示器或前台应用时，下拉菜单会自动关闭。计时进行中或暂停时都可以修改分类，计时长度保持连续。**保存结束那一刻的类别决定整次计时的归属**；例如先选 Research，结束前改成 Study，整次时间都会记入 Study。已保存记录的类别不会随下一次选择改变。

| 当前状态 | 左键点计时器 | 右键点计时器 |
| --- | --- | --- |
| 空闲 | 开始正计时 | 开始 25 分钟番茄钟 |
| 正计时 / 番茄超时 | 保存并结束 | 暂停 |
| 番茄倒计时 | 继续计时 | 暂停 |
| 暂停 | 继续 | 丢弃本次全部计时 |

番茄钟到时播放提示音，随后显示超时长度，保存时包含前 25 分钟。合盖或系统休眠自动暂停，唤醒后手动继续。重载配置保留状态；重启电脑后恢复为暂停并排除关机时间。

## 当天 / 本周统计

点击计时器右侧的 **今日累计时长**，弹出两组分类统计：

- 当天：本机时区的今天 00:00 起。
- 本周：周一 00:00 起，到当前时刻；标题显示周一至周日的日期范围。
- 每组显示科研、课程、社工、未分类，以及合计。
- 弹窗包含正在进行或暂停的本次计时，整次暂按当前选中类别预览，保存时固定。打开时立即更新，此后每 10 秒刷新；丢弃后该次时间从统计中扣除。
- 顶栏累计时长和轨迹展示**已保存**的当日时间，保存或跨日时更新。
- 跨午夜、跨周的计时按实际工作区间拆分；暂停时间不计入。

旧版 `data/focus_YYYY-MM-DD.log` 保留原样，并计入“未分类”。升级时已有计时也按“未分类”迁移；旧版暂停累计时间缺少日期信息，归到升级当天，尚在运行的区间按起止时间拆分。

## 心情记录

点击右侧心情图标，选择开心、平静、专注、疲惫、低落或充满动力。当前图标随选择更新，每次记录带本地时间写入 `data/mood.log`。心情选择界面和记录逻辑随配置一起提供，个人日志不上传。

## 实测范围

在 macOS 26.5 / SketchyBar 2.24.0 上加载验证；15 项自动化计时测试通过。已实测桌面、显示器和前台应用切换事件关闭分类与统计弹窗，并停止统计弹窗轮询。合盖和休眠逻辑有自动化覆盖，尚未做真实合盖测试。

## 安装

需要 macOS、SketchyBar、Python 3.9+、Hack Nerd Font。中文使用系统的苹方字体。

安装 SketchyBar 可参照 [官方安装说明](https://felixkratz.github.io/SketchyBar/setup)。已安装 Homebrew 时可使用：

```sh
brew tap FelixKratz/formulae
brew install sketchybar python
brew install --cask font-hack-nerd-font
```

克隆并安装：

```sh
git clone https://github.com/Jiaxin2006/sketchybar.git
cd sketchybar
./install.sh
sketchybar --reload
```

首次启动可使用 `brew services start sketchybar`。安装脚本在覆盖配置前创建同级时间戳备份，保留已有个人数据；它不会自动重载状态栏。更新时在克隆目录执行 `git pull`、`./install.sh` 和 `sketchybar --reload`。

原生应用菜单可能需要在“系统设置 → 隐私与安全性 → 辅助功能”中授权。`helpers/menus` 保留原来的可选 C helper，可在其目录执行 `make` 编译；当前菜单插件主要使用 AppleScript。

## 本地数据

- `~/.config/sketchybar/data/focus.sqlite3`：新版已保存时长、选中类别、运行状态和本次尚未保存的区间。
- `~/.config/sketchybar/data/focus_YYYY-MM-DD.log`：旧版专注记录，读取兼容，不改写。
- `~/.config/sketchybar/data/mood.log`：心情记录。

SQLite 事务同时保存计时状态和统计记录，避免并发点击、定时刷新或保存中断导致重复入账。数据库和所有个人日志均已通过 `.gitignore` 排除。备份个人统计时保留整个 `data/` 目录。不要删除数据库来重置计时，否则会同时删除新版历史。

计时和统计遵循当前系统时区；更换时区不会重新分配已保存记录的日期。

## 验证

```sh
python3 -m unittest discover -s tests -v
bash -n sketchybarrc install.sh
```

测试使用临时目录，覆盖分类切换、暂停/继续/丢弃、跨日跨周、旧日志迁移、睡眠暂停、番茄钟与事务回滚，不写入真实历史。

布局来源于本地已有 SketchyBar 配置，原配置注明参考 [FelixKratz/dotfiles](https://github.com/FelixKratz/dotfiles)。状态栏接口参考 [SketchyBar 文档](https://felixkratz.github.io/SketchyBar/config/events)。
