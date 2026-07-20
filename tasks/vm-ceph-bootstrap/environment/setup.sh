#!/usr/bin/env bash
# Baked into the VM base image via virt-customize. Runs once per (task,
# base_image) cache key. Network is available; do NOT pass --no-network to
# virt-customize from the framework side.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
    cephadm \
    podman \
    lvm2 \
    xfsprogs \
    chrony \
    jq \
    curl \
    ca-certificates \
    apparmor-utils \
    openssh-server

# Pre-pull the Ceph container image into podman storage. If virt-customize's
# chroot blocks podman's networking, this becomes a no-op and the agent (or
# cephadm itself) will pull on first use — slower, not fatal.
podman pull quay.io/ceph/ceph:v19.2.0 || true

# Two sparse "data disks" per node, attached via loop devices at boot.
mkdir -p /var/lib/cephbench
truncate -s 30G /var/lib/cephbench/disk_b.img
truncate -s 30G /var/lib/cephbench/disk_c.img

cat >/etc/systemd/system/cephbench-loopdisks.service <<'EOF'
[Unit]
Description=Attach Ceph loopback data disks
DefaultDependencies=no
After=local-fs.target
Before=podman.service ceph.target
[Service]
Type=oneshot
ExecStart=/usr/sbin/losetup -f --show /var/lib/cephbench/disk_b.img
ExecStart=/usr/sbin/losetup -f --show /var/lib/cephbench/disk_c.img
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
systemctl enable cephbench-loopdisks.service
