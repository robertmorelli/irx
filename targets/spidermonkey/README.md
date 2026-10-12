# SpiderMonkey 158.0b5 (jsvu)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py spidermonkey`.
Firefox's JS shell, installed with jsvu into `vendor/jsvu-home`
(`HOME=vendor/jsvu-home vendor/node/node_modules/.bin/jsvu --os=mac64arm --engines=spidermonkey`). Its regexp
engine is a port of V8's Irregexp with SpiderMonkey's own Unicode, case-folding and string handling, run by
`driver.js` directly (`scriptArgs`, `readline`). Bugs found here are listed in the
[bug ledger](../../README.md#bug-ledger).
