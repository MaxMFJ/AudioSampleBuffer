# Mac 封面点阵改造

2026-10-10。参考仓库：<https://github.com/XxHuberrr/Mineradio-paused>，读取版本 `d43de565acabfdc1a9c9820a27e81a98ccbebcef`。

参考观察来自 `public/js/modules/02-visual/00-pointer-cover-particles.js`：封面独立规则网格、居中采样、圆点透明边缘、透视尺寸和沿深度方向的律动。默认网格为 183×183。该仓库采用 GPL-3.0；本次 Metal 代码为独立实现，没有复制 JavaScript/GLSL 源代码。

## 当前实现

- “封面点阵”使用暗色留白和中央 0.68 屏高的方形 3D 封面；歌词与封面共享舞台投影。封面外保留 256 列低亮度点阵，鼓点起音触发点阵亮光外扩，且不放大粒子。全屏吉他扫光与鼓点光环仍由独立叠层绘制。
- 其他特效可按“其他特效显示圆形唱片”开关叠加 0.56 屏高的圆形点阵唱片。
- 封面独立绘制并居中采样，网格间距约 2.8 AppKit pt，各轴上限 512。
- 圆点直径约为间距的 90%，通过 drawable 像素尺寸转换，保持 Retina 与普通屏幕上接近的视觉大小。
- 每点直接采样原图；使用 sRGB 显示转换，抗锯齿边缘，不添加光晕、不随鼓点放大。
- 图片局部亮度形成浅浮雕，使用真实透视投影；平滑的吉他强度驱动封面内斜向弦波的深度与亮度，钢琴强度驱动较轻的深度起伏。亮度深度是启发式估算，不是 Core ML 深度模型。

## 验证范围

macOS Debug 构建通过。额外使用独立离屏 Metal 驱动调用实际 `CoverDotDesktopEffectRenderer`，渲染本地缓存封面，GPU command buffer 无错误。1920×1080 对比帧中，排除封面及边缘安全区后，背景变化像素数为 0。

预览位于 `.build/visual-check/cover-dots-before.png` 和 `cover-dots-after.png`。此检查是固定时刻的实际 GPU 渲染，不代表整曲播放观感、Retina 实机或能耗验收。

## 共享 3D 舞台与交互

- 对照参考的指针封面、手势控制和舞台歌词模块：封面与歌词一起旋转，而非旋转独立相机。
- `DesktopCoverInteraction.swift` 被动读取桌面指针，不拦截普通桌面点击。鼠标经过产生局部鼓起，按住左键形成凹陷；Option 拖动翻转并带惯性，Option 双击回正。本应用交互窗口覆盖的位置不触发。
- `DesktopCoverStageUniforms` 每帧同时传给封面与歌词；两者调用同一个 `desktopStageProject`，共用旋转、透视、指针扰动及吉他/钢琴形变。
- `CoverStageLyrics.swift` 将五行歌词绘制为高分辨率透明字形纹理，并贴到共享 3D 投影的四边形上；文字本身不是点阵，周围封面与背景仍保留粒子层。当前行居中，按播放进度推进颜色；字形纹理仅在文本组变化时重建。
- 吉他改为封面内部的柔和斜向弦波：点沿 Z 轴起伏，波峰轻微提亮，不再横向撕裂或扭动歌词；原有电吉他高潮扫光和背景鼓点管线继续使用。音频来源仍沿用现有 HTDemucs 或 FFT 通路。
- 点阵模式设为 60 FPS。封面深度叠加连续时变噪声，并由音乐包络调整起伏；鼠标按压形成凹陷。Metal 原生实现不等同逐像素复刻 Mineradio。

增量检查：Xcode Debug 构建通过；实际 GPU 在无吉他、强吉他、指针鼓起、翻转四种状态下完成渲染，command buffer 无错误。检查图位于 `.build/visual-check/stage-rest.png`、`stage-guitar.png`、`stage-hover.png`、`stage-flip.png`。这些固定状态验证了共同空间变换及中文字形方向，不替代桌面交互、真实歌曲和显示器上的动态验收。

## 2026-10-10 交互与歌词修正

- 输入改为 Core Graphics combined session 的按键/鼠标状态；不再通过全局窗口枚举判定桌面遮挡，避免 Finder 桌面窗口误拦截交互。本应用交互窗口仍会挡住手势。
- Option 拖动在真实桌面上尚未操作验收；实现层不拦截 Finder 点击，按住左键时则只给封面粒子施加负 Z 形变。
- 壁纸 `NSPanel` 显式设置 `hidesOnDeactivate = false`，避免应用失去焦点时面板默认隐藏，使首次显示桌面时粒子刷新与被动手势采样继续工作。
- 歌词使用五行滑动窗口，在开头和结尾保留空槽，使当前行始终在中央；宽高按字形比例和屏幕尺寸适配。
- 歌词纹理按 Retina 画布栅格化，再由 Metal 线性采样；纹理仅重建于歌词窗口变化，不随每帧重复绘制。
- 构建通过，离屏 GPU 渲染检查通过；真实桌面的 Option 手势仍需实际操作确认。
