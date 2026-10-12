// irx host: MinRX (gawk 5.4's new POSIX matcher, from its support library) through minrx_regcomp/regnexec, in the C
// locale, so byte-oriented). Perl-dialect input is translated as for llvm_host.cc:
// (?: and (?<gN> -> (, \x{H} -> raw UTF-8, \d -> [0-9], \s -> [[:space:]], \w -> [[:alnum:]_].
// Lazy quantifiers, lookarounds and \b have no ERE form (translation error -> compile error bit).
#include "minrx.h"
#include <string>
#include "proto.h"
const char *host_name(void) { return "minrx"; }
static bool translate(const std::string &s, std::string &o) {
    for (size_t i = 0; i < s.size(); i++) {
        char c = s[i];
        if (c == '\\') {
            char d = s[++i];
            if (d == 'x') { size_t e = s.find('}', i); uint32_t cp = std::stoul(s.substr(i + 2, e - i - 2), nullptr, 16); i = e;
                Str t = {0}; put_cp(&t, cp); std::string lit(t.buf, t.len); free(t.buf);
                if (lit.size() == 1 && strchr("^$.|?*+()[]{}\\", lit[0])) o += '\\'; o += lit; }
            else if (d == 'd') o += "[0-9]"; else if (d == 'D') o += "[^0-9]";
            else if (d == 's') o += "[[:space:]]"; else if (d == 'S') o += "[^[:space:]]";
            else if (d == 'w') o += "[[:alnum:]_]"; else if (d == 'W') o += "[^[:alnum:]_]";
            else if (d == 'b' || d == 'B') return false;
            else { o += '\\'; o += d; }
        } else if (c == '(' && s.compare(i, 3, "(?:") == 0) { o += '('; i += 2; }
        else if (c == '(' && s.compare(i, 3, "(?<") == 0 && i + 3 < s.size() && s[i + 3] == 'g') { size_t e = s.find('>', i); o += '('; i = e; }
        else if (c == '(' && i + 1 < s.size() && s[i + 1] == '?') return false;
        else if ((c == '*' || c == '+' || c == '?' || c == '}') && i + 1 < s.size() && s[i + 1] == '?') return false;
        else if (c == '[') {
            o += '['; i++;
            if (s[i] == '^') { o += '^'; i++; }
            std::string items, tail;
            while (s[i] != ']') {
                if (s[i] == '\\') { char d = s[++i];
                    if (d == 'x') { size_t e = s.find('}', i); uint32_t cp = std::stoul(s.substr(i + 2, e - i - 2), nullptr, 16); i = e; Str t = {0}; put_cp(&t, cp); items.append(t.buf, t.len); free(t.buf); }
                    else if (d == ']') o += ']';  // must come first
                    else if (d == '-') tail += '-';
                    else if (d == 'd') items += "0-9"; else if (d == 's') items += "[:space:]"; else if (d == 'w') items += "[:alnum:]_";
                    else items += d;
                } else items += s[i];
                i++;
            }
            o += items + tail + ']';
        } else o += c;
    }
    return true;
}

static int compile(minrx_regex_t *re, const std::string &src, const char *flags) {
    int f = MINRX_REG_EXTENDED;
    if (strchr(flags, 'i')) f |= MINRX_REG_ICASE;
    if (strchr(flags, 'm')) f |= MINRX_REG_NEWLINE;
    return minrx_regcomp(re, src.c_str(), f);
}
/* Leftmost-longest match of the whole compiled pattern in s[0..len). */
static bool search(minrx_regex_t *re, const char *s, size_t len, minrx_regmatch_t *m) {
    return minrx_regnexec(re, len, s, 1, m, 0) == 0;
}
int host_case(const char *flags, const char *a, size_t alen, const char *r, size_t rlen, const char *pat, size_t plen, int repeat) {
    std::string ere;
    if (!translate(std::string(pat, plen), ere)) return 0x04;
    // Under REG_NEWLINE ^/$ are line anchors, so the wrapper can't force a full match there;
    // instead match unanchored and require the (leftmost-longest) match to span the subject.
    bool m = strchr(flags, 'm') != nullptr;
    minrx_regex_t re;
    if (compile(&re, m ? "(" + ere + ")" : "^(" + ere + ")$", flags) != 0) return 0x04;
    int bits = 0;
    const char *subj[2] = {a, r}; size_t lens[2] = {alen, rlen};
    for (int rep = 0; rep < (repeat ? 2 : 1); rep++)
        for (int k = 0; k < 2; k++) {
            minrx_regmatch_t mm[1];
            bool hit = search(&re, subj[k], lens[k], mm) && (!m || (mm[0].rm_so == 0 && (size_t)mm[0].rm_eo == lens[k]));
            if (hit) bits |= (1 << k) << (rep * 4);
        }
    minrx_regfree(&re);
    return bits;
}
int host_span(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[4]) {
    if (host_anchored) return 0x40;
    if (host_start[0] || host_start[1]) return 0x40; /* no start-offset search with irx's ^ semantics */
    std::string ere;
    if (!translate(std::string(pat, plen), ere)) return 0x04;
    minrx_regex_t re;
    if (compile(&re, "(" + ere + ")", flags) != 0) return 0x04;
    for (int k = 0; k < 2; k++) {
        minrx_regmatch_t mm[1];
        if (search(&re, subj[k], lens[k], mm)) { out[2 * k] = mm[0].rm_so; out[2 * k + 1] = mm[0].rm_eo; }
        else out[2 * k] = out[2 * k + 1] = -1;
    }
    minrx_regfree(&re);
    return 0;
}
/* Capture mode is not modelled for this engine (POSIX submatch rules): unsupported. */
int host_capture(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[2][2 * CAP_PAIRS]) {
    (void)flags; (void)subj; (void)lens; (void)pat; (void)plen; (void)out;
    return 0x40;
}
