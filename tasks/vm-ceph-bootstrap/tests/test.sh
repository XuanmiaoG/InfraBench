#!/usr/bin/env bash
# syscraft adapter around the vendored cephbench judge.sh.
# Runs on node0 (primary). Writes a 0.0–1.0 float reward to
# /logs/verifier/reward.txt and a per-check breakdown to
# /logs/verifier/judge_output.json.
set -uo pipefail

mkdir -p /logs/verifier

HERE="$(cd "$(dirname "$0")" && pwd)"

OUT=$(bash "${HERE}/judge.sh" --json 2>&1)
RC=$?

echo "$OUT" | tee /logs/verifier/judge_output.json >/dev/null

SCORE=$(python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(int(d.get("score", 0)))
except Exception:
    print(0)
' <<<"$OUT")

python3 -c "print(${SCORE}/100)" > /logs/verifier/reward.txt

echo "vm-ceph-bootstrap score: ${SCORE}/100 (judge rc=${RC})"

[ "$SCORE" -eq 100 ] && exit 0 || exit 1
