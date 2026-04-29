# AudioSampleBuffer

`AudioSampleBuffer` 是一个基于 iOS 的音频播放与可视化实验项目，主要使用 Objective-C 构建，聚焦于以下能力：

- 本地音频播放与频谱分析
- 多种 Metal 音频可视化特效
- LRC 歌词解析与展示
- 歌词编辑与时间轴校准
- 卡拉 OK 录音与基础音频处理
- 音乐搜索与下载能力扩展

---

## 功能概览

### 1) 播放与频谱
- 音频播放控制（播放、暂停、进度）
- 实时频谱分析与波形渲染
- 音频进度视图与播放状态同步

### 2) 视觉特效（Metal）
- 多套音频响应式 Shader（如 Galaxy、Cyberpunk、Holographic 等）
- 支持可视化参数调节与特效切换
- 面向性能的渲染结构与特效管理器

### 3) 歌词系统
- LRC 解析、歌词行同步、UI 展示
- QQ 音乐歌词接口封装（基于项目内实现）
- 本地歌词文件管理与显示联动

### 4) 歌词编辑器
- 音频波形辅助对齐
- 歌词行编辑与时间微调
- 本地歌词列表管理

### 5) Karaoke 与音频处理
- 录音与回放流程
- 基础人声音效处理链路
- 集成 RNNoise / SoundTouch / SpeexDSP 等 DSP 组件

### 6) 下载与平台适配
- 已实现酷狗平台下载流程（参考 `Download` 模块）
- 其他平台受接口稳定性影响，当前以文档说明为主

---

## 目录结构

```text
AudioSampleBuffer/
├─ AudioSampleBuffer/              # iOS 主工程源码
│  ├─ AI/                          # AI 分析与参数调优模块
│  ├─ Animations/                  # 动画协调与特效动画管理
│  ├─ AudioSampleBuffer/           # 音频频谱核心组件
│  ├─ Download/                    # 音乐下载与平台适配
│  ├─ Karaoke/                     # K 歌录音与 DSP
│  ├─ Lyrics/                      # 歌词解析与显示
│  ├─ LyricsEditor/                # 歌词编辑器
│  ├─ VisualEffects/               # 可视化特效（含 Metal）
│  └─ Base.lproj/                  # Storyboard / 启动页
├─ AudioSampleBuffer.xcodeproj/    # Xcode 工程
└─ Tools/                          # Python/Shell 辅助脚本
```

---

## 开发环境

- Xcode（建议使用较新稳定版本）
- iOS SDK（与本机 Xcode 对应）
- macOS（Apple Silicon / Intel 均可）
- 可选：`python3`（运行 `Tools/` 下脚本时需要）
- 可选：`ffmpeg`（处理音频格式与元数据时常用）

---

## 快速开始

1. 克隆仓库并进入目录：

```bash
git clone <your-repo-url>
cd AudioSampleBuffer
```

2. 使用 Xcode 打开工程：

```bash
open AudioSampleBuffer.xcodeproj
```

3. 选择目标设备（模拟器或真机）并运行 `AudioSampleBuffer` Scheme。

4. 如需使用歌词/下载相关脚本，请先安装 Python 依赖（按具体脚本需要）：

```bash
pip3 install pycryptodome requests
```

---

## 工具文档（Tools）

仓库内已提供更细分的工具说明：

- QQ 音乐歌词相关说明：`Tools/README_QQMUSIC.md`
- 歌词提取与处理工具说明：`Tools/README_LYRICS_TOOLS.md`

建议先阅读上述文档，再运行对应脚本。

---

## 已知说明

- 音乐平台接口可能存在变更、限流或地区限制，相关状态请参考：
  - `AudioSampleBuffer/Download/PLATFORM_STATUS.md`
- 本项目用于学习与技术验证，请遵守当地法律法规与平台服务条款。

---
