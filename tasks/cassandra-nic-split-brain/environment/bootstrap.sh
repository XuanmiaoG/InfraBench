#!/usr/bin/env bash
# Runs as root on node0 (primary). Configures Cassandra on all nodes,
# seeds data, then injects fault: brings down enp6s0f1 on node1.

set -euo pipefail

CLUSTER_NIC="enp6s0f1"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes"

# shellcheck source=/opt/syscraft/cloudlab-cluster-info.sh
source /opt/syscraft/cloudlab-cluster-info.sh 2>/dev/null || true

NODE0_IP="${NODE0_IP:-$(syscraft_node_cluster_ip node0)}"
NODE1_IP="${NODE1_IP:-$(syscraft_node_cluster_ip node1)}"
NODE2_IP="${NODE2_IP:-$(syscraft_node_cluster_ip node2)}"
NODE0_IP="${NODE0_IP:-10.10.1.1}"
NODE1_IP="${NODE1_IP:-10.10.1.2}"
NODE2_IP="${NODE2_IP:-10.10.1.3}"

NODE1_HOST="${NODE1_HOST:-$(syscraft_node_host node1)}"
NODE2_HOST="${NODE2_HOST:-$(syscraft_node_host node2)}"

if [ -z "$NODE1_HOST" ] || [ -z "$NODE2_HOST" ]; then
    echo "ERROR: node1/node2 hosts not found in /etc/syscraft/cluster-info" >&2
    exit 1
fi

# Syscraft connects as root; use root SSH for inter-node calls.
remote() {
    local host="$1"; shift
    ssh $SSH_OPTS "root@$host" "$@"
}

ensure_cassandra_ready() {
    local host="$1"
    remote "$host" bash -s <<'SCRIPT'
set -euo pipefail

need_install=0
if ! command -v cassandra >/dev/null 2>&1; then
    need_install=1
fi
if [ ! -f /etc/cassandra/cassandra.yaml ]; then
    need_install=1
fi
python3 - <<'PY' >/dev/null 2>&1 || need_install=1
import yaml
PY

if [ "$need_install" -eq 1 ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -q
    apt-get install -y -q openjdk-11-jdk-headless curl gnupg python3-yaml python3-pip
    if [ ! -f /etc/apt/sources.list.d/cassandra.list ]; then
        curl -fsSL https://downloads.apache.org/cassandra/KEYS | gpg --dearmor -o /usr/share/keyrings/cassandra-archive.gpg 2>/dev/null
        echo "deb [signed-by=/usr/share/keyrings/cassandra-archive.gpg] https://debian.cassandra.apache.org 41x main" > /etc/apt/sources.list.d/cassandra.list
        apt-get update -q
    fi
    apt-get install -y -q --reinstall -o Dpkg::Options::="--force-confmiss" cassandra
    pip3 install cqlsh --break-system-packages 2>/dev/null || true
    systemctl disable cassandra
    systemctl stop cassandra || true
fi

test -f /etc/cassandra/cassandra.yaml
python3 - <<'PY'
import yaml
PY
SCRIPT
}

configure_node() {
    local host="$1"
    local listen_ip="$2"
    remote "$host" bash -s <<SCRIPT
set -e
python3 - <<'PY'
import yaml
with open('/etc/cassandra/cassandra.yaml') as f:
    cfg = yaml.safe_load(f)
cfg['cluster_name'] = 'InfraBench'
cfg['num_tokens'] = 16
cfg['listen_address'] = '${listen_ip}'
cfg['rpc_address'] = '${listen_ip}'
cfg['broadcast_address'] = '${listen_ip}'
cfg['broadcast_rpc_address'] = '${listen_ip}'
cfg['seed_provider'] = [{'class_name': 'org.apache.cassandra.locator.SimpleSeedProvider',
                         'parameters': [{'seeds': '${NODE0_IP}'}]}]
cfg['endpoint_snitch'] = 'SimpleSnitch'
with open('/etc/cassandra/cassandra.yaml', 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False)
PY
rm -rf /var/lib/cassandra/data/* /var/lib/cassandra/commitlog/* \
       /var/lib/cassandra/saved_caches/* /var/lib/cassandra/hints/*
SCRIPT
}

wait_un() {
    local target_count="$1"
    local max_attempts=40
    for i in $(seq 1 $max_attempts); do
        COUNT=$(nodetool status 2>/dev/null | grep -c '^UN' || echo 0)
        echo "  Attempt $i: $COUNT UN nodes (want $target_count)"
        [ "$COUNT" -ge "$target_count" ] && return 0
        sleep 15
    done
    echo "ERROR: Timed out waiting for $target_count UN nodes" >&2
    return 1
}

echo "=== Cleaning up any leftover fault state from previous trials ==="
for host in "$NODE1_HOST" "$NODE2_HOST"; do
    ssh $SSH_OPTS "root@$host" "
        ip link set $CLUSTER_NIC up 2>/dev/null || true
        iptables -D INPUT -p tcp --dport 22 -j DROP 2>/dev/null || true
        systemctl stop cassandra 2>/dev/null || true
    "
done
systemctl stop cassandra 2>/dev/null || true
sleep 5

echo "=== Installing Cassandra on all nodes ==="
for host in localhost "$NODE1_HOST" "$NODE2_HOST"; do
    ( ensure_cassandra_ready "$host" ) &
done
wait

echo "=== Configuring Cassandra on all nodes ==="
configure_node "localhost" "$NODE0_IP"
configure_node "$NODE1_HOST" "$NODE1_IP"
configure_node "$NODE2_HOST" "$NODE2_IP"

echo "=== Starting seed node (node0) ==="
systemctl start cassandra
wait_un 1

echo "=== Starting node1 ==="
remote "$NODE1_HOST" "systemctl start cassandra"
wait_un 2

echo "=== Starting node2 ==="
remote "$NODE2_HOST" "systemctl start cassandra"
wait_un 3

echo "=== All 3 nodes UN. Seeding data ==="
cqlsh "$NODE0_IP" -e "CREATE KEYSPACE IF NOT EXISTS bench WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 3};"
cqlsh "$NODE0_IP" -e "CREATE TABLE IF NOT EXISTS bench.kv (id int PRIMARY KEY, val text);"
cqlsh "$NODE0_IP" -e "INSERT INTO bench.kv (id, val) VALUES (1, 'alpha');"
cqlsh "$NODE0_IP" -e "INSERT INTO bench.kv (id, val) VALUES (2, 'beta');"
cqlsh "$NODE0_IP" -e "INSERT INTO bench.kv (id, val) VALUES (3, 'gamma');"

echo "=== Waiting 10s for full replication ==="
sleep 10

echo "=== FAULT INJECTION: taking down $CLUSTER_NIC on node1 ==="
remote "$NODE1_HOST" "ip link set $CLUSTER_NIC down"

echo "=== Writing divergent rows while node1 is isolated ==="
cqlsh "$NODE0_IP" --request-timeout=15 -e "INSERT INTO bench.kv (id, val) VALUES (4, 'delta');"
cqlsh "$NODE0_IP" --request-timeout=15 -e "INSERT INTO bench.kv (id, val) VALUES (5, 'epsilon');"

echo "=== Bootstrap complete. node1 ($NODE1_IP) has $CLUSTER_NIC down. ==="
