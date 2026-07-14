# Project1

Windows 无 WSL/Docker 的安装、启动、双模型交通标志识别、GPU 训练与评估说明见：

[docs/local-development.md](docs/local-development.md)

当前识别链路：

- GTSRB 分类器：处理 `Test` 这类单标志裁剪图。
- TT100K 检测器：处理完整街景中的交通标志定位。
- `mode=auto` 根据图片尺寸自动选择，也可显式使用 `classify` 或 `detect`。
