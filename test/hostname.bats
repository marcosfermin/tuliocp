#!/usr/bin/env bats
#
# Regression tests for the hostname change helpers.
#
# They run against the repository sources and need neither an installed panel
# nor root, so they can be run straight from a working copy:
#
#   test/test_helper/bats-core/bin/bats test/hostname.bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    source "$REPO_ROOT/func/hosts.sh"
    source "$REPO_ROOT/func/webmail.sh"
    FIXTURES="${BATS_TEST_DIRNAME}/fixtures/hostname"
    WORKDIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$WORKDIR"
}

# Render a fixture and compare the result byte for byte with the expected file.
assert_renders_to() {
    local fixture="$1" old="$2" new="$3" expected="$4"

    hosts_render "$old" "$new" < "$FIXTURES/$fixture" > "$WORKDIR/rendered"
    run diff -u "$FIXTURES/$expected" "$WORKDIR/rendered"
    assert_success
}

#----------------------------------------------------------#
#                    Reported defect                       #
#----------------------------------------------------------#

@test "hosts: hostname mapped on a real address is renamed in place" {
    # The reported defect: the old mapping was left untouched and a second,
    # loopback mapping of the new hostname was appended.
    run hosts_render demo.tuliocp.com panel.tuliocp.com < "$FIXTURES/real-address.hosts"
    assert_success
    assert_line --index 0 "127.0.0.1 localhost"
    assert_line --index 1 "45.79.177.40 panel.tuliocp.com panel"
    assert_equal "${#lines[@]}" 2
    refute_output --partial "demo.tuliocp.com"
}

@test "hosts: the panel FQDN is never added to 127.0.0.1 on its own" {
    run hosts_render demo.tuliocp.com panel.tuliocp.com < "$FIXTURES/no-mapping.hosts"
    assert_success
    assert_line "127.0.1.1 panel.tuliocp.com panel"
    refute_line --regexp "^127\.0\.0\.1.*panel\.tuliocp\.com"
}

#----------------------------------------------------------#
#                        Variants                          #
#----------------------------------------------------------#

@test "hosts: unrelated aliases and the address are preserved" {
    run hosts_render demo.tuliocp.com panel.tuliocp.com < "$FIXTURES/multi-alias.hosts"
    assert_success
    assert_line "45.79.177.40 panel.tuliocp.com panel mail.example.org git"
    assert_line "10.0.0.5 build.example.org build"
}

@test "hosts: the Debian 127.0.1.1 slot is renamed rather than duplicated" {
    run hosts_render demo.tuliocp.com panel.tuliocp.com < "$FIXTURES/loopback-fqdn.hosts"
    assert_success
    assert_line --index 0 "127.0.0.1 localhost"
    assert_line --index 1 "127.0.1.1 panel.tuliocp.com panel"
    assert_equal "${#lines[@]}" 2
}

@test "hosts: a real address wins over a loopback copy of the same name" {
    run hosts_render demo.tuliocp.com panel.tuliocp.com < "$FIXTURES/split-mapping.hosts"
    assert_success
    assert_line --index 0 "127.0.0.1 localhost"
    assert_line --index 1 "45.79.177.40 panel.tuliocp.com panel"
    assert_equal "${#lines[@]}" 2
}

@test "hosts: an FQDN already on 127.0.0.1 stays there, behind localhost" {
    run hosts_render demo.tuliocp.com panel.tuliocp.com < "$FIXTURES/localhost-shared.hosts"
    assert_success
    assert_output "127.0.0.1 localhost panel.tuliocp.com panel"
}

@test "hosts: comments, blank lines and tabs are left alone" {
    assert_renders_to comments.hosts demo.tuliocp.com panel.tuliocp.com comments.expected
}

@test "hosts: mappings that carry neither hostname come out byte for byte" {
    # The reported overreach: unrelated entries were reformatted as a side
    # effect of the rename. Their spacing was collapsed, a repeated alias was
    # silently dropped and a loopback name was hoisted to the front of the
    # list, all on lines that never mentioned either hostname.
    assert_renders_to untouched.hosts demo.tuliocp.com panel.tuliocp.com untouched.expected
}

@test "hosts: a repeated alias on an unrelated mapping is not deduplicated" {
    run hosts_render demo.tuliocp.com panel.tuliocp.com < "$FIXTURES/untouched.hosts"
    assert_success
    assert_line "10.0.0.5    build.example.org    build   build   # CI worker"
}

@test "hosts: a loopback name on an unrelated mapping keeps its position" {
    run hosts_render demo.tuliocp.com panel.tuliocp.com < "$FIXTURES/untouched.hosts"
    assert_success
    assert_line "192.168.15.15   apt.internal apt localhost4 mirror"
}

@test "hosts: every unrelated line survives a rename and a rename back" {
    hosts_render demo.tuliocp.com panel.tuliocp.com \
        < "$FIXTURES/untouched.hosts" > "$WORKDIR/once"
    hosts_render panel.tuliocp.com demo.tuliocp.com \
        < "$WORKDIR/once" > "$WORKDIR/back"

    # Only the panel's own mapping differs from the original, and only in the
    # spacing the rename had to rewrite.
    # diff exits non-zero because the files differ, which is the point: the
    # assertion is on which lines differ.
    run diff --unchanged-line-format='' --old-line-format='%L' --new-line-format='' \
        "$FIXTURES/untouched.hosts" "$WORKDIR/back"
    assert_output "   45.79.177.40   demo.tuliocp.com   demo    # panel"
}

@test "hosts: an unrelated mapping is untouched when the hostname is not in the file" {
    # No mapping owns the hostname, so a new one is appended - and that is the
    # only difference, the existing entries are still copied out unchanged.
    printf '10.0.0.5    build.example.org    build   build\n' > "$WORKDIR/hosts"
    run hosts_render demo.tuliocp.com panel.tuliocp.com < "$WORKDIR/hosts"
    assert_success
    assert_line --index 0 "10.0.0.5    build.example.org    build   build"
    assert_line --index 1 "127.0.1.1 panel.tuliocp.com panel"
    assert_equal "${#lines[@]}" 2
}

@test "hosts: duplicate mappings of the old and new hostname collapse into one" {
    run hosts_render demo.tuliocp.com panel.tuliocp.com < "$FIXTURES/duplicates.hosts"
    assert_success
    assert_line --index 0 "127.0.0.1 localhost"
    assert_line --index 1 "45.79.177.40 panel.tuliocp.com panel"
    assert_equal "${#lines[@]}" 2
}

@test "hosts: an unrelated alias sharing the short name is kept" {
    run hosts_render demo.tuliocp.com panel.tuliocp.com < "$FIXTURES/short-name-clash.hosts"
    assert_success
    assert_line "10.0.0.7 demo.example.org demo"
    assert_line "45.79.177.40 panel.tuliocp.com panel"
}

@test "hosts: an unqualified old hostname is matched on its bare name" {
    run hosts_render demo panel.tuliocp.com < "$FIXTURES/unqualified.hosts"
    assert_success
    assert_line "45.79.177.40 panel.tuliocp.com panel"
    refute_output --partial "10.0.0.9 demo.example.org panel"
}

@test "hosts: IPv6 loopback boilerplate is preserved" {
    run hosts_render demo.tuliocp.com panel.tuliocp.com < "$FIXTURES/ipv6.hosts"
    assert_success
    assert_line "::1 localhost ip6-localhost ip6-loopback"
    assert_line "ff02::1 ip6-allnodes"
    assert_line "45.79.177.40 panel.tuliocp.com panel"
}

@test "hosts: rendering is idempotent" {
    hosts_render demo.tuliocp.com panel.tuliocp.com \
        < "$FIXTURES/multi-alias.hosts" > "$WORKDIR/once"
    hosts_render panel.tuliocp.com panel.tuliocp.com \
        < "$WORKDIR/once" > "$WORKDIR/twice"
    run diff -u "$WORKDIR/once" "$WORKDIR/twice"
    assert_success
}

@test "hosts: renaming back restores the original mapping" {
    hosts_render demo.tuliocp.com panel.tuliocp.com \
        < "$FIXTURES/multi-alias.hosts" > "$WORKDIR/once"
    hosts_render panel.tuliocp.com demo.tuliocp.com \
        < "$WORKDIR/once" > "$WORKDIR/back"
    run diff -u "$FIXTURES/multi-alias.hosts" "$WORKDIR/back"
    assert_success
}

#----------------------------------------------------------#
#                   File level behaviour                   #
#----------------------------------------------------------#

@test "hosts: update_etc_hosts rewrites the file and keeps its permissions" {
    cp "$FIXTURES/real-address.hosts" "$WORKDIR/hosts"
    chmod 0644 "$WORKDIR/hosts"

    run update_etc_hosts demo.tuliocp.com panel.tuliocp.com "$WORKDIR/hosts"
    assert_success
    assert_file_contains "$WORKDIR/hosts" "^45\.79\.177\.40 panel\.tuliocp\.com panel$"
    assert_file_permission 644 "$WORKDIR/hosts"
    # No temporary or backup file is left behind.
    run bash -c "ls '$WORKDIR' | wc -l"
    assert_output "1"
}

@test "hosts: update_etc_hosts leaves the file untouched when validation fails" {
    cp "$FIXTURES/real-address.hosts" "$WORKDIR/hosts"
    local before
    before="$(cat "$WORKDIR/hosts")"

    # Force the validation step to reject the rendered file.
    hosts_validate() { return 1; }

    run update_etc_hosts demo.tuliocp.com panel.tuliocp.com "$WORKDIR/hosts"
    assert_failure
    assert_equal "$(cat "$WORKDIR/hosts")" "$before"
    run bash -c "ls '$WORKDIR' | wc -l"
    assert_output "1"
}

@test "hosts: update_etc_hosts follows a symlinked hosts file" {
    cp "$FIXTURES/real-address.hosts" "$WORKDIR/hosts.real"
    ln -s "$WORKDIR/hosts.real" "$WORKDIR/hosts"

    run update_etc_hosts demo.tuliocp.com panel.tuliocp.com "$WORKDIR/hosts"
    assert_success
    assert_symlink_to "$WORKDIR/hosts.real" "$WORKDIR/hosts"
    assert_file_contains "$WORKDIR/hosts.real" "^45\.79\.177\.40 panel\.tuliocp\.com panel$"
}

@test "hosts: validation rejects a file that lost the hostname" {
    printf '127.0.0.1 localhost\n' > "$WORKDIR/candidate"
    run hosts_validate "$WORKDIR/candidate" panel.tuliocp.com demo.tuliocp.com ""
    assert_failure
    assert_output --partial "mapped 0 times"
}

@test "hosts: validation rejects a file that still maps the old hostname" {
    printf '127.0.0.1 localhost\n45.79.177.40 panel.tuliocp.com\n10.0.0.1 demo.tuliocp.com\n' \
        > "$WORKDIR/candidate"
    run hosts_validate "$WORKDIR/candidate" panel.tuliocp.com demo.tuliocp.com ""
    assert_failure
    assert_output --partial "still mapped"
}

@test "hosts: validation rejects an empty result" {
    : > "$WORKDIR/candidate"
    run hosts_validate "$WORKDIR/candidate" panel.tuliocp.com demo.tuliocp.com ""
    assert_failure
    assert_output --partial "empty"
}

@test "hosts: validation rejects the loss of the localhost mapping" {
    printf '127.0.0.1 localhost\n45.79.177.40 demo.tuliocp.com\n' > "$WORKDIR/reference"
    printf '45.79.177.40 panel.tuliocp.com\n' > "$WORKDIR/candidate"
    run hosts_validate "$WORKDIR/candidate" panel.tuliocp.com demo.tuliocp.com "$WORKDIR/reference"
    assert_failure
    assert_output --partial "localhost"
}

#----------------------------------------------------------#
#               Roundcube configuration                    #
#----------------------------------------------------------#

@test "roundcube: the host is written to the array the plugin reads" {
    cp "$FIXTURES/password-config.inc.php" "$WORKDIR/config.inc.php"

    run set_roundcube_option "$WORKDIR/config.inc.php" password_tulio_host panel.tuliocp.com
    assert_success
    run grep -Fx "\$config['password_tulio_host'] = 'panel.tuliocp.com';" "$WORKDIR/config.inc.php"
    assert_success
    assert_file_not_contains "$WORKDIR/config.inc.php" 'rcmail_config'
}

@test "roundcube: a legacy rcmail_config assignment is replaced, not duplicated" {
    cp "$FIXTURES/password-config-legacy.inc.php" "$WORKDIR/config.inc.php"

    run set_roundcube_option "$WORKDIR/config.inc.php" password_tulio_host panel.tuliocp.com
    assert_success
    run grep -c 'password_tulio_host' "$WORKDIR/config.inc.php"
    assert_output "1"
    run grep -Fx "\$config['password_tulio_host'] = 'panel.tuliocp.com';" "$WORKDIR/config.inc.php"
    assert_success
    assert_file_not_contains "$WORKDIR/config.inc.php" 'rcmail_config'
}

@test "roundcube: the exact line the old command wrote is replaced" {
    # Reproduces what v-change-sys-hostname used to leave in the file.
    printf '<?php\n$rcmail_config[%s] = %s;\n' \
        "'password_tulio_host'" "'demo.tuliocp.com'" > "$WORKDIR/config.inc.php"

    run set_roundcube_option "$WORKDIR/config.inc.php" password_tulio_host panel.tuliocp.com
    assert_success
    run cat "$WORKDIR/config.inc.php"
    assert_output "<?php
\$config['password_tulio_host'] = 'panel.tuliocp.com';"
}

@test "roundcube: unrelated settings are left alone" {
    cp "$FIXTURES/password-config.inc.php" "$WORKDIR/config.inc.php"

    set_roundcube_option "$WORKDIR/config.inc.php" password_tulio_host panel.tuliocp.com
    set_roundcube_option "$WORKDIR/config.inc.php" password_tulio_port 8083

    run grep -Fx '$config["password_driver"] = "tulio";' "$WORKDIR/config.inc.php"
    assert_success
    run grep -Fx '$config["password_minimum_length"] = 8;' "$WORKDIR/config.inc.php"
    assert_success
    run grep -Fx '$config["password_extra_host"] = "password_tulio_host";' "$WORKDIR/config.inc.php"
    assert_success
    # A comment that only mentions the setting is not an assignment.
    run grep -Fx '// password_tulio_host is written by v-change-sys-hostname' "$WORKDIR/config.inc.php"
    assert_success
}

@test "roundcube: the port setting is updated on its own" {
    cp "$FIXTURES/password-config.inc.php" "$WORKDIR/config.inc.php"

    run set_roundcube_option "$WORKDIR/config.inc.php" password_tulio_port 9999
    assert_success
    run grep -Fx "\$config['password_tulio_port'] = '9999';" "$WORKDIR/config.inc.php"
    assert_success
    run grep -Fx '$config["password_tulio_host"] = "localhost";' "$WORKDIR/config.inc.php"
    assert_success
}

@test "roundcube: the shipped driver reads the values that were written" {
    if ! command -v php > /dev/null; then
        skip "no PHP interpreter available"
    fi
    cp "$FIXTURES/password-config.inc.php" "$WORKDIR/config.inc.php"

    # Port 1 on the loopback address refuses the connection immediately, so the
    # driver reports the endpoint it built from the configuration.
    set_roundcube_option "$WORKDIR/config.inc.php" password_tulio_host 127.0.0.1
    set_roundcube_option "$WORKDIR/config.inc.php" password_tulio_port 1

    run php -l "$WORKDIR/config.inc.php"
    assert_success

    run php "$FIXTURES/driver-endpoint.php" "$WORKDIR/config.inc.php" \
        "$REPO_ROOT/install/common/roundcube/tulio.php"
    assert_success
    assert_output --partial "request to 127.0.0.1:1 failed"
    assert_output --partial "result=PASSWORD_CONNECT_ERROR"
    # The credentials the driver was handed are never written to the log.
    refute_output --partial "current-password"
    refute_output --partial "new-password"
}

@test "roundcube: a value containing quotes is escaped instead of breaking the file" {
    if ! command -v php > /dev/null; then
        skip "no PHP interpreter available"
    fi
    cp "$FIXTURES/password-config.inc.php" "$WORKDIR/config.inc.php"

    run set_roundcube_option "$WORKDIR/config.inc.php" password_tulio_host "it's\\bad"
    assert_success
    run php -r '$config = []; require $argv[1]; echo $config["password_tulio_host"];' \
        "$WORKDIR/config.inc.php"
    assert_success
    assert_output "it's\\bad"
}

@test "roundcube: reading back a setting prefers the array the plugin reads" {
    cp "$FIXTURES/password-config-legacy.inc.php" "$WORKDIR/config.inc.php"
    run get_roundcube_option "$WORKDIR/config.inc.php" password_tulio_host
    assert_success
    assert_output "demo.tuliocp.com"

    set_roundcube_option "$WORKDIR/config.inc.php" password_tulio_host panel.tuliocp.com
    run get_roundcube_option "$WORKDIR/config.inc.php" password_tulio_host
    assert_output "panel.tuliocp.com"
}

@test "roundcube: a file that does not parse is never installed" {
    if ! command -v php > /dev/null; then
        skip "no PHP interpreter available"
    fi
    cp "$FIXTURES/password-config-broken.inc.php" "$WORKDIR/config.inc.php"
    local before
    before="$(cat "$WORKDIR/config.inc.php")"

    run set_roundcube_option "$WORKDIR/config.inc.php" password_tulio_host panel.tuliocp.com
    assert_failure
    assert_equal "$(cat "$WORKDIR/config.inc.php")" "$before"
    run bash -c "ls '$WORKDIR' | wc -l"
    assert_output "1"
}
