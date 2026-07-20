# Reference Solution

## Step 1 — Identify which node is down

```bash
# Check SSH connectivity to each node
ssh node1-mgmt   # → Connection refused or timeout → node1 is down

# Confirm via IPMI
ipmitool -I lan -H 10.134.9.223 -U elabman -P Test1234 chassis power status
# → Chassis Power is off
```

## Step 2 — Power on node1 via IPMI

```bash
ipmitool -I lan -H 10.134.9.223 -U elabman -P Test1234 chassis power on
# → Chassis Power Control: Up/On
```

## Step 3 — Wait for boot (~90–120 seconds)

```bash
# Poll until SSH is available
until ssh -o ConnectTimeout=5 -o BatchMode=yes node1-mgmt 'echo up' 2>/dev/null; do
    echo "Waiting for node1 to boot..."
    sleep 15
done
echo "node1 is up"
```

## Step 4 — Verify

```bash
ssh node1-mgmt "uptime"
# → up N minutes (short uptime confirms fresh boot)

ipmitool -I lan -H 10.134.9.223 -U elabman -P Test1234 chassis power status
# → Chassis Power is on
```

## Root Cause Summary

A physical power event (simulated via IPMI `chassis power off`) caused node1 to hard-power off. The OS, SSH daemon, and all running services were terminated immediately — no graceful shutdown. Recovery requires out-of-band management via IPMI because the OS is not running and cannot respond to normal network requests. Once `chassis power on` is issued, the BMC starts the boot sequence independently of the OS.

## Why This Is a True L1 Task

Unlike NIC toggling (`ip link set down`) which is an OS-kernel operation, IPMI `chassis power off` cuts the ATX 12V power rail from the BMC hardware directly. The CPU, memory, and all OS state are wiped. No OS-level tool can prevent or detect this — only the BMC chip (which has its own power supply) remains active.
