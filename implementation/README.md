# Implementation

- `mobile/` – iOS app (SwiftUI) that captures a photo and sends it to the host over WiFi. See `mobile/README.md`.
- `server/` – Python side running on the host PC. Currently `test_server.py`, a minimal UDP discovery + HTTP upload receiver used to validate the phone↔PC transport. Feature matching (ORB, homography, crop) will be added on top of this. See `server/README.md`.
