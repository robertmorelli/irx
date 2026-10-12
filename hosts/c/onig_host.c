/* Oniguruma host. Default Ruby syntax (Ruby's /m is dotall; ^/$ are always line anchors).
 * IRX_ONIG_SYNTAX=perl|java|python|oniguruma picks another syntax; those start single-line
 * (^/$ at string ends), so the m flag sets ONIG_OPTION_NEGATE_SINGLELINE. IRX_ONIG_ASCII makes
 * \w \d \s and POSIX classes ASCII-only. */
#include <oniguruma.h>
#include "proto.h"
static OnigSyntaxType *syntax(void) {
    const char *s = getenv("IRX_ONIG_SYNTAX");
    if (!s || !*s || !strcmp(s, "ruby")) return ONIG_SYNTAX_RUBY;
    if (!strcmp(s, "perl")) return ONIG_SYNTAX_PERL;
    if (!strcmp(s, "java")) return ONIG_SYNTAX_JAVA;
    if (!strcmp(s, "python")) return ONIG_SYNTAX_PYTHON;
    return ONIG_SYNTAX_ONIGURUMA;
}
/* Java and Python syntax have no \\x{H} (Java syntax silently misreads it): write it as the
 * literal character, escaped if it is a metacharacter. Returns a malloc'd buffer. */
static Str native(const char *pat, size_t plen) {
    Str o = {0};
    int lit = syntax() == ONIG_SYNTAX_JAVA || syntax() == ONIG_SYNTAX_PYTHON;
    for (size_t i = 0; i < plen; i++) {
        if (lit && pat[i] == '\\' && i + 2 < plen && pat[i + 1] == 'x' && pat[i + 2] == '{') {
            size_t e = i + 3; uint32_t cp = 0;
            while (e < plen && pat[e] != '}') { char c = pat[e++]; cp = cp * 16 + (uint32_t)(c <= '9' ? c - '0' : (c | 32) - 'a' + 10); }
            if (cp <= 0xFFFF) { char u[8]; snprintf(u, sizeof u, "\\u%04X", (unsigned)cp); put(&o, u, 6); }  /* survives (?x:) */
            else put_cp(&o, cp);
            i = e;
        } else if (pat[i] == '\\' && i + 1 < plen) { put(&o, pat + i, 2); i++; }
        else put(&o, pat + i, 1);
    }
    if (!o.buf) put(&o, "", 0);
    return o;
}
static OnigOptionType options(const char *flags) {
    OnigOptionType opt = ONIG_OPTION_NONE;
    if (strchr(flags, 'i')) opt |= ONIG_OPTION_IGNORECASE;
    if (strchr(flags, 's')) opt |= ONIG_OPTION_MULTILINE;  /* Oniguruma's MULTILINE is dotall */
    if (strchr(flags, 'm') && syntax() != ONIG_SYNTAX_RUBY) opt |= ONIG_OPTION_NEGATE_SINGLELINE;
    if (getenv("IRX_ONIG_ASCII")) opt |= ONIG_OPTION_WORD_IS_ASCII | ONIG_OPTION_DIGIT_IS_ASCII | ONIG_OPTION_SPACE_IS_ASCII | ONIG_OPTION_POSIX_IS_ASCII;
    return opt;
}
const char *host_name(void) { static char b[64]; snprintf(b, sizeof b, "oniguruma-%s%s%s%s", onig_version(), getenv("IRX_ONIG_SYNTAX") ? "-" : "", getenv("IRX_ONIG_SYNTAX") ? getenv("IRX_ONIG_SYNTAX") : "", getenv("IRX_ONIG_ASCII") ? "-ascii" : ""); return b; }
int host_case(const char *flags, const char *a, size_t alen, const char *r, size_t rlen, const char *pat, size_t plen, int repeat) {
    OnigOptionType opt = options(flags);
    /* Python syntax has no \\z; its \\Z is the absolute end. */
    const char *end = syntax() == ONIG_SYNTAX_PYTHON ? ")\\Z" : ")\\z";
    Str np = native(pat, plen);
    Str w = {0}; put(&w, "\\A(?:", 5); put(&w, np.buf, np.len); put(&w, end, 3); free(np.buf);
    regex_t *re; OnigErrorInfo ei;
    int rc = onig_new(&re, (UChar *)w.buf, (UChar *)w.buf + w.len, opt, ONIG_ENCODING_UTF8, syntax(), &ei);
    free(w.buf);
    if (rc != ONIG_NORMAL) return 0x04;
    int bits = 0;
    const char *subj[2] = {a, r}; size_t lens[2] = {alen, rlen};
    for (int rep = 0; rep < (repeat ? 2 : 1); rep++)
        for (int k = 0; k < 2; k++) {
            const UChar *s = (const UChar *)subj[k], *e = s + lens[k];
            int m = onig_search(re, s, e, s, e, NULL, ONIG_OPTION_NONE);
            if (m >= 0) bits |= (1 << k) << (rep * 4);
            else if (m != ONIG_MISMATCH) { bits = 0x08; goto done; }
        }
done:
    onig_free(re);
    return bits;
}
int host_span(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[4]) {
    OnigOptionType opt = options(flags);
    regex_t *re; OnigErrorInfo ei;
    Str np = native(pat, plen);
    int rc0 = onig_new(&re, (const UChar *)np.buf, (const UChar *)np.buf + np.len, opt, ONIG_ENCODING_UTF8, syntax(), &ei);
    free(np.buf);
    if (rc0 != ONIG_NORMAL) return 0x04;
    OnigRegion *rg = onig_region_new();
    int e = 0;
    for (int k = 0; k < 2; k++) {
        const UChar *s = (const UChar *)subj[k], *end = s + lens[k];
        int m = host_anchored ? onig_match(re, s, end, s + host_start[k], rg, ONIG_OPTION_NONE)
                              : onig_search(re, s, end, s + host_start[k], end, rg, ONIG_OPTION_NONE);
        if (m >= 0) { out[2 * k] = rg->beg[0]; out[2 * k + 1] = rg->end[0]; }
        else if (m == ONIG_MISMATCH) out[2 * k] = out[2 * k + 1] = -1;
        else { e = 0x08; break; }
    }
    onig_region_free(rg, 1); onig_free(re);
    return e;
}
int host_capture(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[2][2 * CAP_PAIRS]) {
    OnigOptionType opt = options(flags);
    regex_t *re; OnigErrorInfo ei;
    Str np = native(pat, plen);
    int rc0 = onig_new(&re, (const UChar *)np.buf, (const UChar *)np.buf + np.len, opt, ONIG_ENCODING_UTF8, syntax(), &ei);
    free(np.buf);
    if (rc0 != ONIG_NORMAL) return 0x04;
    OnigRegion *rg = onig_region_new();
    int e = 0;
    for (int k = 0; k < 2 && !e; k++) {
        for (int g = 0; g < 2 * CAP_PAIRS; g++) out[k][g] = -1;
        const UChar *s = (const UChar *)subj[k], *end = s + lens[k];
        int m = onig_search(re, s, end, s, end, rg, ONIG_OPTION_NONE);
        if (m >= 0) {
            if (onig_number_of_names(re) == 0) {
                for (int g = 0; g < rg->num_regs && g < CAP_PAIRS; g++) if (rg->beg[g] >= 0) { out[k][2 * g] = rg->beg[g]; out[k][2 * g + 1] = rg->end[g]; }
            } else {
                /* With named groups only they capture; report group gN at slot N. */
                out[k][0] = rg->beg[0]; out[k][1] = rg->end[0];
                for (int g = 1; g < CAP_PAIRS; g++) {
                    char nm[8]; snprintf(nm, sizeof nm, "g%d", g);
                    int num = onig_name_to_backref_number(re, (const UChar *)nm, (const UChar *)nm + strlen(nm), rg);
                    if (num > 0 && rg->beg[num] >= 0) { out[k][2 * g] = rg->beg[num]; out[k][2 * g + 1] = rg->end[num]; }
                }
            }
        }
        else if (m != ONIG_MISMATCH) e = 0x08;
    }
    onig_region_free(rg, 1); onig_free(re);
    return e;
}
int onig_init_once(void) __attribute__((constructor));
int onig_init_once(void) { OnigEncoding e[1] = {ONIG_ENCODING_UTF8}; onig_initialize(e, 1); return 0; }

/* bench (Shootout 2): compile once, unanchored searches. */
typedef struct { regex_t *re; OnigRegion *rg; } OB;
void *host_bench_compile(const char *flags, const char *pat, size_t plen) {
    regex_t *re; OnigErrorInfo ei;
    Str np = native(pat, plen);
    int rc = onig_new(&re, (const UChar *)np.buf, (const UChar *)np.buf + np.len, options(flags), ONIG_ENCODING_UTF8, syntax(), &ei);
    free(np.buf);
    if (rc != ONIG_NORMAL) return NULL;
    OB *b = (OB *)malloc(sizeof *b); b->re = re; b->rg = onig_region_new();
    return b;
}
int host_bench_search(void *h, int k, const char *s, size_t len) {
    OB *b = (OB *)h; (void)k;
    const UChar *u = (const UChar *)s, *end = u + len;
    int m = onig_search(b->re, u, end, u, end, b->rg, ONIG_OPTION_NONE);
    return m >= 0 ? 1 : m == ONIG_MISMATCH ? 0 : -1;
}
void host_bench_free(void *h) { OB *b = (OB *)h; onig_region_free(b->rg, 1); onig_free(b->re); free(b); }
