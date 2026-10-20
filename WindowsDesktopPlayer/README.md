# Sound Desk for Windows

Windows 桌面播放器工程，按 `MacDesktopPlayer` 的控制台布局搭建，和现有 iOS/macOS targets 保持隔离。工程使用 WPF 和 Windows Media Foundation，可在 macOS 上交叉编译 Windows 目标；运行界面和播放功能需在 Windows 上验收。

## 当前实现

- 控制台与 Mac 单栏布局一致（1040×700）：标题区、歌曲列表/歌词管理/平台账号/窗口预览/平台歌单入口、在线搜索与下载、视觉效果按钮、播放栏和开关区；Windows 11 22H2 及以上使用亚克力背景，旧系统保留渐变
- 在线搜索与 Mac 相同走 qqmp3 接口，下载后按文件头识别 flac/wav/m4a/mp3/aac，附带歌词时写同名 `.lrc`，加入本地曲库并立即播放；文件位于 `%LOCALAPPDATA%\SoundDesk\Downloads`
- “选择本地歌曲”与 Mac 相同：选一首文件后单曲播放
- 播放、暂停、停止、上一首/下一首、收藏、音量和三种循环模式；`MediaElement` 使用 Windows Media Foundation 解码
- 桌面歌词：优先读取同名 `.lrc`，按播放进度同步；缺少本地歌词时尝试 QQ 歌词并缓存
- 动态桌面背景层：显示在桌面图标后面，由原生 Direct3D 11 渲染丁达尔光束（默认）、封面点阵、深空蜂巢和 Windows 原版六边形；控制台可开关
- 氛围光 AI：按 Mac 的提示词调用 OpenAI 兼容接口（默认 DeepSeek），为每首歌生成 10 组情绪配色并按“模型|歌名|歌手”缓存；API Key 用 DPAPI 加密保存。未配置 Key 时使用 Mac 默认配色
- 吉他高潮全屏扫光（鼓点同步）和“其他特效显示圆形唱片”开关，状态写入 `desktop-options.json`
- 左侧歌曲抽屉对齐 Mac：72×120 把手滑出 324 宽面板，分段切换本地/网易云/QQ/酷狗；平台模式 280 ms 防抖搜索、横向歌单卡片、封面行、滚动到底自动加载下一页（每页 40）、单击播放、加载卡片；平台歌曲连播按所在列表切换上一首/下一首，并预取下一首
- 通知区域浮层对齐 Mac：封面模糊背景、居中歌名、进度条、上一首/播放/下一首、循环、打开控制台、退出程序；右键菜单保留
- 平台账号窗口：网易云/QQ/酷狗登录状态、内嵌登录、刷新、退出账号
- 平台歌单窗口：浏览三个平台的个人歌单和歌曲并播放
- 窗口预览：用 DWM 缩略图实时预览任意顶层窗口，可置顶
- 酷狗个人歌单、歌单歌曲和多端点播放地址解析已按 Mac 移植
- 歌词管理可保存显示开关、行数、切换方式、排列、位置、行距、宽度、字号和非当前行样式，浮层即时应用
- WebView2 内嵌平台登录，登录后自动读取必要会话 Cookie，并按当前 Windows 用户使用 DPAPI 加密保存

旧版控制台的本地歌单、最近播放/收藏筛选和窗口内频谱已移除，以与 Mac 保持一致；`%LOCALAPPDATA%\SoundDesk\playlists.json` 不会被删除，但不再读取。

平台服务接口会受曲库权限、会员状态和平台接口变更影响。登录由平台页面处理，Sound Desk 不读取或保存账号密码。内嵌登录需要远程电脑安装 Microsoft Edge WebView2 Runtime；Windows 11 通常已预装，其他环境可通过 Microsoft Edge WebView2 Runtime 安装程序提供。输出频谱采集 Windows 默认播放设备的 WASAPI loopback，因此会包含其他应用的声音。

## Windows 从代码更新并运行

先从托盘菜单退出正在运行的 Sound Desk，再在本目录的 PowerShell 中运行：

```powershell
.\build-windows.ps1 -Run
```

需要 .NET 8 SDK、Visual Studio 2022 Build Tools 的“使用 C++ 的桌面开发”工作负载和 Windows SDK。脚本先使用 Visual Studio MSBuild 重编 Direct3D DLL，再使用 `dotnet` 编译 WPF，无需打包。默认输出为 `bin\Release\net8.0-windows`。

原生渲染接口版本为 5（帧常量缓冲 1120 字节，新增情绪配色、吉他扫光与显示选项），程序会识别旧 DLL 并记录原因。桌面挂载、原生初始化与首帧提交日志位于 `%LOCALAPPDATA%\SoundDesk\wallpaper.log`；首帧提交成功不代表已确认屏幕显示正常，仍需在 Windows 上观察效果。

### 特效移植范围

- 蜂窝：按 `CellularHive.metal` 移植膜面、孔洞、微粒、星场、光环、吉他颜色波与色调处理；颜色波保留八个槽位、2.8 秒寿命和四种默认配色轮换。
- 丁达尔：按 `Tyndall.metal` 移植各层舞台光与三维激光体积求交，保留上下双扇透视、横向扫动以及 CPU 触发后的渐入/保持/渐出。
- 点阵封面：按 `CoverDotMatrix.metal` 移植外部鼓点粒子、独立封面粒子、浅浮雕、吉他共振、钢琴波和透视投影；D3D 用实例化小四边形实现 Metal 的可变尺寸点。其他两个效果使用圆形唱片粒子。Alt 拖动封面旋转，Alt 双击复位，悬停和按压产生局部形变。
- 六边形：恢复最初 WPF 实现的六边形顶点、间距、五色调色板、透明填充/描边与频谱响应，替换此前 D3D 的近似图案。

情绪配色由氛围光 AI 逐曲生成，未配置时使用 Mac 默认配色。已移植非模型 DSP 的 4096 点 FFT、80 个 A 加权频段、HPSS 残差/平坦度及 SuperFlux 瞬态输入，接入封面粒子电流撕裂与波动。桌面渲染调度目标为 60 帧，实际帧率需在 Windows 上观察。吉他高潮扫光已按 Mac 的 BPM 与吉他门控逻辑移植，但没有 HTDemucs 时电吉他置信度为零，触发依赖频谱估计；模型音轨尚未移植，吉他/钢琴使用与 Mac 无模型路径相同的频谱估计，模型专属信号保持为零；封面舞台歌词也未在此轮移植。因此原始几何和渲染公式的移植不代表所有歌曲的触发效果已经与 Mac 完全一致。“视觉效果”右侧显示“原生特效”才表示新管线已加载；“兼容效果（简化）”表示原生初始化或渲染失败，具体原因见日志。

## macOS 交叉编译

安装 .NET 8 SDK 后，在此目录运行：

```sh
./publish-windows.sh
```

脚本会生成自包含的 Windows x64 包，不需要远程电脑另装 .NET Desktop Runtime：

```text
artifacts/SoundDesk-win-x64.zip
```

解压后运行 `win-x64/SoundDesk.exe`。只支持 x64 的 Windows 10/11 测试机；如果远程机是 ARM64，需要把发布 RID 改为 `win-arm64`。

## 远程 Windows 验收

1. 解压 ZIP 并启动 `SoundDesk.exe`，确认窗口和控制台布局正常。
2. 在控制台搜索并下载一首歌，确认自动播放；用“选择本地歌曲”播放 MP3/WAV/M4A，测试暂停、停止、切歌、音量和三种循环模式。
3. 打开歌曲抽屉切换平台、搜索、点歌单卡片、滚动加载更多，确认平台歌曲连播；托盘浮层拖动进度。
4. 切换四种视觉效果和两个开关，配置氛围光 AI 后换歌观察颜色变化。
5. 记录不能播放的格式、窗口缩放/高 DPI 问题和任何异常提示，便于继续修复。

## 尚待移植

- 平台歌单编辑操作（三平台均为只读）
- YAMNet 曲目分类和 HTDemucs 音轨分析：现有模型为 Core ML `.mlpackage`，Windows 版需要可运行的 ONNX 模型与一致的音频预处理/输出映射后再接入
- 桌面歌词封面舞台效果、逐字高亮和多屏幕位置记忆

桌面渲染使用 `native/WallpaperD3D.vcxproj` 编译原生 Direct3D 11 DLL，首次在 Windows 上构建需要 Visual Studio 的“使用 C++ 的桌面开发”工具集和 Windows SDK。Mac 上的 .NET 交叉构建会跳过 Windows 原生 DLL；请在 Windows 上构建后测试 GPU 渲染。运行时体验仍需在远程 Windows 电脑验收。
