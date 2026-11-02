/* mprender.c — minimal hoedown bridge for MacDown Lite (read-only viewer) */
#include <stdlib.h>
#include <string.h>

#include "mprender.h"
#include "buffer.h"
#include "document.h"
#include "html.h"
#include "hoedown_html_patch.h"

#define MP_NESTING_LEVEL 16

static hoedown_renderer *mp_make_html_renderer(int renderer_flags)
{
    hoedown_renderer *r = hoedown_html_renderer_new(
        (hoedown_html_flags)renderer_flags, MP_NESTING_LEVEL);
    if (!r)
        return NULL;

    /* MacDown patches: Prism-compatible code blocks, task-list items. */
    r->blockcode = hoedown_patch_render_blockcode;
    r->listitem  = hoedown_patch_render_listitem;

    hoedown_html_renderer_state_extra *extra =
        (hoedown_html_renderer_state_extra *)
        malloc(sizeof(hoedown_html_renderer_state_extra));
    if (extra) {
        extra->language_addition = NULL; /* no Prism alias mapping needed */
        extra->owner = NULL;
    }
    ((hoedown_html_renderer_state *)r->opaque)->opaque = extra;
    return r;
}

static void mp_free_html_renderer(hoedown_renderer *r)
{
    if (!r)
        return;
    hoedown_html_renderer_state_extra *extra =
        (hoedown_html_renderer_state_extra *)
        ((hoedown_html_renderer_state *)r->opaque)->opaque;
    free(extra);
    ((hoedown_html_renderer_state *)r->opaque)->opaque = NULL;
    hoedown_html_renderer_free(r);
}

char *mp_render_html(const char *md, size_t len,
                     int extensions, int renderer_flags, int smartypants)
{
    if (!md)
        return NULL;

    hoedown_renderer *r = mp_make_html_renderer(renderer_flags);
    if (!r)
        return NULL;

    hoedown_document *doc = hoedown_document_new(
        r, (hoedown_extensions)extensions, MP_NESTING_LEVEL);
    hoedown_buffer *ob = hoedown_buffer_new(64);
    if (!doc || !ob) {
        if (doc) hoedown_document_free(doc);
        if (ob)  hoedown_buffer_free(ob);
        mp_free_html_renderer(r);
        return NULL;
    }

    hoedown_document_render(doc, ob, (const uint8_t *)md, len);

    if (smartypants) {
        hoedown_buffer *ib = ob;
        ob = hoedown_buffer_new(64);
        if (ob)
            hoedown_html_smartypants(ob, ib->data, ib->size);
        else
            ob = ib;
        if (ob != ib)
            hoedown_buffer_free(ib);
    }

    char *result = strdup(hoedown_buffer_cstr(ob));

    hoedown_document_free(doc);
    hoedown_buffer_free(ob);
    mp_free_html_renderer(r);
    return result;
}

char *mp_render_toc(const char *md, size_t len, int extensions)
{
    if (!md)
        return NULL;

    hoedown_renderer *r = hoedown_html_toc_renderer_new(MP_NESTING_LEVEL);
    if (!r)
        return NULL;
    r->header = hoedown_patch_render_toc_header;

    hoedown_document *doc = hoedown_document_new(
        r, (hoedown_extensions)extensions, MP_NESTING_LEVEL);
    hoedown_buffer *ob = hoedown_buffer_new(64);
    if (!doc || !ob) {
        if (doc) hoedown_document_free(doc);
        if (ob)  hoedown_buffer_free(ob);
        hoedown_html_renderer_free(r);
        return NULL;
    }

    hoedown_document_render(doc, ob, (const uint8_t *)md, len);
    char *result = strdup(hoedown_buffer_cstr(ob));

    hoedown_document_free(doc);
    hoedown_buffer_free(ob);
    hoedown_html_renderer_free(r);
    return result;
}

void mp_free(void *p)
{
    free(p);
}
