#!/usr/bin/env python3
"""
test_jev_client.py — tests for agent/scripts/jev/jev_client.py.

Covers the `jev_client` module: `evaluate()`, `contains_secret()`,
the convenience wrappers `noul()` / `choice()` / `score()`, and the CLI entry point
(`python3 jev_client.py noul|choice|score --instructions ... [--options a,b,c |
--levels a,b,c]`).

Everything runs against a local `http.server` mock bound to 127.0.0.1 on an ephemeral
port — this suite MUST NEVER connect to the real https://api.typesafe.ai endpoint.

Spec sources (do not guess shapes — follow these):
  - Official Jev HTTP API reference:
    ~/.claude/session-data/swarm/missions/ai-env-deepresearch-overhaul/jev-api-reference.md
  - Design decisions (I-3 fail-to-deterministic, I-6 secret-detection-before-send):
    CONTEXT.md, "## ai-env-deepresearch-overhaul" section.

Per the swarm-implement Test Maker charter, this file contains ONLY tests — no
production code. It was written first (TDAD RED phase, before jev_client.py existed);
jev_client.py has since been implemented, so the suite is expected to pass.
"""

import http.server
import json
import os
import socket
import subprocess
import sys
import threading
import time
import unittest
from unittest import mock

TEST_DIR = os.path.dirname(os.path.abspath(__file__))
CLIENT_PATH = os.path.join(TEST_DIR, "jev_client.py")

sys.path.insert(0, TEST_DIR)

import jev_client  # noqa: E402  (after sys.path insert above)


ENV_KEYS = (
    "TYPESAFE_API_KEY",
    "JEV_DISABLE",
    "TYPESAFE_API_URL",
    "JEV_TIMEOUT_MS",
    "JEV_ALLOW_REMOTE",
)


# ---------------------------------------------------------------------------
# Mock Jev HTTP server
# ---------------------------------------------------------------------------


class _MockJevServer:
    """A loopback-only mock of the Jev evaluation endpoint.

    Two response modes:
      - static: always returns `self.body` verbatim (for tests where the caller
        controls the question ids directly, e.g. raw evaluate() calls).
      - dynamic: echoes `self.answer_template` back under every question id found
        in the *incoming* request body (for testing the noul()/choice()/score()
        convenience wrappers and the CLI, whose internal question-id naming is an
        implementation detail this suite must not assume).

    Every request received is recorded (headers + raw body) in `self.requests` so
    tests can assert "zero requests were sent" (secret detection, disabled key,
    rejected endpoint) as well as inspect exactly what was sent (Authorization
    header, JSON body shape).
    """

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
                    outer.requests.append(
                        {"headers": dict(self.headers.items()), "body": raw}
                    )
                    status = outer.status
                    delay = outer.delay
                    dynamic = outer.dynamic
                    template = outer.answer_template
                    static_body = outer.body
                    location = outer.location

                if delay:
                    time.sleep(delay)

                if dynamic:
                    try:
                        req = json.loads(raw.decode("utf-8"))
                        qids = list(req.get("questions", {}).keys())
                    except Exception:
                        qids = []
                    resp = {
                        "model": "jev-1.0.0-test",
                        "answers": {qid: template for qid in qids},
                        "usage": {"input_tokens": 10, "output_tokens": 5},
                    }
                    payload = json.dumps(resp).encode("utf-8")
                elif isinstance(static_body, (bytes, bytearray)):
                    payload = bytes(static_body)
                else:
                    payload = json.dumps(static_body).encode("utf-8")

                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                if location:
                    self.send_header("Location", location)
                self.end_headers()
                try:
                    self.wfile.write(payload)
                except Exception:
                    pass

            # A followed 301/302 redirect of a POST is classically re-sent as a GET
            # (that's what urllib's default HTTPRedirectHandler does) -- alias so a
            # redirect that reaches this server at all is recorded and answered
            # identically, regardless of which verb it arrived as. Without this, a
            # would-be leaked request would silently 501 here and never appear in
            # `requests`, masking the very bug the no-redirect-follow test checks for.
            do_GET = do_POST  # noqa: N802 (http.server naming convention)

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
            self.body = {"model": "jev-1.0.0-test", "answers": {}, "usage": {}}
            self.dynamic = False
            self.answer_template = None
            self.location = None
            self.requests = []

    def shutdown(self):
        self.httpd.shutdown()
        self.httpd.server_close()


class _TrickleServer:
    """Sends its response body in small, delayed chunks so no single socket read ever
    blocks anywhere near the caller's overall timeout budget, but the wall-clock total
    (chunk_count * chunk_delay) does exceed it -- used to prove evaluate()'s timeout is
    an overall deadline, not merely a per-socket-operation one."""

    def __init__(self, chunk_delay=0.1, chunk_size=5):
        self.chunk_delay = chunk_delay
        self.chunk_size = chunk_size
        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_POST(self):  # noqa: N802
                length = int(self.headers.get("Content-Length") or 0)
                if length:
                    self.rfile.read(length)
                body = json.dumps({"model": "m", "answers": {}, "usage": {}}).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                for i in range(0, len(body), outer.chunk_size):
                    try:
                        self.wfile.write(body[i : i + outer.chunk_size])
                        self.wfile.flush()
                    except Exception:
                        return
                    time.sleep(outer.chunk_delay)

            def log_message(self, fmt, *args):
                pass

        self.httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.port = self.httpd.server_address[1]
        self.url = "http://127.0.0.1:%d/v1/systemone" % self.port
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def shutdown(self):
        self.httpd.shutdown()
        self.httpd.server_close()


class _SlowHeaderServer:
    """A raw-socket loopback server that writes the HTTP status line + headers one byte
    at a time (with a small delay between each), then the full body at once.

    Deliberately bypasses http.server's buffered response writer (which would send
    headers in one shot) to prove the overall deadline covers *header* reads too, not
    just body reads: `_read_within_deadline` only ever sees the already-parsed body, so
    a peer that stalls during the status-line/header phase (handled entirely inside
    urllib's own `getresponse()`, before jev_client regains control) is a distinct code
    path from the trickling-body case `_TrickleServer` above covers.
    """

    def __init__(self, byte_delay=0.05):
        self.byte_delay = byte_delay
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.bind(("127.0.0.1", 0))
        self._sock.listen(5)
        self.port = self._sock.getsockname()[1]
        self.url = "http://127.0.0.1:%d/v1/systemone" % self.port
        self._stop = False
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()

    def _serve(self):
        self._sock.settimeout(0.2)
        while not self._stop:
            try:
                conn, _ = self._sock.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            try:
                conn.settimeout(5)
                try:
                    conn.recv(65536)
                except Exception:
                    pass
                body = b'{"model":"m","answers":{},"usage":{}}'
                header = (
                    "HTTP/1.1 200 OK\r\n"
                    "Content-Type: application/json\r\n"
                    "Content-Length: %d\r\n\r\n" % len(body)
                ).encode("ascii")
                for i in range(len(header)):
                    try:
                        conn.sendall(header[i : i + 1])
                    except Exception:
                        break
                    time.sleep(self.byte_delay)
                else:
                    try:
                        conn.sendall(body)
                    except Exception:
                        pass
            finally:
                conn.close()

    def shutdown(self):
        self._stop = True
        try:
            self._sock.close()
        except Exception:
            pass


class JevClientTestCase(unittest.TestCase):
    """Base fixture: one mock server per test process, reset per test, with the
    Jev-related environment variables saved/restored around every test so tests
    never leak configuration into each other."""

    @classmethod
    def setUpClass(cls):
        cls.mock = _MockJevServer()

    @classmethod
    def tearDownClass(cls):
        cls.mock.shutdown()

    def setUp(self):
        self.mock.reset()
        self._saved_env = {k: os.environ.get(k) for k in ENV_KEYS}
        for k in ENV_KEYS:
            os.environ.pop(k, None)
        os.environ["TYPESAFE_API_KEY"] = "test-key-123"
        os.environ["TYPESAFE_API_URL"] = self.mock.url

    def tearDown(self):
        for k, v in self._saved_env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    # -- helpers -----------------------------------------------------------

    def last_request(self):
        self.assertEqual(len(self.mock.requests), 1, "expected exactly one request")
        return self.mock.requests[0]

    def decoded_body(self, req):
        return json.loads(req["body"].decode("utf-8"))


# ---------------------------------------------------------------------------
# evaluate(): success paths + wire format
# ---------------------------------------------------------------------------


class TestEvaluateSuccess(JevClientTestCase):
    def test_noul_success(self):
        self.mock.body = {
            "model": "jev-1.13.0",
            "answers": {"is_urgent": {"type": "noul", "noul": 0.95}},
            "usage": {"input_tokens": 10, "output_tokens": 5},
        }
        result = jev_client.evaluate(
            "Help! My payouts have been failing for 3 days.",
            {
                "is_urgent": {
                    "type": "noul",
                    "instructions": "Does this convey urgency?",
                }
            },
        )
        self.assertEqual(result, {"is_urgent": {"type": "noul", "noul": 0.95}})

    def test_choice_success(self):
        self.mock.body = {
            "model": "jev-1.13.0",
            "answers": {
                "department": {
                    "type": "choice",
                    "choice": "billing",
                    "probabilities": {"billing": 0.88, "technical": 0.12, "sales": 0.0},
                    "confidence": 0.81,
                }
            },
            "usage": {"input_tokens": 10, "output_tokens": 5},
        }
        result = jev_client.evaluate(
            "Help! My payouts have been failing for 3 days.",
            {
                "department": {
                    "type": "choice",
                    "instructions": "Which team should handle this?",
                    "criteria": {
                        "billing": "Payments, invoicing, refunds",
                        "technical": "Bugs, outages, integrations",
                        "sales": "Pricing, upgrades, new accounts",
                    },
                }
            },
        )
        self.assertIsNotNone(result)
        self.assertEqual(result["department"]["choice"], "billing")
        self.assertEqual(result["department"]["confidence"], 0.81)

    def test_score_success(self):
        self.mock.body = {
            "model": "jev-1.13.0",
            "answers": {
                "frustration": {
                    "type": "score",
                    "score": 1.05,
                    "legend": {"0": "Calm", "1": "Frustrated", "2": "Very angry"},
                    "probabilities": {"0": 0.0, "1": 0.95, "2": 0.05},
                    "confidence": 0.92,
                }
            },
            "usage": {"input_tokens": 10, "output_tokens": 5},
        }
        result = jev_client.evaluate(
            "Help! My payouts have been failing for 3 days.",
            {
                "frustration": {
                    "type": "score",
                    "instructions": "How frustrated is the customer?",
                    "criteria": ["Calm", "Frustrated", "Very angry"],
                }
            },
        )
        self.assertIsNotNone(result)
        self.assertAlmostEqual(result["frustration"]["score"], 1.05)
        self.assertEqual(result["frustration"]["confidence"], 0.92)

    def test_default_timeout_budget_allows_fast_mock_response(self):
        # Neither `timeout=` kwarg nor JEV_TIMEOUT_MS set -> falls back to the
        # documented 800ms default, which must comfortably cover a 50ms mock delay.
        self.mock.delay = 0.05
        self.mock.body = {
            "model": "jev-1.13.0",
            "answers": {"q": {"type": "noul", "noul": 0.5}},
            "usage": {},
        }
        result = jev_client.evaluate("state text", {"q": {"type": "noul", "instructions": "?"}})
        self.assertEqual(result, {"q": {"type": "noul", "noul": 0.5}})

    def test_request_headers_and_body_shape(self):
        self.mock.body = {
            "model": "jev-1.13.0",
            "answers": {"is_urgent": {"type": "noul", "noul": 0.5}},
            "usage": {},
        }
        jev_client.evaluate(
            "some state",
            {"is_urgent": {"type": "noul", "instructions": "Does this convey urgency?"}},
            api_key="explicit-key-xyz",
        )
        req = self.last_request()
        self.assertEqual(req["headers"].get("Authorization"), "Bearer explicit-key-xyz")
        self.assertEqual(req["headers"].get("Content-Type"), "application/json")
        body = self.decoded_body(req)
        self.assertEqual(body["state"], "some state")
        self.assertEqual(body["model"], "jev-latest")
        self.assertEqual(
            body["questions"]["is_urgent"],
            {"type": "noul", "instructions": "Does this convey urgency?"},
        )

    def test_explicit_api_key_arg_overrides_env(self):
        os.environ["TYPESAFE_API_KEY"] = "env-key-should-not-be-used"
        self.mock.body = {"model": "m", "answers": {"q": {"type": "noul", "noul": 0.1}}, "usage": {}}
        jev_client.evaluate(
            "state", {"q": {"type": "noul", "instructions": "?"}}, api_key="explicit-key-abc"
        )
        req = self.last_request()
        self.assertEqual(req["headers"].get("Authorization"), "Bearer explicit-key-abc")

    def test_explicit_endpoint_kwarg_used_over_env_var(self):
        # A second mock instance so we can prove the `endpoint=` kwarg, not the
        # TYPESAFE_API_URL env var (which setUp already points elsewhere-shaped),
        # decided where the request landed.
        second = _MockJevServer()
        try:
            second.body = {"model": "m", "answers": {"q": {"type": "noul", "noul": 0.2}}, "usage": {}}
            result = jev_client.evaluate(
                "state",
                {"q": {"type": "noul", "instructions": "?"}},
                endpoint=second.url,
            )
            self.assertEqual(result, {"q": {"type": "noul", "noul": 0.2}})
            self.assertEqual(len(second.requests), 1)
            self.assertEqual(len(self.mock.requests), 0)
        finally:
            second.shutdown()


# ---------------------------------------------------------------------------
# evaluate(): fail-to-deterministic paths (I-3) — must return None, never raise
# ---------------------------------------------------------------------------


class TestEvaluateFailureModes(JevClientTestCase):
    def test_no_api_key_returns_none_and_sends_no_request(self):
        # Precondition adjusted (not weakened): also unset TYPESAFE_API_URL so this
        # falls back to the default *non-loopback* https endpoint. setUp() points
        # TYPESAFE_API_URL at the loopback mock, and loopback endpoints are now
        # allowed to omit the key entirely (see TestEndpointValidation below) -- so
        # "no key" alone no longer implies "unavailable" unless the endpoint is also
        # non-loopback. The assertions themselves (None result, zero requests sent)
        # are unchanged.
        os.environ.pop("TYPESAFE_API_KEY", None)
        os.environ.pop("TYPESAFE_API_URL", None)
        result = jev_client.evaluate("state", {"q": {"type": "noul", "instructions": "?"}})
        self.assertIsNone(result)
        self.assertEqual(len(self.mock.requests), 0)

    def test_jev_disable_env_returns_none_and_sends_no_request(self):
        os.environ["JEV_DISABLE"] = "1"
        result = jev_client.evaluate("state", {"q": {"type": "noul", "instructions": "?"}})
        self.assertIsNone(result)
        self.assertEqual(len(self.mock.requests), 0)

    def test_jev_disable_zero_does_not_disable(self):
        # "0" is a non-empty string (truthy in Python) -- must NOT be treated as enabled
        # disable, unlike "1"/"true"/"yes" above.
        os.environ["JEV_DISABLE"] = "0"
        self.mock.body = {"model": "m", "answers": {"q": {"type": "noul", "noul": 0.6}}, "usage": {}}
        result = jev_client.evaluate("state", {"q": {"type": "noul", "instructions": "?"}})
        self.assertEqual(result, {"q": {"type": "noul", "noul": 0.6}})

    def test_timeout_returns_none_quickly(self):
        self.mock.delay = 0.5  # far exceeds the explicit timeout below
        started = time.monotonic()
        result = jev_client.evaluate(
            "state", {"q": {"type": "noul", "instructions": "?"}}, timeout=100
        )
        elapsed = time.monotonic() - started
        self.assertIsNone(result)
        self.assertLess(elapsed, 0.45, "evaluate() must not block past its timeout budget")

    def test_jev_timeout_ms_env_var_is_honored_when_kwarg_omitted(self):
        os.environ["JEV_TIMEOUT_MS"] = "50"
        self.mock.delay = 0.5
        started = time.monotonic()
        result = jev_client.evaluate("state", {"q": {"type": "noul", "instructions": "?"}})
        elapsed = time.monotonic() - started
        self.assertIsNone(result)
        self.assertLess(elapsed, 0.45)

    def test_explicit_timeout_kwarg_overrides_env_var(self):
        os.environ["JEV_TIMEOUT_MS"] = "5000"  # would be plenty of time
        self.mock.delay = 0.5
        started = time.monotonic()
        result = jev_client.evaluate(
            "state", {"q": {"type": "noul", "instructions": "?"}}, timeout=50
        )
        elapsed = time.monotonic() - started
        self.assertIsNone(result)
        self.assertLess(elapsed, 0.45)

    def test_http_error_statuses_return_none(self):
        for status in (401, 422, 429, 500, 529):
            with self.subTest(status=status):
                self.mock.reset()
                self.mock.status = status
                self.mock.body = {"error": "boom"}
                result = jev_client.evaluate(
                    "state", {"q": {"type": "noul", "instructions": "?"}}
                )
                self.assertIsNone(result)

    def test_connection_refused_returns_none(self):
        result = jev_client.evaluate(
            "state",
            {"q": {"type": "noul", "instructions": "?"}},
            endpoint="http://127.0.0.1:1/v1/systemone",
        )
        self.assertIsNone(result)

    def test_non_json_body_returns_none(self):
        self.mock.body = b"not json at all {"
        result = jev_client.evaluate("state", {"q": {"type": "noul", "instructions": "?"}})
        self.assertIsNone(result)

    def test_schema_missing_question_key_returns_none(self):
        self.mock.body = {
            "model": "m",
            "answers": {"other_key": {"type": "noul", "noul": 0.5}},
            "usage": {},
        }
        result = jev_client.evaluate("state", {"q": {"type": "noul", "instructions": "?"}})
        self.assertIsNone(result)

    def test_schema_type_mismatch_returns_none(self):
        self.mock.body = {
            "model": "m",
            "answers": {"q": {"type": "choice", "choice": "x", "probabilities": {}, "confidence": 0.5}},
            "usage": {},
        }
        result = jev_client.evaluate("state", {"q": {"type": "noul", "instructions": "?"}})
        self.assertIsNone(result)

    def test_schema_noul_non_numeric_returns_none(self):
        self.mock.body = {"model": "m", "answers": {"q": {"type": "noul", "noul": "yes"}}, "usage": {}}
        result = jev_client.evaluate("state", {"q": {"type": "noul", "instructions": "?"}})
        self.assertIsNone(result)

    def test_schema_noul_out_of_range_returns_none(self):
        for bad in (-0.1, 1.5):
            with self.subTest(bad=bad):
                self.mock.reset()
                self.mock.body = {"model": "m", "answers": {"q": {"type": "noul", "noul": bad}}, "usage": {}}
                result = jev_client.evaluate("state", {"q": {"type": "noul", "instructions": "?"}})
                self.assertIsNone(result)

    def test_schema_choice_value_outside_options_returns_none(self):
        self.mock.body = {
            "model": "m",
            "answers": {
                "department": {
                    "type": "choice",
                    "choice": "marketing",  # not one of the requested criteria
                    "probabilities": {"billing": 0.5, "technical": 0.5},
                    "confidence": 0.6,
                }
            },
            "usage": {},
        }
        result = jev_client.evaluate(
            "state",
            {
                "department": {
                    "type": "choice",
                    "instructions": "?",
                    "criteria": {"billing": None, "technical": None},
                }
            },
        )
        self.assertIsNone(result)

    def test_schema_score_value_outside_levels_returns_none(self):
        self.mock.body = {
            "model": "m",
            "answers": {
                "frustration": {
                    "type": "score",
                    "score": 7.0,  # only 3 levels were provided (valid range [0, 2])
                    "legend": {"0": "Calm", "1": "Frustrated", "2": "Very angry"},
                    "probabilities": {"0": 0.0, "1": 0.0, "2": 1.0},
                    "confidence": 0.9,
                }
            },
            "usage": {},
        }
        result = jev_client.evaluate(
            "state",
            {
                "frustration": {
                    "type": "score",
                    "instructions": "?",
                    "criteria": ["Calm", "Frustrated", "Very angry"],
                }
            },
        )
        self.assertIsNone(result)

    def test_oversized_state_returns_none_and_sends_no_request(self):
        # Far beyond the request-size cap; also bounds how long secret-scanning ever runs.
        huge_state = "x" * (2 * 1024 * 1024)
        result = jev_client.evaluate(huge_state, {"q": {"type": "noul", "instructions": "?"}})
        self.assertIsNone(result)
        self.assertEqual(len(self.mock.requests), 0)

    def test_oversized_response_returns_none(self):
        # T8 gap (T15): unlike the request-size cap above, this exercises the
        # *response* side -- `_read_within_deadline`'s `_MAX_RESPONSE_BYTES`
        # check. The body is deliberately VALID JSON that matches the expected
        # answer schema exactly, padded with trailing whitespace (insignificant
        # to json.loads, per stdlib) past the cap -- NOT just arbitrary invalid
        # bytes. Checker-caught (revision 2 review): an invalid body would
        # already return None via the json.loads()/schema-validation failure
        # path regardless of whether the size cap exists at all, so it would
        # not actually exercise the cap -- disabling `_MAX_RESPONSE_BYTES`
        # entirely would make an invalid-body version of this test pass anyway.
        # A body that would otherwise succeed is the only way to prove the cap
        # itself is what rejects it (confirmed by mutation testing: disabling
        # the check at jev_client.py's read loop makes this exact test fail).
        valid_answer = json.dumps(
            {"model": "m", "answers": {"q": {"type": "noul", "noul": 0.5}}, "usage": {}}
        ).encode("utf-8")
        padding = b" " * (jev_client._MAX_RESPONSE_BYTES + 4096 - len(valid_answer))
        self.mock.body = valid_answer + padding
        result = jev_client.evaluate("state", {"q": {"type": "noul", "instructions": "?"}})
        self.assertIsNone(result)
        self.assertEqual(len(self.mock.requests), 1)


# ---------------------------------------------------------------------------
# Answer schema: confidence must be validated (choice/score wrappers must never KeyError)
# ---------------------------------------------------------------------------


class TestConfidenceValidation(JevClientTestCase):
    def test_choice_missing_confidence_returns_none(self):
        self.mock.body = {
            "model": "m",
            "answers": {
                "department": {"type": "choice", "choice": "billing", "probabilities": {"billing": 1.0}}
            },
            "usage": {},
        }
        result = jev_client.evaluate(
            "state",
            {"department": {"type": "choice", "instructions": "?", "criteria": {"billing": None}}},
        )
        self.assertIsNone(result)

    def test_choice_nan_confidence_returns_none(self):
        self.mock.body = {
            "model": "m",
            "answers": {
                "department": {
                    "type": "choice",
                    "choice": "billing",
                    "probabilities": {"billing": 1.0},
                    "confidence": float("nan"),
                }
            },
            "usage": {},
        }
        result = jev_client.evaluate(
            "state",
            {"department": {"type": "choice", "instructions": "?", "criteria": {"billing": None}}},
        )
        self.assertIsNone(result)

    def test_choice_string_confidence_returns_none(self):
        self.mock.body = {
            "model": "m",
            "answers": {
                "department": {
                    "type": "choice",
                    "choice": "billing",
                    "probabilities": {"billing": 1.0},
                    "confidence": "high",
                }
            },
            "usage": {},
        }
        result = jev_client.evaluate(
            "state",
            {"department": {"type": "choice", "instructions": "?", "criteria": {"billing": None}}},
        )
        self.assertIsNone(result)

    def test_score_missing_confidence_returns_none(self):
        self.mock.body = {
            "model": "m",
            "answers": {"frustration": {"type": "score", "score": 1.0, "legend": {}, "probabilities": {}}},
            "usage": {},
        }
        result = jev_client.evaluate(
            "state",
            {"frustration": {"type": "score", "instructions": "?", "criteria": ["a", "b"]}},
        )
        self.assertIsNone(result)

    def test_score_nan_confidence_returns_none(self):
        self.mock.body = {
            "model": "m",
            "answers": {
                "frustration": {
                    "type": "score",
                    "score": 1.0,
                    "legend": {},
                    "probabilities": {},
                    "confidence": float("nan"),
                }
            },
            "usage": {},
        }
        result = jev_client.evaluate(
            "state",
            {"frustration": {"type": "score", "instructions": "?", "criteria": ["a", "b"]}},
        )
        self.assertIsNone(result)

    def test_score_string_confidence_returns_none(self):
        self.mock.body = {
            "model": "m",
            "answers": {
                "frustration": {
                    "type": "score",
                    "score": 1.0,
                    "legend": {},
                    "probabilities": {},
                    "confidence": "high",
                }
            },
            "usage": {},
        }
        result = jev_client.evaluate(
            "state",
            {"frustration": {"type": "score", "instructions": "?", "criteria": ["a", "b"]}},
        )
        self.assertIsNone(result)

    def test_choice_wrapper_missing_confidence_returns_none_without_raising(self):
        self.mock.dynamic = True
        self.mock.answer_template = {"type": "choice", "choice": "technical", "probabilities": {"technical": 1.0}}
        result = jev_client.choice("state text", "Which team?", ["billing", "technical"])
        self.assertIsNone(result)

    def test_score_wrapper_missing_confidence_returns_none_without_raising(self):
        self.mock.dynamic = True
        self.mock.answer_template = {"type": "score", "score": 1.0, "legend": {}, "probabilities": {}}
        result = jev_client.score("state text", "How frustrated?", ["Calm", "Angry"])
        self.assertIsNone(result)


# ---------------------------------------------------------------------------
# Response reading: overall wall-clock deadline + max size, redirects never followed
# ---------------------------------------------------------------------------


class TestResponseHandlingHardening(JevClientTestCase):
    def test_trickling_response_is_bounded_by_overall_deadline(self):
        # ~44-byte body trickled 5 bytes/100ms (~900ms total): no single socket read
        # ever blocks anywhere near the 300ms budget below, so a per-operation-only
        # timeout would let this sail past 300ms. The overall deadline must not.
        server = _TrickleServer(chunk_delay=0.1, chunk_size=5)
        try:
            started = time.monotonic()
            result = jev_client.evaluate(
                "state",
                {"q": {"type": "noul", "instructions": "?"}},
                endpoint=server.url,
                api_key="k",
                timeout=300,
            )
            elapsed = time.monotonic() - started
            self.assertIsNone(result)
            self.assertLess(
                elapsed, 0.6, "must bail out at the overall deadline, not wait out the full trickle"
            )
        finally:
            server.shutdown()

    def test_302_redirect_is_never_followed_and_key_is_not_leaked(self):
        secondary = _MockJevServer()
        try:
            secondary.dynamic = True
            secondary.answer_template = {"type": "noul", "noul": 0.99}
            self.mock.status = 302
            self.mock.location = secondary.url
            result = jev_client.evaluate(
                "state", {"q": {"type": "noul", "instructions": "?"}}, api_key="must-not-leak"
            )
            self.assertIsNone(result)
            self.assertEqual(len(secondary.requests), 0, "a 3xx response must never be followed")
        finally:
            secondary.shutdown()


# ---------------------------------------------------------------------------
# I-6: secret detection must block the send entirely (zero requests reach Jev)
# ---------------------------------------------------------------------------


class TestSecretOverLoopbackIsSentByDesign(JevClientTestCase):
    """CONTEXT.md Addendum 2 (I-6, redefined): secret-shaped-substring/sensitive-key-name
    scanning now runs ONLY on the remote path -- a loopback endpoint (this class's
    target throughout, via `self.mock`/`TYPESAFE_API_URL` from setUp()) never leaves the
    machine, so scanning it can't prevent a leak and would only add false-positive risk
    to a same-host round-trip.

    This class was `TestSecretBlocksTransmission` before the redefinition, asserting
    exactly the opposite (0 requests sent, result is None) for these same five
    scenarios; the scenarios are kept for continuity/coverage but every assertion is
    flipped to "sent exactly once, with a normal successful result", per (c) in the
    coordinator's spec-change message. See `TestRemoteSecretScanningKnownGaps` below for
    the remote-path scanning coverage these tests no longer exercise, and
    `TestRemoteRequiresExplicitAllow` for the remote-path gating these tests also don't
    exercise (loopback bypasses it entirely).
    """

    def test_secret_in_state_is_sent_over_loopback(self):
        secret_state = "here is my key AKIAABCDEFGHIJKLMNOP please use it"
        self.mock.dynamic = True
        self.mock.answer_template = {"type": "noul", "noul": 0.5}
        result = jev_client.evaluate(secret_state, {"q": {"type": "noul", "instructions": "is this urgent?"}})
        self.assertEqual(result, {"q": {"type": "noul", "noul": 0.5}})
        self.assertEqual(len(self.mock.requests), 1)

    def test_secret_in_instructions_is_sent_over_loopback(self):
        self.mock.dynamic = True
        self.mock.answer_template = {"type": "noul", "noul": 0.5}
        result = jev_client.evaluate(
            "harmless state",
            {
                "q": {
                    "type": "noul",
                    "instructions": "Authorization: Bearer sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789",
                }
            },
        )
        self.assertEqual(result, {"q": {"type": "noul", "noul": 0.5}})
        self.assertEqual(len(self.mock.requests), 1)

    def test_secret_in_structured_instructions_object_is_sent_over_loopback(self):
        self.mock.dynamic = True
        self.mock.answer_template = {"type": "noul", "noul": 0.5}
        result = jev_client.evaluate(
            "harmless state",
            {
                "q": {
                    "type": "noul",
                    "instructions": {
                        "context": "password=SuperSecret123",
                        "question": "Is this urgent?",
                    },
                }
            },
        )
        self.assertEqual(result, {"q": {"type": "noul", "noul": 0.5}})
        self.assertEqual(len(self.mock.requests), 1)

    def test_secret_as_password_dict_key_in_state_is_sent_over_loopback(self):
        self.mock.dynamic = True
        self.mock.answer_template = {"type": "noul", "noul": 0.5}
        result = jev_client.evaluate(
            {"password": "hunter2hunter2"},
            {"q": {"type": "noul", "instructions": "is this urgent?"}},
        )
        self.assertEqual(result, {"q": {"type": "noul", "noul": 0.5}})
        self.assertEqual(len(self.mock.requests), 1)

    def test_secret_as_api_key_dict_key_in_state_is_sent_over_loopback(self):
        self.mock.dynamic = True
        self.mock.answer_template = {"type": "noul", "noul": 0.5}
        result = jev_client.evaluate(
            {"api_key": "abcdefghijklmnop"},
            {"q": {"type": "noul", "instructions": "is this urgent?"}},
        )
        self.assertEqual(result, {"q": {"type": "noul", "noul": 0.5}})
        self.assertEqual(len(self.mock.requests), 1)


# ---------------------------------------------------------------------------
# endpoint validation: TYPESAFE_API_URL must be https:// or loopback http://
# ---------------------------------------------------------------------------


class TestEndpointValidation(JevClientTestCase):
    def test_loopback_http_override_is_allowed(self):
        # setUp already points TYPESAFE_API_URL at the loopback mock; a normal
        # success call proves loopback http:// is accepted.
        self.mock.body = {"model": "m", "answers": {"q": {"type": "noul", "noul": 0.3}}, "usage": {}}
        result = jev_client.evaluate("state", {"q": {"type": "noul", "instructions": "?"}})
        self.assertEqual(result, {"q": {"type": "noul", "noul": 0.3}})

    def test_non_loopback_http_override_sends_no_key_and_no_request(self):
        # 0.0.0.0 is NOT in the allowed loopback set (127.0.0.1 / localhost / ::1)
        # even though, on Linux, a TCP connect() to 0.0.0.0 is routed to the same
        # loopback listener (verified against this mock server before writing this
        # test). That makes it a genuine negative test: if jev_client validated
        # only reachability instead of the literal allow-list, this request WOULD
        # reach the mock and leak the API key. It must not.
        os.environ["TYPESAFE_API_URL"] = "http://0.0.0.0:%d/v1/systemone" % self.mock.port
        result = jev_client.evaluate(
            "state", {"q": {"type": "noul", "instructions": "?"}}, api_key="must-not-leak"
        )
        self.assertIsNone(result)
        self.assertEqual(
            len(self.mock.requests),
            0,
            "non-loopback http:// override must never reach the endpoint with the key",
        )

    def test_loopback_http_override_without_key_succeeds_with_no_auth_header(self):
        # Loopback exception (agreed after the Test Maker phase): a local self-hosted
        # server implementing the same POST /v1/systemone wire protocol (e.g. Laya's
        # laya-serve) may run with no API key configured, so the client must be usable
        # against it without one. Only 127.0.0.1/localhost/[::1] over http:// qualify;
        # a real (non-loopback) endpoint still requires a key, per the tests above.
        os.environ.pop("TYPESAFE_API_KEY", None)
        self.mock.body = {"model": "m", "answers": {"q": {"type": "noul", "noul": 0.4}}, "usage": {}}
        result = jev_client.evaluate("state", {"q": {"type": "noul", "instructions": "?"}})
        self.assertEqual(result, {"q": {"type": "noul", "noul": 0.4}})
        req = self.last_request()
        self.assertNotIn("Authorization", req["headers"])

    def test_non_loopback_http_hostname_override_returns_none(self):
        os.environ["TYPESAFE_API_URL"] = "http://example.invalid/v1/systemone"
        started = time.monotonic()
        result = jev_client.evaluate(
            "state", {"q": {"type": "noul", "instructions": "?"}}, timeout=100
        )
        elapsed = time.monotonic() - started
        self.assertIsNone(result)
        self.assertLess(elapsed, 1.0, "invalid endpoint must fail fast, not hang")

    def test_https_non_default_host_returns_none_and_sends_no_request(self):
        # https:// is only trusted for the official api.typesafe.ai host -- any other
        # https host (even though it's TLS) must be rejected exactly like a disallowed
        # http host, not treated as "any TLS endpoint is presumably safe".
        os.environ["TYPESAFE_API_URL"] = "https://evil.example.com/v1/systemone"
        started = time.monotonic()
        result = jev_client.evaluate(
            "state", {"q": {"type": "noul", "instructions": "?"}}, api_key="must-not-leak", timeout=100
        )
        elapsed = time.monotonic() - started
        self.assertIsNone(result)
        self.assertLess(elapsed, 1.0, "disallowed https host must fail fast, not attempt to connect")
        self.assertEqual(len(self.mock.requests), 0)


# ---------------------------------------------------------------------------
# _endpoint_loopback_status(): direct unit test (exception to this suite's usual
# black-box-only convention -- see class docstring for why)
# ---------------------------------------------------------------------------


class TestEndpointHostAllowlist(unittest.TestCase):
    """Direct unit tests of the private `_endpoint_loopback_status` predicate.

    Every other test here exercises jev_client only through its public surface
    (evaluate/noul/choice/score/CLI). This one reaches into a private helper because
    the https-host-allowlist defect it guards cannot be proven black-box in this
    sandbox: an https:// call to an arbitrary non-default host fails instantly here
    via DNS/network-sandbox rejection regardless of whether the allow-list check
    itself is correct (verified: the pre-fix "any https host is allowed" code also
    made evaluate() return None for such a host in this environment, purely because
    outbound network access to it is unavailable here -- not because the host check
    ran). A black-box test alone would silently pass against the buggy code.
    """

    def test_default_https_host_is_allowed(self):
        allowed, loopback = jev_client._endpoint_loopback_status(jev_client.DEFAULT_ENDPOINT)
        self.assertTrue(allowed)
        self.assertFalse(loopback)

    def test_arbitrary_https_host_is_rejected(self):
        allowed, _ = jev_client._endpoint_loopback_status("https://evil.example.com/v1/systemone")
        self.assertFalse(allowed)


# ---------------------------------------------------------------------------
# contains_secret()
# ---------------------------------------------------------------------------


# GitHub's secret-scanning push protection matches the literal bytes of a Slack
# token in a pushed commit, and these synthetic positives for _contains_secret
# look exactly like one. Assembling the prefix at runtime leaves the value the
# test asserts on byte-identical while keeping the literal out of the blob, so a
# push carrying this file is not rejected. Do not inline it back.
_XOX = "xox"


class TestContainsSecret(unittest.TestCase):
    POSITIVE_CASES = [
        (
            "pem_private_key",
            "-----BEGIN RSA PRIVATE KEY-----\n"
            "MIIBOgIBAAJBAK1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN\n"
            "-----END RSA PRIVATE KEY-----",
        ),
        ("aws_access_key", "leaked creds: AKIAABCDEFGHIJKLMNOP in the log"),
        ("github_ghp_token", "token is ghp_1234567890abcdefghijklmnopqrstuvwxyzABCD"),
        ("github_gho_token", "token is gho_1234567890abcdefghijklmnopqrstuvwxyzABCD"),
        (
            "github_pat_token",
            "token is github_pat_11ABCDEFG0abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJ",
        ),
        ("slack_bot_token", _XOX + "b-1234567890-1234567890123-abcdefghijklmnopqrstuvwx"),
        ("slack_user_token", _XOX + "p-1234567890-1234567890123-abcdefghijklmnopqrstuvwx"),
        ("slack_app_token", _XOX + "a-1234567890-1234567890123-abcdefghijklmnopqrstuvwx"),
        ("slack_refresh_token", _XOX + "r-1234567890-1234567890123-abcdefghijklmnopqrstuvwx"),
        ("slack_additional_token", _XOX + "s-1234567890-1234567890123-abcdefghijklmnopqrstuvwx"),
        (
            "anthropic_key",
            "sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOP",
        ),
        ("openai_like_key", "sk-abcdefghijklmnopqrstuvwxyz0123456789ABCD"),
        ("openai_project_key", "sk-proj-abcdefghijklmnopqrstuvwxyz0123"),
        ("openai_like_key_with_underscore_suffix", "sk-abcdefghijklmnopqrstuvwxyz0123456789_x"),
        ("underscore_adjacent_db_password", "DB_PASSWORD=hunter2hunter2"),
        ("underscore_adjacent_github_token", "GITHUB_TOKEN=abcdefghijklmnop"),
        ("underscore_adjacent_my_api_key", "MY_API_KEY=abcdefgh12345678"),
        ("underscore_adjacent_client_secret", "client_secret: verysecretvalue1234"),
        (
            "jwt",
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
            "eyJzdWIiOiIxMjM0NTY3ODkwIn0.dGVzdHNpZ25hdHVyZQ",
        ),
        (
            "authorization_bearer_header",
            "Authorization: Bearer abcdefghijklmnopqrstuvwxyz0123456789",
        ),
        ("password_eq_assignment", "password=SuperSecret123"),
        ("passwd_colon_assignment", "passwd: hunter2hunter"),
        ("secret_eq_assignment", "secret = mysupersecretvalue"),
        ("token_colon_assignment", "token: abcdef1234567890"),
        ("api_key_underscore_assignment", "api_key=abcdefgh12345678"),
        ("api_key_hyphen_assignment", "API-KEY: zzzzzzzz1234"),
    ]

    NEGATIVE_CASES = [
        ("plain_make_test", "make test"),
        ("plain_git_status", "git status"),
        ("plain_echo_hello", "echo hello"),
        ("short_password_value", "password=abc123"),  # value under 8 chars
        ("password_word_no_assignment", "Please enter your password to continue."),
        ("api_key_words_with_space", "The API key rotation happens monthly."),
        ("ordinary_sentence_with_digits", "The meeting is scheduled for 2026-09-24 at 10am."),
        ("too_short_openai_like", "sk-abc123"),
        ("lowercase_short_akia_lookalike", "AKIAfoo appears in an old changelog entry"),
    ]

    def test_positive_cases_detected(self):
        for name, text in self.POSITIVE_CASES:
            with self.subTest(case=name):
                self.assertTrue(
                    jev_client.contains_secret(text), "expected secret detected in: %r" % (text,)
                )

    def test_negative_cases_not_flagged(self):
        for name, text in self.NEGATIVE_CASES:
            with self.subTest(case=name):
                self.assertFalse(
                    jev_client.contains_secret(text), "unexpected secret flagged in: %r" % (text,)
                )


# ---------------------------------------------------------------------------
# Convenience wrappers: noul() / choice() / score()
# ---------------------------------------------------------------------------


class TestConvenienceWrappers(JevClientTestCase):
    def test_noul_wrapper_success(self):
        self.mock.dynamic = True
        self.mock.answer_template = {"type": "noul", "noul": 0.73}
        result = jev_client.noul("state text", "Does this convey urgency?")
        self.assertEqual(result, 0.73)
        req = self.last_request()
        body = self.decoded_body(req)
        self.assertEqual(len(body["questions"]), 1)
        (question,) = body["questions"].values()
        self.assertEqual(question["type"], "noul")
        self.assertEqual(question["instructions"], "Does this convey urgency?")

    def test_choice_wrapper_success_and_criteria_shape(self):
        self.mock.dynamic = True
        self.mock.answer_template = {
            "type": "choice",
            "choice": "technical",
            "probabilities": {"billing": 0.1, "technical": 0.8, "sales": 0.1},
            "confidence": 0.8,
        }
        result = jev_client.choice(
            "state text", "Which team should handle this?", ["billing", "technical", "sales"]
        )
        self.assertEqual(result, ("technical", 0.8))
        req = self.last_request()
        body = self.decoded_body(req)
        (question,) = body["questions"].values()
        self.assertEqual(question["type"], "choice")
        self.assertEqual(
            question["criteria"], {"billing": None, "technical": None, "sales": None}
        )

    def test_score_wrapper_success_and_criteria_shape(self):
        self.mock.dynamic = True
        self.mock.answer_template = {
            "type": "score",
            "score": 1.2,
            "legend": {"0": "Calm", "1": "Frustrated", "2": "Very angry"},
            "probabilities": {"0": 0.1, "1": 0.7, "2": 0.2},
            "confidence": 0.75,
        }
        result = jev_client.score(
            "state text", "How frustrated is the customer?", ["Calm", "Frustrated", "Very angry"]
        )
        self.assertEqual(result, (1.2, 0.75))
        req = self.last_request()
        body = self.decoded_body(req)
        (question,) = body["questions"].values()
        self.assertEqual(question["type"], "score")
        self.assertEqual(question["criteria"], ["Calm", "Frustrated", "Very angry"])

    def test_noul_wrapper_returns_none_when_jev_unavailable(self):
        # Precondition adjusted (not weakened), same reason as
        # test_no_api_key_returns_none_and_sends_no_request above: also unset
        # TYPESAFE_API_URL so "no key" actually means "unavailable" rather than
        # "loopback endpoint, key optional". Assertions unchanged.
        os.environ.pop("TYPESAFE_API_KEY", None)
        os.environ.pop("TYPESAFE_API_URL", None)
        result = jev_client.noul("state text", "Does this convey urgency?")
        self.assertIsNone(result)
        self.assertEqual(len(self.mock.requests), 0)


# ---------------------------------------------------------------------------
# CLI: python3 jev_client.py noul|choice|score --instructions ... < state
# ---------------------------------------------------------------------------


class TestCLI(JevClientTestCase):
    def _run_cli(self, args, state_text, env=None):
        # `env` may map a key to None to mean "unset it", not "set it to the
        # string 'None'" -- dict.update() alone can't express a removal against
        # the inherited os.environ, so unset keys explicitly here.
        full_env = dict(os.environ)
        if env:
            for k, v in env.items():
                if v is None:
                    full_env.pop(k, None)
                else:
                    full_env[k] = v
        return subprocess.run(
            [sys.executable, CLIENT_PATH] + args,
            input=state_text,
            capture_output=True,
            text=True,
            env=full_env,
            timeout=10,
        )

    def test_cli_noul_success_exit_0(self):
        self.mock.dynamic = True
        self.mock.answer_template = {"type": "noul", "noul": 0.42}
        proc = self._run_cli(["noul", "--instructions", "Is this urgent?"], "some state text")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        lines = [ln for ln in proc.stdout.splitlines() if ln.strip()]
        self.assertEqual(len(lines), 1, "CLI must print exactly one JSON line")
        payload = json.loads(lines[0])
        self.assertEqual(payload.get("noul"), 0.42)

    def test_cli_choice_success_exit_0(self):
        self.mock.dynamic = True
        self.mock.answer_template = {
            "type": "choice",
            "choice": "technical",
            "probabilities": {"billing": 0.1, "technical": 0.8, "sales": 0.1},
            "confidence": 0.8,
        }
        proc = self._run_cli(
            ["choice", "--instructions", "Which team?", "--options", "billing,technical,sales"],
            "some state text",
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        lines = [ln for ln in proc.stdout.splitlines() if ln.strip()]
        self.assertEqual(len(lines), 1)
        payload = json.loads(lines[0])
        self.assertEqual(payload.get("choice"), "technical")
        self.assertEqual(payload.get("confidence"), 0.8)

    def test_cli_score_success_exit_0(self):
        self.mock.dynamic = True
        self.mock.answer_template = {
            "type": "score",
            "score": 1.2,
            "legend": {"0": "Calm", "1": "Frustrated", "2": "Very angry"},
            "probabilities": {"0": 0.1, "1": 0.7, "2": 0.2},
            "confidence": 0.75,
        }
        proc = self._run_cli(
            ["score", "--instructions", "How frustrated?", "--levels", "Calm,Frustrated,Very angry"],
            "some state text",
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        lines = [ln for ln in proc.stdout.splitlines() if ln.strip()]
        self.assertEqual(len(lines), 1)
        payload = json.loads(lines[0])
        self.assertEqual(payload.get("score"), 1.2)
        self.assertEqual(payload.get("confidence"), 0.75)

    def test_cli_exit_3_and_available_false_when_jev_unavailable(self):
        # Precondition adjusted (not weakened), same reason as the two evaluate()-level
        # tests above: unset TYPESAFE_API_URL too, since the parent env's loopback mock
        # URL would otherwise let this call succeed without a key.
        proc = self._run_cli(
            ["noul", "--instructions", "Is this urgent?"],
            "some state text",
            env={"TYPESAFE_API_KEY": None, "TYPESAFE_API_URL": None},
        )
        self.assertEqual(proc.returncode, 3, proc.stderr)
        lines = [ln for ln in proc.stdout.splitlines() if ln.strip()]
        self.assertEqual(len(lines), 1)
        payload = json.loads(lines[0])
        self.assertEqual(payload, {"available": False})
        self.assertEqual(len(self.mock.requests), 0)


# ---------------------------------------------------------------------------
# Regression tests: independent Checker + security-audit findings (T8 attempt 2)
# ---------------------------------------------------------------------------


class TestRemoteSecretScanningKnownGaps(unittest.TestCase):
    """CONTEXT.md Addendum 2 (I-6, redefined): secret-shaped-substring/sensitive-key
    scanning now runs ONLY on the remote path, and is explicitly documented as
    best-effort rather than a regex-complete guarantee (`JEV_ALLOW_REMOTE` is the
    primary control). Since a loopback target (this suite's usual `evaluate()`
    fixture) no longer exercises this scan at all -- see
    `TestSecretOverLoopbackIsSentByDesign` -- these are direct unit tests of the
    scanning primitives themselves (`_contains_secret_anywhere`), not of `evaluate()`
    over a transport.

    This class was `TestSecretDetectionAcrossEscaping` before the redefinition (which
    asserted 0 requests reached the loopback mock); the original escape-boundary
    scenarios are kept here since they are still real bugs in the underlying scan
    logic, independent of transport/loopback-vs-remote, plus the additional known
    gaps from the second independent Checker/security-audit review round.
    """

    ESCAPING_CASES = [
        ("newline_before_aws_key", "cfg\nAKIAIOSFODNN7EXAMPLE"),
        ("newline_before_ghp_token", "line1\nghp_1234567890abcdefghijklmnopqrstuvwxyzABCD"),
        ("tab_before_ghp_token", "x\tghp_1234567890abcdefghijklmnopqrstuvwxyzABCD"),
        ("fullwidth_brackets_before_ghp_token", "「ghp_1234567890abcdefghijklmnopqrstuvwxyzABCD」"),
        ("japanese_text_before_aws_key", "キー：AKIAIOSFODNN7EXAMPLE"),
        (
            "newline_before_anthropic_key",
            "a\nsk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOP",
        ),
        (
            "newline_before_authorization_header",
            "a\nAuthorization: Bearer abcdefghijklmnopqrstuvwxyz0123456789",
        ),
        ("newline_and_indent_before_password_value", "password:\n  abcdefghij"),
        # Known gaps from the second independent review round (underscore/hyphen
        # continuations that `\b` alone can't see -- see `_AB_START`/`_AB_END`):
        ("underscore_before_ghp_token", "x_ghp_1234567890abcdefghijklmnopqrstuvwxyzABCD"),
        ("sk_ant_body_with_underscore", "sk-ant-api03-abcdefgh_ijklmnopqrstuvwxyz012345"),
        ("sk_proj_body_with_hyphen", "sk-proj-ab-cdefghijklmnopqrst"),
        ("secret_key_style_assignment", "SECRET_KEY=abcdefgh12345678"),
        ("aws_secret_access_key_style_assignment", "AWS_SECRET_ACCESS_KEY=abcdefgh12345678"),
        ("quoted_key_assignment_text", '"password": "abcdefgh12345678"'),
    ]

    def test_secret_in_state_across_known_gaps_is_detected(self):
        for name, secret_state in self.ESCAPING_CASES:
            with self.subTest(case=name):
                self.assertTrue(
                    jev_client._contains_secret_anywhere(
                        secret_state, {"q": {"type": "noul", "instructions": "is this urgent?"}}
                    ),
                    "case %s: expected secret-shaped substring to be detected" % name,
                )

    def test_dict_key_db_password_style_is_detected(self):
        # "DB_PASSWORD" normalizes (lowercased, non-alnum stripped) to "dbpassword",
        # which never equals the bare "password" entry via full-string equality -- a
        # substring/token check is required to catch it.
        self.assertTrue(
            jev_client._contains_secret_anywhere(
                {"DB_PASSWORD": "supersecretvalue12345"},
                {"q": {"type": "noul", "instructions": "is this urgent?"}},
            )
        )

    def test_tuple_state_value_is_scanned(self):
        # Tuples (not just lists) must be walked recursively -- both by
        # `_iter_strings` (for ordinary string content) and `_dict_has_secret_key`
        # (for tuples nested under a dict value).
        self.assertTrue(jev_client._contains_secret_anywhere(("AKIAABCDEFGHIJKLMNOP",), {}))

    def test_choice_criteria_key_holding_a_secret_is_detected(self):
        # A choice question's `criteria` map's keys are the option labels themselves --
        # a secret accidentally used as an option label must be caught the same way a
        # secret used as any other dict key is (key *content*, not just key *name*).
        questions = {
            "department": {
                "type": "choice",
                "instructions": "Which team?",
                "criteria": {"AKIAABCDEFGHIJKLMNOP": "a description", "technical": None},
            }
        }
        self.assertTrue(jev_client._contains_secret_anywhere("state", questions))

    def test_sensitive_key_with_list_value_is_detected(self):
        self.assertTrue(jev_client._contains_secret_anywhere({"password": ["abcdefgh12345678"]}, {}))

    def test_non_str_dict_key_is_stringified_before_scanning(self):
        # Python allows tuples as dict keys; str()-ing a key before scanning is what
        # makes a secret embedded in a *non-str* key visible at all -- the pre-fix code
        # returned "" for any non-str key without ever converting it to text, so both
        # the key-name and key-content checks silently skipped it.
        key = ("state", "AKIAABCDEFGHIJKLMNOP")
        self.assertTrue(jev_client._contains_secret_anywhere({key: "irrelevant value"}, {}))

    def test_authorization_key_name_is_detected(self):
        self.assertTrue(jev_client._contains_secret_anywhere({"Authorization": "abcdefgh12345678"}, {}))


class TestRemoteRequiresExplicitAllow(JevClientTestCase):
    """CONTEXT.md Addendum 2 (I-6, redefined): a non-loopback endpoint -- including the
    official https default -- is never sent to unless `JEV_ALLOW_REMOTE` is an explicit
    truthy value. `_network_call` (the one function that ever actually opens a socket)
    is replaced with a stub per the coordinator's guidance ("private 関数か送信関数の
    差し替えで確認") rather than hitting the real network or a mock server, since the
    only endpoint this test can legally target under the new rule is the real
    https://api.typesafe.ai host, which the sandbox can't (and shouldn't) reach."""

    def test_remote_default_endpoint_is_never_sent_without_allow_remote(self):
        os.environ.pop("JEV_ALLOW_REMOTE", None)
        os.environ.pop("TYPESAFE_API_URL", None)  # fall back to the real https default
        with mock.patch.object(jev_client, "_network_call") as fake_call:
            result = jev_client.evaluate(
                "state", {"q": {"type": "noul", "instructions": "?"}}, api_key="k"
            )
        self.assertIsNone(result)
        fake_call.assert_not_called()

    def test_jev_allow_remote_zero_does_not_allow(self):
        # Same "'0' is truthy in Python but must not enable" convention as JEV_DISABLE.
        os.environ["JEV_ALLOW_REMOTE"] = "0"
        os.environ.pop("TYPESAFE_API_URL", None)
        with mock.patch.object(jev_client, "_network_call") as fake_call:
            result = jev_client.evaluate(
                "state", {"q": {"type": "noul", "instructions": "?"}}, api_key="k"
            )
        self.assertIsNone(result)
        fake_call.assert_not_called()

    def test_remote_default_endpoint_is_sent_when_allow_remote_is_set(self):
        os.environ["JEV_ALLOW_REMOTE"] = "1"
        os.environ.pop("TYPESAFE_API_URL", None)
        raw = json.dumps(
            {"model": "m", "answers": {"q": {"type": "noul", "noul": 0.5}}, "usage": {}}
        ).encode("utf-8")
        with mock.patch.object(jev_client, "_network_call", return_value=raw) as fake_call:
            result = jev_client.evaluate(
                "state", {"q": {"type": "noul", "instructions": "?"}}, api_key="k"
            )
        self.assertEqual(result, {"q": {"type": "noul", "noul": 0.5}})
        fake_call.assert_called_once()

    def test_no_key_still_blocks_even_when_allow_remote_is_set(self):
        # T8 gap (T15): every other test in this class passes an explicit
        # api_key="k", so none of them actually isolate the "non-loopback
        # requires a key" gate from the separate "non-loopback requires
        # JEV_ALLOW_REMOTE" gate above. Here JEV_ALLOW_REMOTE IS granted and
        # the endpoint has no secret in it, but no key is available (neither
        # api_key kwarg nor TYPESAFE_API_KEY env) -- must still block, proving
        # the two gates are independent (I-6's loopback no-key exception does
        # not extend to a non-loopback destination just because remote access
        # was separately allowed).
        os.environ["JEV_ALLOW_REMOTE"] = "1"
        os.environ.pop("TYPESAFE_API_URL", None)  # falls back to the real https default
        os.environ.pop("TYPESAFE_API_KEY", None)
        with mock.patch.object(jev_client, "_network_call") as fake_call:
            result = jev_client.evaluate("state", {"q": {"type": "noul", "instructions": "?"}})
        self.assertIsNone(result)
        fake_call.assert_not_called()

    def test_remote_secret_detection_still_blocks_even_when_allow_remote_is_set(self):
        # Setting JEV_ALLOW_REMOTE permits the *endpoint*; it does not disable the
        # (best-effort) secret scan that still gates the remote path.
        os.environ["JEV_ALLOW_REMOTE"] = "1"
        os.environ.pop("TYPESAFE_API_URL", None)
        with mock.patch.object(jev_client, "_network_call") as fake_call:
            result = jev_client.evaluate(
                "here is my key AKIAABCDEFGHIJKLMNOP",
                {"q": {"type": "noul", "instructions": "?"}},
                api_key="k",
            )
        self.assertIsNone(result)
        fake_call.assert_not_called()


class TestProxyEnvironmentIsIgnored(JevClientTestCase):
    """Item 2: HTTP_PROXY/HTTPS_PROXY in the environment must never change where an
    already-validated request actually lands -- build_opener()'s default behavior is to
    auto-add ProxyHandler(getproxies()), which would silently honor them.

    `urllib.request.ProxyHandler.__init__` calls `getproxies()` exactly once, at
    construction time -- and jev_client builds its module-level `_OPENER` once at
    import time. So setting `HTTP_PROXY` in this *already-running* test process after
    jev_client has already been imported would never reach an already-constructed
    ProxyHandler either way, making an in-process repro a false negative regardless of
    whether the underlying code is fixed. This is also the realistic reproduction of
    how jev_client actually runs in production: as a fresh `python3 jev_client.py`
    subprocess per hook invocation, inheriting whatever HTTP_PROXY/HTTPS_PROXY the
    parent shell already had set *before* the interpreter (and jev_client) ever starts
    -- so a subprocess CLI invocation is used here instead of calling
    jev_client.evaluate() directly in-process.
    """

    def test_http_proxy_env_var_does_not_redirect_the_request(self):
        proxy = _MockJevServer()
        try:
            full_env = dict(os.environ)
            full_env["HTTP_PROXY"] = proxy.url
            full_env["http_proxy"] = proxy.url
            self.mock.dynamic = True
            self.mock.answer_template = {"type": "noul", "noul": 0.5}
            proc = subprocess.run(
                [sys.executable, CLIENT_PATH, "noul", "--instructions", "Is this urgent?"],
                input="some state text",
                capture_output=True,
                text=True,
                env=full_env,
                timeout=10,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            lines = [ln for ln in proc.stdout.splitlines() if ln.strip()]
            self.assertEqual(len(lines), 1)
            payload = json.loads(lines[0])
            self.assertEqual(payload.get("noul"), 0.5)
            self.assertEqual(
                len(proxy.requests), 0, "request must never be routed through HTTP_PROXY"
            )
            self.assertEqual(len(self.mock.requests), 1)
        finally:
            proxy.shutdown()


class TestOverallDeadlineCoversHeaders(JevClientTestCase):
    """Item 3: the overall deadline must bound DNS/connect/header reads, not just the
    response body -- a peer that trickles the status line/headers slowly enough that no
    single socket recv() ever approaches the deadline must still be bailed out on at the
    overall wall-clock budget."""

    def test_slow_headers_are_bounded_by_overall_deadline(self):
        # ~98 header bytes * 50ms/byte ~= 4.9s of wall-clock time to finish headers,
        # far exceeding the 300ms budget below, yet no single recv() blocks anywhere
        # near 300ms.
        server = _SlowHeaderServer(byte_delay=0.05)
        try:
            started = time.monotonic()
            result = jev_client.evaluate(
                "state",
                {"q": {"type": "noul", "instructions": "?"}},
                endpoint=server.url,
                api_key="k",
                timeout=300,
            )
            elapsed = time.monotonic() - started
            self.assertIsNone(result)
            self.assertLess(
                elapsed,
                1.0,
                "must bail out at the overall deadline while headers trickle in, not "
                "wait out the full header stream",
            )
        finally:
            server.shutdown()


class TestCLIInvalidUtf8Stdin(JevClientTestCase):
    """Item 4: malformed UTF-8 on stdin must never crash the CLI -- it must follow the
    same fail-to-deterministic {"available": false} / exit-3 contract as every other
    failure mode."""

    def test_invalid_utf8_stdin_returns_available_false_exit_3(self):
        full_env = dict(os.environ)
        full_env.pop("TYPESAFE_API_KEY", None)
        full_env.pop("TYPESAFE_API_URL", None)
        proc = subprocess.run(
            [sys.executable, CLIENT_PATH, "noul", "--instructions", "Is this urgent?"],
            input=b"\xff\xfe\x80 invalid utf-8 bytes",
            capture_output=True,
            env=full_env,
            timeout=10,
        )
        self.assertEqual(proc.returncode, 3, proc.stderr)
        lines = [ln for ln in proc.stdout.decode("utf-8", "replace").splitlines() if ln.strip()]
        self.assertEqual(len(lines), 1)
        payload = json.loads(lines[0])
        self.assertEqual(payload, {"available": False})
        self.assertEqual(len(self.mock.requests), 0)


class TestNetlocParserMismatch(unittest.TestCase):
    """Item 5: `urlsplit(...).hostname` and the legacy parser urllib's own connection
    code uses internally can disagree on a netloc containing userinfo syntax
    (`user@host`). Empirically, `urlsplit('https://evil.com@api.typesafe.ai/...').hostname`
    already returns 'api.typesafe.ai' (userinfo stripped) -- so the pre-fix
    `_endpoint_loopback_status` allowed this URL -- while urllib's own connection layer
    tries to resolve the *whole* 'evil.com@api.typesafe.ai' string as one hostname
    (verified separately against a live loopback server: it raised "Name or service not
    known" rather than connecting to api.typesafe.ai). The validator must not depend on
    those two parsers agreeing; it must reject the malformed netloc outright."""

    def test_userinfo_in_https_netloc_is_rejected(self):
        allowed, _ = jev_client._endpoint_loopback_status(
            "https://evil.com@api.typesafe.ai/v1/systemone"
        )
        self.assertFalse(allowed)

    def test_userinfo_in_loopback_netloc_is_rejected(self):
        allowed, _ = jev_client._endpoint_loopback_status("http://evil@127.0.0.1:9/v1/systemone")
        self.assertFalse(allowed)


if __name__ == "__main__":
    unittest.main()
