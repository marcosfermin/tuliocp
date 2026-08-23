#!/usr/bin/env bats
#
# Regression tests for certificate verification in the phpMyAdmin sign-on
# client, which posts the panel API key to the panel and gets database
# credentials back.
#
# They talk to a throwaway HTTPS endpoint on the loopback address and need
# neither an installed panel nor root:
#
#   test/test_helper/bats-core/bin/bats test/pma-sso.bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

setup_file() {
    export REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export TEMPLATE="$REPO_ROOT/install/deb/phpmyadmin/tulio-sso.php"
    export HARNESS="${BATS_TEST_DIRNAME}/fixtures/phpmyadmin/sso-endpoint.php"
    export TLS_SERVER="${BATS_TEST_DIRNAME}/fixtures/roundcube/tls-server.php"

    command -v php > /dev/null || return 0
    command -v openssl > /dev/null || return 0

    export CERTDIR="$(mktemp -d)"

    # A throwaway CA, plus four certificates for the loopback endpoint: one it
    # issued for the address, one it issued for the name that address answers
    # to, one nobody issued, and one it issued for the panel's own name.
    openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
        -subj "/CN=Tulio Test CA" \
        -addext "basicConstraints=critical,CA:TRUE" \
        -keyout "$CERTDIR/ca.key" -out "$CERTDIR/ca.crt" 2> /dev/null

    issue() {
        local name="$1" subject="$2" san="$3"
        openssl req -newkey rsa:2048 -nodes -subj "$subject" \
            -keyout "$CERTDIR/$name.key" -out "$CERTDIR/$name.csr" 2> /dev/null
        openssl x509 -req -in "$CERTDIR/$name.csr" -days 2 \
            -CA "$CERTDIR/ca.crt" -CAkey "$CERTDIR/ca.key" -CAcreateserial \
            -extfile <(printf 'subjectAltName=%s\n' "$san") \
            -out "$CERTDIR/$name.crt" 2> /dev/null
    }

    issue trusted "/CN=127.0.0.1" "IP:127.0.0.1"
    issue byname "/CN=localhost" "DNS:localhost"
    issue panel "/CN=panel.tuliocp.com" "DNS:panel.tuliocp.com,DNS:demo.tuliocp.com"

    openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=127.0.0.1" \
        -addext "subjectAltName=IP:127.0.0.1" \
        -keyout "$CERTDIR/selfsigned.key" -out "$CERTDIR/selfsigned.crt" 2> /dev/null
}

teardown_file() {
    [ -n "${CERTDIR:-}" ] && rm -rf "$CERTDIR"
}

setup() {
    REPO_ROOT="${REPO_ROOT:-$(cd "${BATS_TEST_DIRNAME}/.." && pwd)}"
    source "$REPO_ROOT/func/pma.sh"
    WORKDIR="$(mktemp -d)"
    SERVER_PID=""
    # A recognisable stand-in for the two secrets the client holds, so the
    # assertions that neither ever reaches the output cannot pass by accident.
    API_KEY_VALUE="fixture-api-key-2f7c1d"
    PMA_KEY_VALUE="fixture-pma-key-8b40ae"
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
# It answers with the JSON body the client expects from the panel.
start_endpoint() {
    local cert="$1" key="$2"

    REQUEST_LOG="$WORKDIR/request.log"
    php "$TLS_SERVER" "$cert" "$key" "$WORKDIR/port" "$REQUEST_LOG" \
        '{"login":{"user":"tmp_fixture","password":"tmp_secret"}}' &
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

# Render the shipped template the way v-add-sys-pma-sso does.
# render_client <api host> [ca file]
render_client() {
    run pma_sso_render "$TEMPLATE" "$WORKDIR/tulio-sso.php" \
        "$PMA_KEY_VALUE" "$1" "$PORT" "$API_KEY_VALUE" "${2:-}"
    assert_success
}

run_client() {
    run php "$HARNESS" "$WORKDIR/tulio-sso.php"
}

# Neither secret may appear anywhere in the client's output.
refute_secrets() {
    refute_output --partial "$API_KEY_VALUE"
    refute_output --partial "$PMA_KEY_VALUE"
    refute_output --partial "tmp_secret"
}

#----------------------------------------------------------#
#                    Shipped source                        #
#----------------------------------------------------------#

@test "pma-sso: the template parses as PHP" {
    command -v php > /dev/null || skip "no PHP interpreter available"
    run php -l "$TEMPLATE"
    assert_success
}

@test "pma-sso: peer and hostname verification are enabled" {
    run grep -F 'CURLOPT_SSL_VERIFYPEER => true,' "$TEMPLATE"
    assert_success
    run grep -F 'CURLOPT_SSL_VERIFYHOST => 2,' "$TEMPLATE"
    assert_success
}

@test "pma-sso: there is no way to turn verification off" {
    run grep -nE 'CURLOPT_SSL_VERIFY(PEER|HOST)[[:space:]]*(=>|,)[[:space:]]*(false|0|null)' \
        "$TEMPLATE"
    assert_failure
}

@test "pma-sso: redirects are refused and both timeouts are set" {
    run grep -F 'CURLOPT_FOLLOWLOCATION => false,' "$TEMPLATE"
    assert_success
    run grep -F 'CURLOPT_CONNECTTIMEOUT => 10,' "$TEMPLATE"
    assert_success
    run grep -F 'CURLOPT_TIMEOUT => 30,' "$TEMPLATE"
    assert_success
}

@test "pma-sso: every curl handle is closed on every path" {
    # One handle is opened, and every way out of the request past that point
    # closes it: the unreadable CA file, the failed setopt, the failed
    # transfer and the answer itself.
    run bash -c "grep -c '\$curl = curl_init();' '$TEMPLATE'"
    assert_output "1"
    run bash -c "grep -c 'curl_close(\$curl);' '$TEMPLATE'"
    assert_output "4"
}

@test "pma-sso: the keys are never part of a logged message" {
    # Every message the client logs goes through fail(), and no call site
    # passes it a key.
    run grep -nE 'fail\(.*(this->key|this->pma_key|API_KEY|PHPMYADMIN_KEY|postdata)' "$TEMPLATE"
    assert_failure
    run grep -nE 'trigger_error\(.*(this->key|this->pma_key|API_KEY|PHPMYADMIN_KEY|postdata)' \
        "$TEMPLATE"
    assert_failure
}

#----------------------------------------------------------#
#                    Certificate handling                  #
#----------------------------------------------------------#

@test "pma-sso: a trusted certificate completes the sign-on" {
    require_tools
    start_endpoint "$CERTDIR/trusted.crt" "$CERTDIR/trusted.key"
    render_client 127.0.0.1 "$CERTDIR/ca.crt"

    run_client
    assert_success
    assert_output --partial "result=OK"
    assert_output --partial "credentials=received"
    refute_secrets

    # The request really reached the endpoint, at the configured address.
    assert_file_contains "$REQUEST_LOG" "^POST /api/ HTTP/"
    assert_file_contains "$REQUEST_LOG" "^Host: 127.0.0.1:$PORT"
    assert_file_contains "$REQUEST_LOG" "User-Agent: Tulio Control Panel phpMyAdmin SSO"
}

@test "pma-sso: a trusted certificate matching the hostname completes the sign-on" {
    require_tools
    # The same check against a DNS name in the SAN rather than an address,
    # which is the shape of the panel's own certificate.
    start_endpoint "$CERTDIR/byname.crt" "$CERTDIR/byname.key"
    render_client localhost "$CERTDIR/ca.crt"

    run_client
    assert_success
    assert_output --partial "result=OK"
    assert_file_contains "$REQUEST_LOG" "^Host: localhost:$PORT"
}

@test "pma-sso: an untrusted certificate sends nothing and fails the sign-on" {
    require_tools
    start_endpoint "$CERTDIR/selfsigned.crt" "$CERTDIR/selfsigned.key"
    # No CA file: the system trust store does not know this certificate.
    render_client 127.0.0.1

    run_client
    assert_success
    assert_output --partial "result=FAILED"
    assert_output --partial "curl error 60"
    refute_secrets

    # Not one byte of the request left the client.
    assert_file_empty "$REQUEST_LOG"
    run stat -c %s "$REQUEST_LOG"
    assert_output "0"
}

@test "pma-sso: a certificate issued for another name sends nothing and fails" {
    require_tools
    # The panel's certificate served to a client that was pointed at the bare
    # address: trusted issuer, wrong name.
    start_endpoint "$CERTDIR/panel.crt" "$CERTDIR/panel.key"
    render_client 127.0.0.1 "$CERTDIR/ca.crt"

    run_client
    assert_success
    assert_output --partial "result=FAILED"
    assert_output --partial "curl error 60"
    refute_secrets
    assert_file_empty "$REQUEST_LOG"
}

@test "pma-sso: an unreadable CA file fails closed" {
    require_tools
    start_endpoint "$CERTDIR/trusted.crt" "$CERTDIR/trusted.key"
    render_client 127.0.0.1 "$WORKDIR/missing-ca.crt"

    run_client
    assert_success
    assert_output --partial "result=FAILED"
    assert_output --partial "CA file is not readable"
    assert_file_empty "$REQUEST_LOG"
}

@test "pma-sso: an endpoint that is not there is not treated as a sign-on" {
    require_tools
    start_endpoint "$CERTDIR/trusted.crt" "$CERTDIR/trusted.key"
    render_client 127.0.0.1 "$CERTDIR/ca.crt"

    # Take the endpoint away so the connection is refused: the client must
    # report a failure rather than a sign-on.
    kill "$SERVER_PID" 2> /dev/null || true
    wait "$SERVER_PID" 2> /dev/null || true
    SERVER_PID=""

    run_client
    assert_success
    assert_output --partial "result=FAILED"
    refute_secrets
}

#----------------------------------------------------------#
#                      Rendering                           #
#----------------------------------------------------------#

@test "pma-sso: rendering substitutes every placeholder" {
    command -v php > /dev/null || skip "no PHP interpreter available"
    PORT=8083
    render_client panel.tuliocp.com

    run grep -c '%[A-Z_]\+%' "$WORKDIR/tulio-sso.php"
    assert_output "0"
    run grep -Fx "define(\"API_HOST_NAME\", \"panel.tuliocp.com\");" "$WORKDIR/tulio-sso.php"
    assert_success
    run grep -Fx "define(\"API_CA_FILE\", \"\");" "$WORKDIR/tulio-sso.php"
    assert_success
}

@test "pma-sso: a key containing shell and sed metacharacters survives rendering" {
    command -v php > /dev/null || skip "no PHP interpreter available"
    PORT=8083
    # & is the one that bites: sed reads it as the matched text, and so does
    # bash's own ${text//from/to} from 5.2 onwards.
    API_KEY_VALUE='a/b&c|d.e*f'
    render_client panel.tuliocp.com

    run grep -Fx "define(\"API_KEY\", \"$API_KEY_VALUE\");" "$WORKDIR/tulio-sso.php"
    assert_success
    run php -l "$WORKDIR/tulio-sso.php"
    assert_success
}

@test "pma-sso: a value PHP would reinterpret is refused rather than escaped" {
    command -v php > /dev/null || skip "no PHP interpreter available"
    local bad
    for bad in 'key"with"quotes' 'key\with\backslash' 'key$with$dollar'; do
        run pma_sso_render "$TEMPLATE" "$WORKDIR/tulio-sso.php" \
            "$bad" panel.tuliocp.com 8083 apikey ""
        assert_failure
        assert_output --partial "refusing to render"
        assert_file_not_exists "$WORKDIR/tulio-sso.php"
    done
}

@test "pma-sso: a CA path that is not absolute leaves verification on" {
    require_tools
    start_endpoint "$CERTDIR/selfsigned.crt" "$CERTDIR/selfsigned.key"
    # Only an absolute path is taken as a trust anchor. A relative one - or an
    # unsubstituted placeholder, which is the case this guards - is ignored,
    # and ignoring it must mean the system trust store, not no verification.
    render_client 127.0.0.1 "relative/ca.crt"

    run_client
    assert_success
    assert_output --partial "result=FAILED"
    assert_output --partial "curl error 60"
    assert_file_empty "$REQUEST_LOG"
}

@test "pma-sso: a half rendered client is never installed" {
    command -v php > /dev/null || skip "no PHP interpreter available"
    # A template with a placeholder this function does not know about.
    sed 's/%API_KEY%/%API_SECRET%/' "$TEMPLATE" > "$WORKDIR/template.php"

    run pma_sso_render "$WORKDIR/template.php" "$WORKDIR/tulio-sso.php" \
        pma panel.tuliocp.com 8083 key ""
    assert_failure
    assert_output --partial "%API_SECRET%"
    assert_file_not_exists "$WORKDIR/tulio-sso.php"
    # No temporary file was left behind either.
    run bash -c "ls '$WORKDIR' | wc -l"
    assert_output "1"
}

@test "pma-sso: the installed values can be read back for an upgrade" {
    command -v php > /dev/null || skip "no PHP interpreter available"
    PORT=8083
    render_client panel.tuliocp.com /usr/local/tulio/ssl/certificate.crt

    run pma_sso_read_define "$WORKDIR/tulio-sso.php" API_HOST_NAME
    assert_success
    assert_output "panel.tuliocp.com"
    run pma_sso_read_define "$WORKDIR/tulio-sso.php" API_KEY
    assert_success
    assert_output "$API_KEY_VALUE"
    run pma_sso_read_define "$WORKDIR/tulio-sso.php" API_CA_FILE
    assert_success
    assert_output "/usr/local/tulio/ssl/certificate.crt"
}

@test "pma-sso: an unsubstituted placeholder does not read back as a value" {
    run pma_sso_read_define "$TEMPLATE" API_KEY
    assert_failure
    run pma_sso_read_define "$TEMPLATE" API_CA_FILE
    assert_failure
}

#----------------------------------------------------------#
#                    Upgrade in place                      #
#----------------------------------------------------------#

@test "pma-sso: the keys of an installed 1.10.4 client can be recovered" {
    local installed="${BATS_TEST_DIRNAME}/fixtures/phpmyadmin/installed-1.10.4.php"

    # The version that did not verify the certificate, with its keys in place.
    run grep -F 'CURLOPT_SSL_VERIFYPEER, false' "$installed"
    assert_success

    run pma_sso_read_define "$installed" PHPMYADMIN_KEY
    assert_success
    assert_output "legacyPmaKey123"
    run pma_sso_read_define "$installed" API_KEY
    assert_success
    assert_output "legacyApiKey456"
    run pma_sso_read_define "$installed" API_HOST_NAME
    assert_success
    assert_output "panel.tuliocp.com"
    run pma_sso_read_define "$installed" API_TULIO_PORT
    assert_success
    assert_output "8083"
    # It predates the trust anchor setting, so there is nothing to carry over.
    run pma_sso_read_define "$installed" API_CA_FILE
    assert_failure
}

@test "pma-sso: upgrading in place keeps the keys and turns verification on" {
    command -v php > /dev/null || skip "no PHP interpreter available"
    cp "${BATS_TEST_DIRNAME}/fixtures/phpmyadmin/installed-1.10.4.php" \
        "$WORKDIR/tulio-sso.php"

    # Exactly what the 1.10.5 upgrade step does: read the installed values back
    # and re-render the fixed template with them.
    local key host port api
    key="$(pma_sso_read_define "$WORKDIR/tulio-sso.php" PHPMYADMIN_KEY)"
    host="$(pma_sso_read_define "$WORKDIR/tulio-sso.php" API_HOST_NAME)"
    port="$(pma_sso_read_define "$WORKDIR/tulio-sso.php" API_TULIO_PORT)"
    api="$(pma_sso_read_define "$WORKDIR/tulio-sso.php" API_KEY)"

    run pma_sso_render "$TEMPLATE" "$WORKDIR/tulio-sso.php" \
        "$key" "$host" "$port" "$api" ""
    assert_success

    # The keys the operator's phpMyAdmin depends on survived untouched.
    run pma_sso_read_define "$WORKDIR/tulio-sso.php" PHPMYADMIN_KEY
    assert_output "legacyPmaKey123"
    run pma_sso_read_define "$WORKDIR/tulio-sso.php" API_KEY
    assert_output "legacyApiKey456"
    run pma_sso_read_define "$WORKDIR/tulio-sso.php" API_HOST_NAME
    assert_output "panel.tuliocp.com"

    # And verification is now on.
    assert_file_contains "$WORKDIR/tulio-sso.php" "CURLOPT_SSL_VERIFYPEER => true,"
    assert_file_contains "$WORKDIR/tulio-sso.php" "CURLOPT_SSL_VERIFYHOST => 2,"
    assert_file_not_contains "$WORKDIR/tulio-sso.php" "CURLOPT_SSL_VERIFYPEER, false"
    run php -l "$WORKDIR/tulio-sso.php"
    assert_success
}

@test "pma-sso: upgrading an already upgraded client changes nothing" {
    command -v php > /dev/null || skip "no PHP interpreter available"
    PORT=8083
    render_client panel.tuliocp.com
    cp "$WORKDIR/tulio-sso.php" "$WORKDIR/before.php"

    local key host port api ca
    key="$(pma_sso_read_define "$WORKDIR/tulio-sso.php" PHPMYADMIN_KEY)"
    host="$(pma_sso_read_define "$WORKDIR/tulio-sso.php" API_HOST_NAME)"
    port="$(pma_sso_read_define "$WORKDIR/tulio-sso.php" API_TULIO_PORT)"
    api="$(pma_sso_read_define "$WORKDIR/tulio-sso.php" API_KEY)"
    ca="$(pma_sso_read_define "$WORKDIR/tulio-sso.php" API_CA_FILE)" || ca=""

    run pma_sso_render "$TEMPLATE" "$WORKDIR/tulio-sso.php" \
        "$key" "$host" "$port" "$api" "$ca"
    assert_success

    run diff -u "$WORKDIR/before.php" "$WORKDIR/tulio-sso.php"
    assert_success
}
