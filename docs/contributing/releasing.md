# Releasing

This page covers the parts of a release that are easy to get wrong: pinning the
installer, bumping package revisions, and the order in which things must be
pushed and published.

## Package revisions

Each package records its Debian revision in a file next to its control file:

| Package              | Revision file                 |
| -------------------- | ----------------------------- |
| `tulio`              | `src/deb/tulio/pkgrev`        |
| `tulio-nginx`        | `src/deb/nginx/pkgrev`        |
| `tulio-php`          | `src/deb/php/pkgrev`          |
| `tulio-web-terminal` | `src/deb/web-terminal/pkgrev` |

`hst_autocompile.sh` reads these files and appends `-<pkgrev>+<distro>` to the
`Version:` in the control file, producing e.g. `1.30.4-2+debian13`.

Bump the revision — **not** the upstream version — whenever the packaging
changes but the software inside does not. Changes to the control file's
description or dependencies, to `copyright`, or to a maintainer script all
qualify. Without the bump, apt sees the same version it already has and never
offers the rebuilt package.

Reset the revision to `1` when the upstream version in the control file changes,
since the new upstream version already sorts higher.

`--pkgrev <n>` overrides the file for a one-off or CI build. Do not use it for
official builds; the revision belongs in git so the published version can be
traced back to a commit.

## Pinning the installer

`install/tulio-install.sh` is the wrapper users download. It fetches the
OS-specific second stage (`install/tulio-install-debian.sh`) and executes it, so
that second stage is pinned to an exact commit and verified by SHA-256 before it
runs. Two constants at the top of the wrapper hold the pin:

- `TULIO_INSTALLER_REF` — full 40-character commit SHA
- `TULIO_INSTALLER_SHA256_debian` — SHA-256 of `install/tulio-install-debian.sh`
  at that commit

Both are refreshed by:

```bash
bash src/release/pin-installer.sh HEAD
```

The commit being pinned has to already contain the second-stage script, so the
order is:

1. Commit every change that touches `install/tulio-install-<os>.sh`.
2. Run `bash src/release/pin-installer.sh HEAD`.
3. Commit the refreshed pin.

If the constants are left at their placeholder zeros, or the download does not
match the pinned hash, the wrapper aborts without executing anything. There is
no fallback to a branch.

## Publish order

The installer pins an exact package version and validates it against the
`release` branch, so **source must be pushed before packages are published**:

1. Push `main`.
2. Push `release`.
3. Build the packages on the apt host.
4. Publish to `apt.tuliocp.com` with `reprepro`.

Publishing first leaves a window where the repository offers a version that no
branch describes, and the installer's version check rejects the install.

## Verifying a publish

After `reprepro includedeb`, confirm on a client that apt sees the new revision
and that the shipped metadata is what you intended:

```bash
apt-get update
apt-cache policy tulio-nginx tulio-php
apt-get install --simulate --reinstall tulio-nginx tulio-php
dpkg-deb -f tulio-nginx_1.30.4-2+debian13_amd64.deb Version Description
dpkg-deb --fsys-tarfile tulio-nginx_1.30.4-2+debian13_amd64.deb \
	| tar -xO ./usr/share/doc/tulio-nginx/copyright
```

The `copyright` file must be present at `/usr/share/doc/<package>/copyright`.
`DEBIAN/copyright` is not a control file dpkg recognises, so a copy placed there
never reaches the installed system.
