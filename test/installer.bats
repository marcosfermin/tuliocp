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

# --- Documented support matrix ------------------------------------------- #

@test "README and docs advertise amd64 only" {
    grep -qi 'amd64' "$REPO_ROOT/README.md"
    run ! grep -qiE 'requires a 64-bit operating system \(AMD64/x86_64 or ARM64' "$REPO_ROOT/README.md"
    run ! grep -q 'Tulio only runs on AMD64 / x86_64 and ARM64' "$REPO_ROOT/docs/introduction/getting-started.md"
}

# --- Package revisions --------------------------------------------------- #

@test "every packaged component records a numeric package revision" {
    for pkg in tulio nginx php web-terminal; do
        [ -f "$REPO_ROOT/src/deb/$pkg/pkgrev" ]
        run cat "$REPO_ROOT/src/deb/$pkg/pkgrev"
        [[ "$output" =~ ^[0-9]+$ ]]
    done
}

@test "the build reads the package revision from src/deb/<pkg>/pkgrev" {
    grep -q 'get_branch_file "src/deb/\$pkg_dir/pkgrev"' "$REPO_ROOT/src/hst_autocompile.sh"
    grep -q 'apply_distro_version "\$BUILD_DIR_TULIONGINX/DEBIAN/control" "" "nginx"' "$REPO_ROOT/src/hst_autocompile.sh"
    grep -q 'apply_distro_version "\$BUILD_DIR_TULIOPHP/DEBIAN/control" "" "php"' "$REPO_ROOT/src/hst_autocompile.sh"
}
