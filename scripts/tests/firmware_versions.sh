#!/usr/bin/env bash
# Copyright (c) 2026 Salvo Giangreco
# SPDX-License-Identifier: GPL-3.0-or-later

# Exercise firmware selection and cache validation without network, sudo or build tools.
set -e

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

export SRC_DIR="$TEST_DIR/src"
export OUT_DIR="$TEST_DIR/out"
export FW_DIR="$OUT_DIR/fw"
export ODIN_DIR="$OUT_DIR/odin"
export TOOLS_DIR="$TEST_DIR/tools"
export WORK_DIR="$OUT_DIR/work"
export DEBUG=false
export SOURCE_FIRMWARE="SM-S901E/TUR/350999641234561"
export TARGET_FIRMWARE="SM-S911B/TUR/352404911234563"
export SOURCE_EXTRA_FIRMWARES="" TARGET_EXTRA_FIRMWARES=""
export SOURCE_PLATFORM_SDK_VERSION=36 TARGET_PLATFORM_SDK_VERSION=36
export SOURCE_FIRMWARE_VERSION=latest
export TARGET_FIRMWARE_VERSION="S911BXXS8EZA1/S911BOXM8EZA1/S911BXXU8EYI5"

mkdir -p "$SRC_DIR/scripts/utils" "$TOOLS_DIR/venv/bin" "$TEST_DIR/bin" "$ODIN_DIR/SM-S911B_TUR" "$FW_DIR/SM-S911B_TUR"
for FILE in common_utils firmware_utils log_utils; do
    ln -s "$REPO_DIR/scripts/utils/$FILE.sh" "$SRC_DIR/scripts/utils/$FILE.sh"
done
# shellcheck disable=SC2016
echo 'source "$SRC_DIR/scripts/utils/common_utils.sh"' > "$SRC_DIR/scripts/utils/build_utils.sh"
echo ':' > "$TOOLS_DIR/venv/bin/activate"

# Any accidental network access or download fails the cached-firmware cases.
for TOOL in curl samloader; do
    printf '#!/usr/bin/env bash\necho "Unexpected %s call" >&2\nexit 99\n' "$TOOL" > "$TEST_DIR/bin/$TOOL"
    chmod +x "$TEST_DIR/bin/$TOOL"
done
export PATH="$TEST_DIR/bin:$PATH"

source "$SRC_DIR/scripts/utils/firmware_utils.sh"

[[ "$(GET_PINNED_FIRMWARE_VERSION "$SOURCE_FIRMWARE")" == "" ]]
[[ "$(GET_PINNED_FIRMWARE_VERSION "$TARGET_FIRMWARE")" == "$TARGET_FIRMWARE_VERSION" ]]
[[ "$(GET_PINNED_FIRMWARE_VERSION "SM-OTHER/XXX/identifier")" == "" ]]
[[ "$(GET_FIRMWARE_DOWNLOAD_VERSION "$TARGET_FIRMWARE_VERSION")" == "$TARGET_FIRMWARE_VERSION/S911BXXS8EZA1" ]]
[[ "$(GET_FIRMWARE_DOWNLOAD_VERSION "PDA/CSC/MODEM")" == "PDA/CSC/MODEM/PDA" ]]
[[ "$(GET_FIRMWARE_DOWNLOAD_VERSION "PDA/CSC/MODEM/PDA")" == "PDA/CSC/MODEM/PDA" ]]
FIRMWARE_VERSION_MATCHES "$TARGET_FIRMWARE_VERSION" "$TARGET_FIRMWARE_VERSION/S911BXXS8EZA1"
if FIRMWARE_VERSION_MATCHES "$TARGET_FIRMWARE_VERSION" "S911BXXUAGZIF/S911BOXMAGZIF/S911BXXUAGZIF"; then
    echo "Different firmware versions compared equal" >&2
    exit 1
fi
if (SOURCE_FIRMWARE="$TARGET_FIRMWARE" SOURCE_FIRMWARE_VERSION="other"; GET_PINNED_FIRMWARE_VERSION "$TARGET_FIRMWARE") > "$OUT_DIR/conflict.log" 2>&1; then
    echo "Conflicting pins were accepted" >&2
    exit 1
fi

printf '%s' "$TARGET_FIRMWARE_VERSION" > "$ODIN_DIR/SM-S911B_TUR/.downloaded"
bash "$REPO_DIR/scripts/download_fw.sh" --ignore-source > "$OUT_DIR/download.log" 2>&1

printf '%s' "$TARGET_FIRMWARE_VERSION" > "$FW_DIR/SM-S911B_TUR/.extracted"
echo "unrelated/download/version" > "$ODIN_DIR/SM-S911B_TUR/.downloaded"
bash "$REPO_DIR/scripts/download_fw.sh" --ignore-source > "$OUT_DIR/download.log" 2>&1
rm "$FW_DIR/SM-S911B_TUR/.extracted"

echo "S911BXXUAGZIF/S911BOXMAGZIF/S911BXXUAGZIF" > "$ODIN_DIR/SM-S911B_TUR/.downloaded"
if bash "$REPO_DIR/scripts/download_fw.sh" --ignore-source > "$OUT_DIR/download.log" 2>&1; then
    echo "Mismatched downloaded firmware was accepted" >&2
    exit 1
fi
grep -q 'Cached firmware does not match' "$OUT_DIR/download.log"

printf '%s' "$TARGET_FIRMWARE_VERSION" > "$ODIN_DIR/SM-S911B_TUR/.downloaded"
printf '%s' "$TARGET_FIRMWARE_VERSION" > "$FW_DIR/SM-S911B_TUR/.extracted"
bash "$REPO_DIR/scripts/extract_fw.sh" --ignore-source > "$OUT_DIR/extract.log" 2>&1

echo "wrong/version/cached" > "$FW_DIR/SM-S911B_TUR/.extracted"
if bash "$REPO_DIR/scripts/extract_fw.sh" --ignore-source > "$OUT_DIR/extract.log" 2>&1; then
    echo "Mismatched extracted firmware was accepted" >&2
    exit 1
fi
grep -q 'Extracted firmware does not match' "$OUT_DIR/extract.log"

# make_rom may reuse existing extractions without invoking download_fw/extract_fw.
if bash "$REPO_DIR/scripts/internal/create_work_dir.sh" > "$OUT_DIR/work.log" 2>&1; then
    echo "Work directory accepted an extraction from another firmware" >&2
    exit 1
fi
grep -q 'TARGET firmware must be extracted from' "$OUT_DIR/work.log"
[[ ! -d "$WORK_DIR" ]]

printf '%s' "$TARGET_FIRMWARE_VERSION" > "$FW_DIR/SM-S911B_TUR/.extracted"
mkdir -p "$FW_DIR/SM-S911B_TUR/system/system"
echo 'ro.build.version.sdk=37' > "$FW_DIR/SM-S911B_TUR/system/system/build.prop"
if bash "$REPO_DIR/scripts/internal/create_work_dir.sh" > "$OUT_DIR/work.log" 2>&1; then
    echo "Work directory accepted Android 17 with an Android 16 configuration" >&2
    exit 1
fi
grep -q 'SDK 37 does not match configured SDK 36' "$OUT_DIR/work.log"
[[ ! -d "$WORK_DIR" ]]

# Reject the wrong download before --force removes an existing extraction.
echo 'wrong/download/version' > "$ODIN_DIR/SM-S911B_TUR/.downloaded"
if bash "$REPO_DIR/scripts/extract_fw.sh" --ignore-source --force > "$OUT_DIR/extract.log" 2>&1; then
    echo "Forced extraction accepted the wrong download" >&2
    exit 1
fi
grep -q 'Downloaded firmware does not match' "$OUT_DIR/extract.log"
[[ "$(cat "$FW_DIR/SM-S911B_TUR/.extracted")" == "$TARGET_FIRMWARE_VERSION" ]]

# Unpinned devices retain the existing latest-firmware cache behavior.
cat > "$TEST_DIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo '<latest>TEST_PDA/TEST_CSC/TEST_MODEM</latest>'
EOF
echo 'TEST_PDA/TEST_CSC/TEST_MODEM' > "$ODIN_DIR/SM-S911B_TUR/.downloaded"
rm "$FW_DIR/SM-S911B_TUR/.extracted"
TARGET_FIRMWARE_VERSION=latest \
    bash "$REPO_DIR/scripts/download_fw.sh" --ignore-source > "$OUT_DIR/latest.log" 2>&1

# Simulate a real download, including Samsung's appended TAR MD5 footers.
cat > "$TEST_DIR/bin/samloader" <<'EOF'
#!/usr/bin/env python3
import hashlib
import os
from pathlib import Path
import sys
import zipfile
args = sys.argv
expected = os.environ['TARGET_FIRMWARE_VERSION']
if expected == 'latest':
    assert '-v' not in args
else:
    assert args[args.index('-v') + 1] == expected + '/' + expected.split('/')[0]
directory = Path(args[args.index('-O') + 1])
version = os.environ.get('SERVER_FIRMWARE_VERSION', os.environ['TARGET_FIRMWARE_VERSION']).split('/')
with zipfile.ZipFile(directory / 'stock.zip', 'w') as archive:
    for prefix, build in [('AP', version[0]), ('CSC_OXM', version[1]), ('CP', version[2])]:
        name = f'{prefix}_{build}_test.tar'
        data = b'stock firmware fixture\n'
        footer = f'{hashlib.md5(data).hexdigest()}  {name}\n'.encode()
        archive.writestr(name + '.md5', data + footer)
EOF
chmod +x "$TEST_DIR/bin/samloader"
bash "$REPO_DIR/scripts/download_fw.sh" --ignore-source --force > "$OUT_DIR/download.log" 2>&1
FIRMWARE_VERSION_MATCHES "$(cat "$ODIN_DIR/SM-S911B_TUR/.downloaded")" "$TARGET_FIRMWARE_VERSION"

if SERVER_FIRMWARE_VERSION="S911BXXUAGZIF/S911BOXMAGZIF/S911BXXUAGZIF" \
        bash "$REPO_DIR/scripts/download_fw.sh" --ignore-source --force > "$OUT_DIR/download.log" 2>&1; then
    echo "A substituted firmware was accepted as the pinned version" >&2
    exit 1
fi
grep -q 'Samsung returned a different AP firmware' "$OUT_DIR/download.log"
[[ ! -f "$ODIN_DIR/SM-S911B_TUR/.downloaded" ]]

# Unpinned downloads must keep samloader's existing latest-version selection.
TARGET_FIRMWARE_VERSION=latest SERVER_FIRMWARE_VERSION="TEST_PDA/TEST_CSC/TEST_MODEM" \
    bash "$REPO_DIR/scripts/download_fw.sh" --ignore-source --force > "$OUT_DIR/latest-download.log" 2>&1
[[ "$(cat "$ODIN_DIR/SM-S911B_TUR/.downloaded")" == "TEST_PDA/TEST_CSC/TEST_MODEM" ]]

echo "Firmware version selection and cache checks passed."
