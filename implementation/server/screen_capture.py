"""Captures the primary monitor as JPEG bytes, for matching against phone photos."""

import cv2
import mss
import numpy as np


def capture_primary_screen_jpeg() -> bytes:
    with mss.mss() as sct:
        monitor = sct.monitors[1]  # index 0 is "all monitors combined"
        raw = sct.grab(monitor)

    frame = np.array(raw)
    frame_bgr = cv2.cvtColor(frame, cv2.COLOR_BGRA2BGR)
    success, encoded = cv2.imencode(".jpg", frame_bgr)
    if not success:
        raise RuntimeError("Failed to encode screenshot as JPEG")
    return encoded.tobytes()
