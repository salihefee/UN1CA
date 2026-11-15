#!/usr/bin/env bash
set -e
MODPATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$(cd "$MODPATH/../../../.." && pwd)"
export SRC_DIR
source "$SRC_DIR/scripts/utils/common_utils.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
export WORK_DIR="$TEST_DIR"
export TARGET_OS_BUILD_SYSTEM_EXT_PARTITION=true
export DEBUG=false
mkdir -p "$WORK_DIR/vendor/etc/init" "$WORK_DIR/vendor/bin" "$WORK_DIR/vendor/firmware" "$WORK_DIR/configs"
cat > "$TEST_DIR/stock-proca.rc" <<'EOF'
# Process Authenticator startup
service proca /vendor/bin/vendor.samsung.hardware.security.proca@2.0-service
    class early_hal
    user system
    group system
    disabled

on late-fs
    wait_for_prop vendor.sys.qseecomd.enable true
    start proca
EOF
cp "$TEST_DIR/stock-proca.rc" "$WORK_DIR/vendor/etc/init/pa_daemon_qsee.rc"
printf 'unrelated-service\n' > "$WORK_DIR/vendor/etc/init/camera.rc"
printf 'binary-preserved\n' > "$WORK_DIR/vendor/bin/vendor.samsung.hardware.security.proca@2.0-service"
printf 'ta-preserved\n' > "$WORK_DIR/vendor/firmware/proca.mdt"
printf 'vendor/etc/init/pa_daemon_qsee.rc 0 0 644 capabilities=0x0\nvendor/etc/init/camera.rc 0 0 644 capabilities=0x0\n' > "$WORK_DIR/configs/fs_config-vendor"
printf '/vendor/etc/init/pa_daemon_qsee\\.rc u:object_r:vendor_configs_file:s0\n/vendor/etc/init/camera\\.rc u:object_r:vendor_configs_file:s0\n' > "$WORK_DIR/configs/file_context-vendor"
ABORT() { printf '%s\n' "$*" >&2; exit 1; }
source "$MODPATH/customize.sh"
[[ ! -e "$WORK_DIR/vendor/etc/init/pa_daemon_qsee.rc" ]]
if grep -q pa_daemon_qsee "$WORK_DIR/configs/fs_config-vendor" ||
        grep -q pa_daemon_qsee "$WORK_DIR/configs/file_context-vendor"; then
    echo 'Removed startup file still has filesystem metadata' >&2
    exit 1
fi
[[ "$(cat "$WORK_DIR/vendor/etc/init/camera.rc")" == unrelated-service ]]
[[ "$(cat "$WORK_DIR/vendor/bin/vendor.samsung.hardware.security.proca@2.0-service")" == binary-preserved ]]
[[ "$(cat "$WORK_DIR/vendor/firmware/proca.mdt")" == ta-preserved ]]
[[ "$(wc -l < "$WORK_DIR/configs/fs_config-vendor")" == 1 ]]
[[ "$(wc -l < "$WORK_DIR/configs/file_context-vendor")" == 1 ]]
# Reapplication is harmless.
source "$MODPATH/customize.sh"
# A changed file containing an unrelated service must be rejected before removal.
cp "$TEST_DIR/stock-proca.rc" "$WORK_DIR/vendor/etc/init/pa_daemon_qsee.rc"
printf '\nservice camera /vendor/bin/camera\n' >> "$WORK_DIR/vendor/etc/init/pa_daemon_qsee.rc"
if (source "$MODPATH/customize.sh") > "$TEST_DIR/guard.log" 2>&1; then
    echo 'Unexpected multi-service file was accepted' >&2
    exit 1
fi
[[ -f "$WORK_DIR/vendor/etc/init/pa_daemon_qsee.rc" ]]
grep -q '^service camera ' "$WORK_DIR/vendor/etc/init/pa_daemon_qsee.rc"
echo 'PROCA startup removal, metadata cleanup, unrelated payload preservation, idempotence and future-firmware guard passed.'
