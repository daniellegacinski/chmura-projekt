"""Interfejs HTTP wokół modułu reguł – Lab 7.

Bez SQS i DynamoDB: przyjmuje dane zamówienia i zwraca decyzję oraz wersję.
POST /decide  {"sku": "SKU-A", "quantity": 6, "scenario": "normal", "attempt": 1}
GET  /health
"""
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

from rules import TransientFailure, decide

APP_VERSION = os.environ.get("APP_VERSION", "dev")
GIT_SHA = os.environ.get("GIT_SHA", "local")


class Handler(BaseHTTPRequestHandler):
    def send_json(self, status, body):
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            self.send_json(200, {"status": "ok", "version": APP_VERSION, "commit": GIT_SHA})
        else:
            self.send_json(404, {"error": "NOT_FOUND"})

    def do_POST(self):
        if self.path != "/decide":
            self.send_json(404, {"error": "NOT_FOUND"})
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length))
            sku = body["sku"]
            quantity = body["quantity"]
            scenario = body.get("scenario", "normal")
            attempt = int(body.get("attempt", 1))
            if not isinstance(sku, str) or isinstance(quantity, bool) or not isinstance(quantity, int):
                raise ValueError
        except (ValueError, KeyError, TypeError):
            self.send_json(400, {"error": "INVALID_INPUT", "version": APP_VERSION})
            return
        try:
            result = decide(sku, quantity, scenario, attempt)
        except TransientFailure:
            self.send_json(503, {"error": "TRANSIENT_FAILURE", "version": APP_VERSION, "commit": GIT_SHA})
            return
        self.send_json(200, {**result, "version": APP_VERSION, "commit": GIT_SHA})


if __name__ == "__main__":
    print(f"Serwer reguł, wersja {APP_VERSION} ({GIT_SHA}), port 8080", flush=True)
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()