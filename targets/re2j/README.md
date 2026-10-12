# re2j 1.8

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py re2j`.
Google's pure-Java port of RE2 (`com.google.re2j`, jar from Maven Central in `vendor/re2j`), checked against the
same `re2` dialect as the C++ library. The host is the `java.util.regex` host with re2j's `Pattern`/`Matcher`;
re2j has no `region`, so there is no sticky mode. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
