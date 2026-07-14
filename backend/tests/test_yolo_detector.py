from io import BytesIO

import numpy as np
import pytest
from PIL import Image

from app.services.yolo_detector import (
    InvalidImageError,
    LocalYoloDetector,
    ModelUnavailableError,
)


class FakeTensor:
    def __init__(self, value):
        self.value = value

    def cpu(self):
        return self

    def tolist(self):
        return self.value


class FakeBoxes:
    xyxy = FakeTensor([[1.0, 2.0, 20.0, 22.0]])
    conf = FakeTensor([0.91])
    cls = FakeTensor([1.0])


class FakeResult:
    boxes = FakeBoxes()
    names = {0: "p10", 1: "pl60"}
    speed = {"inference": 12.5}
    orig_shape = (24, 32)

    @staticmethod
    def plot():
        return np.zeros((24, 32, 3), dtype=np.uint8)


class FakeModel:
    names = FakeResult.names

    def __init__(self):
        self.calls = []

    def predict(self, **kwargs):
        self.calls.append(kwargs)
        return [FakeResult()]


def make_jpeg(width=32, height=24):
    output = BytesIO()
    Image.new("RGB", (width, height), color="white").save(output, format="JPEG")
    return output.getvalue()


def test_detector_prefers_gpu_and_converts_ultralytics_result(tmp_path):
    model_path = tmp_path / "best.pt"
    model_path.write_bytes(b"checkpoint")
    model = FakeModel()
    loaded_paths = []
    detector = LocalYoloDetector(
        model_path=model_path,
        device="auto",
        model_factory=lambda path: loaded_paths.append(path) or model,
        cuda_available=lambda: True,
    )

    prediction = detector.predict(
        make_jpeg(),
        confidence=0.3,
        iou=0.5,
        image_size=640,
    )

    assert detector.selected_device == "0"
    assert loaded_paths == [str(model_path)]
    assert prediction.width == 32
    assert prediction.height == 24
    assert prediction.inference_time_ms == 12.5
    assert prediction.detections[0].class_id == 1
    assert prediction.detections[0].class_name == "pl60"
    assert prediction.detections[0].confidence == pytest.approx(0.91)
    assert prediction.detections[0].bbox == (1.0, 2.0, 20.0, 22.0)
    assert prediction.annotated_jpeg.startswith(b"\xff\xd8")
    assert len(model.calls) == 1
    call = model.calls[0]
    assert call["source"].size == (32, 24)
    assert {
        key: call[key]
        for key in ("conf", "iou", "imgsz", "device", "verbose")
    } == {
        "conf": 0.3,
        "iou": 0.5,
        "imgsz": 640,
        "device": "0",
        "verbose": False,
    }


def test_detector_auto_falls_back_to_cpu(tmp_path):
    model_path = tmp_path / "best.pt"
    model_path.write_bytes(b"checkpoint")
    detector = LocalYoloDetector(
        model_path=model_path,
        device="auto",
        model_factory=lambda _path: FakeModel(),
        cuda_available=lambda: False,
    )

    assert detector.selected_device == "cpu"


def test_detector_exposes_checkpoint_class_names_lazily(tmp_path):
    model_path = tmp_path / "best.pt"
    model_path.write_bytes(b"checkpoint")
    model = FakeModel()
    detector = LocalYoloDetector(
        model_path=model_path,
        model_factory=lambda _path: model,
    )

    assert detector.class_names == {0: "p10", 1: "pl60"}


def test_detector_rejects_missing_checkpoint_before_loading(tmp_path):
    factory_called = False

    def model_factory(_path):
        nonlocal factory_called
        factory_called = True
        return FakeModel()

    detector = LocalYoloDetector(
        model_path=tmp_path / "missing.pt",
        model_factory=model_factory,
    )

    with pytest.raises(ModelUnavailableError, match="checkpoint does not exist"):
        detector.predict(make_jpeg())

    assert factory_called is False


def test_detector_rejects_corrupt_image_without_running_model(tmp_path):
    model_path = tmp_path / "best.pt"
    model_path.write_bytes(b"checkpoint")
    model = FakeModel()
    detector = LocalYoloDetector(
        model_path=model_path,
        model_factory=lambda _path: model,
    )

    with pytest.raises(InvalidImageError, match="decode"):
        detector.predict(b"not-an-image")

    assert model.calls == []
