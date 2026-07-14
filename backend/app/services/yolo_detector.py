from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from threading import RLock
from typing import Any, Callable

import cv2
from PIL import Image, UnidentifiedImageError

from app.core.logger import get_logger

logger = get_logger(__name__)


class ModelUnavailableError(RuntimeError):
    pass


class InvalidImageError(ValueError):
    pass


@dataclass(frozen=True)
class DetectedObject:
    class_id: int
    class_name: str
    confidence: float
    bbox: tuple[float, float, float, float]


@dataclass(frozen=True)
class ImagePrediction:
    width: int
    height: int
    inference_time_ms: float
    detections: tuple[DetectedObject, ...]
    annotated_jpeg: bytes


def _load_ultralytics_model(model_path: str):
    from ultralytics import YOLO

    return YOLO(model_path)


def _cuda_is_available() -> bool:
    import torch

    return bool(torch.cuda.is_available())


class LocalYoloDetector:
    """Lazy, process-local wrapper around an Ultralytics detection model."""

    def __init__(
        self,
        model_path: str | Path,
        device: str = "auto",
        model_factory: Callable[[str], Any] | None = None,
        cuda_available: Callable[[], bool] | None = None,
    ):
        self.model_path = Path(model_path).expanduser().resolve()
        self.requested_device = str(device).strip().lower() or "auto"
        self._model_factory = model_factory or _load_ultralytics_model
        self._cuda_available = cuda_available or _cuda_is_available
        self._model = None
        self._selected_device: str | None = None
        self._lock = RLock()

    @property
    def selected_device(self) -> str:
        if self._selected_device is None:
            if self.requested_device == "auto":
                self._selected_device = "0" if self._cuda_available() else "cpu"
            else:
                self._selected_device = self.requested_device

            if self._selected_device != "cpu" and not self._cuda_available():
                raise ModelUnavailableError(
                    f"CUDA device {self._selected_device} was requested but CUDA is unavailable"
                )
        return self._selected_device

    def _get_model_locked(self):
        if not self.model_path.is_file():
            raise ModelUnavailableError(
                f"YOLO checkpoint does not exist: {self.model_path}"
            )
        if self._model is None:
            try:
                self._model = self._model_factory(str(self.model_path))
            except Exception as exc:
                raise ModelUnavailableError(
                    f"Unable to load YOLO checkpoint {self.model_path}: {exc}"
                ) from exc
            logger.info(
                "Loaded YOLO checkpoint %s for device %s",
                self.model_path,
                self.selected_device,
            )
        return self._model

    @property
    def class_names(self) -> dict[int, str]:
        with self._lock:
            names = self._get_model_locked().names
            if isinstance(names, dict):
                return {int(class_id): str(name) for class_id, name in names.items()}
            return {class_id: str(name) for class_id, name in enumerate(names)}

    @staticmethod
    def _decode_image(image_bytes: bytes) -> Image.Image:
        try:
            image = Image.open(BytesIO(image_bytes))
            image.load()
            return image.convert("RGB")
        except (UnidentifiedImageError, OSError, ValueError) as exc:
            raise InvalidImageError(f"Unable to decode uploaded image: {exc}") from exc

    def predict(
        self,
        image_bytes: bytes,
        confidence: float = 0.25,
        iou: float = 0.45,
        image_size: int = 640,
    ) -> ImagePrediction:
        image = self._decode_image(image_bytes)

        with self._lock:
            model = self._get_model_locked()
            try:
                results = model.predict(
                    source=image,
                    conf=confidence,
                    iou=iou,
                    imgsz=image_size,
                    device=self.selected_device,
                    verbose=False,
                )
            except Exception as exc:
                raise ModelUnavailableError(f"YOLO inference failed: {exc}") from exc

            if not results:
                raise ModelUnavailableError("YOLO inference returned no image result")

            result = results[0]
            detections = self._convert_detections(result)
            annotated_jpeg = self._encode_annotated_image(result.plot())

        height, width = getattr(result, "orig_shape", (image.height, image.width))
        inference_time_ms = float(getattr(result, "speed", {}).get("inference", 0.0))
        return ImagePrediction(
            width=int(width),
            height=int(height),
            inference_time_ms=inference_time_ms,
            detections=detections,
            annotated_jpeg=annotated_jpeg,
        )

    @staticmethod
    def _convert_detections(result) -> tuple[DetectedObject, ...]:
        boxes = getattr(result, "boxes", None)
        if boxes is None:
            return ()

        coordinates = boxes.xyxy.cpu().tolist()
        confidences = boxes.conf.cpu().tolist()
        class_ids = boxes.cls.cpu().tolist()
        names = result.names
        converted = []
        for bbox, confidence, class_id_value in zip(
            coordinates, confidences, class_ids
        ):
            class_id = int(class_id_value)
            class_name = names[class_id] if isinstance(names, dict) else names[class_id]
            converted.append(
                DetectedObject(
                    class_id=class_id,
                    class_name=str(class_name),
                    confidence=float(confidence),
                    bbox=tuple(float(value) for value in bbox),
                )
            )
        return tuple(converted)

    @staticmethod
    def _encode_annotated_image(image) -> bytes:
        encoded, buffer = cv2.imencode(".jpg", image)
        if not encoded:
            raise ModelUnavailableError("Unable to encode annotated image")
        return buffer.tobytes()
