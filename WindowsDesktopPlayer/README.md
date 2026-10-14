# Sound Desk for Windows

Windows 桌面播放器工程，按 `MacDesktopPlayer` 的控制台布局搭建，和现有 iOS/macOS targets 保持隔离。工程使用 WPF 和 Windows Media Foundation，可在 macOS 上交叉编译 Windows 目标；运行界面和播放功能需在 Windows 上验收。

## 当前实现

- 暗色半透明控制台、曲库侧栏、搜索、最近播放和收藏筛选
- 多选导入本地音频，持久化文件路径、最近播放时间和时长
- 播放、暂停、上一首/下一首、进度拖动、音量和三种循环模式
- `MediaElement` 使用 Windows Media Foundation 解码本机支持的音频格式

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

## 后续移植模块

Mac 端还包含平台账号和歌单、同步歌词、音频响应式桌面效果、多显示器桌面层级和 YAMNet/HTDemucs 分析。Mac 端依赖 AppKit、AVFoundation、Metal、Accelerate 和 Core ML；Windows 版需用 Windows API、WASAPI/Direct3D 与 ONNX Runtime 等分别实现。本工程目前保留对应入口，尚未接入这些能力。
