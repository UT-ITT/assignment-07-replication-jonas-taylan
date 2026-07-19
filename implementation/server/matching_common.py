"""
Shared homography + crop logic for the ORB and SIFT matchers.

Both matchers detect keypoints, match descriptors, and run Lowe's ratio test
differently, but the tail of the pipeline — compute a RANSAC homography,
validate it, project the photo's corners into the screenshot, and crop the
bounding box — is identical, so it lives here.

The validation step is what the paper refers to when it says "the final
image's dimensions and size are validated to discard false positives". A
plain findHomography()+crop (as in the original scripts) happily returns
degenerate matches: a mathematically valid homography can collapse the
photo's rectangle onto a near-line or a tiny sliver (e.g. crops like 5x1 or
41x3), which are meaningless. We reject those here before cropping.
"""

import cv2
import numpy as np


class ImageProcessingError(Exception):
    """Custom exception raised for errors during image processing."""
    pass


# Minimum number of RANSAC inliers (matches that geometrically agree with the
# homography) for it to be trusted. An absolute count is more robust than a
# ratio here: photos of a screen produce many ambiguous descriptor matches
# (repeated text/UI, reflections, moiré), so the inlier *fraction* is often
# low even for a correct match — but a solid cluster of ~15 geometrically
# consistent inliers still pins down a stable homography.
MIN_INLIERS = 15
# The cropped region must cover at least this fraction of the screenshot area.
# Real screen regions are sizeable; slivers of a few pixels are false positives.
MIN_AREA_RATIO = 0.01
# The projected quad's sides must not be wildly lopsided (guards against the
# rectangle collapsing toward a line).
MAX_ASPECT_RATIO = 20.0


def homography_and_crop(photo_gray, screen_colored, photo_pts, screen_pts):
    """
    Computes a validated RANSAC homography from photo->screen point
    correspondences, projects the photo's corners into the screenshot, and
    returns the cropped bounding-box region.

    Raises ImageProcessingError if the homography is missing or degenerate.
    """
    M, mask = cv2.findHomography(photo_pts, screen_pts, cv2.RANSAC, 5.0)

    if M is None or not M.any():
        raise ImageProcessingError("Could not find homography between the images.")

    # --- validate: enough matches actually support this homography ---
    if mask is not None:
        inliers = int(mask.sum())
        total = int(mask.shape[0])
        if inliers < MIN_INLIERS:
            raise ImageProcessingError(
                f"Homography rejected: only {inliers} inliers out of {total} matches "
                f"(need at least {MIN_INLIERS})."
            )

    # --- project the photo's corners into the screenshot ---
    h, w = photo_gray.shape
    pts = np.float32([[0, 0], [0, h - 1], [w - 1, h - 1], [w - 1, 0]]).reshape(-1, 1, 2)
    dst = cv2.perspectiveTransform(pts, M)

    # --- validate: the projected quad is a sane, convex, non-degenerate shape ---
    quad = dst.reshape(-1, 2)
    if not _is_convex(quad):
        raise ImageProcessingError("Homography rejected: projected region is not convex (degenerate match).")

    quad_area = cv2.contourArea(quad.astype(np.float32))
    screen_area = screen_colored.shape[0] * screen_colored.shape[1]
    if quad_area < MIN_AREA_RATIO * screen_area:
        raise ImageProcessingError(
            f"Homography rejected: matched region too small "
            f"({quad_area / screen_area:.1%} of screen, need {MIN_AREA_RATIO:.0%})."
        )

    # --- crop the axis-aligned bounding box, clamped to screen bounds ---
    minX = max(0, int(np.min(dst[:, 0, 0])))
    minY = max(0, int(np.min(dst[:, 0, 1])))
    maxX = min(screen_colored.shape[1], int(np.max(dst[:, 0, 0])))
    maxY = min(screen_colored.shape[0], int(np.max(dst[:, 0, 1])))

    if minX >= maxX or minY >= maxY:
        raise ImageProcessingError("Invalid crop dimensions calculated from homography.")

    crop_w = maxX - minX
    crop_h = maxY - minY
    aspect = max(crop_w, crop_h) / max(1, min(crop_w, crop_h))
    if aspect > MAX_ASPECT_RATIO:
        raise ImageProcessingError(
            f"Homography rejected: crop aspect ratio {aspect:.0f}:1 is degenerate."
        )

    return screen_colored[minY:maxY, minX:maxX]


def _is_convex(quad) -> bool:
    """True if the 4-point quad is convex (all cross products same sign)."""
    n = len(quad)
    if n != 4:
        return False
    signs = []
    for i in range(n):
        a = quad[i]
        b = quad[(i + 1) % n]
        c = quad[(i + 2) % n]
        cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
        signs.append(cross > 0)
    return all(signs) or not any(signs)
