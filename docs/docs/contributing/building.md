# Building packages

::: info
For building `tulio-nginx` or `tulio-php`, at least 2 GB of memory is required!
:::

Here is more detailed information about the build scripts that are run from `src`:

## Installing Tulio from a branch

The following is useful for testing a Pull Request or a branch on a fork.

1. Install Node.js [Download](https://nodejs.org/en/download) or use [Node Source APT](https://github.com/nodesource/distributions)

```bash
# Replace with https://github.com/username/tuliocp.git if you want to test a branch that you created yourself
git clone https://github.com/marcosfermin/tuliocp.git
cd ./tuliocp/

# Replace main with the branch you want to test
git checkout main

cd ./src/

# Compile packages
./hst_autocompile.sh --all --noinstall --keepbuild '~localsrc'

cd ../install

bash tulio-install-{os}.sh --with-debs /tmp/tuliocp-src/deb/
```

Any option can be appended to the installer command. [See the complete list](../introduction/getting-started#list-of-installation-options).

## Build packages only

```bash
# Only Tulio
./hst_autocompile.sh --tulio --noinstall --keepbuild '~localsrc'
```

```bash
# Tulio + tulio-nginx and tulio-php
./hst_autocompile.sh --all --noinstall --keepbuild '~localsrc'
```

## Build and install packages

::: info
Use if you have Tulio already installed, for your changes to take effect.
:::

```bash
# Only Tulio
./hst_autocompile.sh --tulio --install '~localsrc'
```

```bash
# Tulio + tulio-nginx and tulio-php
./hst_autocompile.sh --all --install '~localsrc'
```

## Updating Tulio from GitHub

The following is useful for pulling the latest staging/beta changes from GitHub and compiling the changes.

::: info
The following method only supports building the `tulio` package. If you need to build `tulio-nginx` or `tulio-php`, use one of the previous commands.
:::

1. Install Node.js [Download](https://nodejs.org/en/download) or use [Node Source APT](https://github.com/nodesource/distributions)

```bash
v-update-sys-tulio-git [USERNAME] [BRANCH]
```

**Note:** Sometimes dependencies will get added or removed when the packages are installed with `dpkg`. It is not possible to preload the dependencies. If this happens, you will see an error like this:

```bash
dpkg: error processing package tulio (–install):
dependency problems - leaving unconfigured
```

To solve this issue, run:

```bash
apt install -f
```

## Building for other architectures or OS releases on the same machine

`hst_autocompile.sh` only ever builds for the environment it's actually running in (its own `--cross` flag just makes the architecture-independent `tulio` package build for both AMD64 and ARM64 directly, with no emulation needed). To also build `tulio-nginx`, `tulio-php` or `tulio-web-terminal` (which contain compiled native code) for **other** architectures or OS releases on the same machine, use `chroot_build_all.sh` instead — it spins up and runs the unmodified `hst_autocompile.sh` inside each one.

```bash
./chroot_build_all.sh --all '~localsrc'
```

Every combination is built inside a QEMU-emulated chroot (debootstrap + `qemu-user-static`). The first run downloads/bootstraps a minimal root filesystem per combination under `/var/lib/tuliocp-build-chroot/<distro>-<release>-<arch>`; subsequent runs reuse it, so only the first build of a given combination is slow.
