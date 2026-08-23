#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Source-level regression guards for the installer.
#
# The installer cannot be executed in a test harness — it repartitions a
# server's package set — so these tests assert the invariants that were
# reviewed rather than the runtime behaviour: amd64-only support, an
# architecture check that runs before any network access, a repository probe
# that checks the architecture's own index, a release-pinned second stage, and
# fingerprint-verified apt keys.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    WRAPPER="$REPO_ROOT/install/tulio-install.sh"
    DEBIAN="$REPO_ROOT/install/tulio-install-debian.sh"
    UBUNTU="$REPO_ROOT/install/tulio-install-ubuntu.sh"
    export REPO_ROOT WRAPPER DEBIAN UBUNTU
}

# Line number of the first match of a pattern in a file, or empty.
line_of() {
    grep -n -m1 -E "$2" "$1" | cut -d: -f1
}

@test "every installer script parses" {
    for script in "$WRAPPER" "$DEBIAN" "$UBUNTU"; do
        run bash -n "$script"
        [ "$status" -eq 0 ]
    done
}

# --- Architecture: amd64 only ------------------------------------------- #

@test "no installer maps aarch64 to an arm64 package architecture" {
    for script in "$WRAPPER" "$DEBIAN" "$UBUNTU"; do
        run ! grep -qE '^\s*aarch64\)' "$script"
        run ! grep -qE 'ARCH="?arm64' "$script"
    done
}

@test "the wrapper refuses any architecture other than x86_64" {
    grep -q 'if \[ "$architecture" != "x86_64" \]' "$WRAPPER"
    grep -q 'no_arch_support_message' "$WRAPPER"
}

@test "the Debian installer aborts on an unsupported architecture" {
    grep -q 'check_result 1 "Unsupported architecture: \$architecture"' "$DEBIAN"
}

@test "the architecture check runs before the repository probe" {
    arch_line=$(line_of "$DEBIAN" 'Unsupported architecture: \$architecture')
    probe_line=$(line_of "$DEBIAN" 'repo_base="https://\$RHOST/dists/\$codename"')
    [ -n "$arch_line" ]
    [ -n "$probe_line" ]
    [ "$arch_line" -lt "$probe_line" ]
}

@test "the wrapper rejects unsupported architectures before downloading anything" {
    arch_line=$(line_of "$WRAPPER" 'no_arch_support_message "\$architecture"')
    download_line=$(line_of "$WRAPPER" 'fetch_and_run_installer "\$@"')
    [ -n "$arch_line" ]
    [ -n "$download_line" ]
    [ "$arch_line" -lt "$download_line" ]
}

# --- Repository probe ---------------------------------------------------- #

@test "the repository probe checks the binary-ARCH index, not just the suite" {
    grep -q 'main/binary-\$ARCH/Release' "$DEBIAN"
    grep -q 'main/binary-\$ARCH/Packages.gz' "$DEBIAN"
}

@test "the repository probe requires the suite Release to advertise the architecture" {
    grep -q 'Architectures:.*\\b\$ARCH\\b' "$DEBIAN"
}

@test "every repository probe request fails closed" {
    # Each probe must use curl -f so an HTML error page is not read as success.
    run grep -c 'curl -fsS --proto' "$DEBIAN"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

# --- Second-stage pinning ------------------------------------------------ #

@test "the wrapper pins the second stage to a commit, not a branch" {
    grep -q '^TULIO_INSTALLER_REF=' "$WRAPPER"
    grep -q 'installer_url="https://raw.githubusercontent.com/\$TULIO_INSTALLER_REPO/\$TULIO_INSTALLER_REF/' "$WRAPPER"
    # The mutable release branch must not be used as a download source.
    run ! grep -qE 'raw\.githubusercontent\.com/[^"]*/release/install/tulio-install-\$type\.sh' "$WRAPPER"
}

@test "the wrapper refuses to run with an unset or placeholder pin" {
    grep -q "TULIO_INSTALLER_REF.*grep -qE '\^\[0-9a-f\]{40}\\\$'" "$WRAPPER"
    grep -q "expected_sha.*grep -qE '\^\[0-9a-f\]{64}\\\$'" "$WRAPPER"
}

@test "the wrapper verifies the download before executing it" {
    sha_line=$(line_of "$WRAPPER" 'actual_sha" != "\$expected_sha')
    exec_line=$(line_of "$WRAPPER" '^\s*bash "\$installer" "\$@"')
    [ -n "$sha_line" ]
    [ -n "$exec_line" ]
    [ "$sha_line" -lt "$exec_line" ]
}

@test "the wrapper downloads to a temporary file and rejects an empty one" {
    grep -q 'mktemp -d /tmp/tuliocp-install' "$WRAPPER"
    grep -q 'if \[ ! -s "\$installer" \]' "$WRAPPER"
}

@test "the wrapper uses failing, HTTPS-only downloads" {
    grep -q "curl -fsSL --proto '=https'" "$WRAPPER"
    grep -q 'wget --https-only' "$WRAPPER"
    # curl -s -O and bare wget silently produced error pages before.
    run ! grep -qE '^\s*curl -s -O' "$WRAPPER"
}

@test "an unpinned wrapper aborts instead of falling back to a branch" {
    run bash -c "
        set -e
        grep -q 'this installer is not pinned to a released revision' '$WRAPPER'
        grep -q 'no pinned checksum for the' '$WRAPPER'
    "
    [ "$status" -eq 0 ]
}

# --- apt key import ------------------------------------------------------ #

@test "installers pin the exact TulioCP apt signing key fingerprint" {
    for script in "$DEBIAN" "$UBUNTU"; do
        grep -q "TULIO_APT_KEY_FINGERPRINT='766950984D6D728AF4EE623451D8B0CD5126BF11'" "$script"
        grep -q 'import_apt_key "https://\$RHOST/pubkey.gpg" /usr/share/keyrings/tulio-keyring.gpg "\$TULIO_APT_KEY_FINGERPRINT"' "$script"
    done
}

@test "no installer imports an apt key through an unchecked pipeline" {
    for script in "$DEBIAN" "$UBUNTU"; do
        run bash -c "grep -v '^[[:space:]]*#' '$script' | grep -q 'gpg --dearmor | tee'"
        [ "$status" -ne 0 ]
    done
}

@test "import_apt_key aborts on download, conversion and fingerprint failure" {
    for script in "$DEBIAN" "$UBUNTU"; do
        grep -q 'Failed to download the repository signing key from' "$script"
        grep -q 'converted to an empty keyring' "$script"
        grep -q 'Repository signing key fingerprint mismatch for' "$script"
    done
}

@test "the keyring check is a whole-keyring check, not a substring match" {
    for script in "$DEBIAN" "$UBUNTU"; do
        grep -q 'verify_apt_keyring "\$dearmored" "\$expected_fp" "\$url"' "$script"
        # `grep -qx "$expected_fp"` over every fpr line accepted a keyring that
        # carried the pinned key plus an attacker's own primary key.
        run ! grep -q 'fingerprints" | grep -qx' "$script"
    done
}

# --- apt key import: behaviour ------------------------------------------- #
#
# verify_apt_keyring is the one piece of the installer that can be executed in
# isolation, so it is tested for real against keyrings built here: the pinned
# key alone must be accepted, and the same keyring with a second, throwaway
# primary key appended must be rejected.

# Extracts verify_apt_keyring from an installer into a sourceable file.
extract_verify_apt_keyring() {
    sed -n '/^verify_apt_keyring() {/,/^}$/p' "$1" > "$BATS_TEST_TMPDIR/verify.sh"
    [ -s "$BATS_TEST_TMPDIR/verify.sh" ]
    # shellcheck disable=SC1090
    source "$BATS_TEST_TMPDIR/verify.sh"
}

# Generates a throwaway primary key (with a subkey) and exports it into
# <keyring>. Echoes the primary key's fingerprint.
make_throwaway_key() {
    local uid="$1" keyring="$2" fp
    gpg --batch --quiet --passphrase '' --quick-generate-key "$uid" default default never > /dev/null 2>&1
    fp=$(gpg --batch --with-colons --list-keys "$uid" | awk -F: '$1 == "pub" { pub = 1; next } $1 == "fpr" && pub { print $10; exit }')
    [ -n "$fp" ]
    gpg --batch --quiet --quick-add-key "$fp" default sign never > /dev/null 2>&1
    gpg --batch --quiet --export "$fp" > "$keyring"
    [ -s "$keyring" ]
    echo "$fp"
}

setup_keyring_fixtures() {
    command -v gpg > /dev/null || skip "gpg is not installed"
    export GNUPGHOME="$BATS_TEST_TMPDIR/gnupg"
    mkdir -p "$GNUPGHOME"
    chmod 700 "$GNUPGHOME"
    GOOD_FP=$(make_throwaway_key "TulioCP Test Signing Key <test@tuliocp.invalid>" "$BATS_TEST_TMPDIR/good.gpg")
    EVIL_FP=$(make_throwaway_key "Not TulioCP <evil@example.invalid>" "$BATS_TEST_TMPDIR/evil.gpg")
    [ "$GOOD_FP" != "$EVIL_FP" ]
    # A keyring is a concatenation of key blocks, which is exactly how an
    # attacker would smuggle an extra key past a "contains the right one" test.
    cat "$BATS_TEST_TMPDIR/good.gpg" "$BATS_TEST_TMPDIR/evil.gpg" > "$BATS_TEST_TMPDIR/good_plus_evil.gpg"
}

@test "verify_apt_keyring accepts the pinned key and only the pinned key" {
    setup_keyring_fixtures
    for script in "$DEBIAN" "$UBUNTU"; do
        extract_verify_apt_keyring "$script"

        # The legitimate key, subkeys and all.
        run verify_apt_keyring "$BATS_TEST_TMPDIR/good.gpg" "$GOOD_FP" "https://apt.example/pubkey.gpg"
        [ "$status" -eq 0 ]

        # The legitimate key with an attacker's primary key appended.
        run verify_apt_keyring "$BATS_TEST_TMPDIR/good_plus_evil.gpg" "$GOOD_FP" "https://apt.example/pubkey.gpg"
        [ "$status" -ne 0 ]
        [[ "$output" == *"2 primary keys"* ]]
        [[ "$output" == *"The key was NOT installed"* ]]

        # A wholly different key.
        run verify_apt_keyring "$BATS_TEST_TMPDIR/evil.gpg" "$GOOD_FP" "https://apt.example/pubkey.gpg"
        [ "$status" -ne 0 ]
        [[ "$output" == *"not the pinned one"* ]]

        # An empty or non-key file.
        echo "not a key" > "$BATS_TEST_TMPDIR/junk.gpg"
        run verify_apt_keyring "$BATS_TEST_TMPDIR/junk.gpg" "$GOOD_FP" "https://apt.example/pubkey.gpg"
        [ "$status" -ne 0 ]
        [[ "$output" == *"no primary key"* ]]
    done
}

@test "verify_apt_keyring accepts subkeys of the pinned key" {
    setup_keyring_fixtures
    extract_verify_apt_keyring "$DEBIAN"

    # Add two more subkeys to the pinned primary: subkeys must not be mistaken
    # for extra primary keys.
    gpg --batch --quiet --passphrase '' --quick-add-key "$GOOD_FP" default encr never > /dev/null 2>&1
    gpg --batch --quiet --passphrase '' --quick-add-key "$GOOD_FP" default auth never > /dev/null 2>&1
    gpg --batch --quiet --export "$GOOD_FP" > "$BATS_TEST_TMPDIR/good_subkeys.gpg"
    subkeys=$(gpg --batch --with-colons --show-keys "$BATS_TEST_TMPDIR/good_subkeys.gpg" | grep -c '^sub:')
    [ "$subkeys" -ge 3 ]

    run verify_apt_keyring "$BATS_TEST_TMPDIR/good_subkeys.gpg" "$GOOD_FP" "https://apt.example/pubkey.gpg"
    [ "$status" -eq 0 ]
}

# --- Documented support matrix ------------------------------------------- #

@test "README and docs advertise amd64 only" {
    grep -qi 'amd64' "$REPO_ROOT/README.md"
    run ! grep -qiE 'requires a 64-bit operating system \(AMD64/x86_64 or ARM64' "$REPO_ROOT/README.md"
    run ! grep -q 'Tulio only runs on AMD64 / x86_64 and ARM64' "$REPO_ROOT/docs/introduction/getting-started.md"
}

# --- Package revisions --------------------------------------------------- #

@test "the upstream version is the same everywhere it is stated" {
    # The installer aborts when its own version does not match the Version: in
    # the release branch's control file, so these have to move together. The
    # docs nav and the README state the same number to users.
    version=$(grep '^Version: ' "$REPO_ROOT/src/deb/tulio/control" | awk '{print $2}')
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]

    grep -q "^TULIO_INSTALL_VER='${version}'\$" "$DEBIAN"
    grep -q "^TULIO_INSTALL_VER='${version}'\$" "$UBUNTU"
    grep -q "^	\"version\": \"${version}\",\$" "$REPO_ROOT/package.json"
    grep -q "^	\"version\": \"${version}\",\$" "$REPO_ROOT/package-lock.json"
    grep -q "<strong>Version:</strong> ${version} " "$REPO_ROOT/README.md"
}

@test "the release has an upgrade step and a changelog entry" {
    # A panel on the previous version finds the step by its file name, so a
    # release without one silently skips its own migration.
    version=$(grep '^Version: ' "$REPO_ROOT/src/deb/tulio/control" | awk '{print $2}')
    [ -f "$REPO_ROOT/install/upgrade/versions/${version}.sh" ]
    grep -q "^## \[${version}\]" "$REPO_ROOT/CHANGELOG.md"
}

@test "every packaged component records a numeric package revision" {
    for pkg in tulio nginx php web-terminal; do
        [ -f "$REPO_ROOT/src/deb/$pkg/pkgrev" ]
        run cat "$REPO_ROOT/src/deb/$pkg/pkgrev"
        [[ "$output" =~ ^[0-9]+$ ]]
    done
}

@test "the installers ask apt for the package revision that is actually built" {
    # The software list pins tulio to an exact version, and reprepro keeps only
    # the newest revision of a package, so an installer still asking for -1
    # after a -2 rebuild makes every fresh install fail at apt-get install.
    pkgrev=$(cat "$REPO_ROOT/src/deb/tulio/pkgrev")
    for script in "$DEBIAN" "$UBUNTU"; do
        grep -q "^TULIO_PKG_REV='${pkgrev}'\$" "$script"
        grep -q 'TULIO_INSTALL_BUILD="\${TULIO_BASE_VER}-\${TULIO_PKG_REV}+\${os_id}\${TULIO_CHANNEL}"' "$script"
        # No hard-coded revision left behind.
        run ! grep -q 'TULIO_INSTALL_BUILD=.*BASE_VER}-[0-9]' "$script"
    done
}

@test "the wrapper's pin matches the second stage in this tree" {
    # The wrapper refuses to run a second stage whose hash differs from the pin,
    # so a commit that edits install/tulio-install-debian.sh without refreshing
    # the pin (bash src/release/pin-installer.sh HEAD) publishes an installer
    # that either aborts or silently runs the previous revision.
    pinned_sha=$(grep "^TULIO_INSTALLER_SHA256_debian=" "$WRAPPER" | cut -d"'" -f2)
    tree_sha=$(sha256sum "$DEBIAN" | awk '{print $1}')
    [ "$pinned_sha" = "$tree_sha" ]

    pinned_ref=$(grep '^TULIO_INSTALLER_REF=' "$WRAPPER" | cut -d"'" -f2)
    ref_sha=$(git -C "$REPO_ROOT" show "$pinned_ref:install/tulio-install-debian.sh" | sha256sum | awk '{print $1}')
    [ "$ref_sha" = "$pinned_sha" ]
}

@test "the build reads the package revision from src/deb/<pkg>/pkgrev" {
    grep -q 'get_branch_file "src/deb/\$pkg_dir/pkgrev"' "$REPO_ROOT/src/hst_autocompile.sh"
    grep -q 'apply_distro_version "\$BUILD_DIR_TULIONGINX/DEBIAN/control" "" "nginx"' "$REPO_ROOT/src/hst_autocompile.sh"
    grep -q 'apply_distro_version "\$BUILD_DIR_TULIOPHP/DEBIAN/control" "" "php"' "$REPO_ROOT/src/hst_autocompile.sh"
}
