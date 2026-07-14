from concurrent.futures import Future
from io import BytesIO

import cv2
import numpy as np
from PIL import Image
from sqlalchemy.orm import sessionmaker

from app.entity.db_models import DetectionResult, DetectionTask, User
from app.services.detection_task_service import DetectionTaskService
from app.services.video_detection_service import VideoDetectionService
from app.services.yolo_detector import DetectedObject, ImagePrediction


class ImmediateExecutor:
    def submit(self, function, *args, **kwargs):
        future = Future()
        try:
            future.set_result(function(*args, **kwargs))
        except Exception as exc:
            future.set_exception(exc)
        return future


class FakeCapture:
    def __init__(self, frames, opened=True, fps=10.0):
        self.frames = list(frames)
        self.opened = opened
        self.fps = fps
        self.index = 0
        self.released = False

    def isOpened(self):
        return self.opened

    def get(self, prop):
        if prop == cv2.CAP_PROP_FRAME_COUNT:
            return len(self.frames)
        if prop == cv2.CAP_PROP_FPS:
            return self.fps
        if prop == cv2.CAP_PROP_FRAME_WIDTH:
            return self.frames[0].shape[1] if self.frames else 0
        if prop == cv2.CAP_PROP_FRAME_HEIGHT:
            return self.frames[0].shape[0] if self.frames else 0
        return 0

    def read(self):
        if not self.opened or self.index >= len(self.frames):
            return False, None
        frame = self.frames[self.index]
        self.index += 1
        return True, frame

    def release(self):
        self.released = True


class FakeRealtimeDetector:
    selected_device = "0"
    class_names = {0: "pl60"}

    def __init__(self, model_path):
        self.model_path = model_path
        self.calls = []

    def predict_realtime(self, image_bytes, confidence, iou, image_size, device=None):
        with Image.open(BytesIO(image_bytes)) as image:
            width, height = image.size
        self.calls.append(
            {
                "confidence": confidence,
                "iou": iou,
                "image_size": image_size,
                "device": device,
            }
        )
        return ImagePrediction(
            width=width,
            height=height,
            inference_time_ms=8.0,
            detections=(
                DetectedObject(
                    class_id=29,
                    class_name="pl60",
                    confidence=0.9,
                    bbox=(1.0, 2.0, 12.0, 14.0),
                ),
            ),
            annotated_jpeg=b"annotated-frame",
        )


def create_user(db_session, username):
    user = User(
        username=username,
        email=f"{username}@example.com",
        hashed_password="test-hash",
    )
    db_session.add(user)
    db_session.commit()
    db_session.refresh(user)
    return user


def build_service(db_session, tmp_path, capture):
    model_path = tmp_path / "best.pt"
    model_path.write_bytes(b"checkpoint")
    detector = FakeRealtimeDetector(model_path)
    task_service = DetectionTaskService(
        detector=detector,
        output_dir=tmp_path / "detections",
    )
    worker_sessions = sessionmaker(bind=db_session.get_bind())
    service = VideoDetectionService(
        detector=detector,
        task_service=task_service,
        session_factory=worker_sessions,
        output_dir=tmp_path / "detections",
        temp_dir=tmp_path / "videos",
        capture_factory=lambda _path: capture,
        executor=ImmediateExecutor(),
    )
    return service, detector


def test_video_task_samples_frames_persists_results_and_cleans_source(
    db_session, tmp_path
):
    user = create_user(db_session, "video_service_user")
    frames = [np.full((24, 32, 3), value, dtype=np.uint8) for value in range(6)]
    capture = FakeCapture(frames)
    service, detector = build_service(db_session, tmp_path, capture)

    submission = service.submit(
        db=db_session,
        user_id=user.id,
        filename="road.mp4",
        content=b"fake-video",
        confidence=0.3,
        iou=0.5,
        image_size=640,
        sample_rate=2,
        max_frames=3,
    )
    db_session.expire_all()
    status = service.get_status(db_session, user.id, submission.task_id)
    task = db_session.get(DetectionTask, submission.task_id)
    records = (
        db_session.query(DetectionResult)
        .filter(DetectionResult.task_id == submission.task_id)
        .all()
    )

    assert status["status"] == "completed"
    assert status["progress"] == 100
    assert status["sampled_frames"] == 3
    assert [frame["frame_index"] for frame in status["key_frames"]] == [0, 2, 4]
    assert status["key_frames"][0]["traffic_signs"][0]["display_name"] == "最高限速 60 km/h"
    assert status["metadata"] == {
        "total_frames": 6,
        "fps": 10.0,
        "duration": 0.6,
        "width": 32,
        "height": 24,
    }
    assert task.status == "completed"
    assert task.total_images == 3
    assert task.total_objects == 3
    assert len(records) == 3
    assert records[0].image_path == "road.mp4#frame=0"
    assert all(call["device"] == "0" for call in detector.calls)
    assert capture.released is True
    assert list((tmp_path / "videos").glob("**/*")) == []


def test_video_task_marks_decode_failure_and_cleans_source(db_session, tmp_path):
    user = create_user(db_session, "video_failure_user")
    capture = FakeCapture([], opened=False)
    service, _detector = build_service(db_session, tmp_path, capture)

    submission = service.submit(
        db=db_session,
        user_id=user.id,
        filename="broken.mp4",
        content=b"broken",
        confidence=0.25,
        iou=0.45,
        image_size=640,
        sample_rate=5,
        max_frames=50,
    )
    db_session.expire_all()
    status = service.get_status(db_session, user.id, submission.task_id)

    assert status["status"] == "failed"
    assert "Unable to open video" in status["error"]
    assert capture.released is True
    assert list((tmp_path / "videos").glob("**/*")) == []
