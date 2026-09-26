#!/usr/bin/env python3
"""
test_latency.py - latency A/B for POST /evaluate (Step 21).

The question: is the ~780ms Postgres fetch seen against Neon caused by WAN/TLS/pooler
(then RDS in the same VPC collapses it) or by SQLAlchemy session handling (then it stays)?

Measures two paths separately, using distinct flag names so the cache state is known:
  MISS  - first evaluation of a flag: Redis miss -> Postgres fetch -> cache fill
  HIT   - repeat evaluation inside the cache TTL (10s): served from Redis
plus GET /health for a no-DB-work baseline (it does hit the DB with a ping).

Zero dependencies (stdlib only) so it runs anywhere:

  From the laptop, through the ALB (includes internet round trip to the ALB):
      ./test_latency.py                       # ALB hostname read via kubectl
      BASE_URL=http://<alb-dns> ./test_latency.py

  Inside the cluster (server-side numbers only; removes laptop <-> ALB latency):
      kubectl exec -i -n feature-flag-dev deploy/feature-flag-api -- \
          env BASE_URL=http://localhost:8000 python - < test_latency.py

JWT secret: taken from $JWT_SECRET_KEY (set inside the pod), otherwise read from Secrets
Manager. It is never printed.
"""
import base64
import hashlib
import hmac
import json
import os
import statistics
import subprocess
import sys
import time
import urllib.request

FLAGS = int(os.environ.get("FLAGS", "40"))   # distinct flags == number of cache-miss samples
HIT_ROUNDS = int(os.environ.get("HIT_ROUNDS", "5"))
RUN_ID = str(int(time.time()))[-6:]          # keeps flag names unique across reruns


def base_url():
    if os.environ.get("BASE_URL"):
        return os.environ["BASE_URL"].rstrip("/")
    host = subprocess.check_output([
        "kubectl", "get", "ingress", "feature-flag-api", "-n", "feature-flag-dev",
        "-o", "jsonpath={.status.loadBalancer.ingress[0].hostname}",
    ], text=True).strip()
    return f"http://{host}"


def jwt_secret():
    if os.environ.get("JWT_SECRET_KEY"):
        return os.environ["JWT_SECRET_KEY"]
    out = subprocess.check_output([
        "aws", "secretsmanager", "get-secret-value", "--secret-id", "ff-idp/jwt-secret",
        "--profile", "ff-idp", "--region", "ap-south-1",
        "--query", "SecretString", "--output", "text",
    ], text=True)
    return json.loads(out)["JWT_SECRET_KEY"]


def b64(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=")


def make_token(secret):
    """HS256 JWT signed by hand (the app only reads the sub and role claims)."""
    head = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    body = b64(json.dumps({"sub": "latency-test", "role": "admin", "exp": 9999999999}).encode())
    sig = b64(hmac.new(secret.encode(), head + b"." + body, hashlib.sha256).digest())
    return (head + b"." + body + b"." + sig).decode()


def call(method, url, token=None, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=15) as r:
        r.read()
    return (time.perf_counter() - t0) * 1000  # ms


def summarize(label, ms):
    ms = sorted(ms)
    p95 = ms[min(len(ms) - 1, int(len(ms) * 0.95))]
    print(f"{label:<28} n={len(ms):<4} p50={statistics.median(ms):8.1f} ms  "
          f"p95={p95:8.1f} ms  max={ms[-1]:8.1f} ms")


def main():
    base = base_url()
    print(f"Target: {base}   flags={FLAGS} hit_rounds={HIT_ROUNDS}\n")
    token = make_token(jwt_secret())

    # Baseline: /health (does a DB ping, no cache)
    health = [call("GET", f"{base}/health") for _ in range(30)]

    # Create the flags (not timed)
    names = [f"lat-{RUN_ID}-{i}" for i in range(FLAGS)]
    for n in names:
        call("POST", f"{base}/flags", token, {
            "name": n, "flag_type": "boolean", "default_value": True, "environment": "dev"})

    def evaluate(name):
        return call("POST", f"{base}/evaluate", token,
                    {"flag_name": name, "user_id": "u1", "environment": "dev"})

    # MISS: each flag evaluated for the first time (creating a flag does not fill the cache
    # for /evaluate reads; if it does, the MISS numbers will look like HIT numbers - see note)
    miss = [evaluate(n) for n in names]

    # HIT: repeat evaluations well inside the 10s TTL
    hit = []
    for _ in range(HIT_ROUNDS):
        hit += [evaluate(n) for n in names]

    print("=== Results (client-side wall clock) ===")
    summarize("GET /health", health)
    summarize("POST /evaluate  MISS (DB)", miss)
    summarize("POST /evaluate  HIT (Redis)", hit)
    print("\nBaseline to beat: Neon over WAN p95 ~ 970 ms, Postgres fetch ~ 780 ms.")
    print("If MISS p95 is close to HIT p95 the cache was already warm (flag create fills it),")
    print("in that case read the DB cost from the app's flag_evaluation_duration_seconds instead.")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001
        print(f"FAILED: {e}", file=sys.stderr)
        sys.exit(1)
