#!/usr/bin/env bash
# Oracle solution: deploy a complete Ceph cluster on a 7-node vm-cluster.
# Runs on node0 (primary). Assumes cephadm + podman pre-installed via setup.sh.
set -euxo pipefail

CEPH_IMAGE="quay.io/ceph/ceph:v19.2.0"

# ── 1. Bootstrap mon/mgr on node0 ────────────────────────────────────────────
NODE0_IP=$(awk -F= '/^node0=/{print $2}' /etc/syscraft/cluster-info)

cephadm --image "$CEPH_IMAGE" bootstrap \
  --mon-ip "$NODE0_IP" \
  --allow-fqdn-hostname \
  --initial-dashboard-user admin \
  --initial-dashboard-password adminpass \
  --skip-pull

# Install ceph CLI tools on the host so we can drive the cluster natively
cephadm install ceph-common 2>/dev/null || true
# Add /usr/bin to PATH in case cephadm placed binaries there
export PATH="/usr/bin:/usr/local/bin:$PATH"

# Wait for cluster to be reachable
for i in $(seq 1 60); do
  ceph status &>/dev/null && break
  sleep 15
done

# Disable HTTPS dashboard to avoid cert warnings (not needed for scoring)
ceph mgr module disable dashboard 2>/dev/null || true

# ── 2. Copy SSH key to worker nodes ──────────────────────────────────────────
PUB_KEY=$(cat /etc/ceph/ceph.pub)

for node in node1 node2 node3 node4 node5 node6; do
  ssh -o StrictHostKeyChecking=no root@"$node" \
    "mkdir -p /root/.ssh && echo '$PUB_KEY' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"
done

# ── 3. Add worker nodes to cluster ───────────────────────────────────────────
for node in node1 node2 node3 node4 node5 node6; do
  NODE_IP=$(awk -F= "/^${node}=/{print \$2}" /etc/syscraft/cluster-info)
  ceph orch host add "$node" "$NODE_IP"
done

# Wait for all hosts to appear
for i in $(seq 1 30); do
  COUNT=$(ceph orch host ls --format json | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)
  [ "$COUNT" -ge 7 ] && break
  sleep 10
done

# ── 4. Ensure loop devices exist + unload AppArmor on all nodes ───────────────
# setup.sh enables cephbench-apparmor-unload.service, but it may not have run
# before this script executes. Explicitly flush AppArmor profiles on every node
# to prevent the "ValueError: too many values to unpack" in cephadm ceph-volume.
echo "Flushing AppArmor and verifying loop devices on all nodes..."
for node in node0 node1 node2 node3 node4 node5 node6; do
  ssh -o StrictHostKeyChecking=no root@"$node" bash -s <<'REMOTE'
    apparmor_parser -R /etc/apparmor.d/ 2>/dev/null || true
    systemctl stop apparmor 2>/dev/null || true
    # Attach loop devices if not already attached
    for img in /var/lib/cephbench/disk_b.img /var/lib/cephbench/disk_c.img; do
      losetup -j "$img" | grep -q . || losetup -f --show "$img"
    done
    losetup -l | grep cephbench || true
REMOTE
done

# ── 5. Deploy OSDs via raw mode spec ─────────────────────────────────────────
# Loop devices (type=loop) are invisible to ceph orch device ls and
# ceph-volume lvm batch crashes with IndexError when it tries to inspect them
# (classifies as "LVM type" but finds no LVs → lv.lvs[0] out of range).
# method:raw bypasses lvm batch entirely and writes bluestore directly to the
# device — the only working approach for loop-backed OSDs.
echo "Applying OSD spec with method:raw for loop devices..."
cat > /tmp/osd-spec.yaml << 'EOF'
service_type: osd
service_id: raw_loop_osds
placement:
  host_pattern: '*'
spec:
  method: raw
  data_devices:
    paths:
      - /dev/loop0
      - /dev/loop1
EOF
ceph orch apply -i /tmp/osd-spec.yaml

# Wait for OSDs to come up: 7 nodes × 2 disks = 14 OSDs minimum
echo "Waiting for OSDs (target ≥14)..."
for i in $(seq 1 120); do
  OSD_COUNT=$(ceph osd stat --format json 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("num_up_osds",0))' 2>/dev/null || echo 0)
  echo "  iter $i: $OSD_COUNT OSDs up"
  [ "$OSD_COUNT" -ge 14 ] && break
  sleep 15
done

# Silence common non-blocking warnings and wait for HEALTH_OK (best-effort)
ceph config set global mon_allow_pool_delete true 2>/dev/null || true
ceph config set global auth_allow_insecure_global_id_reclaim false 2>/dev/null || true
echo "Waiting for HEALTH_OK (best-effort, will proceed anyway after 5 min)..."
for i in $(seq 1 15); do
  HEALTH=$(ceph health --format json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || echo "")
  echo "  iter $i: $HEALTH"
  [ "$HEALTH" = "HEALTH_OK" ] && break
  ceph osd pool set .mgr pg_autoscale_mode on 2>/dev/null || true
  ceph health detail 2>/dev/null || true
  sleep 20
done
# Do NOT block on HEALTH_OK — proceed with pool/RBD setup regardless

# ── 6. Create replicated pool data_rep (size=3, app=rbd) ────────────────────
ceph osd pool create data_rep replicated
ceph osd pool set data_rep size 3
ceph osd pool set data_rep min_size 2
ceph osd pool application enable data_rep rbd

# ── 7. Create erasure-coded pool data_ec (jerasure k=4 m=2 host-domain) ─────
ceph osd erasure-code-profile set ec_profile \
  plugin=jerasure \
  technique=reed_sol_van \
  k=4 \
  m=2 \
  crush-failure-domain=host

ceph osd pool create data_ec erasure ec_profile
ceph osd pool set data_ec allow_ec_overwrites true
ceph osd pool application enable data_ec rbd

# ── 8. Create 100 GiB RBD image in data_rep ──────────────────────────────────
rbd create data_rep/bench_image --size 102400

# ── 9. Map, format XFS, mount ────────────────────────────────────────────────
# rbd map prints the device path; use that directly rather than parsing
# showmapped JSON (which changed from dict to list in Ceph v19).
RBD_DEV=$(rbd map data_rep/bench_image)

mkfs.xfs "$RBD_DEV"
mkdir -p /mnt/ceph_data
mount "$RBD_DEV" /mnt/ceph_data

# ── 10. Smoke test: write + read ──────────────────────────────────────────────
echo "hello ceph" > /mnt/ceph_data/probe.txt
grep -q "hello ceph" /mnt/ceph_data/probe.txt

echo "vm-ceph-bootstrap solution completed successfully"
