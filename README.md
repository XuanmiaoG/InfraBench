# InfraBench

**A benchmark for infrastructure agents.**

Twelve real operational incidents — from IPMI power recovery to silent data corruption — spanning hardware, local systems, distributed systems, and user applications.

Accepted at **[HotInfra '26](https://hotinfra.org/)** · co-located with **ISCA '26** · Raleigh, NC

<p align="center">
  <a href="https://xuanmiaog.github.io/InfraBench/"><img alt="Leaderboard" src="https://img.shields.io/badge/leaderboard-live-B0321C?style=flat-square" /></a>
  <a href="paper/hotinfra26-final71.pdf"><img alt="Paper" src="https://img.shields.io/badge/paper-HotInfra%20'26%20PDF-1C1A16?style=flat-square" /></a>
  <a href="CONTRIBUTING.md"><img alt="Contribute" src="https://img.shields.io/badge/contribute-write%20a%20task-3E7B52?style=flat-square" /></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-Apache%202.0-5D5850?style=flat-square" /></a>
</p>

<p align="center">
  <a href="https://xuanmiaog.github.io/InfraBench/"><strong>Leaderboard &amp; site →</strong></a>
  &nbsp;·&nbsp;
  <a href="https://hotinfra.org/2026/papers/hotinfra26-final71.pdf"><strong>Paper (PDF) →</strong></a>
  &nbsp;·&nbsp;
  <a href="CONTRIBUTING.md"><strong>Contribute a task →</strong></a>
</p>

---

## Why InfraBench?

Most agent benchmarks stop at containers and coding puzzles. Infrastructure work is different: agents must reason across **layers**, survive **fault injection**, and leave the system in a **verifiable** state.

| Layer | Focus | Sample in this repo |
|-------|--------|---------------------|
| **L1** Hardware | IPMI, power, physical control | [`ipmi-node-power-recovery`](tasks/ipmi-node-power-recovery/) |
| **L2** Local systems | NIC, host networking | [`cassandra-nic-split-brain`](tasks/cassandra-nic-split-brain/) |
| **L3** Distributed | Clusters, storage, control planes | [`cassandra-dead-node-removal`](tasks/cassandra-dead-node-removal/), [`vm-ceph-bootstrap`](tasks/vm-ceph-bootstrap/) |
| **L4** User applications | DBs, app config, recovery | [`db-wal-recovery`](tasks/db-wal-recovery/) |

Published results: **12 tasks × 11 model configurations** (Claude Code, Codex, Cursor CLI, Gemini CLI, OpenCode, …). See the [project site](https://xuanmiaog.github.io/InfraBench/).

---

## What's public vs closed

This repository is the **public InfraBench surface**. The evaluation runtime (**Syscraft** — Docker / KVM / CloudLab backends, fault scenarios, agent adapters) remains **closed-source for now**.

```
InfraBench/
├── tasks/              # hello-world + curated paper-task packages (full dirs)
├── CONTRIBUTING.md     # how to write & PR a task
├── AGENTS.md           # agent-oriented authoring notes
├── paper/              # HotInfra '26 camera-ready PDF
└── docs/               # static website (GitHub Pages)
```

| You want… | Go here |
|-----------|---------|
| Smallest example | [`tasks/hello-world`](tasks/hello-world/) |
| Curated paper samples | [`tasks/README.md`](tasks/README.md) |
| Authoring guide | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| Agent checklist | [`AGENTS.md`](AGENTS.md) |
| Paper PDF | [`paper/hotinfra26-final71.pdf`](paper/hotinfra26-final71.pdf) · [HotInfra mirror](https://hotinfra.org/2026/papers/hotinfra26-final71.pdf) |
| Leaderboard UI | [xuanmiaog.github.io/InfraBench](https://xuanmiaog.github.io/InfraBench/) |

### Evaluation runtime

- Treat paper tasks here as **canonical package layouts** and verifier patterns.
- `hello-world` is the on-ramp we will wire to a lightweight Docker runner when that opens up.
- For collaboration or evaluation access, [open an issue](https://github.com/XuanmiaoG/InfraBench/issues) or contact the authors listed in the paper.

---

## Quick look: task shape

```
my-task/
├── task.toml          # env type, resources, difficulty
├── instruction.md     # what the agent sees
├── environment/       # Dockerfile  or  setup.sh + bootstrap.sh
├── solution/          # optional reference solve.sh
└── tests/             # verifier → /logs/verifier/reward.{txt,json}
```

Full templates and submission checklist: **[CONTRIBUTING.md](CONTRIBUTING.md)**.

---

## Citation

```bibtex
@inproceedings{infrabench2026,
  title     = {InfraBench: A Benchmark for Infrastructure Agents},
  booktitle = {Workshop on Hot Topics in System Infrastructure (HotInfra)},
  year      = {2026},
  note      = {Co-located with ISCA '26},
  url       = {https://hotinfra.org/2026/papers/hotinfra26-final71.pdf}
}
```

Update author fields from the camera-ready PDF when citing formally.

---

## License

Task materials and documentation in this repository are released under [Apache License 2.0](LICENSE) unless a subdirectory states otherwise. The HotInfra PDF remains under the workshop / publisher terms applicable to the camera-ready paper.

## Links

- Site: https://xuanmiaog.github.io/InfraBench/
- Paper: https://hotinfra.org/2026/papers/hotinfra26-final71.pdf
- Contribute: [CONTRIBUTING.md](CONTRIBUTING.md)
