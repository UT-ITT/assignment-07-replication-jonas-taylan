"""
ScreenshotMatcher test server.

Minimal stand-in for the "PC daemon" described in the ScreenshotMatcher
paper. It does two things:

1. Bonjour/mDNS advertisement: registers itself as a "_shotmatcher._tcp"
   service on the local network (via the `zeroconf` package) so the iOS app
   can discover it with NWBrowser, without either side needing to know IP
   addresses in advance.
2. HTTP upload: runs an HTTP server on port 8000 and accepts a
   multipart/form-data POST to /upload containing a "photo" field. Received
   photos are saved to ./received/, and the same image is echoed back in the
   HTTP response as a stand-in "result" image.

This script does not yet perform any feature matching / homography — the
response is just the uploaded photo echoed back, so the app's receive path
can be built and tested end-to-end. The matching pipeline (ORB, homography,
crop) is a separate, later step that will replace the echo with a real
cropped screenshot.

An earlier version used a hand-rolled UDP broadcast protocol for discovery,
which turned out to be unreliable on a WiFi extender network (broadcast
packets computed for the wrong subnet mask never arrived). Bonjour/mDNS is
the platform-native mechanism for local service discovery on Apple devices
and is handled by the OS network stack, so it isn't subject to that class of
bug.

Usage:
    python3 test_server.py

Dependencies:
    pip install zeroconf
"""

import os
import socket
from datetime import datetime
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from zeroconf import Zeroconf, ServiceInfo

SERVICE_TYPE = "_shotmatcher._tcp.local."
HTTP_PORT = 8000

RECEIVED_DIR = Path(__file__).parent / "received"

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
        if self.path != "/upload":
            self.send_response(404)
            self.end_headers()
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

        # No real matching pipeline yet: echo the photo back as the "result"
        # so the app's receive/gallery path has something to display. This
        # is also where a matching failure would be reported (see below).
        if MATCHING_ALWAYS_FAILS:
            self.send_response(422)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"No matching screen region found")
            print("[upload] simulated matching failure (MATCHING_ALWAYS_FAILS=1)")
            return

        self.send_response(200)
        self.send_header("Content-Type", "image/jpeg")
        self.send_header("Content-Length", str(len(jpeg_bytes)))
        self.end_headers()
        self.wfile.write(jpeg_bytes)

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
