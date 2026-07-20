<p align="center">
  <img src="docs/logo.svg" width="48" height="48" alt="InfraBench" />
</p>

<h1 align="center">InfraBench</h1>

<p align="center">
  <code>HOTINFRA '26 — CO-LOCATED WITH ISCA '26 · RALEIGH, NC</code>
</p>

<p align="center">
  <strong>A benchmark for infrastructure agents.</strong>
</p>

<p align="center">
  Twelve real operational incidents — from IPMI power recovery to silent data<br />
  corruption — spanning hardware, local systems, distributed systems, and user applications.
</p>

<p align="center">
  <a href="https://xuanmiaog.github.io/InfraBench/"><strong>View leaderboard ↓</strong></a>
  &nbsp;&nbsp;·&nbsp;&nbsp;
  <a href="https://hotinfra.org/2026/papers/hotinfra26-final71.pdf"><strong>Paper (PDF) →</strong></a>
  &nbsp;&nbsp;·&nbsp;&nbsp;
  <a href="CONTRIBUTING.md"><strong>Contribute a task →</strong></a>
</p>

<p align="center">
  <code>12 tasks</code>&nbsp;&nbsp;&nbsp;<code>11 configs</code>&nbsp;&nbsp;&nbsp;<code>3 backends</code>
</p>

---

### Task coverage by layer

```
L4  User Applications      ████████░░░░░░░░░░░░   3 tasks
L3  Distributed Systems    ████████████████████  7 tasks
L2  Local Systems          ███░░░░░░░░░░░░░░░░░   1 task
L1  Hardware               ███░░░░░░░░░░░░░░░░░   1 task
```

Published suite: **12 × 11** score matrix across Claude Code, Codex, Cursor CLI, Gemini CLI, OpenCode, and more — full leaderboard on the [project site](https://xuanmiaog.github.io/InfraBench/).

---

## 01 &nbsp; What makes it different

Coding benchmarks ask agents to edit files in a sandbox.  
InfraBench asks them to **operate real systems**.

| | Typical agent bench | InfraBench |
|---|---|---|
| Environment | Container / repo checkout | Docker · KVM · CloudLab bare metal |
| Failure model | Static unit tests | Fault injection, drift, corruption |
| Success signal | Pass a test suite | Multi-check verifier with partial credit |
| Stack view | App / code only | **L1 → L4** infrastructure layers |

Agents must diagnose across layers, survive concurrent faults, and leave the machine in a state a human SRE would accept.

---

## 02 &nbsp; Curated tasks in this repo

This is the **public** surface. Full task directories (instruction, environment, verifier) — treat them as the canonical package format.

| Task | Layer | Diff. | Backend |
|------|:-----:|:-----:|---------|
| [`hello-world`](tasks/hello-world/) | — | Easy | Docker · start here |
| [`ipmi-node-power-recovery`](tasks/ipmi-node-power-recovery/) | L1 | Easy | CloudLab |
| [`cassandra-nic-split-brain`](tasks/cassandra-nic-split-brain/) | L2 | Medium | CloudLab |
| [`cassandra-dead-node-removal`](tasks/cassandra-dead-node-removal/) | L3 | Medium | CloudLab |
| [`vm-ceph-bootstrap`](tasks/vm-ceph-bootstrap/) | L3 | Hard | VM cluster |
| [`db-wal-recovery`](tasks/db-wal-recovery/) | L4 | Hard | Container |

More of the 12-task HotInfra suite will land here over time. Index: [`tasks/README.md`](tasks/README.md).

### Task shape

```
my-task/
├── task.toml          # env, resources, difficulty
├── instruction.md     # what the agent sees
├── environment/       # Dockerfile  —or—  setup.sh + bootstrap.sh
├── solution/          # optional reference solve.sh
└── tests/             # verifier → /logs/verifier/reward.{txt,json}
```

How to author one: **[CONTRIBUTING.md](CONTRIBUTING.md)** · agent notes: **[AGENTS.md](AGENTS.md)**

---

## 03 &nbsp; Evaluation runtime

End-to-end runs use **Syscraft** (provisioning, fault scenarios, agent adapters).  
**That harness is not open-sourced in this repository yet.**

- Use these tasks as **layout + verifier references** today.
- `hello-world` is the on-ramp for a future lightweight Docker runner.
- Need eval access or collaboration? [Open an issue](https://github.com/XuanmiaoG/InfraBench/issues) or contact the authors in the paper.

```
InfraBench/
├── tasks/           curated packages
├── CONTRIBUTING.md  write a task
├── AGENTS.md        agent authoring notes
├── paper/           HotInfra '26 PDF
└── docs/            project website (GitHub Pages)
```

---

## 04 &nbsp; Citation

```bibtex
@inproceedings{infrabench2026,
  title     = {InfraBench: A Benchmark for Infrastructure Agents},
  booktitle = {Workshop on Hot Topics in System Infrastructure (HotInfra)},
  year      = {2026},
  note      = {Co-located with ISCA '26},
  url       = {https://hotinfra.org/2026/papers/hotinfra26-final71.pdf}
}
```

Copy author fields from the [camera-ready PDF](paper/hotinfra26-final71.pdf) when citing formally.

---

<p align="center">
  <a href="https://xuanmiaog.github.io/InfraBench/">Site</a>
  ·
  <a href="https://hotinfra.org/2026/papers/hotinfra26-final71.pdf">Paper</a>
  ·
  <a href="CONTRIBUTING.md">Contribute</a>
  ·
  <a href="LICENSE">Apache 2.0</a>
</p>

<p align="center">
  <sub>University of Wisconsin–Madison · Iowa State University</sub>
</p>
