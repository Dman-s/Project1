# 第三方声明

## 软件许可

本仓库源代码按 [GNU Affero General Public License v3.0](LICENSE) 发布。AGPL-3.0 只说明本仓库软件的许可，不自动覆盖训练数据、第三方代码或模型权重，也不授予这些材料的商业使用或再分发权。

Ultralytics 依赖项及由其代码产生的模型组件另受 [Ultralytics 官方许可](https://www.ultralytics.com/license)约束：适用时应遵守 AGPL-3.0，或取得 Ultralytics Enterprise License。满足 Ultralytics 条款不等于已经满足训练数据和检查点来源条款。

## TT100K 数据集

TT100K 数据集未提交到本仓库。[TT100K 官方页面](https://cg.cs.tsinghua.edu.cn/traffic-sign/)将该数据集标为 Creative Commons Attribution-NonCommercial（CC BY-NC），并要求商业用途联系数据集维护者。使用者应保留署名、限于许可允许的非商业用途，并自行确认训练产物的使用和分发方式符合适用条款。

使用 TT100K 时请引用：Zhu, Zhe; Liang, Dun; Zhang, Songhai; Huang, Xiaolei; Li, Baoli; Hu, Shimin. "Traffic-Sign Detection and Classification in the Wild." CVPR, 2016。

```bibtex
@InProceedings{Zhe_2016_CVPR,
  author    = {Zhu, Zhe and Liang, Dun and Zhang, Songhai and Huang, Xiaolei and Li, Baoli and Hu, Shimin},
  title     = {Traffic-Sign Detection and Classification in the Wild},
  booktitle = {The IEEE Conference on Computer Vision and Pattern Recognition (CVPR)},
  year      = {2016}
}
```

GTSRB 数据集同样未提交到本仓库；使用者必须从其正式来源获取，并单独核验数据和训练产物条款。

## 模型工件

模型文件不属于本仓库源代码许可的自动覆盖范围。文件名、大小和 SHA-256 只能证明工件身份，不能证明发布权。

- `tt100k-yolo11n-common45.pt` 使用 TT100K 训练；其使用或发布必须同时考虑 TT100K 的 CC BY-NC 条款、上述引用要求和 Ultralytics 许可义务，不能仅标记为 AGPL-3.0。
- `tt100k-yolo11s-reference42.pt` 来自用户提供的本地参考项目，但训练者、上游来源、数据集版本和再分发授权尚无可核验记录。因此该检查点当前不得上传、发布或再分发。只有补齐来源链、数据条款和权利人授权后，才能重新评估发布资格。
- `gtsrb-yolo11n-cls.pt` 的发布资格取决于其训练来源、GTSRB 条款和 Ultralytics 义务；发布前必须完成相同的来源核验。
