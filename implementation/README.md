# Implementation

- `mobile/` – iOS app (SwiftUI) that captures a photo, discovers the host via Bonjour, and uploads it. See `mobile/README.md`.
- `server/` – Python host daemon (`server.py`) that advertises itself via Bonjour, receives the photo, captures its own screen, matches the two with OpenCV (ORB or SIFT), and returns the cropped result. See `server/README.md`.
