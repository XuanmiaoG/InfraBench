# Contributing a task to InfraBench

InfraBench evaluates AI agents on **real infrastructure operations** — provisioning, diagnosis, and repair across hardware, local systems, distributed systems, and user applications.

This repository publishes **task specifications** (instruction, environment, verifier). The evaluation runtime (Syscraft) is not open-sourced yet; see the [README](README.md#evaluation-runtime). You can still contribute by authoring a well-structured task that matches the layout below.

## Task layout

```
my-task/
├── task.toml          # environment type, resources, timeout, metadata
├── instruction.md     # natural-language brief for the agent
├── environment/
│   └── Dockerfile     # docker tasks
│   # or setup.sh + bootstrap.sh for vm / vm-cluster
├── solution/
│   └── solve.sh       # reference solution (optional, used by oracle agents)
└── tests/
    └── test.sh        # verifier — writes reward to /logs/verifier/
```

Start from [`tasks/hello-world`](tasks/hello-world) (smallest Docker example), then study a paper task at the layer you care about under [`tasks/`](tasks/).

## Verifier contract

Emit either a scalar reward:

```bash
echo 1.0 > /logs/verifier/reward.txt
```

or structured JSON with partial credit:

```json
{
  "reward": 0.0,
  "checks": [
    {"name": "service health", "passed": true, "scored": false},
    {"name": "root cause fixed", "passed": false, "scored": true}
  ]
}
```

- `scored: true` — checks that measure meaningful repair progress (contribute to partial score).
- `scored: false` — diagnostics / anti-bypass / reachability (affect pass/fail, do not inflate partials).

## `task.toml` templates

### Docker

```toml
[task]
name = "myorg/my-task"

[metadata]
difficulty = "easy"          # easy | medium | hard
category = "infrastructure"

[environment]
type = "docker"
cpus = 2
memory_mb = 4096

[agent]
timeout_sec = 300
```

### Single-node VM

```toml
[task]
name = "myorg/my-vm-task"

[environment]
type = "vm"
base_image = "ubuntu-24.04"
cpus = 2
memory_mb = 4096
storage_mb = 20480

[agent]
timeout_sec = 300
```

VM tasks use `environment/setup.sh` (cached package install) and optional `bootstrap.sh` (per-trial) instead of a Dockerfile.

### VM cluster

```toml
[task]
name = "myorg/my-cluster-task"

[environment]
type = "vm-cluster"
network = "192.168.100.0/24"

[[environment.nodes]]
name = "primary"
cpus = 2
memory_mb = 4096
storage_mb = 20480

[[environment.nodes]]
name = "worker"
cpus = 2
memory_mb = 4096
storage_mb = 20480

[agent]
timeout_sec = 600
```

The agent SSHes into the first node (`primary`). Nodes resolve each other by hostname.

## What makes a strong InfraBench task

1. **Real ops, not toy puzzles** — grounded in incident response, deployment, or repair that a human SRE would recognize.
2. **Layered stack** — situate the failure in L1 hardware → L2 local systems → L3 distributed → L4 user applications when possible.
3. **Honest verifiers** — prefer multi-check `reward.json` over a single opaque pass/fail; resist reward hacking.
4. **Clear instructions** — `instruction.md` states the goal and constraints without leaking the root cause unless that is part of the scenario.
5. **Reproducible environment** — pin packages / images; document CloudLab profiles or base images in a short task README if needed.

## Submission checklist

- [ ] Directory matches the layout above
- [ ] `instruction.md` is self-contained
- [ ] Verifier writes `/logs/verifier/reward.txt` or `reward.json`
- [ ] `task.toml` declares `type`, resources, and `[metadata].difficulty`
- [ ] Reference `solution/solve.sh` works under the intended environment (when you have runner access)
- [ ] Open a PR against this repo with a short description: layer, backend, what is being tested

## Agent-oriented notes

If you are an coding agent authoring a task, also read [AGENTS.md](AGENTS.md).

## Questions

Open an issue on this repository, or contact the authors listed in the [HotInfra '26 paper](paper/hotinfra26-final71.pdf).
