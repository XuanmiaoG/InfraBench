#!/usr/bin/env bash
# Verifier runs as root on node0. Checks node1 power + SSH + uptime.

set -uo pipefail

IPMI_USER="elabman"
IPMI_PASS="Test1234"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

# shellcheck source=/opt/syscraft/cloudlab-cluster-info.sh
source /opt/syscraft/cloudlab-cluster-info.sh 2>/dev/null || true

if [ -f /etc/syscraft/ipmi-incident.env ]; then
    # shellcheck source=/etc/syscraft/ipmi-incident.env
    source /etc/syscraft/ipmi-incident.env
fi

NODE1_HOST="${node1_host:-$(syscraft_node_host node1)}"
NODE1_BMC="${node1_bmc:-$(syscraft_node_bmc node1)}"

if [ -z "$NODE1_BMC" ] && [ -n "$NODE1_HOST" ]; then
    NODE1_BMC="$(syscraft_remote_discover_bmc_ip "$NODE1_HOST" "$SSH_OPTS")"
fi

mkdir -p /logs/verifier

score=0
details=""

check() {
    local label="$1" result="$2" points="$3"
    if [ "$result" = "pass" ]; then
        score=$((score + points))
        details="${details}  [PASS +${points}] ${label}\n"
    else
        details="${details}  [FAIL  +0] ${label}\n"
    fi
}

# ── Check 1: IPMI reports power ON (40 pts) ──────────────────────────────────
POWER_STATUS="unknown"
if [ -n "$NODE1_BMC" ]; then
    POWER_STATUS=$(ipmitool -I lan -H "$NODE1_BMC" -U "$IPMI_USER" -P "$IPMI_PASS" \
        chassis power status 2>/dev/null || echo "unknown")
fi
echo "$POWER_STATUS" | grep -qi "power is on" \
    && check "node1 BMC chassis power is ON" "pass" 40 \
    || check "node1 BMC chassis power is ON (got: $POWER_STATUS)" "fail" 40

# ── Check 2: SSH reachable (40 pts) ──────────────────────────────────────────
SSH_RESULT="down"
if [ -n "$NODE1_HOST" ]; then
    SSH_RESULT=$(ssh $SSH_OPTS "root@$NODE1_HOST" "echo up" 2>/dev/null || echo "down")
fi
[ "$SSH_RESULT" = "up" ] \
    && check "node1 SSH reachable as root" "pass" 40 \
    || check "node1 SSH reachable as root" "fail" 40

# ── Check 3: uptime < 30 min (20 pts) ────────────────────────────────────────
UPTIME_SECS=99999
if [ "$SSH_RESULT" = "up" ]; then
    UPTIME_SECS=$(ssh $SSH_OPTS "root@$NODE1_HOST" \
        "awk '{printf \"%d\", \$1}' /proc/uptime" 2>/dev/null || echo "99999")
    UPTIME_SECS=$(echo "${UPTIME_SECS:-99999}" | tr -d '[:space:]')
    [ "${UPTIME_SECS:-99999}" -lt 1800 ] 2>/dev/null \
        && check "node1 uptime < 30 min (fresh boot confirmed)" "pass" 20 \
        || check "node1 uptime < 30 min (got ${UPTIME_SECS}s)" "fail" 20
else
    check "node1 uptime < 30 min (SSH unavailable)" "fail" 20
fi

# ── Reward ────────────────────────────────────────────────────────────────────
[ "$score" -eq 100 ] && REWARD="1.0" || REWARD="0.$(printf '%02d' $score)"
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
    "ipmi_power_on": $(echo "$POWER_STATUS" | grep -qi "power is on" && echo true || echo false),
    "ssh_reachable": $([ "$SSH_RESULT" = "up" ] && echo true || echo false),
    "recently_rebooted": $([ "${UPTIME_SECS:-99999}" -lt 1800 ] 2>/dev/null && echo true || echo false)
  }
}
JSON
