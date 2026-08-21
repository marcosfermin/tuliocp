<h1 align="center">Tulio Control Panel</h1>

<h2 align="center">Lightweight and powerful control panel for the modern web</h2>

<p align="center"><strong>Version:</strong> 1.10.3 | <a href="https://github.com/marcosfermin/tuliocp/blob/release/CHANGELOG.md">View Changelog</a></p>

<p align="center">
	<a href="https://github.com/marcosfermin/tuliocp">GitHub</a> |
	<a href="https://github.com/marcosfermin/tuliocp/issues">Issue tracker</a>
</p>

## **Welcome!**

TulioCP is derived from HestiaCP (GPL-3.0), itself derived from VestaCP.

Tulio Control Panel is designed to provide administrators an easy to use web and command line interface, enabling them to quickly deploy and manage web domains, mail accounts, DNS zones, and databases from one central dashboard without the hassle of manually deploying and configuring individual components or services.

> **Project status:** TulioCP is a rebrand in progress. The hosted services the
> upstream project relied on (apt repository, documentation site, forum, IP echo
> service, package mirrors) do **not** yet exist for TulioCP. Every place in the
> tree that depends on one is marked with a
> `TODO(tulio): infrastructure not yet deployed` comment. Until those services
> are stood up, installation from a remote repository will not work — build and
> install from source instead. Automatic updates are disabled by default for the
> same reason.

## Features and Services

- Apache2 and NGINX with PHP-FPM
- Multiple PHP versions (5.6 - 8.5, 8.5 as default)
- DNS Server (Bind) with clustering capabilities
- POP/IMAP/SMTP mail services with Anti-Virus, Anti-Spam, and Webmail (ClamAV, SpamAssassin, Sieve, Roundcube)
- MariaDB/MySQL and/or PostgreSQL databases
- Let's Encrypt SSL support with wildcard certificates
- Firewall with brute-force attack detection and IP lists (iptables, fail2ban, and ipset).

## Supported platforms and operating systems

- **Debian:** 13, 12, 11
- **Ubuntu:** 26.04 LTS, 24.04 LTS, 22.04 LTS

**NOTES:**

- Tulio Control Panel does not support 32 bit operating systems!
- Tulio Control Panel in combination with OpenVZ 7 or lower might have issues with DNS and/or firewall. If you use a Virtual Private Server we strongly advice you to use something based on KVM or LXC!

## Installing Tulio Control Panel

- **NOTE:** You must install Tulio Control Panel on top of a fresh operating system installation to ensure proper functionality.

While we have taken every effort to make the installation process and the control panel interface as friendly as possible (even for new users), it is assumed that you will have some prior knowledge and understanding in the basics how to set up a Linux server before continuing.

### Step 1: Log in

To start the installation, you will need to be logged in as **root** or a user with super-user privileges. You can perform the installation either directly from the command line console or remotely via SSH:

```bash
ssh root@your.server
```

### Step 2: Download

Download the installation script for the latest release:

```bash
wget https://raw.githubusercontent.com/marcosfermin/tuliocp/release/install/tulio-install.sh
```

If the download fails due to an SSL validation error, please be sure you've installed the ca-certificate package on your system - you can do this with the following command:

```bash
apt-get update && apt-get install ca-certificates
```

### Step 3: Run

To begin the installation process, simply run the script and follow the on-screen prompts:

```bash
bash tulio-install.sh
```

You will receive a welcome email at the address specified during installation (if applicable) and on-screen instructions after the installation is completed to log in and access your server.

### Custom installation

You may specify a number of various flags during installation to only install the features in which you need. To view a list of available options, run:

```bash
bash tulio-install.sh -h
```

To install without a remote apt repository, build the `.deb` packages locally with
`src/hst_autocompile.sh` and pass them to the installer via `--with-debs`.

## How to upgrade an existing installation

Automatic updates are **disabled by default**, because no TulioCP apt repository
exists yet. Once one is available, they can be enabled from
**Server Settings > Updates** or with `v-add-cron-tulio-autoupdate apt`. To
manually check for and install available updates, use the apt package manager:

```bash
apt-get update
apt-get upgrade
```

## Issues & Support Requests

Bugs and other reproducible issues should be filed via GitHub by [creating a new issue report](https://github.com/marcosfermin/tuliocp/issues).

**IMPORTANT: We _cannot_ provide support for requests that do not describe the troubleshooting steps that have already been performed, or for third-party applications not related to Tulio Control Panel (such as WordPress). Please make sure that you include as much information as possible in your issue reports!**

## Contributions

If you would like to contribute to the project, please [read our Contribution Guidelines](https://github.com/marcosfermin/tuliocp/blob/release/CONTRIBUTING.md) for a brief overview of our development process and standards.

## Attribution and License

TulioCP is derived from HestiaCP (GPL-3.0), itself derived from VestaCP.

Tulio Control Panel is licensed under [GPL v3](https://github.com/marcosfermin/tuliocp/blob/release/LICENSE). The upstream project's release history is preserved verbatim in [CHANGELOG.md](CHANGELOG.md).

The TulioCP name and logo are not covered by the GPL and may not be used to imply
endorsement by, or affiliation with, the upstream HestiaCP or VestaCP projects.
