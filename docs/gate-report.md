# irx performance gate

| scenario | cases | cases/s | tables | zero-mass | build ms/table | sample us | print us | engine-wait us/case | peak managed MiB | peak RSS MiB | mismatches | replay | caps |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| short-strings | 4000 | 404 | 5 | 0 | 2078.5 | 182.39 | 0.39 | 48.2 | 855 | 376 | 0 | ok | ok |
| long-strings | 3000 | 209 | 4 | 0 | 4167.5 | 297.79 | 0.37 | 1809.4 | 936 | 495 | 0 | ok | ok |
| case-folding | 4000 | 249 | 5 | 0 | 3787.9 | 245.99 | 0.39 | 49.6 | 986 | 686 | 0 | ok | ok |
| multiline-dotall | 3000 | 245 | 4 | 0 | 3759.2 | 203.95 | 0.37 | 45.7 | 991 | 703 | 0 | ok | ok |
| repeated-length | 3000 | 122 | 7 | 0 | 4010.6 | 423.03 | 0.43 | 439.7 | 1086 | 840 | 111 | ok | ok |
| tiny-budgets | 3000 | 7064 | 7 | 0 | 10.5 | 6.48 | 0.31 | 100.4 | 96 | 841 | 0 | ok | ok |
| retry-exhaustion | 0 | 0 | 0 | 0 | 0.0 | 0.00 | 0.00 | 0.0 | 0 | 841 | 0 | ok | ok |

> retry-exhaustion: table retry exhaustion: 5 consecutive failed attempts for table 0 (zero-mass=0, resource=5, invalid=0) (finite retries verified)

Measured 2026-10-09 on an Apple Silicon Mac (8 physical cores), d8 15.5.35.20 (Homebrew), irx ReleaseFast,
single lane, interp mode, `samples_per_table` 500–1000 (so table builds dominate wall time; production
campaigns use 100k samples per table, where sampling amortizes to ~7 µs/case). `repeated-length` mismatches
are the irregexp quick-check regression described in the README. Full campaigns (3 modes, 2 lanes) ran at
~11k cases/s.
