#!/usr/bin/env bash
# Runs once on each node during environment setup (before bootstrap.sh).
# Installs Cassandra 4.1.x and dependencies.

set -euo pipefail

NODE_IP="${NODE_IP:-}"   # Set by framework: 10.10.1.1, 10.10.1.2, or 10.10.1.3
SEEDS="10.10.1.1"

export DEBIAN_FRONTEND=noninteractive

# Java
apt-get update -q
apt-get install -y -q openjdk-11-jdk-headless curl gnupg python3-yaml

# Cassandra 4.1 repo
if [ ! -f /etc/apt/sources.list.d/cassandra.list ]; then
    rm -f /usr/share/keyrings/cassandra-archive.gpg
    curl -fsSL https://downloads.apache.org/cassandra/KEYS | gpg --batch --no-tty --dearmor -o /usr/share/keyrings/cassandra-archive.gpg
    echo "deb [signed-by=/usr/share/keyrings/cassandra-archive.gpg] https://debian.cassandra.apache.org 41x main" \
        > /etc/apt/sources.list.d/cassandra.list
    apt-get update -q
fi
apt-get install -y -q cassandra

# cqlsh (standalone, avoids bundled driver bug)
apt-get install -y -q python3-pip
pip3 install cqlsh --break-system-packages

# SSH between nodes (node0 acts as jump host for the agent)
# Keys are injected by the framework via CloudLab profile

systemctl disable cassandra
systemctl stop cassandra || true
