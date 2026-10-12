# Python regex module

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py python-regex`.
The third-party [`regex`](https://pypi.org/project/regex/) module (default `VERSION0`, compatible with `re`),
installed in a private virtualenv at `vendor/pyregex` (`python3 -m venv vendor/pyregex && vendor/pyregex/bin/pip install regex`).
It shares the [`python-re`](../python-re) host (`IRX_PY_ENGINE=regex`); the `python-regex` dialect
differs from `re` in Perl-like Unicode classes, `\p{…}`, simple case folding and variable-length lookbehind.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
