/* irx line protocol for native regex hosts.
 * request : [batch_seq, [[flags, A, R, pattern], ...]]   (one ASCII JSON line)
 * response: "<batch_seq> <2 hex digits per case>"
 * Bits: 0 A matches, 1 R matches, 2 compile error, 3 runtime error,
 *       4/5 second A/R run (mode "repeat"), 6 unsupported (e.g. lone surrogate).
 * Mode "span": 8 hex digits per case = byte offsets A start, A end, R start, R end of an
 *   unanchored search (ff = no match), or fe + bits when the case fails (src/span.zig).
 *   Hosts that support it define host_span (byte offsets in out[0..3], -1 = no match;
 *   returns 0, or error bits 0x04/0x08).
 * Strings are decoded to UTF-8; a lone surrogate escape marks the case unsupported.
 * Each host provides: int host_case(const char *flags, const char *a, size_t alen,
 *   const char *r, size_t rlen, const char *pat, size_t plen, int repeat);  -> bits
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

int host_case(const char *flags, const char *a, size_t alen, const char *r, size_t rlen,
              const char *pat, size_t plen, int repeat);
const char *host_name(void);
int host_span(const char *flags, const char *const subj[2], const size_t lens[2],
              const char *pat, size_t plen, long out[4]);
/* Mode "capture": per subject, whole match then groups 1..6 as byte offsets (-1 = unset /
 * no match); returns 0 or failure bits (see src/capture.zig). */
#define CAP_PAIRS 7
int host_capture(const char *flags, const char *const subj[2], const size_t lens[2],
                 const char *pat, size_t plen, long out[2][2 * CAP_PAIRS]);

typedef struct { char *buf; size_t len, cap; int bad; } Str;

static void put(Str *s, const char *p, size_t n) {
    if (s->len + n + 1 > s->cap) { s->cap = (s->len + n + 1) * 2; s->buf = (char *)realloc(s->buf, s->cap); }
    memcpy(s->buf + s->len, p, n); s->len += n; s->buf[s->len] = 0;
}
static void put_cp(Str *s, uint32_t c) {
    char b[4]; size_t n;
    if (c < 0x80) { b[0] = c; n = 1; }
    else if (c < 0x800) { b[0] = 0xC0 | (c >> 6); b[1] = 0x80 | (c & 63); n = 2; }
    else if (c < 0x10000) { b[0] = 0xE0 | (c >> 12); b[1] = 0x80 | ((c >> 6) & 63); b[2] = 0x80 | (c & 63); n = 3; }
    else { b[0] = 0xF0 | (c >> 18); b[1] = 0x80 | ((c >> 12) & 63); b[2] = 0x80 | ((c >> 6) & 63); b[3] = 0x80 | (c & 63); n = 4; }
    put(s, b, n);
}
static int hex4(const char *p, uint32_t *out) {
    uint32_t v = 0;
    for (int i = 0; i < 4; i++) {
        char c = p[i]; v <<= 4;
        if (c >= '0' && c <= '9') v |= c - '0'; else if (c >= 'a' && c <= 'f') v |= c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') v |= c - 'A' + 10; else return 0;
    }
    *out = v; return 1;
}
/* Parse a JSON string at *pp (pointing at '"'); advance past it. */
static int parse_str(const char **pp, Str *s) {
    const char *p = *pp; s->len = 0; s->bad = 0; put(s, "", 0);
    if (*p != '"') return 0;
    p++;
    while (*p && *p != '"') {
        if (*p != '\\') { put(s, p, 1); p++; continue; }
        p++;
        switch (*p) {
        case '"': put(s, "\"", 1); p++; break;
        case '\\': put(s, "\\", 1); p++; break;
        case '/': put(s, "/", 1); p++; break;
        case 'n': put(s, "\n", 1); p++; break;
        case 'r': put(s, "\r", 1); p++; break;
        case 't': put(s, "\t", 1); p++; break;
        case 'b': put(s, "\b", 1); p++; break;
        case 'f': put(s, "\f", 1); p++; break;
        case 'u': {
            uint32_t c, d;
            if (!hex4(p + 1, &c)) return 0;
            p += 5;
            if (c >= 0xD800 && c <= 0xDBFF && p[0] == '\\' && p[1] == 'u' && hex4(p + 2, &d) && d >= 0xDC00 && d <= 0xDFFF) {
                c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00); p += 6;
            } else if (c >= 0xD800 && c <= 0xDFFF) { s->bad = 1; c = 0xFFFD; }
            put_cp(s, c); break;
        }
        default: return 0;
        }
    }
    if (*p != '"') return 0;
    *pp = p + 1; return 1;
}
static void skip_ws(const char **p) { while (**p == ' ') (*p)++; }

int main(int argc, char **argv) {
    const char *mode = argc > 1 ? argv[1] : "default";
    int repeat = strcmp(mode, "repeat") == 0 || strcmp(mode, "tierup") == 0;
    int span = strcmp(mode, "span") == 0;
    int capture = strcmp(mode, "capture") == 0;
    setvbuf(stdout, NULL, _IOFBF, 1 << 16);
    printf("ready %s mode=%s\n", host_name(), mode); fflush(stdout);
    char *line = NULL; size_t cap = 0; ssize_t n;
    Str f = {0}, a = {0}, r = {0}, pat = {0};
    Str out = {0};
    while ((n = getline(&line, &cap, stdin)) > 0) {
        const char *p = line;
        if (*p != '[') continue;
        p++;
        long long seq = strtoll(p, (char **)&p, 10);
        out.len = 0;
        char hdr[32]; snprintf(hdr, sizeof hdr, "%lld ", seq); put(&out, hdr, strlen(hdr));
        if (*p == ',') p++;
        if (*p == '[') p++;
        for (;;) {
            skip_ws(&p);
            if (*p == ']') break;
            if (*p == ',') { p++; continue; }
            if (*p != '[') { fprintf(stderr, "bad request\n"); return 1; }
            p++;
            int ok = parse_str(&p, &f) && *p++ == ',' && parse_str(&p, &a) && *p++ == ',' &&
                     parse_str(&p, &r) && *p++ == ',' && parse_str(&p, &pat) && *p++ == ']';
            if (!ok) { fprintf(stderr, "bad case\n"); return 1; }
            if (capture) {
                char hx[4 * 2 * CAP_PAIRS + 1];
                if (a.bad || r.bad || pat.bad) { snprintf(hx, sizeof hx, "fe40"); memset(hx + 4, '0', sizeof hx - 5); hx[sizeof hx - 1] = 0; }
                else {
                    const char *subj[2] = {a.buf, r.buf}; size_t lens[2] = {a.len, r.len}; long o[2][2 * CAP_PAIRS];
                    int e = host_capture(f.buf, subj, lens, pat.buf, pat.len, o);
                    if (e) { snprintf(hx, sizeof hx, "fe%02x", e & 0xff); memset(hx + 4, '0', sizeof hx - 5); hx[sizeof hx - 1] = 0; }
                    else {
                        char *q = hx;
                        for (int k = 0; k < 2; k++) for (int g = 0; g < CAP_PAIRS; g++) {
                            long s = o[k][2 * g], t = o[k][2 * g + 1];
                            q += sprintf(q, "%02lx%02lx", s < 0 ? 255 : s, s < 0 ? 255 : t);
                        }
                    }
                }
                put(&out, hx, 4 * 2 * CAP_PAIRS);
                continue;
            }
            if (span) {
                char hx[9];
                if (a.bad || r.bad || pat.bad) snprintf(hx, sizeof hx, "fe400000");
                else {
                    const char *subj[2] = {a.buf, r.buf}; size_t lens[2] = {a.len, r.len}; long o[4];
                    int e = host_span(f.buf, subj, lens, pat.buf, pat.len, o);
                    if (e) snprintf(hx, sizeof hx, "fe%02x0000", e & 0xff);
                    else snprintf(hx, sizeof hx, "%02lx%02lx%02lx%02lx", o[0] < 0 ? 255 : o[0], o[0] < 0 ? 255 : o[1], o[2] < 0 ? 255 : o[2], o[2] < 0 ? 255 : o[3]);
                }
                put(&out, hx, 8);
                continue;
            }
            int bits = (a.bad || r.bad || pat.bad) ? 0x40
                     : host_case(f.buf, a.buf, a.len, r.buf, r.len, pat.buf, pat.len, repeat);
            char hx[3]; snprintf(hx, sizeof hx, "%02x", bits & 0xff); put(&out, hx, 2);
        }
        put(&out, "\n", 1);
        fwrite(out.buf, 1, out.len, stdout); fflush(stdout);
    }
    return 0;
}
