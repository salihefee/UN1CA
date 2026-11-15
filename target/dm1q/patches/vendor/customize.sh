# The firmware extractor initializes capabilities to zero. These services ship
# with CAP_NET_BIND_SERVICE in S911BXXS8EZA1 and need it in the rebuilt image.
for BINARY in pd-mapper pm-service sensors.qti; do
    if [ ! -f "$WORK_DIR/vendor/bin/$BINARY" ]; then
        ABORT "File not found: vendor/bin/$BINARY"
    fi

    LOG "- Preserving CAP_NET_BIND_SERVICE for /vendor/bin/$BINARY"
    PATTERN="${BINARY//./\\.}"
    sed -i -E "/^vendor\/bin\/$PATTERN / s/capabilities=0x[[:xdigit:]]+/capabilities=0x400/" \
        "$WORK_DIR/configs/fs_config-vendor"
done

unset BINARY PATTERN
