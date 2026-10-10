# Mac Desktop Player prototype

独立的 macOS 原型，不改动 iOS target。当前包含桌面层 Metal 动效窗口、鼠标事件穿透、多显示器窗口、音乐库、用户歌单、收藏/最近播放、本地导入，以及与 iOS 云端下载入口相同的 QQ 音乐搜索/详情解析/音频下载流程。

## 构建

```sh
./build-app.sh
open .build/MacDesktopPlayer.app
```

窗口采用 AppKit `.desktop` 层级，并启用 `ignoresMouseEvents`，目标是让画面位于桌面图标后方且不拦截桌面点击。Finder 图标层级、Spaces 和多显示器行为仍需在实际桌面上验收。

播放中的声音通过 Accelerate/vDSP 的共享 C 分析器做 4096 点 FFT 和 80 频带分析，再驱动 Metal 背景。YAMNet iOS 分析器已接入 Mac target：首启编译随包提供的模型，歌曲详情里的“Core ML 分析”可运行整曲离线 521 类分析并缓存结果。导入音频会复制到 Application Support，歌单和播放记录以 JSON 持久化。“在线搜索”复用 iOS 云端搜索使用的 `api.qqmp3.vip`：先搜索歌曲，再按结果 ID 获取音频详情和下载链接，下载后加入本地曲库。该服务及其上游音源由第三方维护，返回内容、可用性和授权状态可能变化；请仅下载你有权保存的内容。另保留用户提供 HTTPS 音频直链的下载入口。

桌面背景效果可选“深空蜂巢”。该效果使用独立的 macOS Metal shader，以 60 FPS 绘制音频响应式孔洞隧道，并额外加入蜂巢颗粒汇聚、细胞边缘微粒、双层星尘、节奏冲击环、内圈放射光束和乐器分色。它复用实时频段与分离乐器能量，不依赖 iOS 视图或渲染器。

YAMNet 与 HTDemucs 模型包已分别通过 `coremlcompiler` 编译到 macOS 13 目标；YAMNet 推理已接通。HTDemucs 模型约 186 MB，尚未接入 Mac 推理界面，建议作为可选模型资源处理，而不是无提示地增大主应用安装包。桌面图标层级、Finder 点击穿透、Spaces、多显示器、Core ML 首次编译/预测和实际能耗仍需在目标 Mac 上验收。
