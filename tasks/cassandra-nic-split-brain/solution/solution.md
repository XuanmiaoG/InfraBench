# Reference Solution

## Step 1 — Identify the degraded node

```bash
nodetool status
# → node1 (10.10.1.2) shows DN (Down/Normal)
```

## Step 2 — Diagnose: cluster NIC is down

```bash
ssh node1 ip link show enp6s0f1
# → state DOWN — the cluster-internal NIC is offline
```

The management NIC (`enp1s0f0`) is still up (SSH works), but node1 lost its cluster gossip link on `enp6s0f1`.

## Step 3 — Restore the NIC

```bash
ssh node1 sudo ip link set enp6s0f1 up
```

Cassandra gossip will detect the NIC coming back and automatically mark node1 as UN within ~30–60 seconds.

## Step 4 — Confirm node rejoined

```bash
nodetool status
# → All 3 nodes UN
```

## Step 5 — Repair stale data

While node1 was isolated, writes at QUORUM consistency went to node0 and node2. node1 missed those mutations.

```bash
ssh node1 nodetool repair bench
# Wait for: "Repair completed successfully"
```

## Step 6 — Verify consistency

```bash
cqlsh 10.10.1.2 -e "CONSISTENCY ONE; SELECT * FROM bench.kv;"
# → Should show 5 rows (ids 1–5, including delta and epsilon written during outage)
```

## Root Cause Summary

Physical NIC failure on node1's cluster interface (`enp6s0f1`) caused the node to become unreachable on the Cassandra gossip/storage network (10.10.1.x). The node continued to function (OS up, management SSH accessible) but was invisible to the cluster. Writes at QUORUM consistency proceeded with 2/3 replicas (node0 + node2), leaving node1 with a stale copy. Bringing the NIC back up restores gossip, and `nodetool repair` performs Merkle-tree-based anti-entropy sync to reconcile the divergent data.
