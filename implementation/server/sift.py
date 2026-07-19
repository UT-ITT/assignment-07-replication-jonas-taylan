import cv2
import numpy as np

from matching_common import ImageProcessingError, homography_and_crop

# Re-exported so existing `from sift import ImageProcessingError` keeps working.
__all__ = ["process_sift", "ImageProcessingError"]


def process_sift(photo_bytes, screen_bytes):
    """
    Process images using SIFT from in-memory byte arrays.
    This is designed for server environments (e.g. FastAPI/Flask) to avoid disk I/O.

    :param photo_bytes: Bytes of the uploaded photo image.
    :param screen_bytes: Bytes of the uploaded screen image.
    :return: Cropped result image as a numpy array (BGR format), ready to be encoded.
    """
    # 1. Decode images from bytes
    photo_arr = np.frombuffer(photo_bytes, np.uint8)
    screen_arr = np.frombuffer(screen_bytes, np.uint8)

    photo = cv2.imdecode(photo_arr, cv2.IMREAD_GRAYSCALE)
    screen = cv2.imdecode(screen_arr, cv2.IMREAD_GRAYSCALE)
    screen_colored = cv2.imdecode(screen_arr, cv2.IMREAD_COLOR)

    if photo is None or screen is None or screen_colored is None:
        raise ImageProcessingError("Could not decode one or both images from the provided bytes.")

    # 2. Extract SIFT features
    sift = cv2.SIFT_create(2000)
    kp_photo, des_photo = sift.detectAndCompute(photo, None)
    kp_screen, des_screen = sift.detectAndCompute(screen, None)

    if des_photo is None or des_screen is None:
        raise ImageProcessingError("Could not extract SIFT features from the images.")

    # 3. Match features (FLANN-based)
    descriptor_matcher = cv2.DescriptorMatcher_create('FlannBased')

    # FLANN requires float32 descriptors for SIFT
    if des_photo.dtype != np.float32:
        des_photo = des_photo.astype(np.float32)
    if des_screen.dtype != np.float32:
        des_screen = des_screen.astype(np.float32)

    matches = descriptor_matcher.knnMatch(des_photo, des_screen, k=2)

    # 4. Filter good matches (Lowe's ratio test)
    good_matches = []
    for m, n in matches:
        if m.distance < 0.75 * n.distance:
            good_matches.append(m)

    if len(good_matches) < 20:
        raise ImageProcessingError(f"Not enough good matches found (need at least 20, found {len(good_matches)}).")

    # 5. + 6. Validated homography and crop (shared with the ORB matcher)
    photo_pts = np.float32([kp_photo[m.queryIdx].pt for m in good_matches]).reshape(-1, 1, 2)
    screen_pts = np.float32([kp_screen[m.trainIdx].pt for m in good_matches]).reshape(-1, 1, 2)

    return homography_and_crop(photo, screen_colored, photo_pts, screen_pts)
