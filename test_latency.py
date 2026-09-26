import requests
import time
import sys
import jwt
import json
import subprocess

ALB_URL = "http://k8s-ffidp-feabb0d7a0-389480458.ap-south-1.elb.amazonaws.com"
ENDPOINT = f"{ALB_URL}/health"

def get_jwt_secret():
    out = subprocess.check_output([
        "aws", "secretsmanager", "get-secret-value", 
        "--secret-id", "ff-idp/jwt-secret", 
        "--profile", "ff-idp", "--region", "ap-south-1", 
        "--query", "SecretString", "--output", "text"
    ])
    return json.loads(out)["JWT_SECRET_KEY"]

def test_latency(url, headers=None, requests_count=50):
    latencies = []
    print(f"Testing {url} with {requests_count} requests...")
    for i in range(requests_count):
        start = time.perf_counter()
        try:
            r = requests.get(url, headers=headers, timeout=5)
            r.raise_for_status()
            latencies.append(time.perf_counter() - start)
        except Exception as e:
            print(f"Request {i} failed: {e}")
            continue
        time.sleep(0.01)

    if not latencies:
        print("All requests failed.")
        sys.exit(1)

    latencies.sort()
    avg = sum(latencies) / len(latencies)
    p95 = latencies[int(len(latencies) * 0.95)]
    print(f"Completed {len(latencies)} requests")
    print(f"Avg latency: {avg*1000:.2f} ms")
    print(f"p95 latency: {p95*1000:.2f} ms")

if __name__ == "__main__":
    print("=== Unauthenticated (/health) ===")
    test_latency(ENDPOINT)
    
    print("\n=== Authenticated (/api/v1/flags) ===")
    secret = get_jwt_secret()
    token = jwt.encode({"sub": "admin", "role": "admin", "exp": 9999999999}, secret, algorithm="HS256")
    test_latency(f"{ALB_URL}/api/v1/flags", headers={"Authorization": f"Bearer {token}"})
