# ICU NSRegularExpression

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py icu`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN icu 1m results -->
### icu: 1-minute smoke campaign

* 59,392 patterns, 2 tables, 232 distinct findings; self-check 281,792 probes, 3,280 mismatches, 0 engine failures
* findings by kind: 232 timeout (batch), 199 selfcheck_mismatch (selfcheck)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END icu 1m results -->

<!-- BEGIN icu 10m results -->
### ICU NSRegularExpression: 10m campaign

* 599,840 patterns, 7 tables, 2,342 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 2,342 timeout (batch)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END icu 10m results -->

<!-- BEGIN icu 10m triage -->
### icu: 10-minute campaign triage

* New: **IRX-ICU-1**, an infinite loop: a lazy unbounded loop whose body matches empty, followed by a failure
  (`a(?:)*?b` on `"ac"`). The fuzzer generates this shape so often that every batch timed out and the campaign
  executed **0** cases, so this run says nothing else about ICU. Rerun after excluding lazy loops over nullable
  bodies from the `icu` dialect, or with a per-case watchdog.
* Self-check clean.
<!-- END icu 10m triage -->
