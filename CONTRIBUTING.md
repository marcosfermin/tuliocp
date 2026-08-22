# Tulio Control Panel - Contribution Guidelines

Tulio Control Panel is maintained by a single person in their own time. There is
no company, no development team and no paid support behind it. Contributions are
welcome, but please expect review to take days rather than hours.

## Ways to contribute

- **Testing development builds**:
  - Install a build from the `main` branch on a throwaway server and report what
    breaks. `v-update-sys-tulio-git tuliocp main install` builds and installs the
    current `main` branch from GitHub. Do not do this on a production server —
    `main` is a development snapshot.
  - File what you find as an [issue](https://github.com/marcosfermin/tuliocp/issues).
- **Code review and bug fixes**:
  - Read over the code and if you notice errors (even spelling mistakes), submit
    a pull request with your changes.
- **New features**:
  - Is there a feature you'd love to see included? Open an issue to discuss it
    first, or submit a pull request. Not every request can be accommodated;
    developing, implementing and testing a feature takes time, so a request may
    be declined or deferred.
- **Translations**:
  - TulioCP does not run a hosted translation platform. Translations are edited
    directly in `web/locale/` and submitted as pull requests. See
    [Contributing to Tulio's translations](https://tuliocp.com/docs/panel/contributing/translations.html)
    for the full procedure, or read
    [`docs/contributing/translations.md`](docs/contributing/translations.md) in
    this repository.
- **Documentation**:
  - The panel documentation lives in [`docs/`](docs/) and is published at
    [tuliocp.com/docs/panel](https://tuliocp.com/docs/panel/). Corrections and
    additions are as valuable as code.

## Reporting security issues

Do **not** report vulnerabilities through issues or pull requests. Follow
[SECURITY.md](SECURITY.md), which asks you to open a private
[security advisory](https://github.com/marcosfermin/tuliocp/security/advisories/new)
or email <hello@tuliocp.com>.

## Development Guidelines

Additional information on how to contribute to Tulio Control Panel can be found
in the [Development](https://tuliocp.com/docs/panel/contributing/development.html)
documentation, whose source is
[`docs/contributing/development.md`](docs/contributing/development.md). Build
instructions are in
[`docs/contributing/building.md`](docs/contributing/building.md).

### Code formatting and comments

We ask that you follow existing naming schemes and coding conventions where possible, and that you add comments in your source code where appropriate to aid other developers in debugging and understanding your code in the future.

To ensure your changes meet our formatting requirements, please run `npm install` from the root of the repository before committing your changes. This will set up pre-commit hooks for automatic formatting, which will help to get your changes merged as quickly as possible.

### Workflow and process

Development takes place in branches. There are two long-lived branches:

| Branch    |                                                              Description                                                              |
| --------- | :-----------------------------------------------------------------------------------------------------------------------------------: |
| `main`    |                      Contains a snapshot of the latest development code.<br>**Not intended for production use.**                      |
| `release` | Contains the latest stable release.<br>**Intended for production use. This branch contains the same code as the published packages.** |

Pull requests target `main`. `release` is updated as part of cutting a release.

### Creating a new branch and submitting pull requests

The first step is to create a fork of the `marcosfermin/tuliocp` repository under your GitHub account so that you may submit pull requests and patches.

Once you've created your fork, clone the repository to your computer and make sure that you've checked out the `main` branch. **Always** create a new topic branch for your work.

### Branch naming convention

- **Prefix:** `topic/` (such as **fix**, **feature**, **refactor**, etc.)
- **ID**: `888` (GitHub Issue ID if an issue exists)
- **Title:** `my-awesome-patch`

Branch name examples:

- `feature/777-my-awesome-new-feature` or `feature/my-other-new-feature`
- `fix/000-some-bug-fix` or `fix/this-feature-is-broken`
- `refactor/v-change-domain-owner`
- `test/mail-domain-ssl`

### Squashing commits for smaller changes

To keep the project's commit history readable, please **squash your commits** when it's appropriate. For example, smaller commits related to the same piece of code, such as commits labelled "Fixed item 1", "Adjusted color of button XYZ", "Adjusted alignment of button XYZ" can be squashed into one commit with the title "Fixed button issues in item".

### What happens when I submit a pull request?

- Your work will be reviewed and validated.
- Your changes will be tested to ensure that there are no issues.
- If changes need to be made, you will be notified via GitHub.
- Once approved, your code will be merged for inclusion in an upcoming release of Tulio Control Panel.

All pull requests must include a brief but descriptive title, and a detailed description of the changes that you've made. **Only include commits that are related to your feature, bug fix, or patch in your pull request!**

## Thank you

Contributions of every size are appreciated — bug reports, documentation fixes
and translations just as much as code.
