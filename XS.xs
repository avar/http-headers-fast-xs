#define PERL_NO_GET_CONTEXT     /* we want efficiency */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "glog.h"
#include "hlist.h"

MODULE = HTTP::Headers::Fast::XS		PACKAGE = HTTP::Headers::Fast::XS
PROTOTYPES: DISABLE


void*
hhf_hlist_create()

  PREINIT:
    HList* h = 0;

  CODE:
    h = hlist_create();
    GLOG(("=C= created hlist %p\n", h));
    RETVAL = (void*) h;

  OUTPUT: RETVAL


void
hhf_hlist_destroy(unsigned long nh)

  PREINIT:
    HList* h = 0;

  CODE:
    h = (HList*) nh;
    GLOG(("=C= destroying hlist %p\n", h));
    hlist_unref(h);


void
hhf_hlist_clear(unsigned long nh)

  PREINIT:
    HList* h = 0;

  CODE:
    GLOG(("=C= clearing hlist %p\n", h));
    h = (HList*) nh;
    hlist_clear(h);


void
hhf_hlist_header_get(unsigned long nh, int translate_underscore, const char* name)

  PREINIT:
    HList* h = 0;
    SList* s = 0;

  PPCODE:
    h = (HList*) nh;
    GLOG(("=C= HEADER_GET(%p, %d, %s)\n", h, translate_underscore, name));
    s = hlist_get_header(h, translate_underscore,
                         name);
    int count = s ? slist_size(s) : 0;
    if (count <= 0) {
      GLOG(("=C= header_get: empty values\n"));
      XSRETURN_EMPTY;
    }
    GLOG(("=C= header_get: returning %d values\n", count));
    EXTEND(SP, count);
    for (SNode* n = s->head; n != 0; n = n->nxt) {
      /* TODO: This can probably be optimised A LOT*/
      GLOG(("=C= header_get: returning [%s]\n", n->str));
      PUSHs(sv_2mortal(newSVpv(n->str, 0)));
    }


void
hhf_hlist_header_set(unsigned long nh, int translate_underscore, int new_only, int keep_previous, int want_answer, const char* name, SV* val)

  PREINIT:
    HList* h = 0;
    SList* s = 0;
    SList* t = 0;
    AV* arr = 0;
    int count = 0;

  PPCODE:
    h = (HList*) nh;
    GLOG(("=C= HEADER_SET(%p, %d, %d, %d, %s, %p)\n",
          h, translate_underscore, new_only, keep_previous, name, val));

    /* We look for the current values for the header and keep a reference to them */
    s = hlist_get_header(h, translate_underscore,
                         name);
    count = s ? slist_size(s) : 0;
    GLOG(("=C= header_set: will later return %d values\n", count));
    if (s) {
      if (new_only) {
        /* header should not have existed before */
        GLOG(("=C= header_set: tried to init already-existing header, bye\n"));
        XSRETURN_EMPTY;
      }

      if (keep_previous) {
        if (want_answer) {
          /* Make a deep copy of the current value */
          GLOG(("=C= header_set: making a deep copy\n"));
          t = slist_clone(s);
        }
      } else {
        /* Make a shallow copy of the current value */
        GLOG(("=C= header_set: making a shallow copy\n"));
        t = slist_ref(s);

        /* Erase what is already there for this header */
        hlist_del_header(h, translate_underscore,
                         name);
        GLOG(("=C= header_set: deleted key [%s]\n", name));
      }
    }

    if (val) {

      /* Scalar? Just convert it to string. */
      if (SvIOK(val) || SvNOK(val) || SvPOK(val)) {
        STRLEN slen;
        const char* elem = SvPV(val, slen);
        hlist_add_header(h, translate_underscore,
                         name, elem);
        GLOG(("=C= header_set: added single value [%s]\n", elem));
      }

      /* Reference? */
      if (SvROK(val)) {
        GLOG(("=C= header_set: is a ref\n"));
        SV* deref = (SV*) SvRV(val);
        if (SvTYPE(deref) == SVt_PVAV) {
          GLOG(("=C= header_set: is an arrayref\n"));
          arr = (AV*) SvRV(val);

          /* Add each element in val as a value for name. */
          count = av_len(arr) + 1;
          GLOG(("=C= header_set: array has %d elementds\n", count));
          for (int j = 0; j < count; ++j) {
            SV** svp = av_fetch(arr, j, 0);
            if (SvIOK(*svp) || SvNOK(*svp) || SvPOK(*svp)) {
              STRLEN slen;
              const char* elem = SvPV(*svp, slen);
              hlist_add_header(h, translate_underscore,
                               name, elem);
              GLOG(("=C= header_set: added value %d [%s]\n", j, elem));
            }
          }
        }
      }
    }

    /* We now can put in the return stack all the original values */
    count = t ? slist_size(t) : 0;
    GLOG(("=C= header_set: returning %d values\n", count));
    if (t) {
      EXTEND(SP, count);
      for (SNode* n = t->head; n != 0; n = n->nxt) {
        /* TODO: This can probably be optimised A LOT*/
        GLOG(("=C= header_set: returning [%s]\n", n->str));
        PUSHs(sv_2mortal(newSVpv(n->str, 0)));
      }

      GLOG(("=C= header_set: now erasing the %d values for %p\n", count, t));
      slist_unref(t);
      GLOG(("=C= header_set: finished erasing the %d values\n", count));
    }

void
hhf_hlist_header_remove(unsigned long nh, int translate_underscore, const char* name)

  PREINIT:
    HList* h = 0;
    SList* s = 0;
    SList* t = 0;
    int count = 0;

  PPCODE:
    h = (HList*) nh;
    GLOG(("=C= HEADER_REMOVE(%p, %d, %s)\n", h, translate_underscore, name));

    /* We look for the current values for the header and keep a reference to them */
    s = hlist_get_header(h, translate_underscore,
                         name);
    count = s ? slist_size(s) : 0;
    GLOG(("=C= header_remove: will later return %d values\n", count));
    if (s) {
        GLOG(("=C= header_remove: making a shallow copy\n"));
        t = slist_ref(s);

        /* Erase what is already there for this header */
        hlist_del_header(h, translate_underscore,
                         name);
        GLOG(("=C= header_remove: deleted key [%s]\n", name));
    }

    /* We now can put in the return stack all the original values */
    count = t ? slist_size(t) : 0;
    GLOG(("=C= header_remove: returning %d values\n", count));
    if (t) {
      EXTEND(SP, count);
      for (SNode* n = t->head; n != 0; n = n->nxt) {
        /* TODO: This can probably be optimised A LOT*/
        GLOG(("=C= header_remove: returning [%s]\n", n->str));
        PUSHs(sv_2mortal(newSVpv(n->str, 0)));
      }

      GLOG(("=C= header_remove: now erasing the %d values for %p\n", count, t));
      slist_unref(t);
      GLOG(("=C= header_remove: finished erasing the %d values\n", count));
    }


void
hhf_hlist_header_names(unsigned long nh)

  PREINIT:
    HList* h = 0;
    HList* t = 0;

  PPCODE:
    h = (HList*) nh;
    GLOG(("=C= HEADER_NAMES(%p)\n", h));

    for (t = h; t != 0; t = t->nxt) {
      if (!t->name) {
        continue;
      }

      EXTEND(SP, 1);

      /* TODO: This can probably be optimised A LOT*/
      GLOG(("=C= header_names: returning [%s]\n", t->canonical_name));
      PUSHs(sv_2mortal(newSVpv(t->canonical_name, 0)));
    }


void*
hhf_hlist_clone(unsigned long nh)

  PREINIT:
    HList* h = 0;
    HList* t = 0;

  CODE:
    h = (HList*) nh;
    GLOG(("=C= CLONE(%p)\n", h));

    t = hlist_clone(h);
    GLOG(("=C= CLONE(%p) => %p\n", h, t));

    RETVAL = t;

  OUTPUT: RETVAL
