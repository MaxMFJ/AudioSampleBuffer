# Mac 丁达尔：Camera-Directed Laser / Laser Tunnel

Mac 默认启用三维蓝色镭射通道，12 条光束分为上下两组。原有二维扇形作为 `tyndallLaserMode=0` 保留。修改仅作用于 Mac 蓝色镭射，继续使用原来的蓝色 AI 配色、音频触发/锁定包络、节拍亮度增强、解析发光 halo 和 tone mapping。

底部四盏雾灯由实时 FFT 中音触发（门限 0.02，0.08 达到完整触发强度），使用 12 秒锁定动画；这组灯不依赖人声曲线或乐器分离结果。四个灯位分布在屏幕宽度约 16%、39%、61%、84% 处，随宽高比扩大扇形张角、光束扩散和摇摆范围，以覆盖宽屏。

## 三维空间与传播

摄像机固定在原点，局部 Forward 指向 +Z。发射器在摄像机前方 `depth` 处，中心方向为 `normalize(camera.position - laserOrigin)`，再按 `cameraAimStrength` 与舞台朝前方向混合。上下组保留原扇形的屏幕发射位置（屏幕坐标 p.y = ±0.56），通过逆透视将这两个边缘锚点放到 depth 纵深处；调整 depth 或视场角不会将发射点移入画面中央。上下组各有独立空间位置，光束在摄像机 Right/Up 方向上添加发散角，并用摄像机局部空间的 Yaw/Pitch 旋转矩阵整体扫描。独立光孔位置和上下发散偏移避免所有光束汇聚到摄像机中心。

每条光束是世界空间中有固定半径和 `beamLength` 的有限发光体。通过全屏 fragment 的摄像机射线与三维有限光束体的最近距离求可见发光；这是一种解析体积渲染，不是二维线段缩放。体积发光沿世界空间的距离变化。空间端点在投影前裁剪到 Near Plane，透视投影采用摄像机局部坐标除以 `2 * z * tan(verticalFOV / 2)`。投影后的包围范围只用于跳过不可能被照亮的像素；光束厚度、扫描段位置和散射计算仍在三维空间中进行。

扫描头按 `fract(time * approachSpeed / beamLength + phaseOffset) * beamLength` 沿光束从发射器向前推进，附带短尾迹。高频音量对速度有最高 12% 的增强。扫描头越过 Near Plane 后继续在完整空间长度上运行，不会被固定在屏幕前的裁剪端点。近处的厚度和扫描段扩张由透视自然产生，静止摄像机同样可见。

## 横扫与吉他高潮

三维蓝光每 16 秒在迎面透视和左右横扫之间平滑交替。横扫沿摄像机局部 Yaw 转动同一批有空间长度的光束，俯仰幅度在横扫期间降低；默认横扫张幅约为平时的 1.7 倍，仍受 `yawAmplitude` 控制，设为 0 可关闭左右摆动。上下发射位置、纵深、Near Plane 裁剪和迎面扫描段均保持三维计算。

检测到现有的吉他高潮扫光触发时，蓝光在触发包络内保持可见，不受 14 秒常规显示周期和高频门限压灭；左右横扫权重提高，蓝光强度最多增强 115%。高潮结束后平滑返回交替运动。

## 参数

参数通过 `UserDefaults` 读取，每帧应用；代码入口为 `DesktopLaserTunnelUniforms`。角度单位为弧度，长度单位为世界空间单位。`beamCount` 是上下两组的总数，整数值；奇数时上组多一条。

| 参数 | UserDefaults 键 | 默认值 | 范围 |
| --- | --- | ---: | --- |
| beamCount | tyndallLaserBeamCount | 12 | 1–64 |
| fanAngle | tyndallLaserFanAngle | 0.60 | 0–1.4 |
| depth | tyndallLaserDepth | 8 | 0.62–100；至少在 Near Plane 后方 0.5 |
| beamLength | tyndallLaserBeamLength | 12 | 0.01–100 |
| approachSpeed | tyndallLaserApproachSpeed | 7 | 0–100 |
| cameraAimStrength | tyndallLaserCameraAimStrength | 0.90 | 0–1 |
| yawAmplitude | tyndallLaserYawAmplitude | 0.24 | 0–π |
| pitchAmplitude | tyndallLaserPitchAmplitude | 0.17 | 0–π/2 |
| glowIntensity | tyndallLaserGlowIntensity | 1 | 0–10 |
| nearPlane | tyndallLaserNearPlane | 0.12 | 0.01–1 |
| verticalFOV | tyndallLaserVerticalFOV | 0.90 | 0.35–2.2 |
| mode | tyndallLaserMode | 1 | 0：原二维扇形；1：三维通道 |

例如设置横向扫描幅度（重新打开 App 后生效）：

```sh
defaults write com.audiosamplebuffer.macdesktopplayer tyndallLaserYawAmplitude -float 0.35
```

固定摄像机并关闭光束整体摇摆，可将 Yaw/Pitch 都设为 0，此时迎面扫描仍沿 Z 方向传播。增加 `depth` 时，应同时保证 `beamLength` 足够到达 Near Plane，否则得到的是远处的短光束。光束总数增加会提高每像素的体积计算开销，默认总数保留为 12。

## 验证边界

实现使用同一 shader 的真实 Metal 离屏连续帧核对迎面传播、Yaw/Pitch、原二维模式和 Near Plane。极近发射点、最长光束、64 条光束、单条光束、零张角、零速度和零发光的数值检查使用 RGBA32Float 渲染目标，检查输出是否为有限且非负的值。离屏帧使用固定测试音频数据，不能代替歌曲播放时的动态视觉验收。
