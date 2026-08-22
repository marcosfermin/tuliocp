#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Unit tests for func/syshealth.sh that run against the repository sources
# instead of an installed panel. A throwaway $TULIO tree and a stubbed
# $BIN/v-change-sys-config-value stand in for the real installation, so these
# tests can run in CI on a machine without TulioCP.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export REPO_ROOT

    TULIO="$BATS_TEST_TMPDIR/tulio"
    BIN="$TULIO/bin"
    export TULIO BIN

    mkdir -p "$TULIO/conf" "$BIN"

    # Stub of v-change-sys-config-value: append or replace KEY='VALUE'.
    cat > "$BIN/v-change-sys-config-value" << 'STUB'
#!/bin/bash
key="$1"
value="$2"
conf="$TULIO/conf/tulio.conf"
if grep -q "^$key=" "$conf"; then
	sed -i "s|^$key=.*|$key='$value'|" "$conf"
else
	echo "$key='$value'" >> "$conf"
fi
STUB
    chmod +x "$BIN/v-change-sys-config-value"

    # syshealth_repair_system_config() re-reads the config through source_conf()
    # from func/main.sh, which pulls in the rest of the panel. Stub it out.
    source_conf() {
        # shellcheck disable=SC1090
        source "$1"
    }
    export -f source_conf

    # shellcheck source=../func/syshealth.sh
    source "$REPO_ROOT/func/syshealth.sh"
}

# Writes a minimal tulio.conf holding only the keys passed as arguments.
write_conf() {
    : > "$TULIO/conf/tulio.conf"
    for line in "$@"; do
        echo "$line" >> "$TULIO/conf/tulio.conf"
    done
}

conf_value() {
    grep "^$1=" "$TULIO/conf/tulio.conf" | head -n1 | cut -d= -f2- | tr -d "'"
}

@test "missing API_ALLOWED_IP defaults to 127.0.0.1, not allow-all" {
    write_conf "API='yes'"
    API='yes'

    run syshealth_repair_system_config
    [ "$status" -eq 0 ]

    [ "$(conf_value API_ALLOWED_IP)" = "127.0.0.1" ]
}

@test "repair never writes allow-all into tulio.conf" {
    write_conf "API='yes'"
    API='yes'

    run syshealth_repair_system_config
    [ "$status" -eq 0 ]

    run ! grep -q "allow-all" "$TULIO/conf/tulio.conf"
}

@test "repair announces the 127.0.0.1 default it is about to write" {
    write_conf "API='yes'"
    API='yes'

    run syshealth_repair_system_config
    [ "$status" -eq 0 ]

    [[ "$output" == *"API_ALLOWED_IP ('127.0.0.1')"* ]]
}

@test "an existing API_ALLOWED_IP value is left untouched" {
    write_conf "API='yes'" "API_ALLOWED_IP='203.0.113.7'"
    API='yes'

    run syshealth_repair_system_config
    [ "$status" -eq 0 ]

    [ "$(conf_value API_ALLOWED_IP)" = "203.0.113.7" ]
}

@test "no API_ALLOWED_IP key is added when the legacy API is disabled" {
    write_conf "API='no'"
    API='no'

    run syshealth_repair_system_config
    [ "$status" -eq 0 ]

    run ! grep -q "^API_ALLOWED_IP=" "$TULIO/conf/tulio.conf"
}

@test "func/syshealth.sh source contains no allow-all default" {
    run ! grep -q "allow-all" "$REPO_ROOT/func/syshealth.sh"
}
