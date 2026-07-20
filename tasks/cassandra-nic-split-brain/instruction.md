# Cassandra NIC Split-Brain Repair

## Situation

You are managing a 3-node Cassandra 4.1.x cluster running on bare-metal servers. The cluster was healthy until approximately 10 minutes ago when monitoring alerts started firing.

**Cluster nodes (accessible via SSH from node0):**
- `node0` — 10.10.1.1 (you are here); management alias: `node0-mgmt`
- `node1` — 10.10.1.2 (`ssh node1`); management alias: `node1-mgmt`
- `node2` — 10.10.1.3 (`ssh node2`); management alias: `node2-mgmt`

> **Note**: `node0/1/2` aliases resolve to the cluster-internal network (10.10.1.x).  
> `node0/1/2-mgmt` aliases resolve to the out-of-band management network and remain reachable even if the cluster NIC is down.

**Keyspace:** `bench`  
**Table:** `bench.kv` (schema: `id int PRIMARY KEY, val text`)  
**Replication factor:** 3 (all nodes hold all data)  
**Consistency level in use:** QUORUM

## Symptoms

- `nodetool status` shows one or more nodes as `DN` (Down/Normal) or in an unexpected state
- Reads at QUORUM consistency may fail or return stale data
- Recent writes to the keyspace may not be visible on all replicas

## Your Task

1. **Diagnose**: Determine the root cause of the cluster degradation. Identify which node is affected and why.

2. **Restore connectivity**: The physical cluster NIC (`enp6s0f1`, on the 10.10.1.x subnet) on the affected node was taken offline. Bring it back up so the node can rejoin the cluster.

3. **Repair data**: After the node rejoins, the affected node's data may be stale due to writes that occurred during the outage. Run the appropriate Cassandra repair operation to synchronize data across all replicas.

4. **Verify**: Confirm that:
   - All 3 nodes show `UN` (Up/Normal) in `nodetool status`
   - `nodetool repair bench` completes successfully on the affected node
   - A QUORUM read of `SELECT * FROM bench.kv` returns consistent results across all nodes

## Available Tools

- SSH access to all nodes from node0: `ssh node1`, `ssh node2`
- `nodetool` — Cassandra operations tool
- `cqlsh 10.10.1.1` — CQL shell (connect to any node IP)
- `ip link`, `ip addr` — network interface management
- Standard Linux tools

## Constraints

- Do **not** restart Cassandra unless absolutely necessary — prefer network-level and repair operations
- Do **not** wipe data directories or run `nodetool removenode`
- The management network (`enp1s0f0`, public IPs) must remain up at all times
