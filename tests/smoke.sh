#!/usr/bin/env bash
# Minimal smoke test: build the image, run it with required env vars,
# verify it answers an EHLO on port 25.
set -euo pipefail

IMAGE="${IMAGE:-reference-postfix:smoke}"
PORT="${PORT:-12525}"
NAME="reference-postfix-smoke"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker build -t "$IMAGE" .

docker run -d --rm --name "$NAME" \
  -p "$PORT:25" \
  -e POSTFIX_HOSTNAME=mail.example.test \
  -e POSTFIX_DOMAIN=example.test \
  "$IMAGE"

# Wait for postfix to fully start (supervisord brings it up after rsyslog).
# Probe by trying an actual SMTP banner read, not just a TCP connect.
for i in $(seq 1 30); do
  banner=$({ sleep 1; printf 'QUIT\r\n'; sleep 1; } | nc 127.0.0.1 "$PORT" 2>/dev/null | head -1 || true)
  if [[ "$banner" =~ ^220 ]]; then
    break
  fi
  sleep 1
done

# Talk to postfix WITHOUT pipelining (postfix's anti-pipelining check
# rejects commands sent before the 220 banner). Sleep between sends.
RESP=$({ sleep 2; printf 'EHLO smoke.test\r\n'; sleep 1; printf 'QUIT\r\n'; sleep 1; } | nc 127.0.0.1 "$PORT" || true)

if ! echo "$RESP" | grep -q '^220 mail.example.test ESMTP'; then
  echo "FAIL: missing 220 banner"
  echo "--- response ---"
  echo "$RESP"
  echo "--- container logs ---"
  docker logs "$NAME"
  exit 1
fi

if ! echo "$RESP" | grep -q '^250'; then
  echo "FAIL: EHLO not answered with 250"
  echo "--- response ---"
  echo "$RESP"
  echo "--- container logs ---"
  docker logs "$NAME"
  exit 1
fi

echo "OK: postfix banner + EHLO 250 received"
