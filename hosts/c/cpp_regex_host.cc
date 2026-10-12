// irx host: C++ std::regex from the platform's standard library (libc++ on macOS), ECMAScript grammar,
// over code points (std::wregex; wchar_t is 32-bit here). Flags: i -> icase, m -> multiline; s, u, v
// have no equivalent (the target's flag sets leave them out). Full match via regex_match.
#include <regex>
#include <string>
#include <cwchar>
#include "proto.h"
const char *host_name(void) { return "cpp-std-regex"; }
static std::wstring widen(const char *s, size_t n) {  // UTF-8 -> code points
    std::wstring w;
    for (size_t i = 0; i < n;) {
        unsigned char c = (unsigned char)s[i];
        uint32_t cp; int len;
        if (c < 0x80) { cp = c; len = 1; } else if (c < 0xE0) { cp = c & 0x1F; len = 2; } else if (c < 0xF0) { cp = c & 0x0F; len = 3; } else { cp = c & 0x07; len = 4; }
        for (int k = 1; k < len && i + k < n; k++) cp = (cp << 6) | ((unsigned char)s[i + k] & 0x3F);
        w.push_back((wchar_t)cp); i += len;
    }
    return w;
}
/* \x{H} -> the literal code point (escaped if it is a regex metacharacter): std::regex has no
 * \x{…} or \u{…} form. */
static std::wstring pattern(const char *p, size_t n) {
    std::wstring in = widen(p, n), out;
    for (size_t i = 0; i < in.size(); i++) {
        if (in[i] == L'\\' && i + 2 < in.size() && in[i + 1] == L'x' && in[i + 2] == L'{') {
            size_t e = in.find(L'}', i);
            wchar_t c = (wchar_t)std::stoul(std::wstring(in, i + 3, e - i - 3), nullptr, 16);
            if (wcschr(L"^$\\.*+?()[]{}|/-", c)) out.push_back(L'\\');
            out.push_back(c); i = e;
        } else if (in[i] == L'\\' && i + 1 < in.size()) { out.push_back(in[i]); out.push_back(in[++i]); }
        else out.push_back(in[i]);
    }
    return out;
}
static std::regex_constants::syntax_option_type opts(const char *flags) {
    auto o = std::regex_constants::ECMAScript;
    if (strchr(flags, 'i')) o |= std::regex_constants::icase;
    if (strchr(flags, 'm')) o |= std::regex_constants::multiline;
    return o;
}
/* Code-point index -> UTF-8 byte offset in s (the target reports utf8 units). */
static long byteOff(const char *s, size_t n, long cps) {
    size_t i = 0; long k = 0;
    while (i < n && k < cps) { unsigned char c = (unsigned char)s[i]; i += c < 0x80 ? 1 : c < 0xE0 ? 2 : c < 0xF0 ? 3 : 4; k++; }
    return (long)i;
}
int host_case(const char *flags, const char *a, size_t alen, const char *r, size_t rlen, const char *pat, size_t plen, int repeat) {
    std::wregex re;
    try { re.assign(pattern(pat, plen), opts(flags)); } catch (const std::regex_error &) { return 0x04; }
    int bits = 0;
    const char *subj[2] = {a, r}; size_t lens[2] = {alen, rlen};
    try {
        for (int rep = 0; rep < (repeat ? 2 : 1); rep++)
            for (int k = 0; k < 2; k++)
                if (std::regex_match(widen(subj[k], lens[k]), re)) bits |= (1 << k) << (rep * 4);
    } catch (const std::regex_error &) { return 0x40; }  // error_complexity / error_stack: resource limits
    return bits;
}
int host_span(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[4]) {
    if (host_anchored || host_start[0] || host_start[1]) return 0x40;
    std::wregex re;
    try { re.assign(pattern(pat, plen), opts(flags)); } catch (const std::regex_error &) { return 0x04; }
    try {
        for (int k = 0; k < 2; k++) {
            std::wstring w = widen(subj[k], lens[k]);
            std::wsmatch m;
            if (std::regex_search(w, m, re)) { out[2 * k] = byteOff(subj[k], lens[k], m.position(0)); out[2 * k + 1] = byteOff(subj[k], lens[k], m.position(0) + m.length(0)); }
            else out[2 * k] = out[2 * k + 1] = -1;
        }
    } catch (const std::regex_error &) { return 0x40; }
    return 0;
}
/* Capture mode: whole match then groups 1..6 per subject, UTF-8 byte offsets (-1 = unset). */
int host_capture(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[2][2 * CAP_PAIRS]) {
    std::wregex re;
    try { re.assign(pattern(pat, plen), opts(flags)); } catch (const std::regex_error &) { return 0x04; }
    try {
        for (int k = 0; k < 2; k++) {
            std::wstring w = widen(subj[k], lens[k]);
            std::wsmatch m;
            bool hit = std::regex_search(w, m, re);
            for (int g = 0; g < CAP_PAIRS; g++) {
                if (hit && (size_t)g < m.size() && m[g].matched) {
                    long p = (long)m.position((std::size_t)g), e = p + (long)m.length((std::size_t)g);
                    out[k][2 * g] = byteOff(subj[k], lens[k], p); out[k][2 * g + 1] = byteOff(subj[k], lens[k], e);
                } else out[k][2 * g] = out[k][2 * g + 1] = -1;
            }
        }
    } catch (const std::regex_error &) { return 0x40; }
    return 0;
}
