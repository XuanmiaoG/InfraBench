#!/usr/bin/env bash
# judge.sh — CephBench automated scoring script.
# Verifies the Ceph deployment and outputs a score from 0–100.
# Usage: bash judge.sh [--json]
set -uo pipefail

JSON_OUTPUT=0
[ "${1:-}" = "--json" ] && JSON_OUTPUT=1

# ── Resolve ceph/rbd commands ─────────────────────────────────────────────────
# On bare-metal cephadm deployments, ceph/rbd may only be available inside the
# cephadm shell container. Wrap them if not found natively.
if ! command -v ceph &>/dev/null; then
    if command -v cephadm &>/dev/null; then
        ceph() { cephadm shell -- ceph "$@" 2>/dev/null; }
        rbd()  { cephadm shell -- rbd  "$@" 2>/dev/null; }
    else
        echo "ERROR: neither 'ceph' nor 'cephadm' found in PATH" >&2
        exit 2
    fi
fi

SCORE=0
declare -a RESULTS
declare -a DETAILS

pass() {
    local pts=$1 msg=$2 detail="${3:-}"
    SCORE=$((SCORE + pts))
    RESULTS+=("PASS")
    DETAILS+=("[+${pts}pts] PASS: ${msg}${detail:+ | ${detail}}")
}

fail() {
    local pts=$1 msg=$2 detail="${3:-}"
    RESULTS+=("FAIL")
    DETAILS+=("[+0/${pts}pts] FAIL: ${msg}${detail:+ | ${detail}}")
}

# ── Check 1a: Cluster reachable / bootstrap succeeded (5 pts) ────────────────
CEPH_STATUS_JSON=$(ceph status --format json 2>/dev/null) || CEPH_STATUS_JSON=''
if [ -n "$CEPH_STATUS_JSON" ] && python3 -c "import json,sys; json.loads(sys.argv[1])" "$CEPH_STATUS_JSON" 2>/dev/null; then
    pass 5 "Ceph cluster is reachable (bootstrap succeeded)"
else
    fail 5 "Ceph cluster not reachable" "ceph status returned no output or failed"
    CEPH_STATUS_JSON='{}'
fi

# ── Check 1b: Cluster HEALTH_OK (15 pts) ─────────────────────────────────────
HEALTH_JSON=$(ceph health --format json 2>/dev/null) || HEALTH_JSON='{}'
HEALTH_STATUS=$(python3 -c "
import json, sys
try:
    print(json.loads(sys.argv[1]).get('status', 'UNKNOWN'))
except Exception:
    print('PARSE_ERROR')
" "$HEALTH_JSON")

if [ "$HEALTH_STATUS" = "HEALTH_OK" ]; then
    pass 15 "Cluster health is HEALTH_OK"
else
    fail 15 "Cluster health" "got=${HEALTH_STATUS}, expected=HEALTH_OK"
fi

# ── Check 2: data_rep pool (15 pts) ──────────────────────────────────────────
POOL_JSON=$(ceph osd pool ls detail --format json 2>/dev/null) || POOL_JSON='[]'

DATA_REP_RESULT=$(python3 -c "
import json, sys
try:
    pools = json.loads(sys.argv[1])
    for p in pools:
        if p.get('pool_name') == 'data_rep':
            size_ok = p.get('size') == 3
            type_ok = p.get('type') == 1  # 1=replicated
            apps = p.get('application_metadata', {})
            app_ok = 'rbd' in apps
            if size_ok and type_ok and app_ok:
                print('ok')
            else:
                print(f'size={p.get(\"size\")} type={p.get(\"type\")} apps={list(apps.keys())}')
            sys.exit(0)
    print('pool_not_found')
except Exception as e:
    print(f'parse_error:{e}')
" "$POOL_JSON")

if [ "$DATA_REP_RESULT" = "ok" ]; then
    pass 15 "Pool data_rep: replicated, size=3, app=rbd"
else
    fail 15 "Pool data_rep" "$DATA_REP_RESULT"
fi

# ── Check 3: data_ec pool + erasure code profile (15 pts) ────────────────────
EC_POOL_PROFILE=$(python3 -c "
import json, sys
try:
    pools = json.loads(sys.argv[1])
    for p in pools:
        if p.get('pool_name') == 'data_ec':
            print(p.get('erasure_code_profile', ''))
            sys.exit(0)
    print('')
except Exception:
    print('')
" "$POOL_JSON")

EC_CHECK_RESULT="pool_not_found"
if [ -n "$EC_POOL_PROFILE" ]; then
    EC_PROFILE_JSON=$(ceph osd erasure-code-profile get "$EC_POOL_PROFILE" --format json 2>/dev/null) || EC_PROFILE_JSON='{}'
    EC_CHECK_RESULT=$(python3 -c "
import json, sys
try:
    p = json.loads(sys.argv[1])
    checks = {
        'k':                    (p.get('k') == '4',               f'k={p.get(\"k\")} (need 4)'),
        'm':                    (p.get('m') == '2',               f'm={p.get(\"m\")} (need 2)'),
        'technique':            (p.get('technique') == 'reed_sol_van', f'technique={p.get(\"technique\")}'),
        'plugin':               (p.get('plugin') == 'jerasure',   f'plugin={p.get(\"plugin\")}'),
        'crush-failure-domain': (p.get('crush-failure-domain') == 'host', f'domain={p.get(\"crush-failure-domain\")}'),
    }
    failed = [v[1] for k,(ok,v) in checks.items() if not ok]
    print('ok' if not failed else 'fail: ' + ', '.join(failed))
except Exception as e:
    print(f'parse_error:{e}')
" "$EC_PROFILE_JSON")
fi

if [ "$EC_CHECK_RESULT" = "ok" ]; then
    pass 15 "Pool data_ec: erasure k=4 m=2 reed_sol_van host-domain" "profile=${EC_POOL_PROFILE}"
else
    fail 15 "Pool data_ec" "${EC_CHECK_RESULT}"
fi

# ── Check 4: bench_image exists ~100GB (20 pts) ───────────────────────────────
RBD_INFO=$(rbd info data_rep/bench_image --format json 2>/dev/null) || RBD_INFO='{}'
RBD_CHECK=$(python3 -c "
import json, sys
try:
    info = json.loads(sys.argv[1])
    size = info.get('size', 0)
    lo, hi = 95 * 1024**3, 105 * 1024**3
    if lo <= size <= hi:
        print(f'ok:{size}')
    else:
        print(f'size={size} not in [{lo},{hi}]')
except Exception as e:
    print(f'parse_error:{e}')
" "$RBD_INFO")

if [[ "$RBD_CHECK" == ok:* ]]; then
    pass 20 "RBD image bench_image exists in data_rep (~100GB)" "size=$(echo "$RBD_CHECK" | cut -d: -f2)"
else
    fail 20 "RBD image bench_image" "$RBD_CHECK"
fi

# ── Check 5: /mnt/ceph_data mounted (20 pts) ──────────────────────────────────
# Use --mountpoint (not --target) to verify /mnt/ceph_data is an actual mount point,
# not just a directory that happens to exist on a parent filesystem.
FSTYPE=$(findmnt -n -o FSTYPE --mountpoint /mnt/ceph_data 2>/dev/null || true)
if [ -n "$FSTYPE" ]; then
    pass 20 "/mnt/ceph_data is mounted" "fstype=${FSTYPE}"
elif mount | grep -qE ' /mnt/ceph_data (type| )'; then
    FSTYPE=$(mount | grep ' /mnt/ceph_data ' | awk '{print $5}' || echo "unknown")
    pass 20 "/mnt/ceph_data is mounted" "fstype=${FSTYPE} (via mount)"
else
    fail 20 "/mnt/ceph_data not mounted"
fi

# ── Check 6: Write test (10 pts) ──────────────────────────────────────────────
# Only attempt write test if the mount check passed (FSTYPE is set from above).
PROBE_FILE="/mnt/ceph_data/.judge_probe_$$"
PROBE_DATA="cephbench-judge-probe-$$"
if [ -n "${FSTYPE:-}" ] && printf "%s\n" "$PROBE_DATA" > "$PROBE_FILE" 2>/dev/null; then
    READ_BACK=$(cat "$PROBE_FILE" 2>/dev/null || echo "")
    rm -f "$PROBE_FILE" 2>/dev/null || true
    if [ "$READ_BACK" = "$PROBE_DATA" ]; then
        pass 10 "Write+read test on /mnt/ceph_data succeeded"
    else
        fail 10 "Write+read test" "read_back mismatch"
    fi
else
    fail 10 "Write test on /mnt/ceph_data" "not mounted or cannot write"
fi

# ── Output ────────────────────────────────────────────────────────────────────
if [ "$JSON_OUTPUT" -eq 1 ]; then
    python3 -c "
import json, sys
results = sys.argv[1:]
score = sum(int(r.split('[+')[1].split('pts]')[0]) for r in results if 'PASS' in r)
checks = []
for r in results:
    passed = 'PASS' in r and 'FAIL' not in r.split('PASS')[0]
    checks.append({'passed': passed, 'detail': r})
print(json.dumps({'score': score, 'total': 100, 'checks': checks}, indent=2))
" "${DETAILS[@]}"
else
    echo ""
    echo "=================================="
    echo "  CephBench Score: ${SCORE}/100"
    echo "=================================="
    for detail in "${DETAILS[@]}"; do
        echo "  ${detail}"
    done
    echo "=================================="
fi

[ "$SCORE" -eq 100 ] && exit 0 || exit 1
