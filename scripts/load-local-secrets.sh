#!/usr/bin/env bash
# load-local-secrets.sh - copy credentials that must survive `make down` from the
# operator's laptop into Secrets Manager. Called by `make up` right after 20-data.
#
# Why: under the destroy-every-session lifecycle, 20-data recreates every secret with
# placeholders. A permanent secret would cost $0.40/month and break "$0 idle", so the
# source of truth for these few values is ~/.idp (mode 700/600), never Git or TF state.
#
#   ~/.idp/backstage-app.env           APP_ID=..., CLIENT_ID=...  (not secret)
#   ~/.idp/backstage-app.pem           GitHub App private key
#   ~/.idp/backstage-client-secret     GitHub App client secret
#
# Values travel via stdin only; nothing is printed or written to disk.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-idp}" AWS_PAGER=""
D="$HOME/.idp"

missing=()
for f in backstage-app.env backstage-app.pem backstage-client-secret; do
  [ -s "$D/$f" ] || missing+=("$f")
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "WARN: skipping idp/backstage-github-app - missing in $D: ${missing[*]}"
  echo "      Backstage starts, but GitHub reads/writes and templates will fail."
  exit 0
fi

python3 - "$D" <<'PY' | aws secretsmanager put-secret-value --region ap-south-1 \
    --secret-id idp/backstage-github-app --secret-string file:///dev/stdin \
    --query 'Name' --output text
import json, sys, pathlib
d = pathlib.Path(sys.argv[1])
env = dict(l.split("=", 1) for l in (d / "backstage-app.env").read_text().split() if "=" in l)
print(json.dumps({
    "appId": env["APP_ID"],
    "clientId": env["CLIENT_ID"],
    "clientSecret": (d / "backstage-client-secret").read_text().strip(),
    "privateKey": (d / "backstage-app.pem").read_text(),
}))
PY
echo "Loaded idp/backstage-github-app from $D"
