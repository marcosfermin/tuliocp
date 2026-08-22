# TulioCP security policy

Thanks for taking an interest in the security of TulioCP.

## Reporting a vulnerability

If you believe you have found a vulnerability in Tulio Control Panel, report it
privately by [opening a security advisory on GitHub](https://github.com/marcosfermin/tuliocp/security/advisories/new).
If you cannot use GitHub, email <hello@tuliocp.com> instead.

Please include a detailed description of the vulnerability, the services
involved (e.g. exim, dovecot) and the versions you tested, full steps to
reproduce, and your findings and expected results.

Do not open a public issue, or post about the report anywhere else, before a fix
has been released.

TulioCP is a fork of HestiaCP. If the vulnerability is also present in upstream
HestiaCP or VestaCP, please report it to those projects as well — TulioCP cannot
issue fixes on their behalf, and they do not receive reports sent here.

TulioCP is maintained by a single person in their own time, so expect a reply
within a few days rather than within hours.

## Supported versions

| Version | Supported          |
| ------- | ------------------ |
| Latest  | :white_check_mark: |

## Qualifying Vulnerabilities

### Vulnerabilities we really care about

- Remote command execution
- Code/SQL Injection
- Authentication bypass
- Privilege Escalation
- Cross-site scripting (XSS)
- Performing limited admin actions without authorization
- CSRF

### Vulnerabilities we accept

- Open redirects
- Password brute-forcing that circumvents rate limiting

## Non-Qualifying Vulnerabilities

- Theoretical attacks without proof of exploitability
- Attacks that are the result of a third party library should be reported to the library maintainers
- Social engineering
- Reflected file download
- Physical attacks
- Weak SSL/TLS/SSH algorithms or protocols
- Attacks involving physical access to a user’s device, or involving a device or network that’s already seriously compromised (eg man-in-the-middle).
- The user attacks themselves
- anything in `/test/` folder
