#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# Exercise both plaintext-policy branches of the real module without apktool.
# Distinct fixture policies ensure recovery never receives the normal default.
# The fixture functions are called indirectly by the sourced module.
# shellcheck disable=SC2317
CHECK_POLICIES()
(
    local CASE="$1"
    export SRC_DIR="$FIXTURE_DIR/$CASE/source"
    export APKTOOL_DIR="$FIXTURE_DIR/$CASE/apktool"
    export MODPATH="$FIXTURE_DIR/$CASE/module"
    export TARGET_CODENAME="fixture"
    export DEBUG=false
    export SOURCE_DVFSAPP_CONFIG_DVFS_POLICY_FILENAME="dvfs_policy_default"
    export TARGET_DVFSAPP_CONFIG_DVFS_POLICY_FILENAME="dvfs_policy_default"
    export SOURCE_DVFSAPP_CONFIG_SSRM_POLICY_FILENAME="siop_source"
    export TARGET_DVFSAPP_CONFIG_SSRM_POLICY_FILENAME="$CASE"
    local ASSETS="$APKTOOL_DIR/system/priv-app/SamsungDeviceHealthManagerService/SamsungDeviceHealthManagerService.apk/assets"
    mkdir -p "$ASSETS" "$MODPATH/assets" "$SRC_DIR/target/fixture/dvfs"
    printf '<normal-policy/>\n' > "$MODPATH/assets/siop_default.xml"
    printf '<recovery-policy/>\n' > "$MODPATH/assets/ssrm_default.xml"
    touch "$ASSETS/siop_default" "$ASSETS/siop_model" "$ASSETS/ssrm_default"
    if [[ "$CASE" != "ssrm_default" ]]; then
        printf '<model-policy/>\n' > "$SRC_DIR/target/fixture/dvfs/siop_model.xml"
    fi

    LOG() { :; }
    LOGW() { printf '%s\n' "$*" >&2; }
    ABORT() { printf '%s\n' "$*" >&2; exit 1; }
    DECODE_APK() { :; }
    SMALI_PATCH() { :; }
    SET_FLOATING_FEATURE_CONFIG() { :; }
    EVAL() { eval "$1"; }
    source "$REPO_DIR/unica/patches/dvfs/customize.sh"

    cmp "$ASSETS/siop_default.xml" "$MODPATH/assets/siop_default.xml"
    cmp "$ASSETS/ssrm_default.xml" "$MODPATH/assets/ssrm_default.xml"
    if [[ "$CASE" != "ssrm_default" ]]; then
        cmp "$ASSETS/$CASE.xml" "$SRC_DIR/target/fixture/dvfs/siop_model.xml"
    fi
    for NAME in siop_default siop_model ssrm_default; do
        [[ ! -e "$ASSETS/$NAME" ]]
    done
)

CHECK_POLICIES ssrm_default
CHECK_POLICIES siop_fixture
printf 'Normal, model and recovery thermal policies are preserved in both branches.\n'
