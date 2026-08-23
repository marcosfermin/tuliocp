#!/usr/bin/env bats
#
# Regression tests for certificate verification in the Roundcube password
# driver, which posts the mailbox password to the panel.
#
# They talk to a throwaway HTTPS endpoint on the loopback address and need
# neither an installed panel nor root:
#
#   test/test_helper/bats-core/bin/bats test/roundcube-tls.bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

setup_file() {
    export REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export DRIVER="$REPO_ROOT/install/common/roundcube/tulio.php"
    export HARNESS="${BATS_TEST_DIRNAME}/fixtures/hostname/driver-endpoint.php"
    export TLS_SERVER="${BATS_TEST_DIRNAME}/fixtures/roundcube/tls-server.php"

    command -v php > /dev/null || return 0
    command -v openssl > /dev/null || return 0

    export CERTDIR="$(mktemp -d)"

    # A throwaway CA, plus three certificates for the loopback endpoint:
    # one it issued, one nobody issued, and one it issued for another name.
    openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
        -subj "/CN=Tulio Test CA" \
        -addext "basicConstraints=critical,CA:TRUE" \
        -keyout "$CERTDIR/ca.key" -out "$CERTDIR/ca.crt" 2> /dev/null

    openssl req -newkey rsa:2048 -nodes -subj "/CN=127.0.0.1" \
        -keyout "$CERTDIR/trusted.key" -out "$CERTDIR/trusted.csr" 2> /dev/null
    openssl x509 -req -in "$CERTDIR/trusted.csr" -days 2 \
        -CA "$CERTDIR/ca.crt" -CAkey "$CERTDIR/ca.key" -CAcreateserial \
        -extfile <(printf 'subjectAltName=IP:127.0.0.1\n') \
        -out "$CERTDIR/trusted.crt" 2> /dev/null

    openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=127.0.0.1" \
        -addext "subjectAltName=IP:127.0.0.1" \
        -keyout "$CERTDIR/selfsigned.key" -out "$CERTDIR/selfsigned.crt" 2> /dev/null

    openssl req -newkey rsa:2048 -nodes -subj "/CN=other.example" \
        -keyout "$CERTDIR/othername.key" -out "$CERTDIR/othername.csr" 2> /dev/null
    openssl x509 -req -in "$CERTDIR/othername.csr" -days 2 \
        -CA "$CERTDIR/ca.crt" -CAkey "$CERTDIR/ca.key" -CAcreateserial \
        -extfile <(printf 'subjectAltName=DNS:other.example\n') \
        -out "$CERTDIR/othername.crt" 2> /dev/null
}

teardown_file() {
    [ -n "${CERTDIR:-}" ] && rm -rf "$CERTDIR"
}

setup() {
    REPO_ROOT="${REPO_ROOT:-$(cd "${BATS_TEST_DIRNAME}/.." && pwd)}"
    WORKDIR="$(mktemp -d)"
    SERVER_PID=""
}

teardown() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2> /dev/null
        wait "$SERVER_PID" 2> /dev/null
    fi
    rm -rf "$WORKDIR"
}

require_tools() {
    command -v php > /dev/null || skip "no PHP interpreter available"
    php -m | grep -qx curl || skip "PHP has no curl extension"
    php -m | grep -qx openssl || skip "PHP has no openssl extension"
    command -v openssl > /dev/null || skip "no openssl available"
}

# Start the throwaway endpoint with the given certificate and wait for its port.
start_endpoint() {
    local cert="$1" key="$2"

    REQUEST_LOG="$WORKDIR/request.log"
    php "$TLS_SERVER" "$cert" "$key" "$WORKDIR/port" "$REQUEST_LOG" &
    SERVER_PID=$!

    local waited=0
    while [ ! -s "$WORKDIR/port" ]; do
        sleep 0.1
        waited=$((waited + 1))
        if [ "$waited" -gt 100 ]; then
            fail "the test endpoint did not start"
        fi
    done
    PORT="$(cat "$WORKDIR/port")"
}

# Write a plugin configuration pointing at the endpoint. A second argument adds
# a CA bundle; without it the driver uses the system trust store.
write_config() {
    {
        echo "<?php"
        echo "\$config[\"password_tulio_host\"] = \"127.0.0.1\";"
        echo "\$config[\"password_tulio_port\"] = \"$PORT\";"
        if [ -n "${1:-}" ]; then
            echo "\$config[\"password_tulio_ca_file\"] = \"$1\";"
        fi
    } > "$WORKDIR/config.inc.php"
}

run_driver() {
    run php "$HARNESS" "$WORKDIR/config.inc.php" "$DRIVER"
}

#----------------------------------------------------------#
#                    Shipped source                        #
#----------------------------------------------------------#

@test "driver: parses as PHP" {
    command -v php > /dev/null || skip "no PHP interpreter available"
    run php -l "$DRIVER"
    assert_success
}

@test "driver: enables peer and hostname verification" {
    run grep -F 'CURLOPT_SSL_VERIFYPEER => true,' "$DRIVER"
    assert_success
    run grep -F 'CURLOPT_SSL_VERIFYHOST => 2,' "$DRIVER"
    assert_success
}

@test "driver: has no way to turn verification off" {
    run grep -nE 'CURLOPT_SSL_VERIFY(PEER|HOST)[[:space:]]*=>[[:space:]]*(false|0|null)' "$DRIVER"
    assert_failure
    run grep -nE '(CURLOPT_SSL_VERIFY(PEER|HOST)|CURLOPT_CAINFO)' "$DRIVER"
    assert_success
    # Verification is never made configurable, only the trust store is.
    refute_line --partial "password_tulio_verify"
}

#----------------------------------------------------------#
#                    Certificate handling                  #
#----------------------------------------------------------#

@test "driver: a trusted certificate completes the password change" {
    require_tools
    start_endpoint "$CERTDIR/trusted.crt" "$CERTDIR/trusted.key"
    write_config "$CERTDIR/ca.crt"

    run_driver
    assert_success
    assert_output --partial "result=PASSWORD_SUCCESS"

    # The request really reached the endpoint, at the configured address.
    assert_file_contains "$REQUEST_LOG" "^POST /reset/mail/ HTTP/"
    assert_file_contains "$REQUEST_LOG" "^Host: 127.0.0.1:$PORT"
    assert_file_contains "$REQUEST_LOG" "User-Agent: Tulio Control Panel Password Driver"
}

@test "driver: an untrusted certificate fails the password change" {
    require_tools
    start_endpoint "$CERTDIR/selfsigned.crt" "$CERTDIR/selfsigned.key"
    # No CA bundle: the system trust store does not know this certificate.
    write_config

    run_driver
    assert_success
    assert_output --partial "result=PASSWORD_CONNECT_ERROR"
    assert_output --partial "curl error 60"

    # Nothing was sent to the endpoint that could not be verified.
    assert_file_empty "$REQUEST_LOG"
    refute_output --partial "current-password"
    refute_output --partial "new-password"
}

@test "driver: a certificate issued for another name fails the password change" {
    require_tools
    start_endpoint "$CERTDIR/othername.crt" "$CERTDIR/othername.key"
    write_config "$CERTDIR/ca.crt"

    run_driver
    assert_success
    assert_output --partial "result=PASSWORD_CONNECT_ERROR"
    assert_file_empty "$REQUEST_LOG"
}

@test "driver: the same endpoint succeeds once its issuer is trusted" {
    require_tools
    # The self-signed certificate is accepted only when it is the trust anchor
    # the operator configured, which is the documented escape hatch.
    start_endpoint "$CERTDIR/selfsigned.crt" "$CERTDIR/selfsigned.key"
    write_config "$CERTDIR/selfsigned.crt"

    run_driver
    assert_success
    assert_output --partial "result=PASSWORD_SUCCESS"
    assert_file_contains "$REQUEST_LOG" "^POST /reset/mail/ HTTP/"
}

@test "driver: an unreadable CA bundle fails closed" {
    require_tools
    start_endpoint "$CERTDIR/trusted.crt" "$CERTDIR/trusted.key"
    write_config "$WORKDIR/missing-ca.crt"

    run_driver
    assert_success
    assert_output --partial "result=PASSWORD_CONNECT_ERROR"
    assert_output --partial "CA file is not readable"
    assert_file_empty "$REQUEST_LOG"
}
