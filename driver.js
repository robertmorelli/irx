// irx driver: runs batches of full-match cases and reports 8 result bits per case.
// Protocol (one line each way, ASCII JSON):
//   request : [batch_seq, [[flags, A, R, regex], ...]]
//   response: "<batch_seq> <2 hex digits per case>"
// Bits: 0 test(A), 1 test(R), 2 SyntaxError at construction, 3 other exception,
//       4/5 second test(A)/test(R) (tierup only), 6 unsupported/skipped (linear only), 7 reserved.
// Shell adapters: d8 (arguments, version()), SpiderMonkey (scriptArgs), JSC (arguments),
// QuickJS (--std: scriptArgs[0] is the script, std.in.getline), and bridge mode for
// shells without stdin (tools/bridge.py embeds one batch as __IRX_BATCH/__IRX_MODE).
var __irx_args = typeof __IRX_MODE !== "undefined" ? [__IRX_MODE]
  : (typeof std === "object" && typeof scriptArgs !== "undefined") ? Array.prototype.slice.call(scriptArgs, 1)
  : typeof scriptArgs !== "undefined" ? scriptArgs : (typeof arguments !== "undefined" ? arguments : []);
(function () {
  "use strict";
  var args = __irx_args;
  var mode = args.length > 0 ? String(args[0]) : "interp";
  var bridge = typeof __IRX_BATCH !== "undefined";
  var out = typeof print === "function" ? print
    : (typeof console === "object" && typeof console.log === "function") ? function (s) { console.log(s); } : null;
  if (out && typeof std === "object" && std.out) {
    var p0 = out;
    out = function (s) { p0(s); std.out.flush(); };
  }
  var read = bridge ? null
    : typeof readline === "function" ? readline
    : (typeof std === "object" && std.in) ? function () { return std.in.getline(); } : null;
  if (!out || (!read && !bridge)) throw new Error("driver: shell lacks print/readline");
  var ver = "unknown";
  try { if (typeof version === "function") ver = String(version()); } catch (e) {}

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

  if (bridge) read = (function () { var done = false; return function () { if (done) return null; done = true; return __IRX_BATCH; }; })();
  else out("ready " + ver + " mode=" + mode);
  for (;;) {
    var line = read();
    if (line === null || line === undefined) break;
    if (line.length === 0) continue;
    var msg = JSON.parse(line);
    var seq = msg[0], cases = msg[1];
    var parts = new Array(cases.length);
    for (var i = 0; i < cases.length; i++) {
      var b = runCase(cases[i]);
      parts[i] = HEX[(b >> 4) & 15] + HEX[b & 15];
    }
    out(seq + " " + parts.join(""));
  }
})();
