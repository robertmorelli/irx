# PCRE2 10.49 (interpreter; IRX_PCRE2_JIT=1 for the JIT)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py pcre2`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN pcre2 1m results -->
### pcre2: 1-minute smoke campaign

* 447,104 patterns, 6 tables, 204 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 162 timeout (batch), 42 exception

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2 | exception | `u` | `"a\r"` | `"aaà\r"` | `(?:(?:(?:\D?){0,}){0,3})*a\x{D}` | 08 |
| 2 | exception | `u` | `"aaaaaaaa"` | `""` | `(?:(?:(?:(?:a(?:(?:)\|(?:)\|(?:){0,1}))+){2,}){2,2}){2}` | 08 |
| 2 | exception | `u` | `"aa"` | `"aaàa"` | `(?:(?:(?:(?:(?:)\|.)*)+\|(?:))*)+aa` | 08 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END pcre2 1m results -->
