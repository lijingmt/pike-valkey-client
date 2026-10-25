#!/bin/bash
# Foolproof quickstart for pike-valkey-client.
# Checks Pike, ensures a local Valkey on 127.0.0.1:6379, runs the demo.
# Safe: only reads/writes demo keys on a throwaway test server.
set -u

fail() { echo "ERROR: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

ROOT="$(cd "$(dirname "$0")" && pwd)"

# 1. Pike 9
command -v pike >/dev/null 2>&1 || fail "pike not found. Install Pike 9 first: https://pike.lysator.liu.se/download/"
VER="$(pike --dumpversion 2>/dev/null || echo unknown)"
case "$VER" in
  9*) ok "pike $VER" ;;
  *) fail "need Pike 9, found: $VER" ;;
esac

# 2. Local Valkey on 6379?
if (echo > /dev/tcp/127.0.0.1/6379) >/dev/null 2>&1; then
  ok "valkey already on 127.0.0.1:6379"
else
  command -v docker >/dev/null 2>&1 || fail "nothing on 127.0.0.1:6379 and no docker. Start any Valkey/Redis on 6379, then rerun."
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx 'valkey-test'; then
    docker start valkey-test >/dev/null 2>&1 || fail "could not start existing valkey-test container"
  else
    docker run -d --name valkey-test -p 6379:6379 valkey/valkey:latest >/dev/null 2>&1 \
      || fail "could not start valkey/valkey container"
  fi
  for _ in $(seq 1 30); do
    (echo > /dev/tcp/127.0.0.1/6379) >/dev/null 2>&1 && break
    sleep 1
  done
  (echo > /dev/tcp/127.0.0.1/6379) >/dev/null 2>&1 || fail "valkey still not reachable on 6379"
  ok "started local valkey (docker valkey-test)"
fi

# 3. Run the demo
OUT="$(pike -M"$ROOT" "$ROOT/examples/basic.pike" 2>&1)" || fail "demo failed to run: $OUT"
echo "$OUT" | grep -q 'still alive: PONG' || fail "demo did not complete, got: $OUT"
echo "$OUT"
ok "demo passed"

echo
echo "Next:"
echo "  pike -M. tests/smoke.pike            # 46 checks against live Valkey (uses db 15)"
echo "  pike -M. tests/stress.pike 127.0.0.1 6379 3000"
echo "  pike -M. tests/concurrent.pike 127.0.0.1 6379 1000 10   # 1000 clients"
echo "See README.md for the full runbook."
