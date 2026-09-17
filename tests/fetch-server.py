"""Local stand-in for Nager.Date used by tests/fetch-harness.qml.

Serves the South Africa 2026 fixture for ZA and a misbehaving response for
each of the other country codes the harness asks about, so every guard in
HolidayFetch.qml can be exercised offline:

  ZA  the fixture, with a Content-Length header
  AA  a Content-Length far above the byte limit, then a slow body
  AB  a chunked body far above the byte limit, no Content-Length
  AC  headers, then nothing (a stalled connection)
  AD  a redirect to the ZA year
  anything else  404, like the real API for an unknown country
"""
import argparse
import http.server
import json
import os
import time

FIXTURE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixture-za-2026.json")
PREFIX = "/api/v3/PublicHolidays/"


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def send_json(self, status, body):
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self.path.startswith(PREFIX):
            self.send_json(404, b'{"title":"Not Found"}')
            return
        parts = self.path[len(PREFIX):].split("/")
        code = parts[1] if len(parts) == 2 else ""
        if code == "ZA":
            with open(FIXTURE, "rb") as handle:
                self.send_json(200, handle.read())
        elif code == "AA":
            body = b'[' + b'{"date":"2026-01-01","localName":"x","name":"x","global":true,"types":["Public"]},' * 3000 + b'{}]'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            for offset in range(0, len(body), 4096):
                try:
                    self.wfile.write(body[offset:offset + 4096])
                    self.wfile.flush()
                except OSError:
                    return
                time.sleep(0.01)
        elif code == "AB":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            chunk = b'[' + b'"' + b'x' * 4094 + b'",'
            for _ in range(60):
                try:
                    self.wfile.write(b"%x\r\n" % len(chunk) + chunk + b"\r\n")
                    self.wfile.flush()
                except OSError:
                    return
                time.sleep(0.01)
            self.wfile.write(b"0\r\n\r\n")
        elif code == "AC":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", "2")
            self.end_headers()
            time.sleep(6)
        elif code == "AD":
            self.send_response(302)
            self.send_header("Location", PREFIX + "2026/ZA")
            self.send_header("Content-Length", "0")
            self.end_headers()
        else:
            self.send_json(404, json.dumps({"title": "Not Found", "status": 404}).encode())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=18765)
    args = parser.parse_args()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.daemon_threads = True
    server.serve_forever()


if __name__ == "__main__":
    main()
