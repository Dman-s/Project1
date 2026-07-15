# 模型 v1 发布契约

本文档定义模型 v1 发布时应提供的资源、默认选择、来源说明、评估背景和完整性校验规则。它是发布契约，不表示相关版本或资源已经发布。只有文件名、字节数和 SHA-256 均与本契约一致的文件，才应被视为对应的发布资源。

## 资源清单

| 文件 | 用途 | 默认状态 | 大小（字节） | SHA-256 | 许可 |
| --- | --- | --- | ---: | --- | --- |
| `tt100k-yolo11s-reference42.pt` | TT100K 42 类参考检测器 | 默认检测器 | 19231379 | `E8A0E0F1E5A9004C708D7EEE9EDD97E9E9D0A7986023E96C807D0FFCD3D50F88` | AGPL-3.0 |
| `tt100k-yolo11n-common45.pt` | Project1 common45 检测器 | 可选检测器 | 5488602 | `A73829F11BD5AC940BDD1DF982095AE6F828180B0C3D55285BCDBB9333154D13` | AGPL-3.0 |
| `gtsrb-yolo11n-cls.pt` | GTSRB 分类器 | 默认分类器 | 3291010 | `323E5BD1B0DC5D1F6FBB4C487FAF2320DA0DF9C21132DD46C0C94FEE7B33B16C` | AGPL-3.0 |

## 用途与默认值

- 默认 TT100K 检测器为 `tt100k-yolo11s-reference42.pt`。
- `tt100k-yolo11n-common45.pt` 是可选的 Project1 common45 检测器，不替代默认检测器。
- 默认 GTSRB 分类器为 `gtsrb-yolo11n-cls.pt`。

## 来源与评估背景

### `tt100k-yolo11s-reference42.pt`

该检查点来自用户提供的 42 类参考训练。其自有验证集（own-val）指标为：P `0.74464`、R `0.67341`、mAP50 `0.74842`、mAP50-95 `0.57963`。

记录的推理配置使用 SAHI，切片大小为 `512x512`，重叠比例为 `0.2`。输出映射到 common45 后缺少 `ph5`、`w32` 和 `wo`。样例 `97549.jpg` 的结果为 `pl40`，置信度 `89.32%`，耗时约 `343 ms`。

### `tt100k-yolo11n-common45.pt`

该检查点是可选的 Project1 common45 检测器。仅记录以下旧 corrected-val 基线作为历史背景：P `0.234120`、R `0.310147`、mAP50 `0.177540`、mAP50-95 `0.114286`。

这些数值不是候选检查点指标，不得将其表述为 `tt100k-yolo11n-common45.pt` 候选检查点的评估结果。

### `gtsrb-yolo11n-cls.pt`

该检查点的 top-1 准确率为 `95.6611%`，宏平均召回率为 `90.5966%`，零召回类别数为 `0`。记录的样例包括：`00000` 为类别 `16`，`00006` 为类别 `18`。

## 限制

- `tt100k-yolo11s-reference42.pt` 的 own-val 指标与 corrected45 评估背景不可直接比较，不应据此得出两个检查点之间的优劣结论。
- reference42 输出映射到 common45 时缺少 `ph5`、`w32` 和 `wo`，因此不提供完整的 common45 类别覆盖。
- `tt100k-yolo11n-common45.pt` 没有在本契约中声明候选检查点指标；旧 corrected-val 基线仅用于背景说明。
- 约 `343 ms` 是指定样例的记录值，不是跨硬件、运行时或输入条件的延迟保证。
- 本契约不声明资源已经上传或发布。实际使用前必须校验文件大小和 SHA-256。

## PowerShell 完整性校验

在包含三个模型文件的目录中运行以下 PowerShell。脚本使用 `Get-Item` 校验精确字节数，并使用 `Get-FileHash -Algorithm SHA256` 校验哈希；任一项不匹配都会终止并报错。

```powershell
$expected = @(
    [pscustomobject]@{
        Name = 'tt100k-yolo11s-reference42.pt'
        Size = 19231379
        SHA256 = 'E8A0E0F1E5A9004C708D7EEE9EDD97E9E9D0A7986023E96C807D0FFCD3D50F88'
    }
    [pscustomobject]@{
        Name = 'tt100k-yolo11n-common45.pt'
        Size = 5488602
        SHA256 = 'A73829F11BD5AC940BDD1DF982095AE6F828180B0C3D55285BCDBB9333154D13'
    }
    [pscustomobject]@{
        Name = 'gtsrb-yolo11n-cls.pt'
        Size = 3291010
        SHA256 = '323E5BD1B0DC5D1F6FBB4C487FAF2320DA0DF9C21132DD46C0C94FEE7B33B16C'
    }
)

foreach ($asset in $expected) {
    $file = Get-Item -LiteralPath $asset.Name
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash

    if ($file.Length -ne $asset.Size) {
        throw "$($asset.Name) 大小不匹配：实际 $($file.Length)，预期 $($asset.Size)"
    }
    if ($hash -ne $asset.SHA256) {
        throw "$($asset.Name) SHA-256 不匹配：实际 $hash，预期 $($asset.SHA256)"
    }

    [pscustomobject]@{
        Name = $asset.Name
        Size = $file.Length
        SHA256 = $hash
        Valid = $true
    }
}
```

项目 bootstrap 会按清单强制校验模型文件的 SHA-256，清单同时记录预期字节数。手工获取、发布或转移资源后，应使用上述命令同时复核大小和哈希。
