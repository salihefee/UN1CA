# Copyright (c) 2026 Salvo Giangreco
# SPDX-License-Identifier: GPL-3.0-or-later

# The common UN1CA kernel patch changes PROCA's kernel configuration and the
# debloat list removes proca.db. EZA1's remaining daemon fails its
# eight-byte /dev/proca_config read, exits and is restarted by init. It is a
# Process Authenticator, not a display service. Keep its binary/TA/kernel intact;
# remove only the startup file for this unsupported authentication path.
PROCA_INIT="$WORK_DIR/vendor/etc/init/pa_daemon_qsee.rc"
if [ ! -f "$PROCA_INIT" ]; then
    LOG "- Stock PROCA startup is already absent"
    unset PROCA_INIT
    return 0
fi

# Refuse to remove a future firmware file that also starts other services.
if [[ "$(grep -c '^service ' "$PROCA_INIT")" != "1" ]] || \
        ! grep -q -x -F 'service proca /vendor/bin/vendor.samsung.hardware.security.proca@2.0-service' "$PROCA_INIT" || \
        ! grep -q -E '^[[:space:]]+start proca[[:space:]]*$' "$PROCA_INIT"; then
    ABORT "Unexpected PROCA startup configuration; review before disabling it"
fi

DELETE_FROM_WORK_DIR "vendor" "etc/init/pa_daemon_qsee.rc"
unset PROCA_INIT
