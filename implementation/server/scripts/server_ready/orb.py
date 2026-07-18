import cv2
import numpy as np

class ImageProcessingError(Exception):
    """Custom exception raised for errors during image processing."""
    pass

def process_orb(photo_bytes, screen_bytes):
    """
    Process images using ORB from in-memory byte arrays.
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

    # 2. Extract ORB features
    orb = cv2.ORB_create(2000)
    kp_photo, des_photo = orb.detectAndCompute(photo, None)
    kp_screen, des_screen = orb.detectAndCompute(screen, None)
    
    if des_photo is None or des_screen is None:
         raise ImageProcessingError("Could not extract ORB features from the images.")

    # 3. Match features
    descriptor_matcher = cv2.DescriptorMatcher_create('BruteForce-Hamming')
    matches = descriptor_matcher.knnMatch(des_photo, des_screen, k=2)

    # 4. Filter good matches
    good_matches = []
    for m, n in matches:
        if m.distance < 0.75 * n.distance:
            good_matches.append(m)

    if len(good_matches) < 20:
        raise ImageProcessingError(f"Not enough good matches found (need at least 20, found {len(good_matches)}).")

    # 5. Calculate Homography
    photo_pts = np.float32([ kp_photo[m.queryIdx].pt for m in good_matches ]).reshape(-1,1,2)
    screen_pts = np.float32([ kp_screen[m.trainIdx].pt for m in good_matches ]).reshape(-1,1,2)

    M, mask = cv2.findHomography(photo_pts, screen_pts, cv2.RANSAC, 5.0)

    if M is None or not M.any():
        raise ImageProcessingError("Could not find homography between the images.")

    # 6. Apply Homography and Crop
    h, w = photo.shape
    pts = np.float32([ [0,0],[0,h-1],[w-1,h-1],[w-1,0] ]).reshape(-1,1,2)
    dst = cv2.perspectiveTransform(pts, M)

    minX = int(max(0, np.min(dst[:, 0, 0])))
    minY = int(max(0, np.min(dst[:, 0, 1])))
    maxX = int(np.max(dst[:, 0, 0]))
    maxY = int(np.max(dst[:, 0, 1]))

    # Ensure coordinates are within image bounds
    minX = max(0, minX)
    minY = max(0, minY)
    maxX = min(screen_colored.shape[1], maxX)
    maxY = min(screen_colored.shape[0], maxY)

    if minX >= maxX or minY >= maxY:
         raise ImageProcessingError("Invalid crop dimensions calculated from homography.")

    result_img = screen_colored[minY:maxY, minX:maxX]
    
    return result_img
