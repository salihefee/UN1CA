#!/usr/bin/env bash
# Copyright (c) 2026 Salvo Giangreco
# SPDX-License-Identifier: GPL-3.0-or-later

# Exercise make_rom's cache lifecycle without firmware or image/APK build tools.
set -e

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

export SRC_DIR="$TEST_DIR/src"
export OUT_DIR="$TEST_DIR/out"
export FW_DIR="$OUT_DIR/fw"
export WORK_DIR="$OUT_DIR/work"
export APKTOOL_DIR="$OUT_DIR/apktool"
export SOURCE_FIRMWARE="SOURCE/CSC/identifier"
export TARGET_FIRMWARE="TARGET/CSC/identifier"
export TARGET_PLATFORM=none TARGET_CODENAME=test ROM_VERSION=fixture

mkdir -p "$SRC_DIR/scripts/utils" "$SRC_DIR/scripts/internal" "$SRC_DIR/unica" \
    "$SRC_DIR/target/test" "$FW_DIR/SOURCE_CSC" "$FW_DIR/TARGET_CSC"
touch "$FW_DIR/SOURCE_CSC/.extracted" "$FW_DIR/TARGET_CSC/.extracted"
echo 'initial source' > "$SRC_DIR/target/test/config.sh"

cat > "$SRC_DIR/scripts/utils/build_utils.sh" <<'EOF'
LOG_STEP_IN() { :; }
LOG_STEP_OUT() { :; }
LOGW() { :; }
LOGE() { echo "$*" >&2; }
GET_PROP() { echo "$ROM_VERSION"; }
EOF
cat > "$SRC_DIR/scripts/internal/create_work_dir.sh" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$WORK_DIR"
EOF
cat > "$SRC_DIR/scripts/internal/create_target_files_zip.sh" <<'EOF'
#!/usr/bin/env bash
COUNT=0
if [ -f "$OUT_DIR/generations" ]; then COUNT="$(cat "$OUT_DIR/generations")"; fi
COUNT=$((COUNT + 1))
echo "$COUNT" > "$OUT_DIR/generations"
echo "generation=$COUNT" > "$1"
EOF
cat > "$SRC_DIR/scripts/build_flashable_zip.sh" <<'EOF'
#!/usr/bin/env bash
cat "$1" > "$OUT_DIR/packaged"
EOF
chmod +x "$SRC_DIR/scripts/internal/"*.sh "$SRC_DIR/scripts/build_flashable_zip.sh"

ARCHIVE="$OUT_DIR/test_fixture-target_files.zip"
echo 'stale archive' > "$ARCHIVE"

# A successful ROM rebuild must replace an existing archive before packaging.
bash "$REPO_DIR/scripts/make_rom.sh" --build-rom-zip > "$OUT_DIR/build.log" 2>&1
[[ "$(cat "$OUT_DIR/generations")" == "1" ]]
[[ "$(cat "$OUT_DIR/packaged")" == "generation=1" ]]

# An unchanged work directory can reuse its fresh archive.
bash "$REPO_DIR/scripts/make_rom.sh" --build-rom-zip > "$OUT_DIR/build.log" 2>&1
[[ "$(cat "$OUT_DIR/generations")" == "1" ]]

echo 'changed source' > "$SRC_DIR/target/test/config.sh"
bash "$REPO_DIR/scripts/make_rom.sh" --build-rom-zip > "$OUT_DIR/build.log" 2>&1
[[ "$(cat "$OUT_DIR/generations")" == "2" ]]
[[ "$(cat "$OUT_DIR/packaged")" == "generation=2" ]]

bash "$REPO_DIR/scripts/make_rom.sh" --force --build-rom-zip > "$OUT_DIR/build.log" 2>&1
[[ "$(cat "$OUT_DIR/generations")" == "3" ]]

# A separate build-only run must invalidate its previously generated archive.
touch -d '2000-01-01' "$ARCHIVE"
echo 'another source change' > "$SRC_DIR/target/test/config.sh"
bash "$REPO_DIR/scripts/make_rom.sh" --no-target-files > "$OUT_DIR/build.log" 2>&1
[[ "$(cat "$OUT_DIR/generations")" == "3" ]]
bash "$REPO_DIR/scripts/make_rom.sh" --build-rom-zip > "$OUT_DIR/build.log" 2>&1
[[ "$(cat "$OUT_DIR/generations")" == "4" ]]
[[ "$(cat "$OUT_DIR/packaged")" == "generation=4" ]]

rm "$ARCHIVE"
bash "$REPO_DIR/scripts/make_rom.sh" --build-rom-zip > "$OUT_DIR/build.log" 2>&1
[[ "$(cat "$OUT_DIR/generations")" == "5" ]]

echo 'Target-files rebuild, reuse, deferred packaging and forced-build checks passed.'
