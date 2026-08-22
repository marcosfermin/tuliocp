#!/bin/bash

# ======================================================== #
#
# Tulio Control Panel
# Refresh the installer wrapper's release pin
#
# install/tulio-install.sh downloads the OS-specific second stage of the
# installer from an exact commit and verifies its SHA-256 before executing
# it. This script rewrites those two constants in place so the release
# process does not have to compute them by hand.
#
# Usage:
#   bash src/release/pin-installer.sh [commit-ish]
#
# The commit defaults to HEAD. It must already contain the second-stage
# installer scripts being pinned, so the normal release order is:
#
#   1. commit everything that changes install/tulio-install-<os>.sh
#   2. bash src/release/pin-installer.sh HEAD
#   3. commit the refreshed pin
#   4. push, then publish packages
#
# ======================================================== #

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPPER="$REPO_ROOT/install/tulio-install.sh"

# Operating systems the wrapper can hand off to. Each entry needs a matching
# TULIO_INSTALLER_SHA256_<os> constant in the wrapper.
SUPPORTED_OS="debian"

commitish="${1:-HEAD}"

if [ ! -f "$WRAPPER" ]; then
	echo "Error: $WRAPPER not found." >&2
	exit 1
fi

cd "$REPO_ROOT"

if ! commit=$(git rev-parse --verify "${commitish}^{commit}" 2> /dev/null); then
	echo "Error: '$commitish' is not a commit in this repository." >&2
	exit 1
fi

echo "Pinning installer wrapper to $commit"

for os in $SUPPORTED_OS; do
	path="install/tulio-install-$os.sh"

	if ! git cat-file -e "$commit:$path" 2> /dev/null; then
		echo "Error: $path does not exist at $commit." >&2
		exit 1
	fi

	sha=$(git show "$commit:$path" | sha256sum | awk '{print $1}')
	echo "  $path -> $sha"

	if ! grep -q "^TULIO_INSTALLER_SHA256_${os}=" "$WRAPPER"; then
		echo "Error: TULIO_INSTALLER_SHA256_${os} not found in $WRAPPER." >&2
		exit 1
	fi

	sed -i "s|^TULIO_INSTALLER_SHA256_${os}=.*|TULIO_INSTALLER_SHA256_${os}='${sha}'|" "$WRAPPER"
done

sed -i "s|^TULIO_INSTALLER_REF=.*|TULIO_INSTALLER_REF='${commit}'|" "$WRAPPER"

echo
echo "Updated $WRAPPER:"
grep -E "^TULIO_INSTALLER_(REF|SHA256_)" "$WRAPPER"
echo
echo "Commit the change, then push before publishing packages."
