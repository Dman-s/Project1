# 模型 v1 发布契约

本文档记录模型 v1 候选工件、运行时选择、来源说明、评估背景和完整性校验规则，不表示相关版本或资源已经发布。文件名、字节数和 SHA-256 只用于识别工件，不能证明其许可或再分发资格。

**发布状态：阻塞。** `tt100k-yolo11s-reference42.pt` 的再分发来源尚未完备，不得加入 GitHub Release。在该问题解决且默认下载清单同步调整前，不应创建声称完整可用的 `models-v1` Release。

## 资源清单

| 文件 | 用途 | 本地运行状态 | 大小（字节） | SHA-256 | 发布状态与适用条款 |
| --- | --- | --- | ---: | --- | --- |
| `tt100k-yolo11s-reference42.pt` | TT100K 42 类参考检测器 | 默认检测器 | 19231379 | `E8A0E0F1E5A9004C708D7EEE9EDD97E9E9D0A7986023E96C807D0FFCD3D50F88` | **禁止发布**：缺少可核验的训练来源和再分发授权 |
| `tt100k-yolo11n-common45.pt` | Project1 common45 检测器 | 可选检测器 | 5488602 | `A73829F11BD5AC940BDD1DF982095AE6F828180B0C3D55285BCDBB9333154D13` | 条件发布：TT100K CC BY-NC、署名/引用要求及 Ultralytics 许可义务 |
| `gtsrb-yolo11n-cls.pt` | GTSRB 分类器 | 默认分类器 | 3291010 | `323E5BD1B0DC5D1F6FBB4C487FAF2320DA0DF9C21132DD46C0C94FEE7B33B16C` | 条件发布：先核验 GTSRB 训练来源和 Ultralytics 许可义务 |

## 用途与默认值

- 当前本地配置的默认 TT100K 检测器为 `tt100k-yolo11s-reference42.pt`；这不代表它可以发布。
- `tt100k-yolo11n-common45.pt` 是可选的 Project1 common45 检测器，不替代默认检测器。
- 默认 GTSRB 分类器为 `gtsrb-yolo11n-cls.pt`。

## 来源与评估背景

TT100K 官方页面将数据集标为 [CC BY-NC](https://cg.cs.tsinghua.edu.cn/traffic-sign/)，要求署名且限于许可允许的非商业用途，并给出 CVPR 2016 论文 “Traffic-Sign Detection and Classification in the Wild” 作为引用。仓库 AGPL-3.0 和 Ultralytics AGPL/Enterprise 义务不能替代这些数据条款。完整引用和许可边界见 [第三方声明](../../THIRD_PARTY_NOTICES.md)。

### `tt100k-yolo11s-reference42.pt`

该检查点来自用户提供的 42 类参考训练。训练者、原始项目权利人、所用数据版本和允许再分发的证明尚未记录，因此不得发布。以下指标仅记录本地评估背景：P `0.74464`、R `0.67341`、mAP50 `0.74842`、mAP50-95 `0.57963`。

记录的推理配置使用 SAHI，切片大小为 `512x512`，重叠比例为 `0.2`。输出映射到 common45 后缺少 `ph5`、`w32` 和 `wo`。样例 `97549.jpg` 的结果为 `pl40`，置信度 `89.32%`，耗时约 `343 ms`。

### `tt100k-yolo11n-common45.pt`

该检查点是可选的 Project1 common45 检测器。仅记录以下旧 corrected-val 基线作为历史背景：P `0.234120`、R `0.310147`、mAP50 `0.177540`、mAP50-95 `0.114286`。

这些数值不是候选检查点指标，不得将其表述为 `tt100k-yolo11n-common45.pt` 候选检查点的评估结果。

### `gtsrb-yolo11n-cls.pt`

该检查点的 top-1 准确率为 `95.6611%`，宏平均召回率为 `90.5966%`，零召回类别数为 `0`。记录的样例包括：`00000` 为类别 `16`，`00006` 为类别 `18`。

## 限制

- `tt100k-yolo11s-reference42.pt` 在来源链、数据条款和权利人再分发授权形成可核验记录之前，不得上传到 GitHub Release 或以其他方式分发。
- TT100K 派生权重不能仅以 AGPL-3.0 标注；其使用和发布还受 TT100K CC BY-NC、署名和引用要求约束。
- `tt100k-yolo11s-reference42.pt` 的 own-val 指标与 corrected45 评估背景不可直接比较，不应据此得出两个检查点之间的优劣结论。
- reference42 输出映射到 common45 时缺少 `ph5`、`w32` 和 `wo`，因此不提供完整的 common45 类别覆盖。
- `tt100k-yolo11n-common45.pt` 没有在本契约中声明候选检查点指标；旧 corrected-val 基线仅用于背景说明。
- 约 `343 ms` 是指定样例的记录值，不是跨硬件、运行时或输入条件的延迟保证。
- 本契约不声明资源已经上传或发布。实际使用前必须校验文件大小和 SHA-256。

## PowerShell 完整性校验

在包含本地候选模型的目录中运行以下 PowerShell。脚本使用 `Get-Item` 校验精确字节数，并使用 `Get-FileHash -Algorithm SHA256` 校验哈希；任一项不匹配都会终止并报错。校验成功不代表具有发布权，尤其不得据此发布 `reference42`。

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
