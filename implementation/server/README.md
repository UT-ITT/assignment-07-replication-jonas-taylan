# Server

Python stand-in for the "PC daemon" from the ScreenshotMatcher paper. It
advertises itself on the local network, receives photos from the iOS app,
takes a screenshot of the Mac's display, matches the two with OpenCV, and
sends back the cropped result.

## Setup

```bash
cd implementation/server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python3 server.py
```

On macOS, grant Terminal (or your IDE) **Screen Recording** permission
(System Settings > Privacy & Security > Screen Recording) — otherwise
screenshots come back black.

## Files

- `server.py` – Bonjour advertisement, HTTP upload endpoint, ties together
  screen capture and matching.
- `screen_capture.py` – grabs the primary display as a JPEG (`mss`).
- `orb.py` / `sift.py` – the two selectable feature-matching algorithms
  (ORB with a brute-force Hamming matcher; SIFT with a FLANN matcher), both
  followed by Lowe's ratio test. Originally written by Taylan, since
  extended with the shared validation in `matching_common.py`.
- `matching_common.py` – shared RANSAC homography + crop logic used by both
  matchers, including validation that rejects degenerate matches (see
  below).
- `demo_capture.py` – on each successful match, saves a side-by-side
  `demo/<timestamp>_comparison.jpg` showing the uploaded photo next to the
  cropped result. Useful for live demos; `demo/` is git-ignored.

## Protocol

**Discovery (Bonjour/mDNS):**

- Server registers itself as a `_shotmatcher._tcp` service (via the
  `zeroconf` package) advertising its HTTP port (8000).
- Phone browses for that service type with `NWBrowser` and resolves the
  first result to an IP + port. No custom wire protocol — mDNS handles it.

**Upload & matching (HTTP, port 8000):**

- Phone sends `POST http://<serverIP>:8000/upload?algorithm=orb` (or
  `sift`) with a `multipart/form-data` body, field name `photo`, containing
  the JPEG. `algorithm` defaults to `orb` if omitted.
- Server saves the incoming photo to `received/photo_<timestamp>.jpg`,
  takes a screenshot of its primary display, and matches the photo against
  it.
- On success: `200 OK` with the cropped result image as the JPEG body.
- On failure (not enough matches, degenerate homography, ...): `422` with a
  plain-text reason. The app surfaces this as a "no match found" error.

## Matching pipeline

1. Detect keypoints/descriptors in both images (ORB or SIFT).
2. Match descriptors (brute-force Hamming for ORB, FLANN for SIFT) and
   filter with Lowe's ratio test.
3. Require at least 20 good matches.
4. Compute a homography with `cv2.findHomography(..., cv2.RANSAC, 5.0)`.
5. **Validate** the homography before trusting it (`matching_common.py`):
   - at least 15 RANSAC inliers,
   - the photo's corners project to a convex quad in the screenshot,
   - the matched region covers at least 1% of the screen area,
   - the crop's aspect ratio isn't wildly lopsided (max 20:1).

   This step exists because a mathematically valid homography can still be
   geometrically meaningless — e.g. collapsing the photo's rectangle into a
   5x1-pixel sliver. Without it, degenerate matches would occasionally slip
   through and produce nonsense crops. The paper describes this as
   "the final image's dimensions and size are validated to discard false
   positives".
6. Crop the projected bounding box from the screenshot and return it.

## Known limitation

Matching works well on UI-heavy screens (icons, window borders, images) but
is unreliable on mostly-text content — this matches a limitation the
original paper explicitly names ("the feature matcher works very well for
images with clear borders, it oftentimes fails for images that mainly
contain text").

## Notes

- Both devices must be on the same WiFi network.
- macOS may prompt to allow incoming network connections for Python on
  first run — allow it, otherwise the phone can't reach the server.
- The Bonjour service name (`_shotmatcher`) is intentionally short — mDNS
  service type labels are limited to 15 bytes, and `_screenshotmatcher`
  exceeds that.
- `received/` is git-ignored; it's just local debugging output.
