# Contributing to Tulio’s translations

TulioCP does not run a hosted translation platform. Translations are edited
directly in the repository.

The English source strings live in `web/locale/tuliocp.pot`, and each language
has a catalogue at `web/locale/<lang>/LC_MESSAGES/tuliocp.po`.

To add or improve a translation:

1. Fork [the repository](https://github.com/marcosfermin/tuliocp) and create a
   branch.
2. Edit the `.po` file for your language with a gettext editor such as
   [Poedit](https://poedit.net/), or with any text editor.
3. Do not edit the `.mo` files or `tuliocp.pot` by hand — they are generated.
4. [Open a pull request](https://github.com/marcosfermin/tuliocp/pulls)
   describing which language you changed.

To add a language that does not exist yet, copy `web/locale/tuliocp.pot` to
`web/locale/<lang>/LC_MESSAGES/tuliocp.po` and translate it from there.
