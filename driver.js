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
  for (;;) {
    var line = read();
    if (line === null || line === undefined) break;
    if (line.length === 0) continue;
    var msg = (bridge && typeof __IRX_BATCH_OBJ !== "undefined") ? __IRX_BATCH_OBJ : JSON.parse(line);
    var seq = msg[0], cases = msg[1];
    var parts = new Array(cases.length);
    for (var i = 0; i < cases.length; i++) {
      if (mode === "span" || mode === "lspan") { parts[i] = spanCase(cases[i], mode === "lspan"); continue; }
      if (mode === "capture" || mode === "lcapture") { parts[i] = captureCase(cases[i], mode === "lcapture"); continue; }
      var b = runCase(cases[i]);
      parts[i] = HEX[(b >> 4) & 15] + HEX[b & 15];
    }
    out(seq + " " + parts.join(""));
  }
})();
