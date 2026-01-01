import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, status, html):
        body = html.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/":
            html = (
                "<!doctype html><html><head><meta charset=\"utf-8\">"
                "<title>FounderBooster Port-First Demo</title></head>"
                "<body><h1>FounderBooster Port-First Demo</h1></body></html>"
            )
            self._send_html(200, html)
            return

        if self.path == "/health":
            self._send_json(200, {"status": "ok"})
            return

        if self.path == "/api/hello":
            self._send_json(200, {"message": "hello from FounderBooster port-first demo"})
            return

        self._send_json(404, {"error": "not_found"})

    def log_message(self, format, *args):
        return


def run():
    port = int(os.environ.get("PORT", "3000"))
    server = HTTPServer(("0.0.0.0", port), Handler)

    print(f"Port-first demo running on http://localhost:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Shutting down")
    finally:
        server.server_close()


if __name__ == "__main__":
    run()
