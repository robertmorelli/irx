You are triaging one finished irx fuzzing run, unattended. Nobody will answer questions; just do the work and write the report.

irx is an inverted-pair regex fuzzer that checks a regex engine against an exact model (see README.md, sections "What each case checks", "Output layout", "Bug ledger"). A finding means the engine and the model disagree: either an engine bug, a model gap, or a known/expected quirk.

Steps:
1. Read the run's summary.json and groups/counts.txt (and groups/*.txt) to see what signature groups occurred.
2. Read targets/<engine>/README.md and the README "Bug ledger" section to learn which shapes are already known for this engine (known bugs, documented quirks, model gaps already noted).
3. For each group NOT already explained there, look at one or two findings (case.json, repro.min.js / minimized.irx, triage.json) and run `zig-out/bin/irx replay <finding dir>` to confirm it reproduces. Use tools/probe.py for small ad-hoc checks if useful.
4. Decide per group: known (cite the ledger ID or README note), new engine bug candidate, model gap, or harness/host problem.

Write the report as Markdown to the path given below: a one-line verdict first (e.g. "clean: all groups known" or "NEW: 2 candidates"), then a short table of groups with verdicts, then details only for new candidates (minimized pattern, subject, expected vs actual, replay result).

Ledger: for each NEW engine bug candidate that you reproduced yourself with a direct, minimal probe (tools/probe.py, or a tiny program against the same library), add a row to the "Bug ledger" table in the ledger checkout named below (its README.md, not the README.md of this repository). Copy the format of the neighbouring rows for that engine exactly: next free ID for the engine (`IRX-<ENGINE>-<n>`; also skip IDs listed as taken below), status `Open · not filed`, the minimal repro with actual → expected (cite Perl or another engine as the reference), then a "Tested:" cell with versions, what does and does not fail, and "Found by the `<label>` run on `<target>` on <host> (triage report `<run name>`)" (host and label are given below). Also bump the "confirmed bug IDs" and "distinct bug shapes" counts near the top, and add the ID to that engine's row(s) in the targets table. Do not add rows for known bugs, model gaps, harness problems, or anything you did not reproduce; do not touch anything else in the ledger checkout, and do not run git there (the loop commits and opens a PR). If unsure whether something is new, leave the ledger alone and explain in the report.

Rules: work only inside this repository and the ledger checkout. Do not edit tracked files of this repository, do not git commit/push/checkout, do not install anything, do not delete anything outside the run directory, do not kill processes, and do not start fuzzing campaigns (another process uses the CPUs). Keep it efficient: you have about 45 minutes.
