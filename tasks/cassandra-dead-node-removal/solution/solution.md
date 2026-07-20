# Reference Solution

## Step 1 — Assess the cluster state

```bash
nodetool status
# → Status/State shows:
# UN  10.10.1.1   ...  <uuid-node0>
# DN  10.10.1.2   ...  <uuid-node1>   ← dead node
# UN  10.10.1.3   ...  <uuid-node2>
```

Note the UUID in the last column of the `DN` row — this is node1's **Host ID**.

## Step 2 — Confirm node1 is unreachable

```bash
ssh -o ConnectTimeout=10 node1
# → ssh: connect to host node1 port 22: Connection timed out
# Confirmed: no SSH access, no recovery possible
```

## Step 3 — Remove the dead node from the ring

```bash
# Extract the Host ID automatically
HOST_ID=$(nodetool status | grep '^DN' | awk '{print $(NF-1)}')
echo "Removing host: $HOST_ID"

nodetool removenode "$HOST_ID"
# Output: "RemovalStatus=COMPLETED" (may take 30–120s while data streams)
```

`removenode` evicts the dead node's token ranges and streams any data it exclusively held to the surviving nodes. Unlike `decommission`, it does not require the node to be running.

## Step 4 — Verify ring is clean

```bash
nodetool status
# → Exactly 2 UN nodes, 0 DN nodes:
# UN  10.10.1.1   ...
# UN  10.10.1.3   ...
```

## Step 5 — Verify data integrity at QUORUM

```bash
cqlsh 10.10.1.1 -e "CONSISTENCY QUORUM; SELECT COUNT(*) FROM bench.kv;"
# → 5

cqlsh 10.10.1.3 -e "CONSISTENCY QUORUM; SELECT COUNT(*) FROM bench.kv;"
# → 5
```

QUORUM with RF=3 requires `ceil(3/2) = 2` responses. Both surviving nodes hold complete replicas after `removenode` streaming, so QUORUM reads are satisfied.

## Step 6 — Repair (best practice)

```bash
nodetool repair bench
# Wait for: "Repair command #N finished" in /var/log/cassandra/debug.log
```

After `removenode`, repair runs Merkle-tree anti-entropy between the two surviving nodes to eliminate any remaining inconsistencies.

## Root Cause Summary

node1 suffered a complete hardware failure — both its cluster NIC and OS-level SSH daemon became unreachable. This is distinct from the NIC split-brain scenario: there is no OS running to accept `ip link set up`, no IPMI BMC accessible to power the node back on. The only correct response is to treat the node as permanently dead and remove it from the Cassandra ring via `nodetool removenode`.

## Key Concepts

| Operation | When to use | Node state required |
|-----------|-------------|---------------------|
| `nodetool decommission` | Planned removal (node is healthy) | Node must be **UP** and reachable |
| `nodetool removenode <HOST_ID>` | Emergency removal (node is dead) | Node must be **DN** or unreachable |

**Why not `decommission`?** It streams data *from* the leaving node, which requires the node to be running and reachable over the cluster network. Since node1's cluster NIC is down and SSH is blocked, `decommission` would hang indefinitely.

**Why QUORUM still works?** With RF=3 and 2 surviving nodes, each row has 2 physical replicas. QUORUM requires `ceil(RF/2) = 2` replicas — exactly what we have. Once `removenode` completes its streaming pass, both survivors are guaranteed to hold every row.
