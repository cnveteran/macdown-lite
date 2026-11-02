/* mprender.h — minimal hoedown bridge for MacDown Lite (read-only viewer) */
#ifndef MP_RENDER_H
#define MP_RENDER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Render markdown to an HTML fragment (body only).
 * Returns a malloc'd, NUL-terminated UTF-8 string; caller frees with mp_free().
 * Returns NULL on allocation failure.
 *   extensions     : bitmask, mirrors hoedown_extensions
 *   renderer_flags : bitmask, mirrors hoedown_html_flags (+ MacDown patch bits)
 *   smartypants    : non-zero to run SmartyPants over the output
 */
char *mp_render_html(const char *md, size_t len,
                     int extensions, int renderer_flags, int smartypants);

/* Render markdown to an HTML table-of-contents fragment.
 * Returns a malloc'd string; caller frees with mp_free().
 */
char *mp_render_toc(const char *md, size_t len, int extensions);

/* Free a string returned by mp_render_html / mp_render_toc. */
void mp_free(void *p);

#ifdef __cplusplus
}
#endif

#endif /* MP_RENDER_H */
