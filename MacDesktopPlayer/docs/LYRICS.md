# Mac 歌词模块

`LocalAudioPlayer.lyricsController` 是歌词控制入口。播放器只负责歌曲切换、清空和提供播放时间，不再负责歌词排版。

## 模块职责

- `DesktopLyricsSource`：读取同名 LRC、缓存、音频内嵌歌词和在线歌词；解析时间轴；切歌取消旧请求，避免旧歌词覆盖新歌。
- `DesktopLyricsController`：根据播放时间选择显示行，计算当前行进度，以及位置、字号、透明度等显示参数。
- `DesktopLyricsOverlay`：普通桌面歌词的 AppKit 显示层。
- `CoverStageLyrics`：封面舞台的 Metal 显示层，只消费控制器生成的快照。

## 调整配置

控制台右上角的“歌词管理”打开独立管理窗口，可切换桌面浮层与封面舞台，调整开关、行数、切换方式、排列、位置、宽度、字号和非当前行样式。修改立即生效并保存到本机 `UserDefaults`；恢复默认仅影响当前选中的显示区域。

在主线程修改配置，下一帧生效。普通桌面使用 `overlayConfiguration`，封面舞台使用 `stageConfiguration`。默认分别为四行分散布局和五行居中布局。

```swift
var configuration = audio.lyricsController.stageConfiguration
configuration.lineCount = 3
configuration.position = CGPoint(x: 0.5, y: 0.75)
configuration.lineSpacing = 0.06
configuration.fontSize = .fixed(36)
configuration.maxWidthFraction = 0.8
configuration.inactiveOpacity = 0.4
audio.lyricsController.stageConfiguration = configuration
```

位置采用视图比例坐标，左上角为 `(0, 0)`，右下角为 `(1, 1)`；间距为视图高度比例；固定字号使用 AppKit 点数。显示行数限制为 1～12 行；`isEnabled` 控制该显示面的歌词开关。

`window = .centered` 让当前行位于配置锚点，`window = .grouped` 按行数整组切换。`layout = .column` 使用纵向间距；`.scattered([CGPoint])` 为各行指定相对锚点的偏移，未提供偏移的行使用纵向排列。

## 新增歌词特效

调用 `frame(at:surface:viewport:)` 获取 `DesktopLyricsFrame`，交给新的显示层。每一行包含文本、时间轴索引、当前行标记、行内播放进度（0～1）、位置、字号、字重、透明度和最大宽度。显示层可用进度驱动扫光、粒子、渐变等动画，无须重复读取歌词或选择时间轴行。

空文本代表时间轴边缘的占位行，应跳过绘制；关闭显示时快照行数组为空。Metal 显示层保留现有舞台投影和交互，配置位置作为投影前的布局锚点。
