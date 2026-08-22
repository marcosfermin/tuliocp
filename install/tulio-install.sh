#!/bin/bash

# ======================================================== #
#
# Tulio Control Panel Installation Routine
# Automatic OS detection wrapper
# https://www.tuliocp.com/
#
# Currently Supported Operating Systems:
#
# Debian 13 (trixie), amd64 (x86_64) only
#
# Other releases and other CPU architectures are not supported at this
# time: no TulioCP packages are published for them.
#
# ======================================================== #

set -o pipefail

# -------------------------------------------------------- #
# Release pin
#
# This wrapper downloads and executes the OS-specific second stage of the
# installer. Fetching that from a moving branch would mean the script this
# wrapper runs can change under it at any moment, so both constants below
# pin it to an exact, immutable revision:
#
#   TULIO_INSTALLER_REF     - full 40-character git commit SHA to fetch from
#   TULIO_INSTALLER_SHA256  - SHA-256 of install/tulio-install-<os>.sh at
#                             that commit
#
# Both are refreshed together at release time by:
#
#   bash src/release/pin-installer.sh <commit>
#
# See docs/contributing/releasing.md. Every download and verification step
# below fails closed: nothing is executed unless it was fetched over HTTPS
# from the pinned commit and matches the pinned hash exactly.
# -------------------------------------------------------- #
TULIO_INSTALLER_REF='2273a6cf5b6e5166ae498f898cc3bd4a2fe17807'
TULIO_INSTALLER_SHA256_debian='026c7e6055f4e4394e1d9626aef624ee286254afc4440b6fbba917743bf63961'

TULIO_INSTALLER_REPO='marcosfermin/tuliocp'

# Am I root?
if [ "x$(id -u)" != 'x0' ]; then
	echo 'Error: this script can only be executed by root'
	exit 1
fi

# Check admin user account
if [ ! -z "$(grep ^admin: /etc/passwd)" ] && [ -z "$1" ]; then
	echo "Error: user admin exists"
	echo
	echo 'Please remove admin user before proceeding.'
	echo 'If you want to do it automatically run installer with -f option:'
	echo "Example: bash $0 --force"
	exit 1
fi

# Check admin group
if [ ! -z "$(grep ^admin: /etc/group)" ] && [ -z "$1" ]; then
	echo "Error: group admin exists"
	echo
	echo 'Please remove admin group before proceeding.'
	echo 'If you want to do it automatically run installer with -f option:'
	echo "Example: bash $0 --force"
	exit 1
fi

# Detect OS
if [ -e "/etc/os-release" ] && [ ! -e "/etc/redhat-release" ]; then
	type=$(grep "^ID=" /etc/os-release | cut -f 2 -d '=')
	if [ "$type" = "debian" ]; then
		release=$(cat /etc/debian_version | grep -o "[0-9]\{1,2\}" | head -n1)
		VERSION='debian'
	else
		type="NoSupport"
	fi
else
	type="NoSupport"
fi

no_support_message() {
	echo "****************************************************"
	echo "Your operating system (OS) is not supported by"
	echo "Tulio Control Panel. Supported releases:"
	echo "****************************************************"
	echo "  Debian 13 (trixie)"
	echo ""
	echo "TulioCP publishes packages for Debian 13 only. Support for"
	echo "further releases will be announced at https://tuliocp.com/"
	echo "when packages for them are published."
	echo ""
	exit 1
}

no_arch_support_message() {
	echo "****************************************************"
	echo "Your CPU architecture ($1) is not supported by"
	echo "Tulio Control Panel. Supported architectures:"
	echo "****************************************************"
	echo "  amd64 (x86_64)"
	echo ""
	echo "TulioCP builds and publishes packages for amd64 only. There"
	echo "are no packages for arm64/aarch64 or any other architecture."
	echo ""
	exit 1
}

if [ "$type" = "NoSupport" ]; then
	no_support_message
fi

# TulioCP publishes amd64 packages only. Refuse other architectures here,
# before any download or repository probe, so unsupported hardware gets a
# clear message rather than a confusing failure deep inside the installer.
architecture="$(uname -m)"
if [ "$architecture" != "x86_64" ]; then
	no_arch_support_message "$architecture"
fi

ensure_utf8_locale() {
	local locale_file="/etc/default/locale"

	if locale | grep -qi 'utf-8'; then
		return
	fi

	echo "[ * ] Enabling UTF-8 locale support via C.UTF-8"
	if ! locale-gen C.UTF-8; then
		echo "[ ! ] Failed to generate C.UTF-8 locale. Leaving existing locale untouched."
		return
	fi

	if ! update-locale LANG=C.UTF-8; then
		echo "[ ! ] Failed to update LANG in $locale_file. Leaving existing locale untouched."
		return
	fi

	export LANG=C.UTF-8
}

ensure_utf8_locale

# Resolve the pinned SHA-256 for the detected OS.
expected_sha_var="TULIO_INSTALLER_SHA256_${type}"
expected_sha="${!expected_sha_var}"

# The pin must be a real commit and a real hash before anything is fetched.
# An unset or placeholder pin means this copy of the wrapper was not produced
# by the release process, so refuse to run rather than falling back to a
# mutable branch.
if ! echo "$TULIO_INSTALLER_REF" | grep -qE '^[0-9a-f]{40}$' \
	|| [ "$TULIO_INSTALLER_REF" = "0000000000000000000000000000000000000000" ]; then
	echo "Error: this installer is not pinned to a released revision."
	echo
	echo "TULIO_INSTALLER_REF must be a full 40-character git commit SHA."
	echo "Download the released installer instead:"
	echo "  https://raw.githubusercontent.com/$TULIO_INSTALLER_REPO/release/install/tulio-install.sh"
	exit 1
fi

if ! echo "$expected_sha" | grep -qE '^[0-9a-f]{64}$' \
	|| [ "$expected_sha" = "0000000000000000000000000000000000000000000000000000000000000000" ]; then
	echo "Error: no pinned checksum for the $type installer in this wrapper."
	echo
	echo "Download the released installer instead:"
	echo "  https://raw.githubusercontent.com/$TULIO_INSTALLER_REPO/release/install/tulio-install.sh"
	exit 1
fi

installer_url="https://raw.githubusercontent.com/$TULIO_INSTALLER_REPO/$TULIO_INSTALLER_REF/install/tulio-install-$type.sh"

# Downloads the pinned second stage into $1. Uses curl when available and
# falls back to wget; both are told to fail on HTTP errors and to refuse
# anything but HTTPS, so a redirect to plain HTTP or a 404 error page is
# never mistaken for the installer.
download_installer() {
	local target="$1"

	if command -v curl > /dev/null 2>&1; then
		curl -fsSL --proto '=https' --tlsv1.2 \
			--connect-timeout 15 --max-time 300 \
			--retry 2 --retry-delay 2 \
			-o "$target" "$installer_url"
		return $?
	fi

	if command -v wget > /dev/null 2>&1; then
		wget --https-only --secure-protocol=TLSv1_2 \
			--timeout=30 --tries=3 \
			-q -O "$target" "$installer_url"
		return $?
	fi

	echo "Error: neither curl nor wget is available."
	echo "Install one of them and run this script again:"
	echo "  apt-get update && apt-get install -y curl ca-certificates"
	return 1
}

fetch_and_run_installer() {
	local tmpdir installer

	if ! command -v sha256sum > /dev/null 2>&1; then
		echo "Error: sha256sum is required to verify the installer download."
		echo "Install it and run this script again:"
		echo "  apt-get update && apt-get install -y coreutils"
		exit 1
	fi

	tmpdir=$(mktemp -d /tmp/tuliocp-install.XXXXXXXX) || {
		echo "Error: unable to create a temporary directory."
		exit 1
	}
	# shellcheck disable=SC2064
	trap "rm -rf '$tmpdir'" EXIT

	installer="$tmpdir/tulio-install-$type.sh"

	echo "[ * ] Downloading tulio-install-$type.sh (pinned to ${TULIO_INSTALLER_REF:0:12})"
	if ! download_installer "$installer"; then
		echo "Error: tulio-install-$type.sh download failed."
		echo "  $installer_url"
		exit 1
	fi

	if [ ! -s "$installer" ]; then
		echo "Error: tulio-install-$type.sh downloaded empty."
		echo "  $installer_url"
		exit 1
	fi

	local actual_sha
	actual_sha=$(sha256sum "$installer" | awk '{print $1}')
	if [ "$actual_sha" != "$expected_sha" ]; then
		echo "Error: tulio-install-$type.sh failed checksum verification."
		echo "  expected: $expected_sha"
		echo "  actual:   $actual_sha"
		echo
		echo "The download was modified in transit or the pin is stale."
		echo "Nothing has been executed. Re-download the released installer:"
		echo "  https://raw.githubusercontent.com/$TULIO_INSTALLER_REPO/release/install/tulio-install.sh"
		exit 1
	fi

	# Belt and braces: a valid-looking hash still should not be executed if the
	# payload is not a shell script.
	if ! head -n 1 "$installer" | grep -qE '^#!/bin/(bash|sh)'; then
		echo "Error: tulio-install-$type.sh is not a shell script."
		exit 1
	fi

	echo "[ * ] Checksum verified, starting installation"
	bash "$installer" "$@"
	exit $?
}

# Check for supported operating system before proceeding with download
# of OS-specific installer, and throw error message if unsupported OS detected.
if [ "$type" = "debian" ] && [ "$release" = "13" ]; then
	fetch_and_run_installer "$@"
else
	no_support_message
fi

exit
