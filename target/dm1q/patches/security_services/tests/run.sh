#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

MODPATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT
WORK_DIR="$FIXTURE_DIR/work"
INIT_DIR="$WORK_DIR/vendor/etc/init"
mkdir -p "$INIT_DIR"

cat > "$INIT_DIR/vaultkeeper_common.rc" <<'EOF'
# Deliberately put the similarly named, already-oneshot HAL first.
service vaultkeeper_hal /vendor/bin/vendor.samsung.hardware.security.vaultkeeper@2.0-service
    class early_hal
    user system
    group system
    oneshot
    disabled

service vaultkeeper /vendor/bin/vaultkeeperd
    class core
    user system
    group system
    disabled

on late-fs
    mkdir /dev/socket/vaultkeeper 0770 system system
    start vaultkeeper
    start vaultkeeper_hal
EOF
cat > "$INIT_DIR/cass.rc" <<'EOF'
service cass /vendor/bin/cass
    class core
    user system
    group radio wakelock system
    capabilities BLOCK_SUSPEND
    disabled

on post-fs-data
    start cass
EOF
cp "$INIT_DIR/vaultkeeper_common.rc" "$FIXTURE_DIR/vaultkeeper-original.rc"
cp "$INIT_DIR/cass.rc" "$FIXTURE_DIR/cass-original.rc"

LOG() { :; }
ABORT() { printf '%s\n' "$*" >&2; exit 1; }
source "$MODPATH/customize.sh"
cp "$INIT_DIR/vaultkeeper_common.rc" "$FIXTURE_DIR/vaultkeeper-patched.rc"
cp "$INIT_DIR/cass.rc" "$FIXTURE_DIR/cass-patched.rc"
source "$MODPATH/customize.sh"
cmp "$INIT_DIR/vaultkeeper_common.rc" "$FIXTURE_DIR/vaultkeeper-patched.rc"
cmp "$INIT_DIR/cass.rc" "$FIXTURE_DIR/cass-patched.rc"

python3 - "$FIXTURE_DIR" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
for basename,worker in [('vaultkeeper','vaultkeeper'),('cass','cass')]:
    before=(root/f'{basename}-original.rc').read_text()
    after=(root/f'{basename}-patched.rc').read_text()
    expected=[]
    for line in before.splitlines(keepends=True):
        expected.append(line)
        if line.startswith(f'service {worker} '):expected.append('    oneshot\n')
    assert after==''.join(expected),(worker,'unexpected service/trigger change')
    # Parse service blocks with exact names to check the relevant init options.
    def services(text):
        result={};active=None
        for line in text.splitlines():
            words=line.split()
            if not words or words[0].startswith('#'):continue
            if words[0]=='service':
                active=words[1];result[active]={'command':words[2:],'options':[]}
            elif words[0] in ('on','import'):active=None
            elif active:result[active]['options'].append(words)
        return result
    old=services(before);new=services(after)
    assert new[worker]['command']==old[worker]['command']
    assert ['oneshot'] in new[worker]['options']
    assert [o for o in new[worker]['options'] if o!=['oneshot']]==old[worker]['options']
    for other in old.keys()-{worker}:assert new[other]==old[other]
PY

# An unexpected firmware layout must fail rather than accidentally patch the HAL.
sed -i 's/^service vaultkeeper /service different_worker /' "$INIT_DIR/vaultkeeper_common.rc"
if ( source "$MODPATH/customize.sh" ) > "$FIXTURE_DIR/missing.log" 2>&1; then
    printf 'Missing worker declaration was incorrectly accepted.\n' >&2
    exit 1
fi
# Ambiguous duplicate declarations must also be rejected.
cp "$FIXTURE_DIR/vaultkeeper-original.rc" "$INIT_DIR/vaultkeeper_common.rc"
printf '\nservice vaultkeeper /vendor/bin/vaultkeeperd\n    disabled\n' >> "$INIT_DIR/vaultkeeper_common.rc"
if ( source "$MODPATH/customize.sh" ) > "$FIXTURE_DIR/duplicate.log" 2>&1; then
    printf 'Duplicate worker declarations were incorrectly accepted.\n' >&2
    exit 1
fi
printf 'Security-worker exact-block, HAL/trigger preservation, idempotence and layout guards passed.\n'
