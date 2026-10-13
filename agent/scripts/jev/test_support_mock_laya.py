"""Reusable loopback mock of the Laya/Jev `POST /v1/systemone` wire protocol, shared
by test_guard_advisor.py / test_tier_advisor.py / test_evidence_reducer.py /
test_decide_integration.py (four consumers -- Ponytail step 2, Codebase Reuse:
agent/scripts/jev/test_jev_client.py's own `_MockJevServer` was written inline
for its single caller and is intentionally NOT imported from here, to avoid
coupling this shared helper's shape to jev_client.py's own test file; this is a
deliberately new, small, single-purpose module, not a refactor of that one).

Same dynamic-echo design as `_MockJevServer`: replies to whatever question ids the
incoming request actually asked for, so callers don't need to hardcode a
question-id naming convention. `self.requests` records every request received
(headers + raw body) so tests can assert "zero requests were sent" as well as
inspect exactly what was sent.
"""
import http.server
import json
import threading
import time


class MockLayaServer:
    def __init__(self):
        self.lock = threading.Lock()
        self.reset()
        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_POST(self):  # noqa: N802 (http.server naming convention)
                length = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(length) if length else b""
                with outer.lock:
                    outer.requests.append({"headers": dict(self.headers.items()), "body": raw})
                    status = outer.status
                    delay = outer.delay
                    answer_fn = outer.answer_fn

                if delay:
                    time.sleep(delay)

                try:
                    req = json.loads(raw.decode("utf-8"))
                    questions = req.get("questions", {})
                except Exception:
                    questions = {}
                    req = {}

                answers = {qid: answer_fn(qid, question, req) for qid, question in questions.items()}
                resp = {"model": "laya-test", "answers": answers, "usage": {}}
                payload = json.dumps(resp).encode("utf-8")
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                try:
                    self.wfile.write(payload)
                except Exception:
                    pass

            def log_message(self, fmt, *args):  # silence test output
                pass

        self.httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.port = self.httpd.server_address[1]
        self.url = "http://127.0.0.1:%d/v1/systemone" % self.port
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def reset(self):
        with self.lock:
            self.status = 200
            self.delay = 0.0
            self.requests = []
            self.answer_fn = _default_answer_fn

    def shutdown(self):
        self.httpd.shutdown()
        self.httpd.server_close()


def _default_answer_fn(qid, question, req):
    qtype = question.get("type")
    if qtype == "noul":
        return {"type": "noul", "noul": 0.0}
    if qtype == "choice":
        criteria = question.get("criteria") or {}
        first = next(iter(criteria), None)
        return {"type": "choice", "choice": first, "confidence": 0.5}
    if qtype == "score":
        return {"type": "score", "score": 0, "confidence": 0.5}
    return {}
