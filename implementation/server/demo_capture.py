"""Saves a side-by-side photo/result comparison image for live demos."""

from datetime import datetime
from pathlib import Path

import cv2
import numpy as np

DEMO_DIR = Path(__file__).parent / "demo"

_LABEL_HEIGHT = 40
_GAP = 12
_LABEL_BG = (40, 40, 40)
_LABEL_FG = (255, 255, 255)


def save_comparison(photo_bytes: bytes, result_img) -> Path | None:
    """
    Writes a single image with the uploaded photo (left) and the cropped
    result (right) side by side, each captioned, to demo/. Returns the path,
    or None if the photo couldn't be decoded.
    """
    photo = cv2.imdecode(np.frombuffer(photo_bytes, np.uint8), cv2.IMREAD_COLOR)
    if photo is None:
        return None

    left = _with_label(photo, "Photo")
    right = _with_label(result_img, "Cropped screenshot")

    height = max(left.shape[0], right.shape[0])
    left = _pad_to_height(left, height)
    right = _pad_to_height(right, height)
    gap = np.full((height, _GAP, 3), 255, dtype=np.uint8)
    combined = np.hstack([left, gap, right])

    DEMO_DIR.mkdir(exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    out_path = DEMO_DIR / f"{timestamp}_comparison.jpg"
    cv2.imwrite(str(out_path), combined)
    return out_path


def _with_label(img, text: str):
    h, w = img.shape[:2]
    banner = np.full((_LABEL_HEIGHT, w, 3), _LABEL_BG, dtype=np.uint8)
    cv2.putText(banner, text, (10, 27), cv2.FONT_HERSHEY_SIMPLEX, 0.7, _LABEL_FG, 2, cv2.LINE_AA)
    return np.vstack([banner, img])


def _pad_to_height(img, height: int):
    h, w = img.shape[:2]
    if h == height:
        return img
    padding = np.full((height - h, w, 3), 255, dtype=np.uint8)
    return np.vstack([img, padding])
