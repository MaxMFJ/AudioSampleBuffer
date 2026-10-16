# Sound Desk for Windows

Windows 桌面播放器工程，按 `MacDesktopPlayer` 的控制台布局搭建，和现有 iOS/macOS targets 保持隔离。工程使用 WPF 和 Windows Media Foundation，可在 macOS 上交叉编译 Windows 目标；运行界面和播放功能需在 Windows 上验收。

## 当前实现

- 暗色半透明控制台、曲库侧栏、搜索、最近播放和收藏筛选
- 多选导入本地音频，持久化文件路径、最近播放时间和时长
- 播放、暂停、上一首/下一首、进度拖动、音量和三种循环模式
- `MediaElement` 使用 Windows Media Foundation 解码本机支持的音频格式
- 桌面歌词：优先读取同名 `.lrc`，按播放进度同步；缺少本地歌词时尝试 QQ 歌词并缓存
- 动态桌面背景层：显示在桌面图标后面，由原生 Direct3D 11 全屏着色器与实例化粒子渲染；提供 Mac 风格蜂窝、丁达尔、封面点阵，并保留 Windows 原版六边形效果；播放器控制器支持启用/关闭
- 播放器窗口内同步显示音频频谱，背景效果切换会同步到桌面层
- Windows 通知区域左键打开播放器浮层（封面、进度、播放/切歌/循环），右键提供菜单；关闭控制台会收起到通知区域并继续播放
- 桌面左侧提供可折叠歌曲抽屉，支持本地歌曲搜索/移除，以及网易云、QQ 和酷狗个人歌单入口；网易云和 QQ 歌单读取已接入，酷狗个人歌单接口仍待移植
- 本地用户歌单支持创建、删除、导入歌曲、添加已有歌曲、从歌单移除和重启后恢复；上一首/下一首按开始播放时的当前列表队列运行
- 歌词管理可保存显示开关、行数、切换方式、排列、位置、行距、宽度、字号和非当前行样式，浮层即时应用
- QQ 音乐、网易云、酷狗搜索及可用音源下载；下载曲目加入本地曲库
- WebView2 内嵌平台登录，登录后自动读取必要会话 Cookie，并按当前 Windows 用户使用 DPAPI 加密保存

平台服务接口会受曲库权限、会员状态和平台接口变更影响。登录由平台页面处理，Sound Desk 不读取或保存账号密码。内嵌登录需要远程电脑安装 Microsoft Edge WebView2 Runtime；Windows 11 通常已预装，其他环境可通过 Microsoft Edge WebView2 Runtime 安装程序提供。输出频谱采集 Windows 默认播放设备的 WASAPI loopback，因此会包含其他应用的声音。

## Windows 从代码更新并运行

先从托盘菜单退出正在运行的 Sound Desk，再在本目录的 PowerShell 中运行：

```powershell
.\build-windows.ps1 -Run
```

需要 .NET 8 SDK、Visual Studio 2022 Build Tools 的“使用 C++ 的桌面开发”工作负载和 Windows SDK。脚本先使用 Visual Studio MSBuild 重编 Direct3D DLL，再使用 `dotnet` 编译 WPF，无需打包。默认输出为 `bin\Release\net8.0-windows`。

原生渲染接口版本为 4，程序会识别旧 DLL 并记录原因。桌面挂载、原生初始化与首帧提交日志位于 `%LOCALAPPDATA%\SoundDesk\wallpaper.log`；首帧提交成功不代表已确认屏幕显示正常，仍需在 Windows 上观察效果。

### 特效移植范围

- 蜂窝：按 `CellularHive.metal` 移植膜面、孔洞、微粒、星场、光环、吉他颜色波与色调处理；颜色波保留八个槽位、2.8 秒寿命和四种默认配色轮换。
- 丁达尔：按 `Tyndall.metal` 移植各层舞台光与三维激光体积求交，保留上下双扇透视、横向扫动以及 CPU 触发后的渐入/保持/渐出。
- 点阵封面：按 `CoverDotMatrix.metal` 移植外部鼓点粒子、独立封面粒子、浅浮雕、吉他共振、钢琴波和透视投影；D3D 用实例化小四边形实现 Metal 的可变尺寸点。其他两个效果使用圆形唱片粒子。Alt 拖动封面旋转，Alt 双击复位，悬停和按压产生局部形变。
- 六边形：恢复最初 WPF 实现的六边形顶点、间距、五色调色板、透明填充/描边与频谱响应，替换此前 D3D 的近似图案。

当前使用 Mac 的默认情绪配色，尚未连接 Mac 的逐曲情绪生成结果。已移植非模型 DSP 的 4096 点 FFT、80 个 A 加权频段、HPSS 残差/平坦度及 SuperFlux 瞬态输入，接入封面粒子电流撕裂与波动。桌面渲染调度目标为 60 帧，实际帧率需在 Windows 上观察。模型音轨和吉他高潮尚未移植，吉他/钢琴使用与 Mac 无模型路径相同的频谱估计，模型专属信号保持为零；封面舞台歌词也未在此轮移植。因此原始几何和渲染公式的移植不代表所有歌曲的触发效果已经与 Mac 完全一致。效果选择器下方显示“原生特效”才表示新管线已加载；“兼容效果（简化）”表示原生初始化或渲染失败，具体原因见日志。

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
2. 导入几首本地 MP3/WAV/M4A，测试播放、暂停、切歌、拖动进度、音量和三种循环模式。
3. 搜索曲库、加入收藏、查看最近播放，然后退出并重开，确认曲库记录仍在。
4. 记录不能播放的格式、窗口缩放/高 DPI 问题和任何异常提示，便于继续修复。

## 尚待移植

- 酷狗个人歌单接口；网易云和 QQ 当前为只读歌单与歌曲加载，平台歌单编辑操作未移植
- YAMNet 曲目分类和 HTDemucs 音轨分析：现有模型为 Core ML `.mlpackage`，Windows 版需要可运行的 ONNX 模型与一致的音频预处理/输出映射后再接入
- 桌面歌词封面舞台效果、逐字高亮和多屏幕位置记忆

桌面渲染使用 `native/WallpaperD3D.vcxproj` 编译原生 Direct3D 11 DLL，首次在 Windows 上构建需要 Visual Studio 的“使用 C++ 的桌面开发”工具集和 Windows SDK。Mac 上的 .NET 交叉构建会跳过 Windows 原生 DLL；请在 Windows 上构建后测试 GPU 渲染。运行时体验仍需在远程 Windows 电脑验收。
