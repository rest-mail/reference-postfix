#!/usr/bin/env bash
# Minimal smoke test: build the image, run it standalone, verify postfix
# answers a banner + EHLO on port 25.
#
# The probe runs INSIDE the container via python3 (shipped in the image), not
# host `nc`: the old `sleep | nc | head` pipe hangs on BSD/macOS nc, and this
# also needs no published port.
set -euo pipefail

IMAGE="${IMAGE:-reference-postfix:smoke}"
NAME="reference-postfix-smoke"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker build -t "$IMAGE" .

docker run -d --rm --name "$NAME" \
  -e POSTFIX_HOSTNAME=mail.example.test \
  -e POSTFIX_DOMAIN=example.test \
  "$IMAGE"

# Poll from inside the container until postfix answers EHLO (supervisord brings
# it up after rsyslog). smtplib reads the 220 banner before sending EHLO, so
# postfix's anti-pipelining check is satisfied.
probe='
import smtplib, sys
s = smtplib.SMTP("127.0.0.1", 25, timeout=5)
code, msg = s.ehlo("smoke.test")
s.quit()
print("EHLO", code, msg.decode().splitlines()[0])
sys.exit(0 if code == 250 else 1)
'
for i in $(seq 1 30); do
  if out=$(docker exec "$NAME" python3 -c "$probe" 2>/dev/null); then
    echo "OK: postfix banner + EHLO 250 received"
    echo "  $out"
    exit 0
  fi
  sleep 1
done

echo "FAIL: postfix did not answer EHLO with 250 within 30s"
echo "--- container logs ---"
docker logs "$NAME"
exit 1
