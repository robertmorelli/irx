/* Oniguruma host (Ruby syntax). Note Ruby's /m is dotall; ^/$ are always line anchors. */
#include <oniguruma.h>
#include "proto.h"
const char *host_name(void) { static char b[64]; snprintf(b, sizeof b, "oniguruma-%s", onig_version()); return b; }
int host_case(const char *flags, const char *a, size_t alen, const char *r, size_t rlen, const char *pat, size_t plen, int repeat) {
    OnigOptionType opt = ONIG_OPTION_NONE;
    if (strchr(flags, 'i')) opt |= ONIG_OPTION_IGNORECASE;
    if (strchr(flags, 's')) opt |= ONIG_OPTION_MULTILINE;  /* Ruby: dot matches newline */
    Str w = {0}; put(&w, "\\A(?:", 5); put(&w, pat, plen); put(&w, ")\\z", 3);
    regex_t *re; OnigErrorInfo ei;
    int rc = onig_new(&re, (UChar *)w.buf, (UChar *)w.buf + w.len, opt, ONIG_ENCODING_UTF8, ONIG_SYNTAX_RUBY, &ei);
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
    OnigOptionType opt = ONIG_OPTION_NONE;
    if (strchr(flags, 'i')) opt |= ONIG_OPTION_IGNORECASE;
    if (strchr(flags, 's')) opt |= ONIG_OPTION_MULTILINE;
    regex_t *re; OnigErrorInfo ei;
    if (onig_new(&re, (const UChar *)pat, (const UChar *)pat + plen, opt, ONIG_ENCODING_UTF8, ONIG_SYNTAX_RUBY, &ei) != ONIG_NORMAL) return 0x04;
    OnigRegion *rg = onig_region_new();
    int e = 0;
    for (int k = 0; k < 2; k++) {
        const UChar *s = (const UChar *)subj[k], *end = s + lens[k];
        int m = onig_search(re, s, end, s, end, rg, ONIG_OPTION_NONE);
        if (m >= 0) { out[2 * k] = rg->beg[0]; out[2 * k + 1] = rg->end[0]; }
        else if (m == ONIG_MISMATCH) out[2 * k] = out[2 * k + 1] = -1;
        else { e = 0x08; break; }
    }
    onig_region_free(rg, 1); onig_free(re);
    return e;
}
int onig_init_once(void) __attribute__((constructor));
int onig_init_once(void) { OnigEncoding e[1] = {ONIG_ENCODING_UTF8}; onig_initialize(e, 1); return 0; }
