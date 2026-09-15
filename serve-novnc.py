#!/usr/bin/env python3
"""Static file server for the bundled noVNC, bound to the LAN address only.

Threading matters: noVNC is a few dozen ES modules and the stock single-threaded
http.server serialises them, which shows up as a visibly slow first paint on the
iPad. Everything served is read-only from vendor/novnc.
"""
import os, sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor", "novnc")
BIND = os.environ.get("BIND") or os.environ.get("HOST_IP")
if not BIND:
    sys.exit("BIND/HOST_IP not set (see .env.example)")
PORT = int(os.environ.get("WEB_PORT", "6080"))


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def end_headers(self):
        # The page is re-fetched on every connect; never let Safari cache a
        # stale module graph after a noVNC upgrade.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        pass


if not os.path.isdir(ROOT):
    sys.exit("noVNC not unpacked at %s" % ROOT)

ThreadingHTTPServer.allow_reuse_address = True
ThreadingHTTPServer((BIND, PORT), Handler).serve_forever()
