"""
ScreenshotMatcher server.

Stand-in for the "PC daemon" described in the ScreenshotMatcher paper. It
does three things:

1. Bonjour/mDNS advertisement: registers itself as a "_shotmatcher._tcp"
   service on the local network (via the `zeroconf` package) so the iOS app
   can discover it with NWBrowser, without either side needing to know IP
   addresses in advance.
2. HTTP upload: runs an HTTP server on port 8000 and accepts a
   multipart/form-data POST to /upload containing a "photo" field. Received
   photos are saved to ./received/.
3. Matching: takes a screenshot of the Mac's primary display, then matches
   the phone photo against it using either ORB (feature detection + a
   brute-force Hamming matcher) or SIFT (+ a FLANN-based matcher), both
   followed by Lowe's ratio test + RANSAC homography (see orb.py/sift.py,
   adapted from Taylan's scripts/server_ready/). The algorithm is selected
   per-request via the `algorithm` query parameter on /upload (`orb`, the
   default, or `sift`). The matched region is cropped from the screenshot
   and returned to the phone. If matching fails (not enough good keypoint
   matches, no valid homography, ...), a 422 response is returned instead so
   the app can show a "no match" error.

An earlier version just echoed the uploaded photo back as a stand-in result,
to get the app's receive/gallery path built and tested before the matching
pipeline existed. That echo path is gone now that real matching is wired up.

An even earlier version used a hand-rolled UDP broadcast protocol for
discovery, which turned out to be unreliable on a WiFi extender network
(broadcast packets computed for the wrong subnet mask never arrived).
Bonjour/mDNS is the platform-native mechanism for local service discovery on
Apple devices and is handled by the OS network stack, so it isn't subject to
that class of bug.

Usage:
    python3 -m venv .venv && source .venv/bin/activate
    pip install -r requirements.txt
    python3 test_server.py

On macOS, granting Terminal (or your IDE) Screen Recording permission
(System Settings > Privacy & Security > Screen Recording) is required for
screenshots to work — otherwise mss captures black frames.
"""

import os
import socket
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse, parse_qs
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import cv2
from zeroconf import Zeroconf, ServiceInfo

from orb import process_orb, ImageProcessingError
from sift import process_sift
from screen_capture import capture_primary_screen_jpeg

SERVICE_TYPE = "_shotmatcher._tcp.local."
HTTP_PORT = 8000

RECEIVED_DIR = Path(__file__).parent / "received"

MATCHERS = {
    "orb": process_orb,
    "sift": process_sift,
}
DEFAULT_ALGORITHM = "orb"

# Set MATCHING_ALWAYS_FAILS=1 in the environment to make every upload return
# a matching-failure response, for testing the app's error handling.
MATCHING_ALWAYS_FAILS = os.environ.get("MATCHING_ALWAYS_FAILS") == "1"


def local_ip() -> str:
    """Best-effort local IP lookup (doesn't actually send any packets)."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


def register_service(zeroconf: Zeroconf) -> ServiceInfo:
    ip = local_ip()
    hostname = socket.gethostname().split(".")[0]
    service_name = f"{hostname}.{SERVICE_TYPE}"

    info = ServiceInfo(
        SERVICE_TYPE,
        service_name,
        addresses=[socket.inet_aton(ip)],
        port=HTTP_PORT,
        server=f"{hostname}.local.",
    )
    zeroconf.register_service(info)
    print(f"[bonjour] advertising {service_name} at {ip}:{HTTP_PORT}")
    return info


class UploadHandler(BaseHTTPRequestHandler):
    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path != "/upload":
            self.send_response(404)
            self.end_headers()
            return

        query = parse_qs(parsed.query)
        algorithm = query.get("algorithm", [DEFAULT_ALGORITHM])[0].lower()
        matcher = MATCHERS.get(algorithm)
        if matcher is None:
            self.send_response(400)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(f"Unknown algorithm '{algorithm}'. Use one of: {', '.join(MATCHERS)}".encode("utf-8"))
            return

        content_type = self.headers.get("Content-Type", "")
        if "multipart/form-data" not in content_type:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"Expected multipart/form-data")
            return

        boundary = content_type.split("boundary=")[-1].encode("utf-8")
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)

        jpeg_bytes = self._extract_photo(body, boundary)
        if jpeg_bytes is None:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"No photo field found")
            return

        RECEIVED_DIR.mkdir(exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        out_path = RECEIVED_DIR / f"photo_{timestamp}.jpg"
        out_path.write_bytes(jpeg_bytes)
        print(f"[upload] saved {out_path} ({len(jpeg_bytes)} bytes) from {self.client_address[0]}")

        if MATCHING_ALWAYS_FAILS:
            self._send_matching_failure("Simulated matching failure (MATCHING_ALWAYS_FAILS=1)")
            return

        try:
            screen_jpeg = capture_primary_screen_jpeg()
        except Exception as e:
            self.send_response(500)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(f"Failed to capture screen: {e}".encode("utf-8"))
            print(f"[match] screen capture failed: {e}")
            return

        try:
            result_img = matcher(jpeg_bytes, screen_jpeg)
        except ImageProcessingError as e:
            self._send_matching_failure(str(e))
            return

        success, encoded = cv2.imencode(".jpg", result_img)
        if not success:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b"Failed to encode result image")
            return

        result_bytes = encoded.tobytes()
        print(f"[match] ({algorithm}) matched and cropped to {result_img.shape[1]}x{result_img.shape[0]}")

        self.send_response(200)
        self.send_header("Content-Type", "image/jpeg")
        self.send_header("Content-Length", str(len(result_bytes)))
        self.end_headers()
        self.wfile.write(result_bytes)

    def _send_matching_failure(self, message: str) -> None:
        self.send_response(422)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(message.encode("utf-8"))
        print(f"[match] failed: {message}")

    @staticmethod
    def _extract_photo(body: bytes, boundary: bytes) -> bytes | None:
        parts = body.split(b"--" + boundary)
        for part in parts:
            if b'name="photo"' not in part:
                continue
            header_end = part.find(b"\r\n\r\n")
            if header_end == -1:
                continue
            content = part[header_end + 4:]
            # Each part is followed by exactly "\r\n" before the next
            # boundary marker (per the multipart spec) — strip only that
            # literal trailing separator, not an arbitrary run of
            # \r/\n/- bytes, which previously corrupted JPEGs whose actual
            # last bytes happened to match one of those characters.
            if content.endswith(b"\r\n"):
                content = content[:-2]
            return content
        return None

    def log_message(self, format: str, *args) -> None:
        pass


def main() -> None:
    zeroconf = Zeroconf()
    service_info = register_service(zeroconf)

    server = ThreadingHTTPServer(("0.0.0.0", HTTP_PORT), UploadHandler)
    print(f"[upload] listening on HTTP :{HTTP_PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        zeroconf.unregister_service(service_info)
        zeroconf.close()


if __name__ == "__main__":
    main()
