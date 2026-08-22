# Testing

TulioCP publishes a single apt suite — `trixie` on `apt.tuliocp.com`, for
Debian 13. There is no beta or release-candidate channel, no Discord server and
no forum. To test unreleased code, build the packages yourself and install them
from disk, as described below.

## Testing unreleased code

Build the `.deb` packages from a branch and hand them to the installer.

::: danger
Unreleased code can break a server. Do not test on a machine that hosts
anything you care about.
:::

On a clean Debian 13 (trixie) machine, as root:

```bash
git clone https://github.com/marcosfermin/tuliocp.git
cd tuliocp/src

# Build the tulio package from the checked-out working tree
./hst_autocompile.sh --tulio --noinstall --keepbuild '~localsrc'

# Install using the freshly built packages instead of the apt repository
cd ../install
bash tulio-install.sh --with-debs /tmp/tuliocp-src/deb
```

`--with-debs` makes the installer skip both the remote apt repository and the
release-version check, so the installer and the packages always match.

To upgrade an existing test install to locally built packages:

```bash
dpkg -i /tmp/tuliocp-src/deb/tulio_*.deb
```

See [Building packages](/contributing/building) for the full set of build
options, including `tulio-nginx`, `tulio-php` and `tulio-web-terminal`.

## Running the automated test suite

The functional tests are written with [Bats](https://github.com/bats-core/bats-core),
which is vendored as a git submodule. Clone with submodules, or initialise them
afterwards:

```bash
git clone --recurse-submodules https://github.com/marcosfermin/tuliocp.git
# or, in an existing clone:
git submodule update --init --recursive
```

::: warning
The Bats suite creates and deletes users, domains, databases and mail accounts.
Run it only on a throwaway TulioCP install, never on a production server.
:::

On a machine with TulioCP installed:

```bash
./test/test_helper/bats-core/bin/bats test/checks.bats
./test/test_helper/bats-core/bin/bats test/test.bats
```

Some suites need extra setup:

- `test/restore.bats` restores from pre-built backup archives. No public host
  serves them, so these tests skip unless you set `TULIO_TEST_FIXTURE_URL` to a
  location that does.
- `test/letsencrypt.bats` and `test/wildcard.bats` need a publicly resolvable
  hostname with working DNS.

The same suite runs in CI for every pull request, inside a container built from
`.github/docker/tulio-ci.Dockerfile`.

## Reporting bugs

Please [open an issue](https://github.com/marcosfermin/tuliocp/issues/new/choose)
or [submit a pull request](https://github.com/marcosfermin/tuliocp/pulls).
Include the TulioCP version (`v-list-sys-info`), the exact commands you ran, and
the output you got.
