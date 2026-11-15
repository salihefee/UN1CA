# Copyright (c) 2026 Salvo Giangreco
# SPDX-License-Identifier: GPL-3.0-or-later

# Based on fsrb-android-dev/UN1CA's SM8550 camera fix through 8413d4a1d1d.
# The S22 donor lacks AI clear zoom and carries different night/HDR/RAW libs.
CAMERA_LIBRARIES=(
    "libSwIsp_core.camera.samsung.so"
    "libSwIsp_wrapper_v1.camera.samsung.so"
    "libacz_hhdr.arcsoft.so"
    "libaiclearzoom_raw.arcsoft.so"
    "libaiclearzoomraw_wrapper_v1.camera.samsung.so"
    "libsuperresolutionraw_wrapper_v2.camera.samsung.so"
    "libsuperresolution_raw.arcsoft.so"
    "libae_bracket_hdr.arcsoft.so"
)

for LIBRARY in "${CAMERA_LIBRARIES[@]}"; do
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/$LIBRARY" \
        0 0 644 "u:object_r:system_lib_file:s0"
done

TARGET_FIRMWARE_PATH="$(cut -d "/" -f 1 <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 <<< "$TARGET_FIRMWARE")"
for CONFIG in arcsoft camera.samsung; do
    STOCK_LIST="$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/etc/public.libraries-$CONFIG.txt"
    WORK_LIST="$WORK_DIR/system/system/etc/public.libraries-$CONFIG.txt"
    if [ ! -f "$STOCK_LIST" ] || [ ! -f "$WORK_LIST" ]; then
        ABORT "Missing stock or donor public.libraries-$CONFIG.txt"
    fi

    # Keep donor declarations; expose only restored libraries declared by stock.
    # Copying the entire stock list would declare other, absent S23 libraries.
    for LIBRARY in "${CAMERA_LIBRARIES[@]}"; do
        if grep -q -x -F "$LIBRARY" "$STOCK_LIST" && ! grep -q -x -F "$LIBRARY" "$WORK_LIST"; then
            LOG "- Exposing $LIBRARY in public.libraries-$CONFIG.txt"
            printf '%s\n' "$LIBRARY" >> "$WORK_LIST"
        fi
    done
done

unset CAMERA_LIBRARIES LIBRARY TARGET_FIRMWARE_PATH CONFIG STOCK_LIST WORK_LIST
