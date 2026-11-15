#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_UNDER_TEST="${1:-$REPO_DIR/scripts/internal/create_work_dir.sh}"
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT
export SRC_DIR="$FIXTURE_DIR/source"
export FW_DIR="$FIXTURE_DIR/fw"
export WORK_DIR="$FIXTURE_DIR/work"
export SOURCE_FIRMWARE="SM-SRC/TST/00000000"
export TARGET_FIRMWARE="SM-TGT/TST/00000000"
export SOURCE_FIRMWARE_VERSION=latest TARGET_FIRMWARE_VERSION=latest
export TARGET_OS_BUILD_SYSTEM_EXT_PARTITION=true TARGET_KEEP_ORIGINAL_SIGN=true
export DEBUG=false
mkdir -p "$SRC_DIR/scripts/utils"
for FILE in common_utils firmware_utils log_utils; do
    ln -s "$REPO_DIR/scripts/utils/$FILE.sh" "$SRC_DIR/scripts/utils/$FILE.sh"
done
# Exercise firmware copying without checking/building unrelated ROM tools.
# shellcheck disable=SC2016
echo 'source "$SRC_DIR/scripts/utils/common_utils.sh"' > "$SRC_DIR/scripts/utils/build_utils.sh"
mkdir -p "$FW_DIR/SM-SRC_TST/system/system/bin" "$FW_DIR/SM-SRC_TST/odm/etc" \
    "$FW_DIR/SM-TGT_TST/vendor_dlkm/lib/modules" "$FW_DIR/SM-TGT_TST/kernel" \
    "$WORK_DIR/system/system/bin" "$WORK_DIR/vendor_dlkm/lib/modules" "$WORK_DIR/kernel"
printf 'ro.product.device=fixture\n' > "$FW_DIR/SM-SRC_TST/system/system/build.prop"
printf 'ro.product.odm.device=fixture\n' > "$FW_DIR/SM-SRC_TST/odm/etc/build.prop"
printf '/system u:object_r:system_file:s0\n' > "$FW_DIR/SM-SRC_TST/file_context-system"
printf 'system 0 0 755 capabilities=0x0\n' > "$FW_DIR/SM-SRC_TST/fs_config-system"
printf '/vendor_dlkm u:object_r:vendor_file:s0\n' > "$FW_DIR/SM-TGT_TST/file_context-vendor_dlkm"
printf 'vendor_dlkm 0 0 755 capabilities=0x0\n' > "$FW_DIR/SM-TGT_TST/fs_config-vendor_dlkm"

CHECK_FILES=(system/system/bin/fixture vendor_dlkm/lib/modules/fixture.ko kernel/boot.img)
for RELATIVE in "${CHECK_FILES[@]}"; do
    if [[ "$RELATIVE" == system/* ]]; then
        INPUT="$FW_DIR/SM-SRC_TST/$RELATIVE"
    else
        INPUT="$FW_DIR/SM-TGT_TST/$RELATIVE"
    fi
    # Same length and timestamp, different contents: Samsung's firmware pattern.
    printf 'new-binary\n' > "$INPUT"
    printf 'old-binary\n' > "$WORK_DIR/$RELATIVE"
    touch -t 202201010000 "$INPUT" "$WORK_DIR/$RELATIVE"
done
bash "$SCRIPT_UNDER_TEST" > "$FIXTURE_DIR/create-work-dir.log" 2>&1 || {
    cat "$FIXTURE_DIR/create-work-dir.log" >&2
    exit 1
}
for RELATIVE in "${CHECK_FILES[@]}"; do
    if [[ "$RELATIVE" == system/* ]]; then
        INPUT="$FW_DIR/SM-SRC_TST/$RELATIVE"
    else
        INPUT="$FW_DIR/SM-TGT_TST/$RELATIVE"
    fi
    cmp "$INPUT" "$WORK_DIR/$RELATIVE"
done
printf 'Firmware copies replace stale donor, vendor module and kernel files with identical sizes/timestamps.\n'
