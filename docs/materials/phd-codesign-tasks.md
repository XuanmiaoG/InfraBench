# PhD-Level Hardware/Software Codesign Tasks for Syscraft

Research notes on designing PhD-level evaluation tasks that exercise system-level hardware/software codesign on bare-metal (CloudLab) and VM environments.

## Motivation

CloudLab / bare-metal environments enable a class of evaluation tasks that Docker-based setups cannot support: kernel boot parameters, IRQ affinity, NUMA topology, NVMe namespace control, NIC offloads, CXL memory tiering, and so on. This makes them the natural target for **PhD-level HW/SW codesign tasks** where the agent must reason across the system stack rather than tune a single knob.

The distinguishing property of a PhD-level task should be that it lives on a **Pareto frontier** (performance vs cost vs reliability) — single-knob optimization should not be sufficient. The agent must perform genuine cross-layer reasoning about workload characteristics interacting with device queue models, NUMA topology, scheduler behavior, etc.

| Level | Goal | Example |
|-------|------|---------|
| Sysadmin | Fix the broken thing (recovery) | Restore a split-brain Cassandra cluster |
| Engineer | Make it work (config) | Bring up a new service with reasonable defaults |
| **PhD** | **Find the optimal point on the perf/cost/reliability frontier via deep HW/SW codesign** | **See task categories below** |

## Candidate Task Categories (Ranked)

### Tier 1 — Highest potential, runnable on CloudLab today

#### 1. NVMe storage stack codesign

Given a mixed read/write workload (e.g., RocksDB compaction + foreground OLTP), the agent jointly tunes:

- NVMe queue depth and namespace configuration
- `io_uring` vs `libaio`
- Block I/O scheduler (`mq-deadline` / `kyber` / `bfq`)
- Filesystem choice (XFS / ext4 / btrfs) and mount options (`noatime`, `discard`, etc.)
- cgroup v2 `io.weight`

**Scoring:** p99.9 latency at fixed throughput, plus IOPS efficiency (IOPS / CPU%). The difficulty is that the agent must reason about the workload access pattern interacting with the device queue model.

#### 2. Network dataplane codesign

The agent implements an L4 LB or packet filter using DPDK / XDP / AF_XDP, jointly designing:

- CPU isolation (`isolcpus` / `nohz_full`)
- NIC RSS / RFS queue steering
- IRQ affinity
- NUMA-local memory pools

**Scoring:** maximum pps at fixed p99 latency (< X µs), plus jitter standard deviation. Particularly PhD-level because tuning any single axis alone fails to score.

#### 3. NUMA + memory tiering codesign

For an in-memory analytics workload (DuckDB / ClickHouse), the agent jointly configures:

- THP `madvise` vs `always`
- `numactl` interleave policy
- cgroup `memory.high`
- (If available) CXL / PMEM hot/cold tiering

**Scoring:** scan latency p99 + memory bandwidth utilization.

### Tier 2 — Compelling but require specific hardware

#### 4. RDMA + NCCL collective tuning

Requires InfiniBand or RoCE. The agent configures GPUDirect, `NCCL_TOPO`, QP parameters for multi-node allreduce. **Scoring:** bus bandwidth as fraction of peak. Worthwhile if CloudLab nodes have IB.

#### 5. Real-time / SCHED_DEADLINE jitter optimization

Bootloader parameters (`isolcpus` + `rcu_nocbs` + `nohz_full`) + IRQ steering + SCHED_DEADLINE budget. **Scoring:** cyclictest p99.99 jitter. Narrow scope but very PhD-flavored.

## Scoring Framework

A multi-objective approach with a baseline ratio works well across all categories:

- **Baseline:** naive default configuration (vanilla Linux defaults)
- **Oracle ceiling:** hand-tuned expert configuration from a published artifact
- **Score:** `(agent - baseline) / (oracle - baseline)`
- **SLA gate:** hard constraint (e.g., p99 < X) that must be satisfied for any positive score

This cleanly separates "configured correctly" from "genuinely approached the expert ceiling."

## Reference Papers

The systems community has published detailed hand-tuned configurations that can be reused directly as oracle baselines.

### 1. NVMe / Storage stack

**Design space and baselines:**

- **KVell** (Lepers et al., SOSP '19) — Demonstrates LSM CPU bottlenecks on NVMe; gives RocksDB hand-tuned baseline numbers.
- **SILK** (Balmau et al., ATC '19) — RocksDB tail-latency tuning with compaction I/O scheduling oracle numbers.
- **uFS / SplitFS** (Kadekodi et al., SOSP '19) — Userspace FS vs kernel ext4/XFS; hand-tuned upper bound.
- **ScaleXFS** (Kim et al., FAST '22) — XFS scalability ceiling under multi-core NVMe.

**Auto-tuning frameworks (useful as agent baselines):**

- **OtterTune** (Van Aken et al., SIGMOD '17) — Automated DBMS configuration with expert-DBA vs auto-tuned comparison tables.
- **LlamaTune** (Kanellis et al., VLDB '22) — Sample-efficient improvement over OtterTune; clean design-space description.
- **CherryPick** (Alipourfard et al., NSDI '17) — Bayesian-opt cloud configuration including VM type + storage tier.

### 2. Network dataplane

The most mature category — nearly every SOSP/OSDI paper here provides hand-tuned numbers:

- **IX** (Belay et al., OSDI '14) — Foundational dataplane OS; provides Linux / mTCP / IX baseline comparison.
- **ZygOS** (Prekas et al., SOSP '17) — Work-stealing for µs-scale latency; compared against IX.
- **Shenango** (Ousterhout et al., NSDI '19) — 5 µs core reallocation; includes detailed `isolcpus` + IRQ steering configuration.
- **Caladan** (Fried et al., OSDI '20) — Interference mitigation. **Especially recommended** because the evaluation section lists all hand-tuned IRQ + cgroup configurations.
- **Snap** (Marty et al., SOSP '19) — Google's production network stack with Pony Express tuning details.
- **eRPC** (Kalia et al., NSDI '19) — Extreme single-threaded RPC; ablation tables cover NIC offload / DPDK parameters.
- **Junction** (Fried et al., 2024) — Latest evolution of Caladan with fine-grained CPU sharing.
- **XDP** (Høiland-Jørgensen et al., CoNEXT '18) — XDP vs DPDK vs kernel comparison baseline.

### 3. NUMA + memory tiering

The hottest category in the past 3 years; CXL papers consistently include hand-tuned configurations:

- **TMO** (Weiner et al., ASPLOS '22) — Meta production memory offloading; oracle numbers for PSI-based tuning.
- **TPP** (Maruf et al., ASPLOS '23) — CXL tiered memory page placement. **Appendix contains a complete table of NUMA balancing + kswapd parameters.**
- **Pond** (Li et al., ASPLOS '23) — Azure CXL memory pool with ML-driven configuration vs expert baseline.
- **Memtis** (Lee et al., SOSP '23) — Dynamic page-size determination; especially complete design-space description.
- **Mitosis** (Achermann et al., ASPLOS '20) — Page-table replication for NUMA; analyzes interaction with huge pages.

### 4. Surveys / system-level analyses

Useful when defining the design space for a task spec:

- **An Analysis of Performance Evolution of Linux's Core Operations** (Ren et al., SOSP '19) — Decade-long performance evolution of Linux core operations; reveals which knobs actually matter.
- **Understanding PCIe Performance for End Host Networking** (Neugebauer et al., SIGCOMM '18) — Physical upper bound of PCIe + NIC interaction.
- **My VM is Lighter (and Safer) than your Container** (Manco et al., SOSP '17) — Detailed decomposition of VM vs container overhead.

## Recommended Pattern for Task Design

**Fork the artifacts of these papers directly:**

1. Use the authors' optimal configuration as the **oracle ceiling**.
2. Use default Linux as the **baseline**.
3. Leave N `sysctl` / cgroup / boot parameters as the agent's exploration surface.

This makes the oracle upper bound paper-quality and immediately credible.

### Highest-priority papers to mine

1. **Caladan** + **Shenango** — Open-source artifacts ship with expert `isolcpus` / IRQ / cgroup scripts directly usable as an oracle ceiling.
2. **TPP** and **Memtis** — Appendices give complete `sysctl` + cgroup parameter sets.
3. **SILK** + **KVell** — RocksDB tuning with quantified baseline / expert / paper tiers.

## Personal Recommendation

Most bullish on **(1) NVMe storage codesign** and **(2) DPDK/XDP network dataplane** — both have clear physical upper bounds (device queue model, PCIe bandwidth), demand genuine cross-layer reasoning, and run on common CloudLab profiles (c220g5 / xl170).

A natural next step is to pick one paper artifact (e.g., Caladan) and prototype its conversion into a Syscraft CloudLab task: extract the expert configuration as oracle, define the SLA gate, and identify the exploration surface to expose to the agent.
