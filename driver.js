// irx driver: runs batches of full-match cases and reports 8 result bits per case.
// Protocol (one line each way, ASCII JSON):
//   request : [batch_seq, [[flags, A, R, regex], ...]]
//   response: "<batch_seq> <2 hex digits per case>"
// Bits: 0 test(A), 1 test(R), 2 SyntaxError at construction, 3 other exception,
//       4/5 second test(A)/test(R) (tierup only), 6 unsupported/skipped (linear only), 7 reserved.
// Shell adapters: d8 (arguments, version()), SpiderMonkey (scriptArgs), JSC (arguments),
// QuickJS (--std: scriptArgs[0] is the script, std.in.getline), and bridge mode for
// shells without stdin (tools/bridge.py embeds one batch as __IRX_BATCH/__IRX_MODE).
// Node/Bun (process + fs) and Deno: synchronous line I/O (async pipes would never flush
// inside the blocking loop).
var __irx_rt = (function () {
  var enc = typeof TextEncoder !== "undefined" ? new TextEncoder() : null, dec = typeof TextDecoder !== "undefined" ? new TextDecoder() : null;
  function lineReader(readChunk) {
    var buf = "", eof = false;
    return function () {
      for (;;) {
        var nl = buf.indexOf("\n");
        if (nl >= 0) { var l = buf.slice(0, nl); buf = buf.slice(nl + 1); return l; }
        if (eof) { if (buf.length) { var r = buf; buf = ""; return r; } return null; }
        var chunk = readChunk();
        if (chunk === null) eof = true; else buf += chunk;
      }
    };
  }
  if (typeof Deno === "object" && Deno.stdin) {
    var b = new Uint8Array(1 << 16);
    return { args: Deno.args, out: function (s) { Deno.stdout.writeSync(enc.encode(s + "\n")); },
             read: lineReader(function () { var n = Deno.stdin.readSync(b); return n === null || n === 0 ? null : dec.decode(b.subarray(0, n), { stream: true }); }) };
  }
  if (typeof process === "object" && process.versions && typeof require === "function") {
    var fs = require("fs"), nb = Buffer.alloc(1 << 16);
    return { args: process.argv.slice(2), out: function (s) { fs.writeSync(1, s + "\n"); },
             read: lineReader(function () {
               for (;;) {
                 try { var n = fs.readSync(0, nb, 0, nb.length, null); return n === 0 ? null : nb.toString("utf8", 0, n); }
                 catch (e) { if (e.code === "EAGAIN") continue; if (e.code === "EOF") return null; throw e; }
               }
             }) };
  }
  return null;
})();
var __irx_args = typeof __IRX_MODE !== "undefined" ? [__IRX_MODE]
  : __irx_rt ? __irx_rt.args
  : (typeof std === "object" && typeof scriptArgs !== "undefined") ? Array.prototype.slice.call(scriptArgs, 1)
  : typeof scriptArgs !== "undefined" ? scriptArgs : (typeof arguments !== "undefined" ? arguments : []);
(function () {
  "use strict";
  var args = __irx_args;
  var mode = args.length > 0 ? String(args[0]) : "interp";
  var bridge = typeof __IRX_BATCH !== "undefined";
  var out = __irx_rt ? __irx_rt.out : typeof print === "function" ? print
    : (typeof console === "object" && typeof console.log === "function") ? function (s) { console.log(s); } : null;
  if (out && typeof std === "object" && std.out) {
    var p0 = out;
    out = function (s) { p0(s); std.out.flush(); };
  }
  var read = bridge ? null
    : __irx_rt ? __irx_rt.read
    : typeof readline === "function" ? readline
    : (typeof std === "object" && std.in) ? function () { return std.in.getline(); } : null;
  if (!out || (!read && !bridge)) throw new Error("driver: shell lacks print/readline");
  var ver = "unknown";
  try { if (typeof version === "function") ver = String(version()); } catch (e) {}
  if (__irx_rt) ver = typeof Deno === "object" ? "deno-" + Deno.version.v8 : typeof Bun === "object" ? "bun-" + Bun.version : "node-" + process.versions.v8;

  var tierup = mode === "tierup";
  var linear = mode === "linear";
  var HEX = "0123456789abcdef";

  function wrap(r, flags) {
    if (flags.indexOf("m") >= 0) return "(?<![\\s\\S])(?:" + r + ")(?![\\s\\S])";
    return "^(?:" + r + ")$";
  }

  function runCase(c) {
    var flags = c[0], A = c[1], R = c[2], src = wrap(c[3], flags);
    var bits = 0, re;
    if (linear) {
      if (flags.indexOf("m") >= 0) return 64; // multiline-wrapper
      try { new RegExp(src, flags); } catch (e) { return (e instanceof SyntaxError) ? 4 : 8; }
      try { re = new RegExp(src, flags + "l"); } catch (e) { return (e instanceof SyntaxError) ? 64 : 8; }
    } else {
      try { re = new RegExp(src, flags); } catch (e) { return (e instanceof SyntaxError) ? 4 : 8; }
    }
    try {
      if (re.test(A)) bits |= 1;
      if (re.test(R)) bits |= 2;
      if (tierup) {
        if (re.test(A)) bits |= 16;
        if (re.test(R)) bits |= 32;
      }
    } catch (e) {
      return 8;
    }
    return bits;
  }

  // Span mode: unanchored search; 4 bytes per case (A start, A end, R start, R end) in
  // UTF-16 offsets, ff = no match; fe + bits when the case fails (see src/span.zig).
  // Long modes (lspan, lcapture): the same with 4 hex digits per position, ffff = none,
  // fffe + 00bb = failed.
  function hx(n) { return HEX[(n >> 4) & 15] + HEX[n & 15]; }
  function hx4(n) { return hx((n >> 8) & 255) + hx(n & 255); }
  function spanCase(c, wide) {
    var P = wide ? hx4 : hx, NONE = wide ? "ffff" : "ff";
    function fail(b) { return wide ? "fffe" + hx4(b) + "00000000" : "fe" + hx(b) + "0000"; }
    var re;
    try { re = new RegExp(c[3], c[0]); } catch (e) { return fail((e instanceof SyntaxError) ? 4 : 8); }
    var s = "";
    try {
      for (var k = 1; k <= 2; k++) {
        var m = re.exec(c[k]);
        s += m ? P(m.index) + P(m.index + m[0].length) : NONE + NONE;
      }
    } catch (e) { return fail(8); }
    return s;
  }

  // Bench mode (Shootout 2, tools/irx_bench.py): flags carry "<flags>#<reps>". Compile once (timed),
  // one untimed unanchored search of each subject, then <reps> timed searches of A and of R.
  // Response: 2 hex bits + compile, A, R nanoseconds as 12 hex digits each; "fe" + bits on failure.
  // "benchlinear": V8's linear-time engine (the l flag).
  var nowMs = (typeof performance === "object" && performance && typeof performance.now === "function") ? function () { return performance.now(); }
    : typeof preciseTime === "function" ? function () { return preciseTime() * 1000; }
    : (typeof os === "object" && os && typeof os.now === "function") ? function () { return os.now() / 1000; }
    : function () { return Date.now(); };
  if (__irx_rt && typeof process === "object" && process.hrtime && process.hrtime.bigint) nowMs = function () { return Number(process.hrtime.bigint()) / 1e6; };
  function hx12(ms) { var n = Math.max(0, Math.round(ms * 1e6)); var s = n.toString(16); while (s.length < 12) s = "0" + s; return s; }
  var sink = 0;
  function benchCase(c) {
    function fail(b) { return "fe" + hx(b) + "000000000000000000000000000000000000"; }
    var f = c[0], reps = 1, at = f.indexOf("#");
    if (at >= 0) { reps = Math.max(1, parseInt(f.substring(at + 1), 10) || 1); f = f.substring(0, at); }
    var re, t0 = nowMs();
    try { re = new RegExp(c[3], mode === "benchlinear" ? f + "l" : f); } catch (e) { return fail((e instanceof SyntaxError) ? 4 : 8); }
    var tc = nowMs() - t0, A = c[1], R = c[2], bits = 0, i;
    try {
      if (re.test(A)) bits |= 1;
      if (re.test(R)) bits |= 2;
      var t1 = nowMs();
      for (i = 0; i < reps; i++) if (re.test(A)) sink++;
      var t2 = nowMs();
      for (i = 0; i < reps; i++) if (re.test(R)) sink++;
      var t3 = nowMs();
    } catch (e) { return fail(8); }
    return hx(bits) + hx12(tc) + hx12(t2 - t1) + hx12(t3 - t2);
  }

  // Offset mode (ospan): flags carry "<flags>@<a>,<r>"; search each subject from that
  // lastIndex (g flag), report the span like span mode.
  function offsetCase(c, sticky) {
    var at = c[0].indexOf("@");
    var fl = c[0].slice(0, at), offs = c[0].slice(at + 1).split(",");
    var re;
    try { re = new RegExp(c[3], fl + (sticky ? "y" : "g")); } catch (e) { return "fe" + hx((e instanceof SyntaxError) ? 4 : 8) + "0000"; }
    var s = "";
    try {
      for (var k = 1; k <= 2; k++) {
        re.lastIndex = +offs[k - 1];
        var m = re.exec(c[k]);
        s += m ? hx(m.index) + hx(m.index + m[0].length) : "ffff";
      }
    } catch (e) { return "fe080000"; }
    return s;
  }

  // Global mode (gspan): the first 4 matches of matchAll per subject (each engine's own empty-match
  // advance), 2 hex digits per position, ff = no further match (see src/span.zig checkGlobal).
  var GLOBAL_MATCHES = 4;
  function globalCase(c) {
    var re;
    try { re = new RegExp(c[3], c[0] + "g"); } catch (e) { return "fe" + hx((e instanceof SyntaxError) ? 4 : 8) + "00".repeat(4 * GLOBAL_MATCHES - 2); }
    var s = "";
    try {
      for (var k = 1; k <= 2; k++) {
        var n = 0;
        for (var m of c[k].matchAll(re)) {
          if (n === GLOBAL_MATCHES) break;
          s += hx(m.index) + hx(m.index + m[0].length); n++;
        }
        for (; n < GLOBAL_MATCHES; n++) s += "ffff";
      }
    } catch (e) { return "fe08" + "00".repeat(4 * GLOBAL_MATCHES - 2); }
    return s;
  }

  // Capture mode: like span mode, plus groups 1..6 (via the d flag's indices) per subject:
  // 7 position pairs each, ffff = unset (see src/capture.zig).
  var CAP_GROUPS = 6;
  function captureCase(c, wide) {
    var P = wide ? hx4 : hx, NONE = wide ? "ffff" : "ff";
    function fail(b) { return wide ? "fffe" + hx4(b) + "0000".repeat(26) : "fe" + hx(b) + "00".repeat(26); }
    var re;
    try { re = new RegExp(c[3], c[0] + "d"); } catch (e) { return fail((e instanceof SyntaxError) ? 4 : 8); }
    var s = "";
    try {
      for (var k = 1; k <= 2; k++) {
        var m = re.exec(c[k]);
        for (var g = 0; g <= CAP_GROUPS; g++) {
          var ix = m && g < m.length ? m.indices[g] : undefined;
          s += ix ? P(ix[0]) + P(ix[1]) : NONE + NONE;
        }
      }
    } catch (e) { return fail(8); }
    return s;
  }

  if (bridge) read = (function () { var done = false; return function () { if (done) return null; done = true; return __IRX_BATCH; }; })();
  else out("ready " + ver + " mode=" + mode);
  // JSC's readline returns "" (not null) at end of input; irx never sends empty lines, so a long
  // run of them means stdin is closed.
  var empties = 0;
  for (;;) {
    var line = read();
    if (line === null || line === undefined) break;
    if (line.length === 0) { if (++empties > 1000) break; continue; }
    empties = 0;
    var msg = (bridge && typeof __IRX_BATCH_OBJ !== "undefined") ? __IRX_BATCH_OBJ : JSON.parse(line);
    var seq = msg[0], cases = msg[1];
    var parts = new Array(cases.length);
    for (var i = 0; i < cases.length; i++) {
      if (mode === "span" || mode === "lspan") { parts[i] = spanCase(cases[i], mode === "lspan"); continue; }
      if (mode === "ospan" || mode === "aspan") { parts[i] = offsetCase(cases[i], mode === "aspan"); continue; }
      if (mode === "gspan") { parts[i] = globalCase(cases[i]); continue; }
      if (mode === "bench" || mode === "benchlinear") { parts[i] = benchCase(cases[i]); continue; }
      if (mode === "capture" || mode === "lcapture") { parts[i] = captureCase(cases[i], mode === "lcapture"); continue; }
      var b = runCase(cases[i]);
      parts[i] = HEX[(b >> 4) & 15] + HEX[b & 15];
    }
    out(seq + " " + parts.join(""));
  }
})();
