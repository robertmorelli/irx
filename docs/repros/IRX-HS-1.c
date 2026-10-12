#include <hs/hs.h>
#include <stdio.h>
#include <string.h>
static int hit(unsigned id, unsigned long long f, unsigned long long t, unsigned fl, void *c) { *(int *)c = 1; return 0; }
static int test(const char *pat, unsigned flags, const char *s) {
    hs_database_t *db; hs_compile_error_t *e;
    if (hs_compile(pat, flags, HS_MODE_BLOCK, NULL, &db, &e) != HS_SUCCESS) { printf("compile error: %s\n", e->message); return -1; }
    hs_scratch_t *sc = NULL; hs_alloc_scratch(db, &sc);
    int h = 0; hs_scan(db, s, strlen(s), 0, sc, hit, &h);
    hs_free_scratch(sc); hs_free_database(db); return h;
}
int main(void) {
    const char *s15 = "aaaaaaaaaaaaaaa ", *s16 = "aaaaaaaaaaaaaaaa ", *s40 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ";
    struct { const char *p; unsigned f; const char *name; } cs[] = {
        {"\\A(?:.*\\s)\\z", HS_FLAG_UTF8 | HS_FLAG_UCP, "UTF8|UCP"},
        {"\\A(?:.*\\s)\\z", HS_FLAG_UTF8, "UTF8"},
        {"\\A(?:.*\\s)\\z", HS_FLAG_UCP | HS_FLAG_UTF8 | HS_FLAG_SINGLEMATCH, "UTF8|UCP|SINGLEMATCH"},
        {"\\A(?:.*\\s)\\z", 0, "none"},
        {"^.*\\s$", HS_FLAG_UTF8 | HS_FLAG_UCP, "UTF8|UCP ^$"},
        {"\\A.*\\s\\z", HS_FLAG_UTF8 | HS_FLAG_UCP, "UTF8|UCP no group"},
        {"\\A.*[\\s]\\z", HS_FLAG_UTF8 | HS_FLAG_UCP, "UTF8|UCP [\\s]"},
        {".*\\s\\z", HS_FLAG_UTF8 | HS_FLAG_UCP, "UTF8|UCP unanchored start"},
    };
    printf("Vectorscan %s\n", hs_version());
    for (unsigned i = 0; i < sizeof cs / sizeof cs[0]; i++)
        printf("%-22s %-26s len16=%d len17=%d len41=%d\n", cs[i].p, cs[i].name, test(cs[i].p, cs[i].f, s15), test(cs[i].p, cs[i].f, s16), test(cs[i].p, cs[i].f, s40));
}
