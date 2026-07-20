#!/usr/bin/env bash
# Verifier script. Writes reward (0.0 or 1.0) to /logs/verifier/reward.txt
# Partial credit written to /logs/verifier/reward.json.

set -uo pipefail

NODE0="10.10.1.1"
NODE2="10.10.1.3"
NODE2_HOST="c220g1-030820.wisc.cloudlab.us"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

mkdir -p /logs/verifier

score=0
details=""

check() {
    local label="$1"
    local result="$2"   # "pass" or "fail"
    local points="$3"
    if [ "$result" = "pass" ]; then
        score=$((score + points))
        details="${details}  [PASS +${points}] ${label}\n"
    else
        details="${details}  [FAIL  +0] ${label}\n"
    fi
}

# ── Check 1: node1 removed from ring — 0 DN nodes (40 pts) ──────────────────
RING_STATUS=$(nodetool status 2>/dev/null || true)
DN_COUNT=$(echo "$RING_STATUS" | grep -c '^DN' || true)
UN_COUNT=$(echo "$RING_STATUS" | grep -c '^UN' || true)
DN_COUNT=$(echo "${DN_COUNT:-1}" | tr -d '[:space:]')
UN_COUNT=$(echo "${UN_COUNT:-0}" | tr -d '[:space:]')

ring_clean=false
[ "${DN_COUNT:-1}" -eq 0 ] && ring_clean=true

# Initialize data-check variables so reward.json is always valid
ROW_COUNT_N0=0
ROW_COUNT_N2=0
REPAIR_N0=0
REPAIR_N2=0

if $ring_clean; then
    check "node1 removed from ring (0 DN nodes, ${UN_COUNT} UN remaining)" "pass" 40
else
    check "node1 removed from ring (still ${DN_COUNT} DN nodes in ring)" "fail" 40
fi

# ── Checks 2-4: Only meaningful once the ring is clean ──────────────────────
# Awarding data-integrity points while a DN node is still present would give
# credit for Cassandra's built-in degraded-mode reads, not for the agent's work.

if $ring_clean; then

    # ── Check 2: QUORUM read from node0 — all 5 rows accessible (30 pts) ────
    ROW_COUNT_N0=$(cqlsh "$NODE0" --request-timeout=15 \
        -e 'CONSISTENCY QUORUM; SELECT COUNT(*) FROM bench.kv;' 2>/dev/null \
        | grep -E '^\s+[0-9]+\s*$' | tr -d ' ' || echo 0)
    ROW_COUNT_N0=$(echo "${ROW_COUNT_N0:-0}" | tr -d '[:space:]')
    [ "${ROW_COUNT_N0:-0}" -ge 5 ] \
        && check "QUORUM read from node0: bench.kv has ≥5 rows (got ${ROW_COUNT_N0})" "pass" 30 \
        || check "QUORUM read from node0: bench.kv has ≥5 rows (got ${ROW_COUNT_N0})" "fail" 30

    # ── Check 3: QUORUM read from node2 — all 5 rows accessible (20 pts) ────
    ROW_COUNT_N2=$(ssh $SSH_OPTS "root@$NODE2_HOST" \
        "cqlsh $NODE2 --request-timeout=15 -e 'CONSISTENCY QUORUM; SELECT COUNT(*) FROM bench.kv;' 2>/dev/null | grep -E '^\s+[0-9]+\s*$' | tr -d ' '" \
        2>/dev/null || echo 0)
    ROW_COUNT_N2=$(echo "${ROW_COUNT_N2:-0}" | tr -d '[:space:]')
    [ "${ROW_COUNT_N2:-0}" -ge 5 ] \
        && check "QUORUM read from node2: bench.kv has ≥5 rows (got ${ROW_COUNT_N2})" "pass" 20 \
        || check "QUORUM read from node2: bench.kv has ≥5 rows (got ${ROW_COUNT_N2})" "fail" 20

    # ── Check 4: nodetool repair completed on node0 or node2 (10 pts) ────────
    REPAIR_N0=$(grep -c 'Repair command.*finished' /var/log/cassandra/debug.log 2>/dev/null || echo 0)
    REPAIR_N2=$(ssh $SSH_OPTS "root@$NODE2_HOST" \
        "grep -c 'Repair command.*finished' /var/log/cassandra/debug.log 2>/dev/null" \
        2>/dev/null || echo 0)
    REPAIR_N0=$(echo "${REPAIR_N0:-0}" | tr -d '[:space:]')
    REPAIR_N2=$(echo "${REPAIR_N2:-0}" | tr -d '[:space:]')
    { [ "${REPAIR_N0:-0}" -gt 0 ] || [ "${REPAIR_N2:-0}" -gt 0 ]; } \
        && check "nodetool repair bench completed on a surviving node" "pass" 10 \
        || check "nodetool repair bench completed on a surviving node (no completion log found)" "fail" 10

else
    details="${details}  [SKIP] QUORUM read from node0 (ring not clean)\n"
    details="${details}  [SKIP] QUORUM read from node2 (ring not clean)\n"
    details="${details}  [SKIP] nodetool repair (ring not clean)\n"
fi

# ── Compute final reward ──────────────────────────────────────────────────────
REWARD=$(echo "scale=2; $score / 100" | bc)
[ "$score" -eq 100 ] && REWARD="1.0"
[ "$score" -eq 0 ]   && REWARD="0.0"

printf "Score: %d/100  →  reward=%s\n" "$score" "$REWARD"
printf "%b\n" "$details"

echo "$REWARD" > /logs/verifier/reward.txt
cat > /logs/verifier/reward.json <<JSON
{
  "reward": $REWARD,
  "score": $score,
  "max_score": 100,
  "checks": {
    "node1_removed_from_ring": $( $ring_clean && echo true || echo false),
    "quorum_read_node0": $([ "${ROW_COUNT_N0:-0}" -ge 5 ] 2>/dev/null && echo true || echo false),
    "quorum_read_node2": $([ "${ROW_COUNT_N2:-0}" -ge 5 ] 2>/dev/null && echo true || echo false),
    "repair_completed": $([ "${REPAIR_N0:-0}" -gt 0 ] || [ "${REPAIR_N2:-0}" -gt 0 ] 2>/dev/null && echo true || echo false)
  }
}
JSON
