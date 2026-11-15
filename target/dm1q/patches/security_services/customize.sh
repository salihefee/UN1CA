# Copyright (c) 2026 UN1CA contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# This device's VaultKeeper initialization worker exits reporting a missing
# VK ID, and CASS exits while waiting for it. Retain their existing startup
# attempts, but do not respawn failed workers indefinitely. This does not repair
# provisioning or attestation. Keep the VaultKeeper HAL and framework service.
DM1Q_SECURITY_WORKER_ONESHOT()
{
    local FILE="$WORK_DIR/vendor/etc/init/$1"
    local SERVICE="$2"
    local DECLARATIONS

    [ -f "$FILE" ] || ABORT "File not found: vendor/etc/init/$1"
    DECLARATIONS="$(grep -c -E "^service $SERVICE " "$FILE" || true)"
    [[ "$DECLARATIONS" == "1" ]] || ABORT "Expected one $SERVICE service in vendor/etc/init/$1"

    # Check this exact service block, not similarly named services such as
    # vaultkeeper_hal or a oneshot option in an unrelated block.
    if awk -v service="$SERVICE" '
        $1 == "service" { selected = ($2 == service) }
        $1 == "on" || $1 == "import" { selected = 0 }
        selected && $1 == "oneshot" { found = 1 }
        END { exit !found }
    ' "$FILE"; then
        LOG "- $SERVICE already avoids automatic restart on exit"
    else
        LOG "- Keeping $SERVICE startup; preventing automatic restart after exit"
        sed -i "/^service $SERVICE /a\\    oneshot" "$FILE" || ABORT "Unable to update $SERVICE service"
    fi
}

DM1Q_SECURITY_WORKER_ONESHOT "vaultkeeper_common.rc" "vaultkeeper"
DM1Q_SECURITY_WORKER_ONESHOT "cass.rc" "cass"

unset -f DM1Q_SECURITY_WORKER_ONESHOT
