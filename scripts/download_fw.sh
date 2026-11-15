#!/usr/bin/env bash
# Copyright (c) 2025 Salvo Giangreco
# SPDX-License-Identifier: GPL-3.0-or-later

# [
source "$SRC_DIR/scripts/utils/firmware_utils.sh" || exit 1
source "$TOOLS_DIR/venv/bin/activate" || exit 1

FORCE=false

FIRMWARES=()
MODEL=""
CSC=""
IMEI=""
SERIAL_NO=""
LATEST_FIRMWARE=""
PINNED_FIRMWARE=""
ZIP_FILE=""

PREPARE_SCRIPT()
{
    local EXTRA_FIRMWARES=()
    local IGNORE_SOURCE=false
    local IGNORE_TARGET=false

    while [ "$#" != 0 ]; do
        if [[ "$1" == "--force" ]] || [[ "$1" == "-f" ]]; then
            FORCE=true
        elif [[ "$1" == "--ignore-source" ]]; then
            IGNORE_SOURCE=true
        elif [[ "$1" == "--ignore-target" ]]; then
            IGNORE_TARGET=true
        elif [[ "$1" == "-"* ]]; then
            LOGE "Unknown option: $1"
            PRINT_USAGE
            exit 1
        else
            EXTRA_FIRMWARES+=("$1")
        fi

        shift
    done

    if ! $IGNORE_SOURCE; then
        _CHECK_NON_EMPTY_PARAM "SOURCE_FIRMWARE" "$SOURCE_FIRMWARE" || exit 1
        FIRMWARES+=("$SOURCE_FIRMWARE")
        IFS=':' read -r -a SOURCE_EXTRA_FIRMWARES <<< "$SOURCE_EXTRA_FIRMWARES"
        if [ "${#SOURCE_EXTRA_FIRMWARES[@]}" -ge 1 ]; then
            FIRMWARES+=("${SOURCE_EXTRA_FIRMWARES[@]}")
        fi
    fi

    if ! $IGNORE_TARGET; then
        _CHECK_NON_EMPTY_PARAM "TARGET_FIRMWARE" "$TARGET_FIRMWARE" || exit 1
        FIRMWARES+=("$TARGET_FIRMWARE")
        IFS=':' read -r -a TARGET_EXTRA_FIRMWARES <<< "$TARGET_EXTRA_FIRMWARES"
        if [ "${#TARGET_EXTRA_FIRMWARES[@]}" -ge 1 ]; then
            FIRMWARES+=("${TARGET_EXTRA_FIRMWARES[@]}")
        fi
    fi

    if [ "${#EXTRA_FIRMWARES[@]}" -ge 1 ]; then
        FIRMWARES+=("${EXTRA_FIRMWARES[@]}")
    fi
}

PRINT_USAGE()
{
    echo "Usage: download_fw [options] <firmware>" >&2
    echo " --ignore-source : Skip parsing source firmware flags" >&2
    echo " --ignore-target : Skip parsing target firmware flags" >&2
    echo " -f, --force : Force firmware download" >&2
}

VERIFY_ODIN_PACKAGES()
{
    local FILE_NAME
    local LENGTH
    local STORED_HASH
    local CALCULATED_HASH

    while IFS= read -r f; do
        FILE_NAME="$(basename "$f")"
        LOG_STEP_IN "- Verifying $FILE_NAME..."

        FILE_NAME="${FILE_NAME%.md5}"

        # Samsung stores the output of `md5sum` at the very end of the file
        LENGTH="32" # Length of MD5 hash
        LENGTH="$((LENGTH + 2))" # 2 whitespace chars
        LENGTH="$((LENGTH + ${#FILE_NAME}))" # File name without .md5 extension
        LENGTH="$((LENGTH + 1))" # 1 newline char

        STORED_HASH="$(tail -c "$LENGTH" "$f" | cut -d " " -f 1 -s)"
        if [ ! "$STORED_HASH" ] || [[ "${#STORED_HASH}" != "32" ]]; then
            LOG "\033[0;31m! Expected hash could not be parsed\033[0m"
            exit 1
        fi

        CALCULATED_HASH="$(head -c-$LENGTH "$f" | md5sum | cut -d " " -f 1 -s)"

        if [[ "$STORED_HASH" != "$CALCULATED_HASH" ]]; then
            LOG "\033[0;31m! File is damaged\033[0m"
            exit 1
        fi

        LOG_STEP_OUT
    done < <(find "$ODIN_DIR/${MODEL}_${CSC}" -type f -name "*.md5")
}
# ]

PREPARE_SCRIPT "$@"

for i in "${FIRMWARES[@]}"; do
    PARSE_FIRMWARE_STRING "$i" || exit 1

    PINNED_FIRMWARE="$(GET_PINNED_FIRMWARE_VERSION "$i")" || exit 1
    LATEST_FIRMWARE="${PINNED_FIRMWARE:-$(GET_LATEST_FIRMWARE "$MODEL" "$CSC")}"
    if [ ! "$LATEST_FIRMWARE" ]; then
        LOGE "Latest available firmware could not be fetched"
        exit 1
    fi

    LOG_STEP_IN "- Processing $MODEL firmware with $CSC CSC"
    LOG "- Downloaded firmware: $(cat "$ODIN_DIR/${MODEL}_${CSC}/.downloaded" 2> /dev/null)"
    LOG "- Extracted firmware: $(cat "$FW_DIR/${MODEL}_${CSC}/.extracted" 2> /dev/null)"
    LOG "- Latest available firmware: $LATEST_FIRMWARE"

    LOG_STEP_IN

    if ! $FORCE; then
        if [ "$PINNED_FIRMWARE" ]; then
            # A valid extraction is sufficient even if a different archive was
            # downloaded later. That archive will not be used by this build.
            if [ -f "$FW_DIR/${MODEL}_${CSC}/.extracted" ] && \
                    FIRMWARE_VERSION_MATCHES "$(cat "$FW_DIR/${MODEL}_${CSC}/.extracted")" "$PINNED_FIRMWARE"; then
                LOG "\033[0;33m! This firmware has already been extracted, skipping\033[0m"
                LOG_STEP_OUT; LOG_STEP_OUT
                continue
            fi
            for MARKER in "$FW_DIR/${MODEL}_${CSC}/.extracted" "$ODIN_DIR/${MODEL}_${CSC}/.downloaded"; do
                if [ -f "$MARKER" ] && ! FIRMWARE_VERSION_MATCHES "$(cat "$MARKER")" "$PINNED_FIRMWARE"; then
                    LOGE "Cached firmware does not match $PINNED_FIRMWARE. Use --force to replace it."
                    exit 1
                fi
            done
        fi
        # Skip if firmware has been extracted and equal/newer than the one in FUS
        if [ -f "$FW_DIR/${MODEL}_${CSC}/.extracted" ]; then
            if COMPARE_SEC_BUILD_VERSION "$(cat "$FW_DIR/${MODEL}_${CSC}/.extracted")" "$LATEST_FIRMWARE"; then
                LOG "\033[0;33m! This firmware has already been extracted, skipping\033[0m"
                LOG_STEP_OUT; LOG_STEP_OUT
                continue
            fi
        fi

        # Skip if firmware has already been downloaded
        if [ -f "$ODIN_DIR/${MODEL}_${CSC}/.downloaded" ]; then
            if ! COMPARE_SEC_BUILD_VERSION "$(cat "$ODIN_DIR/${MODEL}_${CSC}/.downloaded")" "$LATEST_FIRMWARE"; then
                LOG "\033[0;33m! A newer firmware is available for download, use --force flag if you want to overwrite it\033[0m"
            else
                LOG "\033[0;33m! This firmware has already been downloaded\033[0m"
            fi
            LOG_STEP_OUT; LOG_STEP_OUT
            continue
        fi
    fi

    LOG "- Downloading firmware..."
    [ -f "$ODIN_DIR/${MODEL}_${CSC}/.downloaded" ] && rm -rf "$ODIN_DIR/${MODEL}_${CSC}"
    mkdir -p "$ODIN_DIR/${MODEL}_${CSC}"
    # Anan's samloader stores its logs in the current working directory, let's move into OUT_DIR just for this time
    DOWNLOAD_VERSION_ARGS=()
    if [ "$PINNED_FIRMWARE" ]; then
        DOWNLOAD_VERSION_ARGS=(-v "$(GET_FIRMWARE_DOWNLOAD_VERSION "$PINNED_FIRMWARE")")
    fi
    (
    cd "$OUT_DIR" || exit 1
    samloader -m "$MODEL" -r "$CSC" -i "$IMEI" -s "$SERIAL_NO" download \
        "${DOWNLOAD_VERSION_ARGS[@]}" -O "$ODIN_DIR/${MODEL}_${CSC}" 1> /dev/null || exit 1
    )

    ZIP_FILE="$(find "$ODIN_DIR/${MODEL}_${CSC}" -name "*.zip" | sort -r | head -n 1)"
    if [ ! "$ZIP_FILE" ] || [ ! -f "$ZIP_FILE" ]; then
        LOG "\033[0;31m! Download failed\033[0m"
        exit 1
    fi

    LOG "- Extracting $(basename "$ZIP_FILE")..."
    EVAL "unzip -o \"$ZIP_FILE\" -d \"$ODIN_DIR/${MODEL}_${CSC}\" && rm -rf \"$ZIP_FILE\"" || exit 1

    VERIFY_ODIN_PACKAGES

    # FUS may substitute a newer package even when an older version is requested.
    # Do not label that package as the requested version.
    if [ "$PINNED_FIRMWARE" ]; then
        for COMPONENT in "AP:1" "CSC:2" "CP:3"; do
            PREFIX="${COMPONENT%:*}"
            VERSION="$(cut -d "/" -f "${COMPONENT#*:}" <<< "$PINNED_FIRMWARE")"
            PATTERN="${PREFIX}_${VERSION}_*.md5"
            [[ "$PREFIX" == "CSC" ]] && PATTERN="CSC_*${VERSION}_*.md5"
            if ! find "$ODIN_DIR/${MODEL}_${CSC}" -maxdepth 1 -name "$PATTERN" -print -quit | grep -q .; then
                LOGE "Samsung returned a different $PREFIX firmware than $PINNED_FIRMWARE"
                exit 1
            fi
        done
    fi

    echo -n "$LATEST_FIRMWARE" > "$ODIN_DIR/${MODEL}_${CSC}/.downloaded"

    LOG_STEP_OUT; LOG_STEP_OUT
done

deactivate

exit 0
