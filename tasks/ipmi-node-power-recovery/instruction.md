# IPMI Node Power Recovery

## Situation

You are managing a 3-node bare-metal cluster. One of the worker nodes has gone completely dark — it is unreachable by SSH and not responding on the network. This happened without any prior warning and you suspect a hardware-level power event.

You have access to **node0** (the management node). All three nodes have IPMI (Intelligent Platform Management Interface) BMC chips that provide out-of-band management access even when the OS is down.

## Cluster Layout

Node SSH targets and BMC addresses are recorded in `/etc/syscraft/cluster-info` on every node (written by Syscraft at trial start). Read them instead of assuming fixed hostnames:

```bash
awk -F= '/^node1=/{print $2}' /etc/syscraft/cluster-info          # management SSH FQDN
awk -F= '/^node1_bmc=/{print $2}' /etc/syscraft/cluster-info      # BMC IP (if probed)
awk -F= '/^node1_cluster_ip=/{print $2}' /etc/syscraft/cluster-info  # 10.10.1.x cluster IP
```

Or source the helper installed by Syscraft:

```bash
source /opt/syscraft/cloudlab-cluster-info.sh
syscraft_node_host node1
syscraft_node_bmc node1
```

Cluster IPs are typically `10.10.1.1` / `10.10.1.2` / `10.10.1.3` on interface `enp6s0f1`. BMC IPs are assigned per machine — discover locally with `ipmitool lan print 1` on each node if not already in cluster-info.

| Node  | Logical name | Cluster IP (typical) | BMC IP |
|-------|--------------|----------------------|--------|
| node0 | node0        | 10.10.1.1            | see cluster-info |
| node1 | node1        | 10.10.1.2            | see cluster-info |
| node2 | node2        | 10.10.1.3            | see cluster-info |

**IPMI credentials** (pre-configured on all BMCs):
- Username: `elabman`
- Password: `Test1234`
- Interface: `-I lan` (IPMI v1.5)

## Your Task

1. **Identify** which node is powered off. Confirm via IPMI that the chassis power state is `off`.

2. **Power on** the node using `ipmitool` over the out-of-band management network.

3. **Wait** for the node to complete its boot sequence and become reachable via SSH.

4. **Verify** the node is fully operational:
   - SSH connectivity restored
   - System uptime is short (recently rebooted)

## Tools Available

```bash
# Check power status of a node via IPMI
ipmitool -I lan -H <bmc_ip> -U elabman -P Test1234 chassis power status

# Power on a node
ipmitool -I lan -H <bmc_ip> -U elabman -P Test1234 chassis power on

# Power off a node (hard)
ipmitool -I lan -H <bmc_ip> -U elabman -P Test1234 chassis power off

# SSH to nodes (once they are up)
ssh "$(awk -F= '/^node1=/{print $2}' /etc/syscraft/cluster-info)"   # management FQDN
ssh node1         # cluster NIC (10.10.1.x) when enp6s0f1 is up
```

## Notes

- Boot time is approximately 90–120 seconds after power-on
- The BMC management network is reachable from node0
- Use the management SSH FQDN from cluster-info (not hardcoded hostnames) — it survives cluster NIC outages and reboots
