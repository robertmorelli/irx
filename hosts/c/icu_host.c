/* irx host: ICU4C's C regex API (uregex_*, Homebrew icu4c), the library NSRegularExpression wraps in an
 * older, Apple-built version. Patterns are converted from UTF-8 to UTF-16; positions are UTF-16 units.
 * Flags: i -> UREGEX_CASE_INSENSITIVE, m -> UREGEX_MULTILINE, s -> UREGEX_DOTALL. */
#include <unicode/uregex.h>
#include <unicode/ustring.h>
#include "proto.h"
const char *host_name(void) { static char b[64]; UVersionInfo v; u_getVersion(v); snprintf(b, sizeof b, "icu4c-%d.%d", v[0], v[1]); return b; }
static UChar *u16(const char *s, size_t n, int32_t *len) {
    UErrorCode e = U_ZERO_ERROR; int32_t need = 0;
    u_strFromUTF8(NULL, 0, &need, s, (int32_t)n, &e);
    UChar *b = (UChar *)malloc(sizeof(UChar) * (need + 1)); e = U_ZERO_ERROR;
    u_strFromUTF8(b, need + 1, len, s, (int32_t)n, &e);
    return b;
}
static URegularExpression *compile(const char *flags, const char *pat, size_t plen, int wrap) {
    uint32_t f = 0;
    if (strchr(flags, 'i')) f |= UREGEX_CASE_INSENSITIVE;
    if (strchr(flags, 'm')) f |= UREGEX_MULTILINE;
    if (strchr(flags, 's')) f |= UREGEX_DOTALL;
    Str w = {0};
    if (wrap) { put(&w, "\\A(?:", 5); put(&w, pat, plen); put(&w, ")\\z", 3); } else put(&w, pat, plen);
    int32_t ul; UChar *up = u16(w.buf ? w.buf : "", w.len, &ul); free(w.buf);
    UErrorCode e = U_ZERO_ERROR; UParseError pe;
    URegularExpression *re = uregex_open(up, ul, f, &pe, &e);
    free(up);
    if (U_FAILURE(e)) return NULL;
    e = U_ZERO_ERROR; uregex_setTimeLimit(re, 50, &e);  /* ~50 ms of match steps, then unsupported (IRX-ICU-1 loops) */
    return re;
}
int host_case(const char *flags, const char *a, size_t alen, const char *r, size_t rlen, const char *pat, size_t plen, int repeat) {
    URegularExpression *re = compile(flags, pat, plen, 1);
    if (!re) return 0x04;
    int bits = 0;
    const char *subj[2] = {a, r}; size_t lens[2] = {alen, rlen};
    for (int rep = 0; rep < (repeat ? 2 : 1); rep++)
        for (int k = 0; k < 2; k++) {
            int32_t ul; UChar *us = u16(subj[k], lens[k], &ul);
            UErrorCode e = U_ZERO_ERROR; uregex_setText(re, us, ul, &e);
            UBool hit = uregex_find(re, 0, &e);
            free(us);
            if (U_FAILURE(e)) { bits = e == U_REGEX_TIME_OUT || e == U_REGEX_STACK_OVERFLOW ? 0x40 : 0x08; goto done; }
            if (hit) bits |= (1 << k) << (rep * 4);
        }
done:
    uregex_close(re);
    return bits;
}
int host_span(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[4]) {
    URegularExpression *re = compile(flags, pat, plen, 0);
    if (!re) return 0x04;
    int rc = 0;
    for (int k = 0; k < 2; k++) {
        int32_t ul; UChar *us = u16(subj[k], lens[k], &ul);
        UErrorCode e = U_ZERO_ERROR; uregex_setText(re, us, ul, &e);
        UBool hit;
        if (host_anchored) {  /* sticky: lookingAt from the offset, with transparent bounds */
            uregex_setRegion(re, (int32_t)host_start[k], ul, &e);
            uregex_useTransparentBounds(re, 1, &e); uregex_useAnchoringBounds(re, 0, &e);
            hit = uregex_lookingAt(re, -1, &e);
        } else hit = uregex_find(re, (int32_t)host_start[k], &e);
        if (U_FAILURE(e)) { rc = e == U_REGEX_TIME_OUT || e == U_REGEX_STACK_OVERFLOW ? 0x40 : 0x08; free(us); break; }
        if (hit) { out[2 * k] = uregex_start(re, 0, &e); out[2 * k + 1] = uregex_end(re, 0, &e); }
        else out[2 * k] = out[2 * k + 1] = -1;
        free(us);
    }
    uregex_close(re);
    return rc;
}
int host_capture(const char *flags, const char *const subj[2], const size_t lens[2], const char *pat, size_t plen, long out[2][2 * CAP_PAIRS]) {
    URegularExpression *re = compile(flags, pat, plen, 0);
    if (!re) return 0x04;
    int rc = 0;
    for (int k = 0; k < 2; k++) {
        int32_t ul; UChar *us = u16(subj[k], lens[k], &ul);
        UErrorCode e = U_ZERO_ERROR; uregex_setText(re, us, ul, &e);
        UBool hit = uregex_find(re, 0, &e);
        if (U_FAILURE(e)) { rc = e == U_REGEX_TIME_OUT || e == U_REGEX_STACK_OVERFLOW ? 0x40 : 0x08; free(us); break; }
        int32_t ng = uregex_groupCount(re, &e);
        for (int g = 0; g < CAP_PAIRS; g++) {
            int32_t s = hit && g <= ng ? uregex_start(re, g, &e) : -1;
            out[k][2 * g] = s; out[k][2 * g + 1] = s < 0 ? -1 : uregex_end(re, g, &e);
        }
        free(us);
    }
    uregex_close(re);
    return rc;
}

/* bench (Shootout 2): compile once, unanchored searches; the UTF-16 text is converted once per
 * subject slot (outside the timed loop). */
typedef struct { URegularExpression *re; UChar *t[2]; int32_t n[2]; int cur; } IB;
void *host_bench_compile(const char *flags, const char *pat, size_t plen) {
    URegularExpression *re = compile(flags, pat, plen, 0);
    if (!re) return NULL;
    IB *b = (IB *)calloc(1, sizeof *b); b->re = re; b->cur = -1;
    return b;
}
int host_bench_search(void *h, int k, const char *s, size_t len) {
    IB *b = (IB *)h; UErrorCode e = U_ZERO_ERROR;
    if (!b->t[k]) b->t[k] = u16(s, len, &b->n[k]);
    if (b->cur != k) { uregex_setText(b->re, b->t[k], b->n[k], &e); b->cur = k; }
    UBool hit = uregex_find(b->re, 0, &e);
    return U_FAILURE(e) ? -1 : hit ? 1 : 0;
}
void host_bench_free(void *h) { IB *b = (IB *)h; uregex_close(b->re); free(b->t[0]); free(b->t[1]); free(b); }
