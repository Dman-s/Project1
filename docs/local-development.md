# Windows 本地开发

本项目可以在没有 WSL、Docker、PostgreSQL、Redis 和 MinIO 的 Windows 环境运行。后端本地模式使用 SQLite，上传文件与标注结果保存在 `backend/uploads`。

## 启动后端

```powershell
cd D:\Project1-main1\backend
.\.venv\Scripts\Activate.ps1

$env:APP_MODE="local"
$env:DATABASE_URL="sqlite:///./data/local.db"
$env:REDIS_ENABLED="false"
$env:MINIO_ENABLED="false"
$env:YOLO_DEVICE="auto"
$env:GTSRB_DEVICE="auto"
$env:YOLO_MODEL_PATH="../qq_3045834499/yolo11-tt100k/42_demo/runs/yolo11s/weights/best.pt"
$env:YOLO_MODEL_NAME="tt100k-yolo11s-reference42"
$env:YOLO_MODEL_TYPE="yolov11s"
$env:YOLO_CANONICALIZE_TT100K_CLASSES="true"
$env:YOLO_CONFIDENCE="0.5"
$env:YOLO_USE_SAHI="true"
$env:YOLO_SAHI_SLICE_HEIGHT="512"
$env:YOLO_SAHI_SLICE_WIDTH="512"
$env:YOLO_SAHI_OVERLAP_RATIO="0.2"
$env:YOLO_SAHI_MODEL_IMAGE_SIZE="640"
$env:GTSRB_MODEL_PATH="../training/runs/gtsrb_yolo11n_cls_gpu_final/weights/best.pt"
$env:YOLO_CONFIG_DIR="D:\Project1-main1\.venv\ultralytics"
$env:MPLCONFIGDIR="D:\Project1-main1\.venv\matplotlib"

python -m uvicorn main:app --host 127.0.0.1 --port 8000
```

首次启动会创建 `backend/data/local.db` 和 ORM 表。健康检查：

- `http://127.0.0.1:8000/api/health`
- `http://127.0.0.1:8000/api/health/detail`

## 启动前端

```powershell
cd D:\Project1-main1\frontend
npm run dev -- --host 127.0.0.1
```

访问 `http://127.0.0.1:5173`。

## 双模型识别

`POST /api/sign-analyzer/analyze` 和 `/batch` 支持表单字段 `mode`：

- `auto`：默认；最长边不超过 512 像素时使用 GTSRB 分类器，否则使用 TT100K 检测器。
- `classify`：强制整图交通标志分类。
- `detect`：强制街景目标检测。

示例：

```powershell
curl.exe -X POST "http://127.0.0.1:8000/api/sign-analyzer/analyze" `
  -H "Authorization: Bearer <TOKEN>" `
  -F "mode=auto" `
  -F "image=@D:\Project1-main1\Test\00000.png"
```

响应包含 `recognition_mode`、`result_type`、`dataset`、模型设备、类别、中文显示名、置信度和标注图 URL。任务历史接口仍为 `/api/sign-analyzer/tasks` 与 `/api/sign-analyzer/tasks/{task_id}`。

当前本机检测器使用 `qq_3045834499/yolo11-tt100k/42_demo/runs/yolo11s/weights/best.pt`。该权重在参考目录自带的验证集上训练 200 epochs，记录的 precision、recall、mAP50、mAP50-95 分别为 `0.74464`、`0.67341`、`0.74842`、`0.57963`。这些指标使用参考目录自己的 42 类切分，不能与 corrected 45 类验证集的结果直接横向比较。

推理层会把参考权重的 42 类编号映射到项目统一的 TT100K common-45 编号，并用 SAHI 按 `512x512`、重叠率 `0.2` 切片检测小目标。真实 GPU API 验证中，`97549.jpg` 从整图推理误判的 `pl60` 修正为官方标注一致的 `pl40`，置信度 `89.32%`，推理耗时约 `343 ms`。该参考权重没有训练 `ph5`、`w32`、`wo` 三类，因此这三类仍需后续 corrected 45 类模型补齐。

## GTSRB 数据与训练

`Test/` 的 12,630 张图片是只读测试集，禁止复制到 train/val。官方真值位于 `Test/GT-final_test.csv`。

```powershell
# 验证并准备项目根目录 Train.tar（按物理标志轨迹分组切分）
powershell -ExecutionPolicy Bypass -File scripts\prepare-gtsrb.ps1

# GPU 训练
powershell -ExecutionPolicy Bypass -File scripts\train-gtsrb-gpu.ps1

# 全量 Test 评估
powershell -ExecutionPolicy Bypass -File scripts\evaluate-gtsrb.ps1
```

当前 GTSRB `best.pt` 在全部 Test 图片上的 top-1 为 `95.6611%`，macro recall 为 `90.5966%`，43 类无零召回；`00000.png` 识别为 class 16，`00006.png` 识别为 class 18。

## TT100K 数据与训练

修正版数据集位于 `training/datasets/tt100k_corrected_45`，严格使用 `train -> train`、`other -> val`、`test -> test`，并固定 45 类顺序。

```powershell
# 仅校验数据
powershell -ExecutionPolicy Bypass -File scripts\train-tt100k-gpu.ps1 -DryRun

# 1280 分辨率 GPU 训练（本机 8GB 显存已验证 batch=8，显式 SGD lr0=0.01）
powershell -ExecutionPolicy Bypass -File scripts\train-tt100k-gpu.ps1

# 另开窗口时可实时查看 epoch、指标与 GPU 状态
powershell -ExecutionPolicy Bypass -File scripts\watch-tt100k-progress.ps1

# 在 corrected val 上评估任一权重
powershell -ExecutionPolicy Bypass -File scripts\evaluate-tt100k.ps1 `
  -Model "training\runs\tt100k_yolo11n_gpu\weights\best.pt" `
  -RunName "tt100k_baseline_corrected"

# 新模型评估完成后，强制执行非回退与相对提升 10% 的晋升门槛
powershell -ExecutionPolicy Bypass -File scripts\check-tt100k-promotion.ps1 `
  -Candidate "training\runs\tt100k_candidate_eval\metrics.json"
```

旧模型 corrected-val 基线：precision `0.234120`、recall `0.310147`、mAP50 `0.177540`、mAP50-95 `0.114286`。

## 验证

```powershell
cd D:\Project1-main1\backend
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m pip check

cd D:\Project1-main1\frontend
npm run test:run
npm run build
```

本地模式不提供 PostgreSQL/pgvector、Redis 队列、MinIO 或信号灯检测；`traffic_lights` 仍返回空数组。
