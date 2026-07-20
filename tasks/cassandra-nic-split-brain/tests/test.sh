#!/usr/bin/env bash
# Verifier script. Writes reward (0.0 or 1.0) to /logs/verifier/reward.txt
# Partial credit written to /logs/verifier/reward.json.

set -uo pipefail

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

# shellcheck source=/opt/syscraft/cloudlab-cluster-info.sh
source /opt/syscraft/cloudlab-cluster-info.sh 2>/dev/null || true

NODE0="${NODE0:-$(syscraft_node_cluster_ip node0)}"
NODE1="${NODE1:-$(syscraft_node_cluster_ip node1)}"
NODE2="${NODE2:-$(syscraft_node_cluster_ip node2)}"
NODE0="${NODE0:-10.10.1.1}"
NODE1="${NODE1:-10.10.1.2}"
NODE2="${NODE2:-10.10.1.3}"

# Management FQDN from cluster-info — reachable when cluster NIC is down.
NODE1_HOST="${NODE1_HOST:-$(syscraft_node_host node1)}"

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

# ── Check 1: All 3 nodes UN (40 pts) ────────────────────────────────────────
UN_COUNT=$(nodetool status 2>/dev/null | grep -c '^UN' || echo 0)
[ "$UN_COUNT" -ge 3 ] && check "All 3 nodes show UN in nodetool status" "pass" 40 \
                       || check "All 3 nodes show UN in nodetool status (got $UN_COUNT)" "fail" 40

# ── Check 2: node1 cluster NIC is up (20 pts) ───────────────────────────────
# SSH via management FQDN so the check works when cluster NIC was down.
NIC_STATE=""
if [ -n "$NODE1_HOST" ]; then
    NIC_STATE=$(ssh $SSH_OPTS "root@$NODE1_HOST" \
        "ip link show enp6s0f1 2>/dev/null | grep -o 'state [A-Z]*'" 2>/dev/null || echo "")
fi
echo "$NIC_STATE" | grep -q "UP" \
    && check "node1 enp6s0f1 is UP" "pass" 20 \
    || check "node1 enp6s0f1 is UP (got: $NIC_STATE)" "fail" 20

# ── Check 3: Repair completed — confirmed via debug.log on node1 (20 pts) ────
REPAIR_LOG=0
if [ -n "$NODE1_HOST" ]; then
    REPAIR_LOG=$(ssh $SSH_OPTS "root@$NODE1_HOST" \
        "grep -c 'Repair command.*finished' /var/log/cassandra/debug.log 2>/dev/null" \
        2>/dev/null || echo "0")
fi
REPAIR_LOG=$(echo "$REPAIR_LOG" | tr -d '[:space:]')
[ "${REPAIR_LOG:-0}" -gt 0 ] 2>/dev/null \
    && check "nodetool repair completed on node1" "pass" 20 \
    || check "nodetool repair completed on node1 (no completion log found)" "fail" 20

# ── Check 4: Data consistency — all 5 rows readable from node1 (20 pts) ─────
ROW_COUNT=0
if [ -n "$NODE1_HOST" ]; then
    ROW_COUNT=$(ssh $SSH_OPTS "root@$NODE1_HOST" \
        "cqlsh $NODE1 --request-timeout=15 -e 'CONSISTENCY ONE; SELECT COUNT(*) FROM bench.kv;' 2>/dev/null | grep -E '^\s+[0-9]+\s*$' | tr -d ' '" \
        2>/dev/null || echo 0)
fi
ROW_COUNT=$(echo "${ROW_COUNT:-0}" | tr -d '[:space:]')
[ "$ROW_COUNT" -ge 5 ] \
    && check "bench.kv has ≥5 rows on node1 (rows written during isolation visible)" "pass" 20 \
    || check "bench.kv has ≥5 rows on node1 (got $ROW_COUNT)" "fail" 20

# ── Compute final reward ─────────────────────────────────────────────────────
REWARD=$(echo "scale=2; $score / 100" | bc)
[ "$score" -eq 100 ] && REWARD="1.0"
[ "$score" -eq 0 ]   && REWARD="0.0"

printf "Score: %d/100  →  reward=%s\n" "$score" "$REWARD"
printf "%b\n" "$details"

# Write outputs
echo "$REWARD" > /logs/verifier/reward.txt
cat > /logs/verifier/reward.json <<JSON
{
  "reward": $REWARD,
  "score": $score,
  "max_score": 100,
  "checks": {
    "all_nodes_un": $([ "$UN_COUNT" -ge 3 ] && echo true || echo false),
    "nic_restored": $(echo "$NIC_STATE" | grep -q "UP" && echo true || echo false),
    "repair_completed": $([ "$REPAIR_LOG" -gt 0 ] && echo true || echo false),
    "data_consistent": $([ "$ROW_COUNT" -ge 5 ] && echo true || echo false)
  }
}
JSON
