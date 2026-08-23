#!/usr/bin/env bats
#
# Regression tests for demo mode and for the API enable semantics.
#
# The commands under test are copied into a throwaway panel tree and pointed at
# it, so nothing here reads or writes an installed panel: the one line that
# hardcodes /etc/tuliocp/tulio.conf is rewritten on the way in, and everything
# else already goes through $TULIO. Neither a panel nor root is needed, so this
# runs straight from a working copy:
#
#   test/test_helper/bats-core/bin/bats test/demo-mode.bats
#
# The point of the sandbox is that a test can put the panel *into* demo mode and
# take it back out again, which is exactly what must never be done to a live one.

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    FIXTURES="${BATS_TEST_DIRNAME}/fixtures/sysconfig"
    WORKDIR="$(mktemp -d)"
    source "$REPO_ROOT/func/sysconfig.sh"
    sandbox_create
}

teardown() {
    rm -rf "$WORKDIR"
}

#----------------------------------------------------------#
#                        Sandbox                           #
#----------------------------------------------------------#

# Build a panel tree the commands can be run against.
sandbox_create() {
    TULIO="$WORKDIR/usr/local/tulio"
    CONF="$TULIO/conf/tulio.conf"
    CALLS="$WORKDIR/calls.log"

    mkdir -p "$TULIO"/{bin,func,conf,log,web/api} "$WORKDIR/etc/tuliocp"
    cp "$REPO_ROOT"/func/*.sh "$TULIO/func/"
    cp "$FIXTURES/tulio.conf" "$CONF"
    printf 'export TULIO=%s\n' "'$TULIO'" > "$WORKDIR/etc/tuliocp/tulio.conf"
    printf '<?php\ndie("Error: Disabled");\n' > "$TULIO/web/api/index.php"
    : > "$CALLS"

    sandbox_command v-change-sys-demo-mode
    sandbox_command v-change-sys-api
    sandbox_command v-change-sys-config-value
    sandbox_command v-add-sys-api-ip

    # Everything the commands shell out to that is not under test. Each records
    # that it was called, so a test can tell a restart that happened from one
    # that was only claimed.
    sandbox_stub v-restart-web 0
    sandbox_stub v-restart-proxy 0
    sandbox_stub v-log-action 0
}

# Copy one command into the sandbox, pointed at the sandbox instead of at
# /etc/tuliocp. That path is the only thing in these scripts that is not
# relative to $TULIO.
sandbox_command() {
    local name="$1"
    sed "s#^source /etc/tuliocp/tulio.conf\$#source $WORKDIR/etc/tuliocp/tulio.conf#" \
        "$REPO_ROOT/bin/$name" > "$TULIO/bin/$name"
    chmod 0755 "$TULIO/bin/$name"
}

# Install a stand-in for a command, with a fixed exit code.
sandbox_stub() {
    local name="$1" code="$2"
    cat > "$TULIO/bin/$name" << EOF
#!/bin/bash
echo "\$(basename "\$0") \$*" >> "$CALLS"
exit $code
EOF
    chmod 0755 "$TULIO/bin/$name"
}

# Run a sandboxed command.
tulio() {
    local name="$1"
    shift
    "$TULIO/bin/$name" "$@"
}

# Read a key out of the sandbox configuration.
conf_value() {
    sysconfig_value "$1" "$CONF"
}

assert_conf() {
    assert_equal "$(conf_value "$1")" "$2"
}

# The layer that holds even when the configuration is hand-edited: the API
# entry point refuses every caller until its die() is commented out.
assert_api_endpoint() {
    local want="$1" line='die("Error: Disabled");'
    [ "$want" = 'on' ] && line="//$line"
    run grep -Fx "$line" "$TULIO/web/api/index.php"
    assert_success
}

# Put the sandbox into demo mode the way the command does.
sandbox_enter_demo_mode() {
    run tulio v-change-sys-demo-mode yes
    assert_success
    assert_conf DEMO_MODE yes
}

#----------------------------------------------------------#
#                  The configuration writer                #
#----------------------------------------------------------#

@test "sysconfig: a value is replaced in place and the file stays sorted" {
    run sysconfig_write DEMO_MODE yes "$CONF"
    assert_success
    assert_conf DEMO_MODE yes
    run bash -c "LC_ALL=C sort -C < '$CONF'"
    assert_success
}

@test "sysconfig: every other key survives a write" {
    local before
    before="$(grep -oE '^[A-Z][A-Z0-9_]*' "$CONF")"
    sysconfig_write DEMO_MODE yes "$CONF"
    assert_equal "$(grep -oE '^[A-Z][A-Z0-9_]*' "$CONF")" "$before"
    assert_conf WEB_SYSTEM apache2
    assert_conf API_ALLOWED_IP ""
}

@test "sysconfig: a key that is not there yet is added" {
    run sysconfig_write NEW_KEY somevalue "$CONF"
    assert_success
    assert_conf NEW_KEY somevalue
}

@test "sysconfig: an empty value is written and read back as empty" {
    sysconfig_write API_ALLOWED_IP "127.0.0.1" "$CONF"
    assert_conf API_ALLOWED_IP "127.0.0.1"
    run sysconfig_write API_ALLOWED_IP "" "$CONF"
    assert_success
    assert_conf API_ALLOWED_IP ""
    run grep -Fx "API_ALLOWED_IP=''" "$CONF"
    assert_success
}

@test "sysconfig: a repeated assignment is collapsed onto the first one" {
    printf "DEMO_MODE='no'\n" >> "$CONF"
    sysconfig_render DEMO_MODE yes < "$CONF" > "$WORKDIR/rendered"
    run grep -c '^DEMO_MODE=' "$WORKDIR/rendered"
    assert_output "1"
    run grep -Fx "DEMO_MODE='yes'" "$WORKDIR/rendered"
    assert_success
}

@test "sysconfig: an unsorted file keeps the order it was in" {
    cp "$FIXTURES/unsorted.conf" "$WORKDIR/unsorted.conf"
    run sysconfig_write DEMO_MODE yes "$WORKDIR/unsorted.conf"
    assert_success
    run head -n 1 "$WORKDIR/unsorted.conf"
    assert_output "ROOT_USER='admin'"
    run grep -Fx "DEMO_MODE='yes'" "$WORKDIR/unsorted.conf"
    assert_success
}

@test "sysconfig: the last assignment of a key is the one reported" {
    printf "DEMO_MODE='yes'\n" >> "$CONF"
    run sysconfig_value DEMO_MODE "$CONF"
    assert_success
    assert_output "yes"
}

@test "sysconfig: reading a key that is not set fails" {
    run sysconfig_value NOT_A_KEY "$CONF"
    assert_failure
    refute_output
}

@test "sysconfig: a value carrying a quote or a line break is refused" {
    local before
    before="$(cat "$CONF")"

    run sysconfig_write APP_NAME "it's broken" "$CONF"
    assert_failure
    assert_output --partial "may not contain"

    run sysconfig_write APP_NAME "$(printf 'two\nlines')" "$CONF"
    assert_failure

    assert_equal "$(cat "$CONF")" "$before"
}

@test "sysconfig: a key that is not a shell variable name is refused" {
    local before
    before="$(cat "$CONF")"
    run sysconfig_write "DEMO MODE" yes "$CONF"
    assert_failure
    assert_output --partial "invalid configuration key"
    run sysconfig_write "demo_mode; rm -rf /" yes "$CONF"
    assert_failure
    assert_equal "$(cat "$CONF")" "$before"
}

@test "sysconfig: a write leaves no temporary or backup file behind" {
    sysconfig_write DEMO_MODE yes "$CONF"
    run bash -c "ls '$TULIO/conf' | wc -l"
    assert_output "1"
}

@test "sysconfig: the file is untouched when the result fails its check" {
    local before
    before="$(cat "$CONF")"
    sysconfig_validate() { return 1; }

    run sysconfig_write DEMO_MODE yes "$CONF"
    assert_failure
    assert_equal "$(cat "$CONF")" "$before"
    run bash -c "ls '$TULIO/conf' | wc -l"
    assert_output "1"
}

@test "sysconfig: a bad write that lands on disk is rolled back" {
    local before
    before="$(cat "$CONF")"
    # Pass the check on the temporary file, fail it on the real one, which is
    # the only path that reaches the rename.
    sysconfig_validate() { [ "$1" = "$CONF" ] && return 1; return 0; }

    run sysconfig_write DEMO_MODE yes "$CONF"
    assert_failure
    assert_equal "$(cat "$CONF")" "$before"
    run bash -c "ls '$TULIO/conf' | wc -l"
    assert_output "1"
}

#----------------------------------------------------------#
#                       Entering demo mode                 #
#----------------------------------------------------------#

@test "demo mode: enabling it from a normal panel turns the API off with it" {
    run tulio v-change-sys-demo-mode yes
    assert_success

    assert_conf DEMO_MODE yes
    assert_conf API no
    assert_conf API_SYSTEM 0
    assert_conf API_ALLOWED_IP ""
    # The layer that holds even if the configuration is hand-edited.
    assert_api_endpoint off
}

@test "demo mode: enabling it restarts the web server and the proxy" {
    tulio v-change-sys-demo-mode yes
    run grep -c 'v-restart-web yes' "$CALLS"
    assert_output "1"
    run grep -c 'v-restart-proxy yes' "$CALLS"
    assert_output "1"
}

@test "demo mode: it is not enabled when the API cannot be turned off" {
    sandbox_stub v-change-sys-api 1

    run tulio v-change-sys-demo-mode yes
    assert_failure
    assert_output --partial "unable to disable the API"
    assert_conf DEMO_MODE no
    # A failure before the mode changed is a failure before the restart too.
    refute_line --partial "v-restart-web"
    run cat "$CALLS"
    refute_output --partial "v-restart-web"
}

@test "demo mode: enabling it again changes nothing and does not fail" {
    sandbox_enter_demo_mode
    : > "$CALLS"

    run tulio v-change-sys-demo-mode yes
    assert_success
    assert_output --partial "already yes"
    assert_conf DEMO_MODE yes
    run cat "$CALLS"
    refute_output --partial "v-restart-web"
}

#----------------------------------------------------------#
#            Leaving demo mode, from inside it             #
#----------------------------------------------------------#

@test "demo mode: it can be turned off while it is on" {
    # The reported defect: the disable path went through
    # v-change-sys-config-value, which check_tulio_demo_mode refuses while
    # DEMO_MODE is yes, so the command was blocked by the mode it was leaving.
    sandbox_enter_demo_mode

    run tulio v-change-sys-demo-mode no
    assert_success
    refute_output --partial "security restrictions"
    assert_conf DEMO_MODE no
}

@test "demo mode: turning it off leaves the API disabled and says so" {
    sandbox_enter_demo_mode

    run tulio v-change-sys-demo-mode no
    assert_success
    assert_conf API no
    assert_conf API_SYSTEM 0
    assert_conf API_ALLOWED_IP ""
    assert_output --partial "The API was left disabled"
    assert_output --partial "v-change-sys-api enable all"
    assert_api_endpoint off
}

@test "demo mode: turning it off restarts the web server and the proxy" {
    sandbox_enter_demo_mode
    : > "$CALLS"

    tulio v-change-sys-demo-mode no
    run grep -c 'v-restart-web yes' "$CALLS"
    assert_output "1"
    run grep -c 'v-restart-proxy yes' "$CALLS"
    assert_output "1"
}

@test "demo mode: a failed restart is reported and reaches the exit code" {
    sandbox_enter_demo_mode
    sandbox_stub v-restart-proxy 1

    run tulio v-change-sys-demo-mode no
    assert_failure
    assert_output --partial "proxy restart failed"
    # The value did land: the command failed after the change, not instead of it.
    assert_conf DEMO_MODE no
}

@test "demo mode: the configuration stays sorted and intact across a round trip" {
    local before
    before="$(grep -oE '^[A-Z][A-Z0-9_]*' "$CONF")"

    sandbox_enter_demo_mode
    tulio v-change-sys-demo-mode no

    assert_equal "$(grep -oE '^[A-Z][A-Z0-9_]*' "$CONF")" "$before"
    run bash -c "LC_ALL=C sort -C < '$CONF'"
    assert_success
}

@test "demo mode: an argument that is neither yes nor no is refused" {
    for bad in maybe "" YES; do
        run tulio v-change-sys-demo-mode "$bad"
        assert_failure
        assert_conf DEMO_MODE no
    done
}

@test "demo mode: no argument at all is refused" {
    run tulio v-change-sys-demo-mode
    assert_failure
    assert_output --partial "Usage:"
    assert_conf DEMO_MODE no
}

#----------------------------------------------------------#
#          What stays blocked while demo mode is on        #
#----------------------------------------------------------#

@test "demo mode: v-change-sys-config-value is still refused" {
    sandbox_enter_demo_mode

    run tulio v-change-sys-config-value THEME light
    assert_failure
    assert_output --partial "security restrictions"
    assert_conf THEME dark
}

@test "demo mode: the guard is not relaxed for DEMO_MODE itself" {
    # v-change-sys-demo-mode writes the value directly. Nothing else gained the
    # ability to, least of all the generic command.
    sandbox_enter_demo_mode

    run tulio v-change-sys-config-value DEMO_MODE no
    assert_failure
    assert_output --partial "security restrictions"
    assert_conf DEMO_MODE yes
}

@test "demo mode: v-change-sys-api is still refused" {
    sandbox_enter_demo_mode

    run tulio v-change-sys-api enable all
    assert_failure
    assert_output --partial "security restrictions"
    assert_conf API no
    assert_conf API_SYSTEM 0
}

@test "demo mode: v-add-sys-api-ip is still refused" {
    sandbox_enter_demo_mode

    run tulio v-add-sys-api-ip 45.79.177.40
    assert_failure
    assert_output --partial "security restrictions"
    assert_conf API_ALLOWED_IP ""
}

@test "demo mode: a superseded DEMO_MODE line cannot make the guard pass" {
    sandbox_enter_demo_mode
    # A shell sourcing the file would read the last assignment, and so does the
    # guard. An earlier line saying otherwise changes nothing.
    sed -i "1i DEMO_MODE='no'" "$CONF"

    run tulio v-change-sys-config-value THEME light
    assert_failure
    assert_output --partial "security restrictions"
}

#----------------------------------------------------------#
#                    API enable semantics                  #
#----------------------------------------------------------#

@test "api: enable with no version enables both, the same as 'all'" {
    # It used to set neither, leaving an operator with an uncommented endpoint,
    # a seeded allow list and an API that was still off.
    run tulio v-change-sys-api enable
    assert_success
    assert_conf API yes
    assert_conf API_SYSTEM 1
}

@test "api: enable all enables both and seeds a loopback-only allow list" {
    run tulio v-change-sys-api enable all
    assert_success
    assert_conf API yes
    assert_conf API_SYSTEM 1
    assert_conf API_ALLOWED_IP "127.0.0.1"
    assert_api_endpoint on
}

@test "api: an allow list that is already set is not re-seeded" {
    sysconfig_write API_ALLOWED_IP "127.0.0.1,45.79.177.40" "$CONF"
    run tulio v-change-sys-api enable all
    assert_success
    assert_conf API_ALLOWED_IP "127.0.0.1,45.79.177.40"
}

@test "api: enable legacy turns on the legacy API only" {
    run tulio v-change-sys-api enable legacy
    assert_success
    assert_conf API yes
    assert_conf API_SYSTEM 0
}

@test "api: enable api turns on the current API only" {
    run tulio v-change-sys-api enable api
    assert_success
    assert_conf API no
    assert_conf API_SYSTEM 1
}

@test "api: an unknown version is refused and nothing is changed" {
    run tulio v-change-sys-api enable everything
    assert_failure
    assert_conf API no
    assert_conf API_SYSTEM 0
    assert_conf API_ALLOWED_IP ""
    assert_api_endpoint off
}

@test "api: an unknown status is refused" {
    run tulio v-change-sys-api activate
    assert_failure
    assert_conf API no
}

@test "api: disable clears both flags and the allow list" {
    tulio v-change-sys-api enable all
    run tulio v-change-sys-api disable
    assert_success
    assert_conf API no
    assert_conf API_SYSTEM 0
    assert_conf API_ALLOWED_IP ""
    assert_api_endpoint off
}

@test "api: a failing configuration write is carried to the exit code" {
    sandbox_stub v-change-sys-config-value 1
    run tulio v-change-sys-api enable all
    assert_failure
    assert_output --partial "unable to set"
}

@test "api: the documented rollback sequence works end to end" {
    # Exactly what ROLLBACK-panel-demo-mode.md tells an operator to run.
    sandbox_enter_demo_mode

    run tulio v-change-sys-demo-mode no
    assert_success
    run tulio v-change-sys-api enable all
    assert_success
    run tulio v-add-sys-api-ip 45.79.177.40
    assert_success

    assert_conf DEMO_MODE no
    assert_conf API yes
    assert_conf API_SYSTEM 1
    assert_conf API_ALLOWED_IP "127.0.0.1,45.79.177.40"
    assert_api_endpoint on
}
