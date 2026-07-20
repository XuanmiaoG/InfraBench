#!/usr/bin/env bash
# Runs as root on node0 (primary). Installs and configures a 3-node Cassandra
# cluster, seeds data, then injects fault: kills node1's cluster NIC and blocks
# SSH so it is completely unreachable — simulating permanent hardware failure.

set -euo pipefail

NODE0_IP="10.10.1.1"
NODE1_IP="10.10.1.2"
NODE2_IP="10.10.1.3"
CLUSTER_NIC="enp6s0f1"

NODE1_HOST="c220g1-030819.wisc.cloudlab.us"
NODE2_HOST="c220g1-030820.wisc.cloudlab.us"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes"

remote() {
    local host="$1"; shift
    ssh $SSH_OPTS "root@$host" "$@"
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
    # Restore cassandra.yaml if fault injection deleted it on this node
    if ssh $SSH_OPTS "root@$host" "test ! -f /etc/cassandra/cassandra.yaml" 2>/dev/null; then
        scp $SSH_OPTS /etc/cassandra/cassandra.yaml "root@$host:/etc/cassandra/cassandra.yaml" 2>/dev/null || true
    fi
done
systemctl stop cassandra 2>/dev/null || true
sleep 5

echo "=== Installing Cassandra on all nodes ==="
for host in localhost "$NODE1_HOST" "$NODE2_HOST"; do
    ( ssh $SSH_OPTS "root@$host" 'bash -s' <<'INSTALL'
export DEBIAN_FRONTEND=noninteractive
# Full skip only if binary AND yaml both exist
which cassandra >/dev/null 2>&1 && test -f /etc/cassandra/cassandra.yaml && exit 0
apt-get update -q
apt-get install -y -q openjdk-11-jdk-headless curl gnupg python3-pip
# Add Cassandra repo only if not already configured
if [ ! -f /etc/apt/sources.list.d/cassandra.list ]; then
    curl -fsSL https://downloads.apache.org/cassandra/KEYS | gpg --dearmor -o /usr/share/keyrings/cassandra-archive.gpg 2>/dev/null
    echo "deb [signed-by=/usr/share/keyrings/cassandra-archive.gpg] https://debian.cassandra.apache.org 41x main" > /etc/apt/sources.list.d/cassandra.list
    apt-get update -q
fi
# --reinstall + --force-confmiss ensures cassandra.yaml is restored even if manually deleted
apt-get install -y -q --reinstall -o Dpkg::Options::="--force-confmiss" cassandra
pip3 install cqlsh --break-system-packages 2>/dev/null || true
systemctl disable cassandra
systemctl stop cassandra || true
echo "Cassandra installed on $(hostname)"
INSTALL
    ) &
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
cqlsh "$NODE0_IP" -e "INSERT INTO bench.kv (id, val) VALUES (4, 'delta');"
cqlsh "$NODE0_IP" -e "INSERT INTO bench.kv (id, val) VALUES (5, 'epsilon');"

echo "=== Waiting 10s for full replication ==="
sleep 10

echo "=== FAULT INJECTION: simulating permanent hardware failure on node1 ==="
# Bring down the cluster NIC so Cassandra gossip fails and node1 is marked DN.
# Then destroy node1's Cassandra config and data so it cannot simply be restarted —
# any recovery attempt via `systemctl start cassandra` will fail without a full
# reinstall. This models a node whose Cassandra state is unrecoverably corrupted.
remote "$NODE1_HOST" "
    ip link set $CLUSTER_NIC down
    systemctl stop cassandra
    rm -f /etc/cassandra/cassandra.yaml
    rm -rf /var/lib/cassandra/data/* /var/lib/cassandra/commitlog/* \
           /var/lib/cassandra/saved_caches/* /var/lib/cassandra/hints/*
"

echo "=== Waiting for Cassandra gossip to mark node1 as DN ==="
for i in $(seq 1 12); do
    DN=$(nodetool status 2>/dev/null | grep -c '^DN' || echo 0)
    echo "  Attempt $i: $DN DN nodes"
    [ "$DN" -ge 1 ] && break
    sleep 15
done

echo "=== Bootstrap complete. node1 ($NODE1_IP) is permanently lost. ==="
echo "    Cluster NIC: DOWN (gossip dead, node1 will appear as DN)"
echo "    Cassandra: STOPPED, config deleted, data wiped"
echo "    Agent must use 'nodetool removenode' to recover cluster."
