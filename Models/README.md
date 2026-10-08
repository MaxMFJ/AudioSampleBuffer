# IMPORTANT — CoreML 三轨分离模型

`HTDemucs6s_Guitar_iOS16.mlpackage` 是应用运行所需的核心模型资源，包含模型规格与权重。请保留整个 `.mlpackage` 目录，不要删除、拆开或只复制其中的 `model.mlmodel`；Xcode 会将其打包进应用，音频分轨功能依赖它。

模型通过 Git LFS 管理。克隆仓库后请确保已安装 Git LFS 并执行 `git lfs pull`，否则模型文件可能只显示为指针文本。
