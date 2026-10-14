# Sound Desk for Windows

Windows 桌面播放器工程，按 `MacDesktopPlayer` 的控制台布局搭建，和现有 iOS/macOS targets 保持隔离。工程使用 WPF 和 Windows Media Foundation，可在 macOS 上交叉编译 Windows 目标；运行界面和播放功能需在 Windows 上验收。

## 当前实现

- 暗色半透明控制台、曲库侧栏、搜索、最近播放和收藏筛选
- 多选导入本地音频，持久化文件路径、最近播放时间和时长
- 播放、暂停、上一首/下一首、进度拖动、音量和三种循环模式
- `MediaElement` 使用 Windows Media Foundation 解码本机支持的音频格式
- 桌面歌词：优先读取同名 `.lrc`，按播放进度同步；缺少本地歌词时尝试 QQ 歌词并缓存
- 动态桌面背景层：显示在桌面图标后面，由原生 Direct3D 11 全屏像素着色器渲染；提供 Mac 风格蜂窝、丁达尔、封面点阵，并保留 Windows 六边形变形效果；播放器控制器支持启用/关闭
- 播放器窗口内同步显示音频频谱，背景效果切换会同步到桌面层
- Windows 通知区域左键打开播放器浮层（封面、进度、播放/切歌/循环），右键提供菜单；关闭控制台会收起到通知区域并继续播放
- 桌面左侧提供可折叠歌曲抽屉，支持本地歌曲搜索/移除，以及网易云、QQ 和酷狗个人歌单入口；网易云和 QQ 歌单读取已接入，酷狗个人歌单接口仍待移植
- 本地用户歌单支持创建、删除、导入歌曲、添加已有歌曲、从歌单移除和重启后恢复；上一首/下一首按开始播放时的当前列表队列运行
- 歌词管理可保存显示开关、行数、切换方式、排列、位置、行距、宽度、字号和非当前行样式，浮层即时应用
- QQ 音乐、网易云、酷狗搜索及可用音源下载；下载曲目加入本地曲库
- WebView2 内嵌平台登录，登录后自动读取必要会话 Cookie，并按当前 Windows 用户使用 DPAPI 加密保存

平台服务接口会受曲库权限、会员状态和平台接口变更影响。登录由平台页面处理，Sound Desk 不读取或保存账号密码。内嵌登录需要远程电脑安装 Microsoft Edge WebView2 Runtime；Windows 11 通常已预装，其他环境可通过 Microsoft Edge WebView2 Runtime 安装程序提供。输出频谱采集 Windows 默认播放设备的 WASAPI loopback，因此会包含其他应用的声音。

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
