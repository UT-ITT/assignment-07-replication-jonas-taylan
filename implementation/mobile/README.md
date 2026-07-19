# ScreenshotMatcher – iOS App

SwiftUI camera app that discovers the Python server on the local WiFi
network via Bonjour/mDNS, sends the captured photo for matching, and shows
the sent/received photos in their own galleries.

## Setup

The Xcode project (`ScreenshotMatcher.xcodeproj`) is generated from
`project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen   # once
cd implementation/mobile
xcodegen generate
open ScreenshotMatcher.xcodeproj
```

Regenerate the project after changing `project.yml` or adding/removing
source files (XcodeGen picks up everything under `ScreenshotMatcher/Sources`
automatically).

## Running on a physical iPhone

1. In Xcode, select your iPhone as the run destination.
2. Under the target's "Signing & Capabilities" tab, set your Apple ID team
   (personal free provisioning is enough for local testing).
3. Make sure the iPhone and the Mac running `implementation/server/server.py`
   are on the **same WiFi network**.
4. Run the app (⌘R). Grant camera and local network permissions when
   prompted.
5. Start the Python server on the Mac first (see
   `implementation/server/README.md`), then launch/foreground the app — it
   browses for the server via Bonjour on launch and shows the connection
   status at the top of the camera screen.
6. Tap the shutter button to capture a photo and send it to the server. The
   result (or an error, if matching failed) appears in the Received tab.

If you change the Bonjour service type (`NSBonjourServices` in `project.yml`
and `serviceType` in `DiscoveryService.swift`) or any other entitlement,
delete the app from the phone before reinstalling — iOS caches the local
network permission per build and a stale install can keep failing with
`NoAuth` errors even after the code is fixed.

## Structure

- `ScreenshotMatcherApp.swift` – app entry point
- `RootView.swift` – tab bar (Camera / Sent / Received)
- `CameraView.swift` – camera viewfinder, connection status, capture button, upload flow
- `CameraManager.swift` – AVFoundation capture session wrapper
- `CameraPreviewView.swift` – UIViewRepresentable live preview layer
- `DiscoveryService.swift` – Bonjour/mDNS discovery of the host PC (NWBrowser)
- `UploadService.swift` – downscales the photo, uploads it (multipart/form-data), returns the result
- `MatchingAlgorithm.swift` – ORB/SIFT selection, sent as a query parameter on upload
- `ConnectionBadge.swift` – compact connection status pill + detail sheet (log, manual connect, algorithm picker)
- `GalleryStore.swift` – persists sent/received photos to disk with a JSON index
- `GalleryView.swift` – grid gallery + detail view (share, delete)

## Discovery/upload protocol

See `implementation/server/README.md` for the protocol shared between the
app and the Python server.

## Troubleshooting notes (from getting this running)

- An earlier version used a hand-rolled UDP broadcast protocol for
  discovery. That failed on a WiFi extender (Fritz!Powerline) network: the
  broadcast address was computed assuming a /24 subnet, but the actual
  network handed out /16 leases, so the computed broadcast address
  (`192.168.2.255`) was never a valid "all devices" address on this network
  and packets silently went nowhere. Bonjour/mDNS avoids this whole class of
  bug because the OS handles the network topology.
- `AVCaptureSession` configuration must happen entirely on a single serial
  queue — mixing MainActor-isolated and background-queue access to the same
  session caused corrupted capture sessions (CoreMedia
  `FigCaptureSourceRemote` errors) on device.
- Uploading full-resolution iPhone photos (several MB) produced poor ORB
  match rates — the paper has the phone "scale it down in resolution"
  before sending, which we were initially missing. `UploadService` now
  downscales to 1280px on the long edge before upload.
