# Test Server

Minimal Python stand-in for the "PC daemon" from the ScreenshotMatcher paper.
Proves the discovery + photo transport path end-to-end; does **not** yet do
any feature matching (ORB/homography/crop) — that's the next step.

## Run

```bash
cd implementation/server
pip install -r requirements.txt
python3 test_server.py
```

## Protocol

**Discovery (Bonjour/mDNS):**

- Server registers itself as a `_shotmatcher._tcp` service (via the
  `zeroconf` package) advertising its HTTP port (8000).
- Phone browses for that service type with `NWBrowser` and resolves the
  first result to an IP + port. No custom wire protocol — mDNS handles it.

(An earlier version used a hand-rolled UDP broadcast on port 50000. That
turned out to be unreliable on a WiFi extender network because the phone's
computed broadcast address assumed the wrong subnet size. Bonjour/mDNS is
the platform-native mechanism for this and is handled by the OS network
stack on both ends.)

**Upload (HTTP, port 8000):**

- Phone sends `POST http://<serverIP>:8000/upload` with
  `multipart/form-data` body, field name `photo`, containing the JPEG.
- Server saves the file to `implementation/server/received/photo_<timestamp>.jpg`
  and responds `200 OK`.

## Notes

- Both devices must be on the same WiFi network.
- macOS may prompt to allow incoming network connections for Python on first
  run — allow it, otherwise the phone can't reach the server.
- The Bonjour service name (`_shotmatcher`) is intentionally short — mDNS
  service type labels are limited to 15 bytes, and `_screenshotmatcher`
  exceeds that.
- `received/` is git-ignored; it's just local test output.
