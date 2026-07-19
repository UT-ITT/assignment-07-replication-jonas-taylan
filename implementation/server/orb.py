import cv2
import numpy as np

from matching_common import ImageProcessingError, homography_and_crop

# Re-exported so existing `from orb import ImageProcessingError` keeps working.
__all__ = ["process_orb", "ImageProcessingError"]


def process_orb(photo_bytes, screen_bytes):
    """Matches a phone photo against a screenshot using ORB and returns the cropped region (BGR numpy array)."""
    photo_arr = np.frombuffer(photo_bytes, np.uint8)
    screen_arr = np.frombuffer(screen_bytes, np.uint8)

    photo = cv2.imdecode(photo_arr, cv2.IMREAD_GRAYSCALE)
    screen = cv2.imdecode(screen_arr, cv2.IMREAD_GRAYSCALE)
    screen_colored = cv2.imdecode(screen_arr, cv2.IMREAD_COLOR)

    if photo is None or screen is None or screen_colored is None:
        raise ImageProcessingError("Could not decode one or both images from the provided bytes.")

    orb = cv2.ORB_create(2000)
    kp_photo, des_photo = orb.detectAndCompute(photo, None)
    kp_screen, des_screen = orb.detectAndCompute(screen, None)

    if des_photo is None or des_screen is None:
        raise ImageProcessingError("Could not extract ORB features from the images.")

    descriptor_matcher = cv2.DescriptorMatcher_create('BruteForce-Hamming')
    matches = descriptor_matcher.knnMatch(des_photo, des_screen, k=2)

    good_matches = []
    for m, n in matches:
        if m.distance < 0.75 * n.distance:
            good_matches.append(m)

    if len(good_matches) < 20:
        raise ImageProcessingError(f"Not enough good matches found (need at least 20, found {len(good_matches)}).")

    photo_pts = np.float32([kp_photo[m.queryIdx].pt for m in good_matches]).reshape(-1, 1, 2)
    screen_pts = np.float32([kp_screen[m.trainIdx].pt for m in good_matches]).reshape(-1, 1, 2)

    return homography_and_crop(photo, screen_colored, photo_pts, screen_pts)
