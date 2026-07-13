import importlib.util
import sys
from pathlib import Path

import pytest


MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "train_gtsrb.py"
SPEC = importlib.util.spec_from_file_location("train_gtsrb", MODULE_PATH)
train_gtsrb = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = train_gtsrb
SPEC.loader.exec_module(train_gtsrb)


def test_gtsrb_training_parser_uses_gpu_defaults(monkeypatch, tmp_path):
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "train_gtsrb.py",
            "--data",
            str(tmp_path / "dataset"),
            "--project",
            str(tmp_path / "runs"),
        ],
    )

    args = train_gtsrb.build_parser().parse_args()

    assert args.model == "yolo11n-cls.pt"
    assert args.epochs == 50
    assert args.imgsz == 128
    assert args.batch == 128
    assert args.device == "0"


def test_validate_classification_dataset_rejects_missing_split(tmp_path):
    (tmp_path / "dataset").mkdir()
    with pytest.raises(FileNotFoundError, match="train"):
        train_gtsrb.validate_classification_dataset(tmp_path / "dataset")
