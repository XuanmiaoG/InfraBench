# Curated InfraBench tasks

These packages are **full task directories** (instruction, environment, verifier). The evaluation runtime is not published in this repository yet — see the root [README](../README.md#evaluation-runtime).

| Task | Layer | Difficulty | Backend | Role |
|------|-------|------------|---------|------|
| [hello-world](hello-world/) | — | Easy | Docker | Minimal on-ramp example |
| [ipmi-node-power-recovery](ipmi-node-power-recovery/) | L1 | Easy | CloudLab | Hardware / IPMI |
| [cassandra-nic-split-brain](cassandra-nic-split-brain/) | L2 | Medium | CloudLab | Local systems / NIC |
| [cassandra-dead-node-removal](cassandra-dead-node-removal/) | L3 | Medium | CloudLab | Distributed recovery |
| [vm-ceph-bootstrap](vm-ceph-bootstrap/) | L3 | Hard | VM cluster | Distributed storage bring-up |
| [db-wal-recovery](db-wal-recovery/) | L4 | Hard | Container | Application / DB recovery |

The full HotInfra '26 suite has **12** tasks; additional tasks will be released over time. Authoring guide: [CONTRIBUTING.md](../CONTRIBUTING.md).
