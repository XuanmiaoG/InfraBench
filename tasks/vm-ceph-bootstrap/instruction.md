You are a Ceph storage administrator. Deploy a Ceph cluster and configure block storage on the following infrastructure.

══════════════════════════════════════════════════════════════════
ENVIRONMENT
══════════════════════════════════════════════════════════════════
Nodes: node0 through node6 (7-node KVM cluster on a private libvirt network)

You are currently on node0. From node0 you have passwordless root SSH to every
other node by short name:
  ssh root@node1   ...   ssh root@node6

`/etc/hosts` and `/etc/syscraft/cluster-info` are populated on every node with
the mapping `<short-name>=<ip>`. Use those for any IP lookups.

Network:
  Single private subnet 192.168.100.0/24 on the only NIC of each VM.
  Look up node0's private IP for `--mon-ip`:
    awk -F= '/^node0=/{print $2}' /etc/syscraft/cluster-info
  Do NOT pass `--cluster-network` — this deployment uses a single network.

Storage:
  Each node has TWO unused raw block devices for OSDs:
    /dev/loop0  (~30 GiB)
    /dev/loop1  (~30 GiB)
  The root filesystem is on /dev/vda — do not touch it.
  The loop devices are attached automatically at boot by a systemd unit; if
  they are missing on a worker for any reason, `losetup -f --show
  /var/lib/cephbench/disk_b.img` (and `disk_c.img`) will recreate them.

OS: Ubuntu 24.04 LTS on all nodes.

Container runtime: podman is installed on all nodes.

Pre-installed tooling (ready to use, no installation needed):
  cephadm (Ceph Squid, v19.x) — available on all nodes via /usr/sbin/cephadm
  podman, lvm2, xfsprogs, chrony, jq — installed on all nodes

Pre-pulled image: quay.io/ceph/ceph:v19.2.0  (Ceph Squid)
  This image is already cached in podman on every node.
  `--image` is a GLOBAL flag that comes BEFORE the subcommand:
    cephadm --image quay.io/ceph/ceph:v19.2.0 bootstrap ...
  NOT: cephadm bootstrap --image ...   (this will fail)

Node hostnames may be FQDN-shaped. Pass `--allow-fqdn-hostname` to cephadm
bootstrap.

When adding hosts to the cluster, the short name must match the actual
hostname on that node. The nodes' short names are `node0`..`node6`.
Correct usage: `ceph orch host add node1 <node1-ip-from-cluster-info>`
              (short name first, then IP as the address)

This is a 7-node cluster — do NOT pass `--single-host-defaults`.

══════════════════════════════════════════════════════════════════
TASKS (all must be completed)
══════════════════════════════════════════════════════════════════

1. Bootstrap a Ceph cluster using cephadm on node0.

2. Join node1 through node6 into the cluster.

3. Add all available data disks (`/dev/loop0` and `/dev/loop1` on each node)
   as OSDs.

4. Create a replicated storage pool named "data_rep" with 3 replicas and
   application=rbd.

5. Create an erasure-coded storage pool named "data_ec" using:
   - Algorithm: reed_sol_van (jerasure plugin)
   - k=4, m=2
   - Failure domain: host

6. In the data_rep pool, create a 100 GiB RBD block device image named
   "bench_image". Map it to a local block device on node0, format it with
   xfs, and mount it at /mnt/ceph_data.

══════════════════════════════════════════════════════════════════
SCORING
══════════════════════════════════════════════════════════════════
   5 pts — Ceph cluster is reachable (bootstrap succeeded)
  15 pts — Cluster health is HEALTH_OK
  15 pts — data_rep pool: 3 replicas, type=replicated, application=rbd
  15 pts — data_ec pool: k=4 m=2 reed_sol_van jerasure host failure domain
  20 pts — bench_image exists in data_rep, size ~100 GiB
  20 pts — /mnt/ceph_data is mounted
  10 pts — data can be written to /mnt/ceph_data
