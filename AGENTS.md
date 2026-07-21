# AGENTS.md — writing InfraBench tasks

This file is for coding agents and humans who author **benchmark tasks**. It is intentionally scoped to task packages. The evaluation harness (Syscraft) remains closed-source for now.

## Non-negotiables

1. Every task is a directory with `task.toml`, `instruction.md`, `environment/`, and `tests/`.
2. The verifier is the source of truth: write `reward.txt` or `reward.json` under `/logs/verifier/`.
3. Do not bake secrets, API keys, or private CloudLab credentials into the task tree.
4. Prefer structured checks with `scored: true|false` over a single opaque score.

## Layout

```
task/
├── task.toml
├── instruction.md
├── environment/     # Dockerfile  OR  setup.sh [+ bootstrap.sh]
├── solution/        # optional solve.sh
└── tests/           # test.sh (+ helpers)
```

Canonical examples in this repo:

| Path | Role |
|------|------|
| `tasks/hello-world` | Minimal Docker task — start here |
| `tasks/ipmi-node-power-recovery` | L1 / Easy / BM Cluster |
| `tasks/cassandra-nic-split-brain` | L2 / Medium / BM Cluster |
| `tasks/cassandra-dead-node-removal` | L3 / Medium / BM Cluster |
| `tasks/vm-ceph-bootstrap` | L3 / Hard / VM cluster |
| `tasks/db-wal-recovery` | L4 / Hard / Container |

## Environment types

| `environment.type` | When to use |
|--------------------|-------------|
| `docker` | Userspace / container-local work |
| `vm` | Kernel modules, block devices, single-node systems work |
| `vm-cluster` | Multi-node distributed systems |
| `cloudlab` | Bare-metal / IPMI / real NIC scenarios |

VM hosts need Linux + KVM. CloudLab tasks need a profile and site access — document that in the PR, do not commit credentials.

## Verifier patterns

Scalar:

```bash
#!/bin/bash
set -euo pipefail
# ... assertions ...
echo 1.0 > /logs/verifier/reward.txt
```

Structured (preferred for InfraBench paper-style tasks):

```bash
#!/bin/bash
set -euo pipefail
mkdir -p /logs/verifier
python3 - <<'PY'
import json, pathlib
checks = [
  {"name": "service up", "passed": True, "scored": False},
  {"name": "data consistent", "passed": False, "scored": True},
]
reward = 1.0 if all(c["passed"] for c in checks) else 0.0
pathlib.Path("/logs/verifier/reward.json").write_text(
    json.dumps({"reward": reward, "checks": checks})
)
PY
```

## Writing `instruction.md`

- State the **goal** and **success criteria** the agent can observe.
- Include operational constraints (do not destroy X, preserve Y).
- Do not paste the root-cause spoilers unless the task is explicitly a known-fault drill.
- Keep it short enough that an agent can act; put long background in comments inside `environment/` scripts if needed.

## PR expectations

See [CONTRIBUTING.md](CONTRIBUTING.md) for the human checklist. Agents should open a PR that:

1. Adds `tasks/<name>/` with a complete package
2. Mentions layer (L1–L4), difficulty, and backend in the PR body
3. Links related paper sections when the task is a HotInfra / InfraBench scenario

## Out of scope here

- Implementing new agent adapters
- Changing the Syscraft CLI or environment factory
- Publishing private evaluation traces

Those stay in the closed Syscraft tree until the runtime is released.
