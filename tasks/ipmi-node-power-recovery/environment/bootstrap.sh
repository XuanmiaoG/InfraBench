#!/usr/bin/env bash
# Runs as root on node0 (primary). Configures IPMI on all nodes and powers off node1.

set -euo pipefail

IPMI_USER="elabman"
IPMI_PASS="Test1234"
IPMI_USER_ID=2

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes"

# shellcheck source=/opt/syscraft/cloudlab-cluster-info.sh
source /opt/syscraft/cloudlab-cluster-info.sh 2>/dev/null || true

NODE1_HOST="${NODE1_HOST:-$(syscraft_node_host node1)}"
NODE2_HOST="${NODE2_HOST:-$(syscraft_node_host node2)}"

if [ -z "$NODE1_HOST" ] || [ -z "$NODE2_HOST" ]; then
    echo "ERROR: node1/node2 hosts not found in /etc/syscraft/cluster-info" >&2
    exit 1
fi

configure_bmc_local() {
    apt-get install -y -q ipmitool 2>/dev/null | tail -1 || true
    ipmitool lan set 1 auth CALLBACK PASSWORD 2>/dev/null || true
    ipmitool lan set 1 auth USER     PASSWORD 2>/dev/null || true
    ipmitool lan set 1 auth OPERATOR PASSWORD 2>/dev/null || true
    ipmitool lan set 1 auth ADMIN    PASSWORD 2>/dev/null || true
    ipmitool user set password "${IPMI_USER_ID}" "${IPMI_PASS}" 2>/dev/null || true
    echo "BMC configured on $(hostname)"
}

export -f configure_bmc_local
export IPMI_USER_ID IPMI_PASS

echo "=== Installing ipmitool and configuring BMC on all nodes ==="
configure_bmc_local

for host in "$NODE1_HOST" "$NODE2_HOST"; do
    ssh $SSH_OPTS "root@$host" \
        "apt-get install -y -q ipmitool 2>/dev/null | tail -1 || true
         ipmitool lan set 1 auth CALLBACK PASSWORD 2>/dev/null || true
         ipmitool lan set 1 auth USER     PASSWORD 2>/dev/null || true
         ipmitool lan set 1 auth OPERATOR PASSWORD 2>/dev/null || true
         ipmitool lan set 1 auth ADMIN    PASSWORD 2>/dev/null || true
         ipmitool user set password ${IPMI_USER_ID} '${IPMI_PASS}' 2>/dev/null || true
         echo done on \$(hostname)" &
done
wait

NODE0_BMC="$(syscraft_discover_bmc_ip)"
NODE1_BMC="$(syscraft_remote_discover_bmc_ip "$NODE1_HOST" "$SSH_OPTS")"
NODE2_BMC="$(syscraft_remote_discover_bmc_ip "$NODE2_HOST" "$SSH_OPTS")"

# Fall back to cluster-info if probe at environment start already recorded BMC IPs.
NODE0_BMC="${NODE0_BMC:-$(syscraft_node_bmc node0)}"
NODE1_BMC="${NODE1_BMC:-$(syscraft_node_bmc node1)}"
NODE2_BMC="${NODE2_BMC:-$(syscraft_node_bmc node2)}"

if [ -z "$NODE1_BMC" ]; then
    echo "ERROR: could not discover node1 BMC IP" >&2
    exit 1
fi

mkdir -p /etc/syscraft
cat > /etc/syscraft/ipmi-incident.env <<EOF
node1_host=${NODE1_HOST}
node1_bmc=${NODE1_BMC}
node0_bmc=${NODE0_BMC}
node2_bmc=${NODE2_BMC}
EOF

echo "=== Verifying IPMI access to all BMCs ==="
for bmc in "$NODE0_BMC" "$NODE1_BMC" "$NODE2_BMC"; do
  if [ -n "$bmc" ]; then
    STATUS=$(ipmitool -I lan -H "$bmc" -U "$IPMI_USER" -P "$IPMI_PASS" chassis power status 2>/dev/null || echo "error")
    echo "  $bmc: $STATUS"
  fi
done

echo "=== FAULT INJECTION: powering off node1 via IPMI ==="
ipmitool -I lan -H "$NODE1_BMC" -U "$IPMI_USER" -P "$IPMI_PASS" chassis power off
sleep 5

STATUS=$(ipmitool -I lan -H "$NODE1_BMC" -U "$IPMI_USER" -P "$IPMI_PASS" chassis power status 2>/dev/null)
echo "node1 BMC reports: $STATUS"
echo "=== Bootstrap complete. node1 is powered off. ==="
