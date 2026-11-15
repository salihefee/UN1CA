# Copyright (c) 2026 Salvo Giangreco
# SPDX-License-Identifier: GPL-3.0-or-later

# Stock S23 vendor selects com.samsung.gamedriver.sm8550 via ro.gfx.driver.0.
# The S22 donor carries the SM8450 package instead.
DELETE_FROM_WORK_DIR "system" "system/priv-app/GameDriver-SM8450"
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" \
    "system/priv-app/GameDriver-SM8550" 0 0 755 "u:object_r:system_file:s0"
