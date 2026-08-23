<h1 align="center">Tulio Control Panel</h1>

<h2 align="center">Lightweight and powerful control panel for the modern web</h2>

<p align="center"><strong>Version:</strong> 1.10.6 | <a href="https://github.com/marcosfermin/tuliocp/blob/release/CHANGELOG.md">View Changelog</a></p>

<p align="center">
	<a href="https://tuliocp.com/">Website</a> |
	<a href="https://tuliocp.com/docs/panel/">Documentation</a> |
	<a href="https://github.com/marcosfermin/tuliocp">GitHub</a> |
	<a href="https://github.com/marcosfermin/tuliocp/issues">Issue tracker</a>
</p>

## **Welcome!**

Tulio Control Panel is designed to provide administrators an easy to use web and command line interface, enabling them to quickly deploy and manage web domains, mail accounts, DNS zones, and databases from one central dashboard without the hassle of manually deploying and configuring individual components or services.

TulioCP is an independently maintained fork of [HestiaCP](https://github.com/hestiacp/hestiacp) (GPL-3.0), which is itself a fork of [VestaCP](https://vestacp.com/). It is not affiliated with, sponsored by, or endorsed by either project. See [Attribution and license](#attribution-and-license) below.

## Features and Services

- Apache2 and NGINX with PHP-FPM
- Multiple PHP versions (5.6 - 8.5, 8.5 as default)
- DNS Server (Bind) with clustering capabilities
- POP/IMAP/SMTP mail services with Anti-Virus, Anti-Spam, and Webmail (ClamAV, SpamAssassin, Sieve, Roundcube)
- MariaDB/MySQL and/or PostgreSQL databases
- Let's Encrypt SSL support with wildcard certificates
- Firewall with brute-force attack detection and IP lists (iptables, fail2ban, and ipset).

## Supported platforms and operating systems

**Debian 13 (trixie) on amd64 (x86_64) only.**

TulioCP publishes `amd64` packages for the `trixie` suite of `apt.tuliocp.com`
and for no other release or architecture. The installer refuses to run on any
other operating system — including older Debian releases and every Ubuntu
release — and on any other CPU architecture. Support for further releases or
architectures will be announced on [tuliocp.com](https://tuliocp.com/) when
packages for them are published.

**NOTES:**

- Tulio Control Panel requires 64-bit AMD64/x86_64 hardware and a 64-bit operating system. There are **no** arm64/aarch64 packages, and 32-bit systems are not supported.
- Tulio Control Panel in combination with OpenVZ 7 or lower might have issues with DNS and/or firewall. If you use a Virtual Private Server we strongly advise you to use something based on KVM or LXC.

## Installing Tulio Control Panel

- **NOTE:** You must install Tulio Control Panel on top of a fresh Debian 13 installation to ensure proper functionality.

While we have taken every effort to make the installation process and the control panel interface as friendly as possible (even for new users), it is assumed that you will have some prior knowledge and understanding in the basics how to set up a Linux server before continuing.

### Step 1: Log in

To start the installation, you will need to be logged in as **root** or a user with super-user privileges. You can perform the installation either directly from the command line console or remotely via SSH:

```bash
ssh root@your.server
```

### Step 2: Download

Download the installation script for the latest release:

```bash
apt-get update && apt-get install -y wget ca-certificates
wget https://raw.githubusercontent.com/marcosfermin/tuliocp/release/install/tulio-install.sh
```

If the download fails due to an SSL validation error, make sure the
`ca-certificates` package is installed, as shown above.

### Step 3: Run

To begin the installation process, simply run the script and follow the on-screen prompts:

```bash
bash tulio-install.sh
```

The wrapper checks that the host is Debian 13, downloads
`tulio-install-debian.sh` from the release branch and hands over to it. That
script then verifies that `https://apt.tuliocp.com/dists/trixie/InRelease` is
reachable before it changes anything on the system, and aborts with an
explanation if it is not.

After installation completes, the on-screen instructions show the panel URL and
the credentials to log in with. If you supplied an email address, the same
details are sent there — note that outbound email only works once the server's
mail configuration and DNS are in place.

### Custom installation

You may specify a number of various flags during installation to only install the features in which you need. To view a list of available options, run:

```bash
bash tulio-install.sh -h
```

### Installing without the apt repository

To install from locally built packages instead of `apt.tuliocp.com` — for a
disconnected host, or to test a branch — build the `.deb` files first and pass
them to the installer:

```bash
git clone https://github.com/marcosfermin/tuliocp.git
cd tuliocp/src
./hst_autocompile.sh --tulio --noinstall --keepbuild '~localsrc'
cd ../install
bash tulio-install.sh --with-debs /tmp/tuliocp-src/deb
```

`--with-debs` also skips the check that the installer version matches the
release branch, so a locally built installer and locally built packages stay
consistent.

## How to upgrade an existing installation

Automatic panel updates are **disabled by default**. This is deliberate: updates
change a running production panel, so enabling them is left to the operator.

To update manually:

```bash
apt-get update
apt-get upgrade
```

To opt in to automatic updates, enable them under **Server Settings > Updates**
in the panel, or run:

```bash
v-add-cron-tulio-autoupdate apt
```

## Issues & Support Requests

Bugs and other reproducible issues should be filed via GitHub by [creating a new issue report](https://github.com/marcosfermin/tuliocp/issues).

TulioCP is maintained by one person in their own time. There is no forum, chat
server or commercial support channel — GitHub issues are the only support
channel, and replies take days rather than hours.

**IMPORTANT: We _cannot_ provide support for requests that do not describe the troubleshooting steps that have already been performed, or for third-party applications not related to Tulio Control Panel (such as WordPress). Please make sure that you include as much information as possible in your issue reports!**

Security vulnerabilities should not be filed as public issues — follow the
[security policy](SECURITY.md) instead.

## Contributions

If you would like to contribute to the project, please [read our Contribution Guidelines](https://github.com/marcosfermin/tuliocp/blob/release/CONTRIBUTING.md) for a brief overview of our development process and standards.

The repository uses git submodules for its test helpers, so clone with:

```bash
git clone --recurse-submodules https://github.com/marcosfermin/tuliocp.git
```

## Attribution and License

TulioCP is a fork of [HestiaCP](https://github.com/hestiacp/hestiacp), which is
itself a fork of [VestaCP](https://vestacp.com/). The great majority of the code
in this repository was written by contributors to those projects and remains
under their copyright. TulioCP claims copyright only over its own modifications.
The full breakdown is in [`src/deb/tulio/copyright`](src/deb/tulio/copyright),
installed at `/usr/share/doc/tulio/copyright` on every TulioCP system.

Tulio Control Panel is licensed under [GPL v3](https://github.com/marcosfermin/tuliocp/blob/release/LICENSE), the same licence as the projects it derives from. The upstream project's release history is preserved verbatim in [CHANGELOG.md](CHANGELOG.md); entries dated before the fork describe upstream releases, not TulioCP releases.

TulioCP is not affiliated with, sponsored by, or endorsed by the HestiaCP or
VestaCP projects, and is not supported by them. The TulioCP name and logo are
not covered by the GPL and may not be used to imply endorsement by, or
affiliation with, either upstream project.
