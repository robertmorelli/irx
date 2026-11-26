## This run tested Perl PR #25087, not blead

The engine was `tools/perl-pr` (vendor/perl5-pr: PR #25087 "fix various regex errors", branch yves/fix_25083_and_friends, head 701da6a), which aims to fix #25081, #25083, #25084, #25085 and #25086 (IRX-PERL-8, -10, -11, -12, -13). Expect those to be gone; if one still reproduces on the PR build, that is a finding (the fix is incomplete), not "known".

For every finding you would call new, also replay it on `tools/perl-blead` (the same Perl without the PR) and on a release (`perl` 5.44 if installed) and say in the report and the ledger "Tested:" cell which builds fail:

- **PR regression**: only the PR build fails (blead is correct). Give it the ID `IRX-PERL-<n>-SPAWNCAMP`: a bug the PR would introduce, caught before it merges. Report it on PR #25087.
- **Pre-existing**: blead fails too. Give it a plain `IRX-PERL-<n>`, with no suffix, even though this run found it. If it is in the family of an issue the PR targets, say so (it belongs on that issue).

`<n>` is the next free number across all IRX-PERL IDs (with or without the suffix, and skipping the taken IDs listed above). Status `Open · not filed`.
