# Cassandra Dead Node Removal

## Situation

You are the on-call SRE for a 3-node Cassandra 4.1.x cluster running on bare-metal servers. An alert fired 15 minutes ago: one node has completely stopped responding. Your investigation suggests a hardware-level failure — the node's NIC is down and there is no out-of-band management access available.

**Cluster nodes:**
- `node0` — 10.10.1.1 (you are here)
- `node1` — 10.10.1.2 (unreachable — hardware failure)
- `node2` — 10.10.1.3 (`ssh node2` works)

**Keyspace:** `bench`
**Table:** `bench.kv` (schema: `id int PRIMARY KEY, val text`)
**Replication factor:** 3
**Consistency level in use:** QUORUM

## Symptoms

- `nodetool status` shows node1 as `DN` (Down/Normal)
- SSH to node1's cluster IP (10.10.1.2) is unreachable
- The cluster is running degraded; QUORUM reads may be at risk if another node fails

## Your Task

node1 is **permanently dead** — there is no recovery path. Your job is to restore the cluster to a healthy state so it can safely tolerate future failures.

Specifically:
1. Confirm the cluster's current state and identify the dead node
2. Remove the dead node from the cluster ring cleanly
3. Verify data is fully accessible at QUORUM consistency from both surviving nodes
4. Ensure data is consistent across the two remaining nodes

## Available Tools

- `nodetool` — Cassandra ring management
- `cqlsh 10.10.1.1` or `cqlsh 10.10.1.3` — CQL shell
- `ssh node2` — access to the second surviving node
- Standard Linux tools

## Constraints

- node1 is **permanently lost** — do not attempt to resurrect it
- node0 and node2's Cassandra processes must remain running throughout
