# Documentation – Assignment 7: Replicating Interaction Techniques

## 1. Paper Selection

### Candidates Considered

**Candidate A: ScreenshotMatcher**
Andreas Schmid, Thomas Fischer, Alexander Weichart, Alexander Hartmann, and Raphael Wimmer. 2021. Demonstrating ScreenshotMatcher: Taking Smartphone Photos to Capture Screenshots. In *Mensch und Computer 2021 (MuC '21)*. ACM. https://doi.org/10.1145/3473856.3474029

ScreenshotMatcher lets users capture a high-fidelity screenshot of a computer display by simply photographing it with a smartphone. A companion application running on the PC identifies the corresponding screen region using feature matching (ORB descriptors with brute-force Hamming-distance matching) and returns a clean, high-resolution screenshot to the phone. In lab conditions, the system achieved an 85% success rate with 90 ms processing time. A subsequent remote user study (n = 19) reported a 47% success rate under real-world conditions with a mean response time of 878 ms. The reference implementation is open source.

**Candidate B: DoubleFlip**
Jaime Ruiz and Yang Li. 2011. DoubleFlip: A Motion Gesture Delimiter for Mobile Interaction. In *Proceedings of the SIGCHI Conference on Human Factors in Computing Systems (CHI '11)*. ACM. https://doi.org/10.1145/1978942.1979341

DoubleFlip is a motion-gesture-based technique that uses a smartphone's built-in accelerometer to detect a distinctive "double flip" motion, serving as a reliable delimiter between everyday device movement and intentional gesture input. The recognizer was validated against 2,100 hours of motion data collected from 99 users and shown to be highly resistant to false positives while maintaining a high recognition rate.

The two candidates were deliberately chosen to represent distinct interaction paradigms — computer-vision-based sensing (ScreenshotMatcher) versus inertial motion-gesture sensing (DoubleFlip) — to ensure a genuine comparison rather than a choice between two closely related approaches.

### Selection Rationale

We selected **ScreenshotMatcher** for replication, for the following reasons:

- **Well-scoped core problem.** The central technical challenge — feature matching between a photographed image and a screen region — is self-contained and can be implemented with standard, freely available libraries (e.g., OpenCV's ORB detector and brute-force matcher), without requiring model training or dataset collection.
- **Fits the two-week timeframe.** Unlike more complex systems, the implementation does not depend on specialized hardware; it only requires a smartphone camera and a PC on the same network.
- **Existing evaluation data available.** The published lab and field results (success rate, latency) provide a concrete benchmark against which our own replication can be compared and discussed.
- **Open-source reference implementation.** The original codebase is publicly available, which reduces implementation risk and can serve as an orientation point without being directly copied.
- **Strong live-demo potential.** The interaction is immediately visible and compelling: the user takes a photo, and a clean screenshot appears moments later — well suited to the 8–10-minute live demonstration required for this assignment.

DoubleFlip was considered a valid alternative and is technically feasible within the same timeframe. It was ultimately not selected because its core interaction — recognizing a delimiter gesture — is less visually compelling as a live demonstration than the immediate, tangible result produced by ScreenshotMatcher.

### References

1. Andreas Schmid, Thomas Fischer, Alexander Weichart, Alexander Hartmann, and Raphael Wimmer. 2021. Demonstrating ScreenshotMatcher: Taking Smartphone Photos to Capture Screenshots. In *Mensch und Computer 2021 (MuC '21)*. ACM. https://doi.org/10.1145/3473856.3474029
2. Jaime Ruiz and Yang Li. 2011. DoubleFlip: A Motion Gesture Delimiter for Mobile Interaction. In *Proceedings of the SIGCHI Conference on Human Factors in Computing Systems (CHI '11)*. ACM. https://doi.org/10.1145/1978942.1979341

## 2. Implementation

### Architecture

Our replication mirrors the two-part architecture from the paper: a native
iOS app (instead of Android, since we only had access to an iPhone) acts as
the camera/viewfinder client, and a Python daemon running on a Mac acts as
the host that performs the matching.

```
 iPhone (SwiftUI app)                      Mac (Python daemon)
 ┌─────────────────────┐   Bonjour/mDNS    ┌──────────────────────┐
 │ Camera viewfinder    │ ───────────────▶ │ Service advertisement │
 │ Bonjour discovery    │ ◀─────────────── │ (_shotmatcher._tcp)   │
 │                      │                   │                      │
 │ Capture + downscale  │   HTTP POST       │ Screen capture (mss) │
 │ photo, upload        │ ───────────────▶ │ ORB / SIFT matching  │
 │                      │                   │ Homography + crop   │
 │ Show result / error  │ ◀─────────────── │ (OpenCV)             │
 └─────────────────────┘   JPEG or 422      └──────────────────────┘
```

**iOS app** (`implementation/mobile/`, SwiftUI):
- `CameraManager` — AVFoundation capture session, live viewfinder and
  single-photo capture.
- `DiscoveryService` — finds the host via Bonjour/mDNS (`NWBrowser`) and
  resolves it to an IP + port.
- `UploadService` — downscales the captured photo, uploads it via HTTP
  `multipart/form-data`, and returns the result image.
- `MatchingAlgorithm` — lets the user pick ORB or SIFT per request.
- `GalleryStore` / `GalleryView` — persists and displays sent and received
  photos in two separate galleries (grid view, share, delete).
- `RootView` — tab bar (Camera / Sent / Received), the app's main
  navigation.

**Python server** (`implementation/server/`):
- `server.py` — advertises the host via Bonjour, exposes an HTTP
  `/upload` endpoint, captures the screen, and dispatches to the matcher.
- `screen_capture.py` — grabs the primary display as JPEG bytes (`mss`).
- `orb.py` / `sift.py` — the two selectable feature-matching pipelines.
- `matching_common.py` — shared homography computation, validation, and
  cropping logic used by both matchers.

### Matching pipeline

Both matchers follow the pipeline described in the paper:

1. Detect keypoints and descriptors in the photo and the screenshot (ORB or
   SIFT).
2. Match descriptors (brute-force Hamming distance for ORB, FLANN for
   SIFT) and filter with Lowe's ratio test.
3. Require at least 20 good matches.
4. Compute a homography between the photo and the screenshot with
   `cv2.findHomography(..., cv2.RANSAC, 5.0)`.
5. Validate the homography (see Section 3 — this validation step was added
   during development, it is not part of the original scripts).
6. Project the photo's corners through the homography, take the
   axis-aligned bounding box, and crop it from the screenshot.

### Deviations from the original

- **iOS instead of Android.** The paper's reference implementation targets
  Android; we built a native SwiftUI app instead, since the team only had
  access to an iPhone. The interaction and pipeline are otherwise
  equivalent.
- **Bonjour/mDNS instead of UDP broadcast.** The paper describes UDP
  broadcast discovery; we switched to Bonjour/mDNS after broadcast proved
  unreliable on our network (see Section 3).
- **ORB and SIFT, selectable.** The paper uses ORB only. We added SIFT as a
  second, user-selectable option, mainly to compare match quality on the
  same input.
- **Explicit homography validation.** The paper mentions that "the final
  image's dimensions and size are validated to discard false positives"
  without detailing the check. We implemented a concrete version of this
  (inlier count, convexity, minimum area, aspect ratio — see Section 3).

## 3. Development Process, Challenges, and Limitations

We built the app and server in the order a working prototype needs them:
first get the phone and PC talking to each other at all, then add the
actual matching, then improve match quality once we could observe it fail
on real photos. Each step below is a real iteration we went through, in
order.

### Getting phone and PC to find each other

We started with the discovery mechanism described in the paper: the phone
broadcasts a UDP packet, the PC listens and replies with its address. This
worked in principle, but consistently failed to find the host over our
actual WiFi setup (a Fritz!Powerline access point). Packet captures on the
Mac showed the broadcast never arrived. The root cause turned out to be a
wrong assumption in our broadcast-address calculation: we assumed a /24
subnet mask (e.g. `192.168.2.255` as the broadcast address), but the
network actually used a /16 lease (`255.255.0.0`), making our computed
address meaningless on that network — packets sent to it went nowhere.

Rather than hand-computing broadcast addresses more carefully, we switched
to Bonjour/mDNS: the Mac registers a `_shotmatcher._tcp` service (via the
`zeroconf` Python package), and the phone browses for it with `NWBrowser`.
This is the platform-native discovery mechanism on Apple devices and is
handled entirely by the OS network stack, so it isn't subject to the same
class of bug and turned out to be considerably more robust on our network.
(Service type names for mDNS are limited to 15 bytes, which is why the
service is called `_shotmatcher` rather than the more descriptive
`_screenshotmatcher`.)

### A corrupted camera session

Early on, the camera preview intermittently failed to start on-device, with
CoreMedia logging `FigCaptureSourceRemote` errors. The cause was a data
race: `AVCaptureSession` configuration calls were split between the main
actor and a background queue. AVFoundation requires all session
configuration to happen serially on one queue; mixing isolation contexts
could let two configuration attempts overlap. The fix was to route all
session setup through a single dedicated serial queue and guard against
re-entering configuration while already configured.

### Getting real matching to work

Once discovery and upload were solid, we replaced the initial echo
placeholder (the server just sent the uploaded photo back, to test the
receive path before real matching existed) with an actual matching
pipeline, adapted from ORB and SIFT scripts one of us had prepared
separately. Testing this live surfaced two further problems:

**Match rate was poor with full-resolution photos.** The app was uploading
full iPhone camera resolution (several MB per photo). ORB's keypoint scales
didn't line up well against a much smaller Mac screenshot, so too few
matches passed Lowe's ratio test. The paper explicitly has the phone "scale
it down in resolution... before sending it to the connected PC"; we had
missed this step. Adding client-side downscaling to 1280px on the long
edge before upload noticeably improved match counts.

**A valid-looking homography could still be nonsense.** Even with more
matches available, we occasionally got results like a `5x1` or `41x3`
pixel crop — a mathematically valid homography whose projected region had
collapsed to a sliver. `cv2.findHomography` with RANSAC will return
*some* matrix as long as enough points roughly agree, without guaranteeing
the result is geometrically sane. We added an explicit validation step
before trusting a homography: a minimum number of RANSAC inliers, a
convexity check on the projected quad, a minimum area relative to the
screen, and a maximum aspect ratio. Our first attempt required a minimum
*fraction* of inliers (50%), which rejected too much — legitimate matches
on repetitive UI often have many ambiguous candidate matches, so the inlier
fraction stays low even for a correct fit. Switching to a minimum absolute
inlier *count* (15) fixed this while still rejecting the degenerate cases.

### A known limitation, confirmed empirically

With validation in place, we noticed a clear pattern: matching works very
reliably on screens with icons, window borders, or images, and works
poorly on screens that are mostly text. This is not a bug in our
implementation — the original paper names exactly this limitation: "the
feature matcher works very well for images with clear borders, it
oftentimes fails for images that mainly contain text." We consider this a
successful (if unplanned) replication of a documented weakness of the
underlying technique, not something to engineer around within this
project's scope. The paper's suggested fix (extending matching with
text-specific features, citing Tsai et al.) is out of scope for a
two-week project.

### Remaining limitations

- **Requires macOS + Xcode to build the app.** Native iOS development has
  no cross-platform path; the app cannot be built, run, or reviewed without
  a Mac. We mitigate this with a recorded demo and the live presentation
  rather than expecting reviewers to build it themselves.
- **Text-heavy screen regions match poorly**, as discussed above — a
  limitation shared with, and confirmed against, the original paper.
- **Requires Screen Recording permission on macOS** for the host to
  capture its own display; without it, `mss` silently returns black
  frames.
- **Same-WiFi-network requirement**, as in the original paper — no
  internet-relayed connection (e.g. via a STUN server) is implemented.
- **Single fixed match-count and validation thresholds.** The 20-match and
  15-inlier thresholds were tuned against our own test photos and screen
  content; they are not adaptive and may need retuning for very different
  screen resolutions or content types.

## 4. Setup

Requires a Mac (for the server and to build the app) and an iPhone on the
same WiFi network.

**Server:**
```bash
cd implementation/server
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python3 server.py
```
Grant Terminal (or your IDE) Screen Recording permission in System
Settings, otherwise screenshots come back black. Full protocol details are
in `implementation/server/README.md`.

**iOS app:**
```bash
brew install xcodegen
cd implementation/mobile
xcodegen generate
open ScreenshotMatcher.xcodeproj
```
Select your iPhone as the run destination, set your Apple ID as the
signing team, and run. Full setup and troubleshooting notes are in
`implementation/mobile/README.md`.