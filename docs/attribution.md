# Attribution and stewardship

## Who maintains TulioCP

TulioCP is an independently maintained project. Development happens in the open
at [github.com/marcosfermin/tuliocp](https://github.com/marcosfermin/tuliocp),
and there is no separate organisation, foundation or company behind it.

There is no donation programme, no paid support tier and no membership scheme.
The only supported channels are the ones listed under
[Getting help](#getting-help) below.

## Where the code comes from

TulioCP is a fork of [Hestia Control Panel](https://github.com/hestiacp/hestiacp),
which is itself a fork of [Vesta Control Panel](https://vestacp.com/). The great
majority of the code in this repository was written by contributors to those two
projects, and it remains under their copyright.

TulioCP claims copyright only over its own modifications. The full breakdown is
in the package copyright file, installed at `/usr/share/doc/tulio/copyright` on
every TulioCP system.

TulioCP is licensed under the [GNU General Public License v3.0 or later](https://github.com/marcosfermin/tuliocp/blob/main/LICENSE),
the same licence as the projects it derives from.

::: warning Not affiliated
TulioCP is **not** affiliated with, sponsored by, or endorsed by the HestiaCP or
VestaCP projects, and it is not supported by them. Do not report TulioCP
problems to those projects. The TulioCP name and logo are not covered by the
GPL and may not be used in a way that implies endorsement by, or affiliation
with, either upstream project.
:::

## Upstream history

The release history of the upstream project is preserved verbatim in
[CHANGELOG.md](https://github.com/marcosfermin/tuliocp/blob/main/CHANGELOG.md).
Entries dated before the fork describe upstream releases, not TulioCP releases.

## Third-party components

TulioCP installs and configures a large amount of third-party software — nginx,
Apache, PHP, MariaDB, PostgreSQL, Bind, Exim, Dovecot, ClamAV, SpamAssassin,
Roundcube, phpMyAdmin, phpPgAdmin and others. Each is distributed under its own
licence by its own authors, and TulioCP claims no ownership over any of them.

The `tulio-nginx` and `tulio-php` packages ship builds of nginx and PHP. Their
licences are reproduced in `/usr/share/doc/tulio-nginx/copyright` and
`/usr/share/doc/tulio-php/copyright`.

Some pages in the [Community](/community/tulio-nginx-cache) section describe
integrations written by third parties for HestiaCP. They are listed because they
are useful, not because TulioCP maintains them or guarantees they work against
TulioCP.

## Getting help

- **Bugs and reproducible issues:** [open an issue on GitHub](https://github.com/marcosfermin/tuliocp/issues)
- **Security vulnerabilities:** follow the [security policy](https://github.com/marcosfermin/tuliocp/blob/main/SECURITY.md);
  do not open a public issue
- **Project website:** [tuliocp.com](https://tuliocp.com/)
