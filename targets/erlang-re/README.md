# Erlang re (OTP 29)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py erlang-re`.
Erlang/OTP's `re` module (Homebrew `erlang`), which wraps PCRE2 in OTP 28+, compiled with `unicode` and `ucp`;
the host is an escript (`hosts/erlang/host.escript`) using `re:run` with `offset` and `anchored`. It shares the
`pcre2` dialect, so it checks OTP's bundled PCRE2 and its wrapper. Bugs found here are listed in the
[bug ledger](../../README.md#bug-ledger).
