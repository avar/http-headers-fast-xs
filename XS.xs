#define PERL_NO_GET_CONTEXT     /* we want efficiency */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "glog.h"
#include "gmem.h"
#include "util.h"
#include "header.h"

#define HLIST_KEY_STR "hlist"

static HList* fetch_hlist(pTHX, SV* self) {
  HList* hl;

  hl = (HList*) SvIV(*hv_fetch((HV*) SvRV(self),
                               HLIST_KEY_STR, sizeof(HLIST_KEY_STR) - 1, 0));
  return hl;
}


MODULE = HTTP::Headers::Fast::XS        PACKAGE = HTTP::Headers::Fast::XS
PROTOTYPES: DISABLE


#################################################################


SV *
new( SV* klass, ... )
  PREINIT:
    int    argc = 0;
    HList* hl = 0;
    SV*    self = 0;
    int    j;
    SV*    pkey;
    SV*    pval;
    char*  ckey;

  CODE:
    argc = items - 1;
    if ( argc % 2 )
        croak("Expecting a hash as input to constructor");

    GLOG(("=X= @@@ new()"));
    self = clone_from(aTHX, klass, 0, 0);
    hl = fetch_hlist(aTHX, self);

    /* create the initial list */
    for (j = 1; j <= argc; ) {
        pkey = ST(j++);

        /* did we reach the end by any chance? */
        if (j > argc) {
          break;
        }

        pval = ST(j++);
        ckey = SvPV_nolen(pkey);
        GLOG(("=X= Will set [%s] to [%s]", ckey, SvPV_nolen(pval)));
        set_value(aTHX, hl, ckey, pval);
    }

    RETVAL = self;

  OUTPUT: RETVAL


SV *
clone( SV* self )
  PREINIT:
    HList* hl = 0;

  CODE:
    hl = fetch_hlist(aTHX, self);
    GLOG(("=X= @@@ clone(%p|%d)", hl, hlist_size(hl)));
    RETVAL = clone_from(aTHX, 0, self, hl);

  OUTPUT: RETVAL


#
# Object's destructor, called automatically
#
void
DESTROY(SV* self, ...)
  PREINIT:
    HList* hl = 0;
    int    j;
    int    k;

  CODE:
    hl = fetch_hlist(aTHX, self);
    GLOG(("=X= @@@ destroy(%p|%d)", hl, hlist_size(hl)));

    for (j = 0; j < hl->ulen; ++j) {
      HNode* hn = &hl->data[j];
      PList* pl = hn->values;
      for (k = 0; k < pl->ulen; ++k) {
        PNode* pn = &pl->data[k];
        sv_2mortal( (SV*) pn->ptr );
      }
    }

    hlist_destroy(hl);


#
# Clear object, leaving it as freshly created.
#
void
clear(SV* self, ...)
  PREINIT:
    HList* hl = 0;

  CODE:
    hl = fetch_hlist(aTHX, self);
    GLOG(("=X= @@@ clear(%p|%d)", hl, hlist_size(hl)));
    hlist_clear(hl);


#
# Get all the keys in an existing HList.
#
void
header_field_names(SV* self)
  PREINIT:
    HList* hl = 0;

  PPCODE:
    hl = fetch_hlist(aTHX, self);
    GLOG(("=X= @@@ header_field_names(%p|%d), want %d",
          hl, hlist_size(hl), GIMME_V));

    hlist_sort(hl);
    PUTBACK;
    return_hlist(aTHX, hl, "header_field_names", GIMME_V);
    SPAGAIN;


#
# init_header
#
void
init_header(SV* self, ...)
  PREINIT:
    int    argc = 0;
    HList* hl = 0;
    SV*    pkey;
    SV*    pval;
    STRLEN len;
    char*  ckey;

  CODE:
    argc = items - 1;
    if (argc != 2) {
      croak("init_header needs two arguments");
    }

    hl = fetch_hlist(aTHX, self);
    GLOG(("=X= @@@ init_header(%p|%d), %d params, want %d",
          hl, hlist_size(hl), argc, GIMME_V));

    pkey = ST(1);
    ckey = SvPV(pkey, len);
    pval = ST(2);

    if (!hlist_get(hl, ckey)) {
      set_value(aTHX, hl, ckey, pval);
    }

#
# push_header
#
void
push_header(SV* self, ...)
  PREINIT:
    int    argc = 0;
    HList* hl = 0;
    int    j;
    SV*    pkey;
    SV*    pval;
    STRLEN len;
    char*  ckey;

  CODE:
    argc = items - 1;
    if (argc % 2 != 0) {
      croak("push_header needs an even number of arguments");
    }

    hl = fetch_hlist(aTHX, self);
    GLOG(("=X= @@@ push_header(%p|%d), %d params, want %d",
          hl, hlist_size(hl), argc, GIMME_V));

    for (j = 1; j <= argc; ) {
        if (j > argc) {
          break;
        }
        pkey = ST(j++);

        if (j > argc) {
          break;
        }
        pval = ST(j++);

        ckey = SvPV(pkey, len);
        set_value(aTHX, hl, ckey, pval);
    }


#
# header
#
void
header(SV* self, ...)
  PREINIT:
    int    argc = 0;
    HList* hl = 0;
    int    j;
    SV*    pkey;
    SV*    pval;
    STRLEN len;
    char*  ckey;
    HList* seen = 0; // TODO: make this more efficient; use Perl hash?

  PPCODE:
    argc = items - 1;
    hl = fetch_hlist(aTHX, self);
    GLOG(("=X= @@@ header(%p|%d), %d params, want %d",
          hl, hlist_size(hl), argc, GIMME_V));

    do {
      if (argc == 0) {
        croak("header called with no arguments");
        break;
      }

      if (argc == 1) {
        pkey = ST(1);
        ckey = SvPV(pkey, len);
        HNode* n = hlist_get(hl, ckey);
        if (n && plist_size(n->values) > 0) {
          PUTBACK;
          return_plist(aTHX, n->values, "header1", GIMME_V);
          SPAGAIN;
        }
        break;
      }

      if (argc % 2 != 0) {
        croak("init_header needs one or an even number of arguments");
        break;
      }

      seen = hlist_create();
      for (j = 1; j <= argc; ) {
          if (j > argc) {
            break;
          }
          pkey = ST(j++);

          if (j > argc) {
            break;
          }
          pval = ST(j++);

          ckey = SvPV(pkey, len);
          int clear = 0;
          if (! hlist_get(seen, ckey)) {
            clear = 1;
            hlist_add(seen, ckey, 0);
          }

          HNode* n = hlist_get(hl, ckey);
          if (n) {
            if (j > argc && plist_size(n->values) > 0) {
              /* Last value, return its current contents */
              PUTBACK;
              return_plist(aTHX, n->values, "header2", GIMME_V);
              SPAGAIN;
            }
            if (clear) {
              plist_clear(n->values);
            }
          }

          set_value(aTHX, hl, ckey, pval);
      }
      hlist_destroy(seen);
      break;
    } while (0);


#
# remove_header
#
void
remove_header(SV* self, ...)
  PREINIT:
    int    argc = 0;
    HList* hl = 0;
    int    j;
    SV*    pkey;
    STRLEN len;
    char*  ckey;
    int    size = 0;
    int    total = 0;

  PPCODE:
    argc = items - 1;
    hl = fetch_hlist(aTHX, self);
    GLOG(("=X= @@@ remove_header(%p|%d), %d params, want %d",
          hl, hlist_size(hl), argc, GIMME_V));

    for (j = 1; j <= argc; ++j) {
      pkey = ST(j);
      ckey = SvPV(pkey, len);

      HNode* n = hlist_get(hl, ckey);
      if (!n) {
        continue;
      }

      size = plist_size(n->values);
      if (size > 0) {
        total += size;
        if (GIMME_V == G_ARRAY) {
          PUTBACK;
          return_plist(aTHX, n->values, "remove_header", G_ARRAY);
          SPAGAIN;
        }
      }

      hlist_del(hl, ckey);
      GLOG(("=X= remove_header: deleted key [%s]", ckey));
    }

    if (GIMME_V == G_SCALAR) {
      GLOG(("=X= remove_header: returning count %d", total));
      EXTEND(SP, 1);
      PUSHs(sv_2mortal(newSViv(total)));
    }


#
# remove_content_headers
#
SV*
remove_content_headers(SV* self, ...)
  PREINIT:
    HList* hl = 0;
    SV*    extra = 0;
    HList* to = 0;
    HNode* n = 0;
    int    j;

  CODE:
    hl = fetch_hlist(aTHX, self);
    GLOG(("=X= @@@ remove_content_headers(%p|%d)",
          hl, hlist_size(hl)));

    extra = clone_from(aTHX, 0, self, 0);
    to = fetch_hlist(aTHX, extra);
    for (j = 0; j < hl->ulen; ) {
      n = &hl->data[j];
      if (! header_is_entity(n->header)) {
        ++j;
        continue;
      }
      hlist_transfer_header(hl, j, to);
    }

    RETVAL = extra;

  OUTPUT: RETVAL


const char*
as_string(SV* self, ...)
  PREINIT:
    HList* hl = 0;
    char* str = 0;
    int size = 0;

  CODE:
    hl = fetch_hlist(aTHX, self);
    GLOG(("=X= @@@ as_string(%p|%d) %d", hl, hlist_size(hl), items));

    const char* cendl = "\n";
    if ( items > 1 ) {
      SV* pendl = ST(1);
      cendl = SvPV_nolen(pendl);
    }

    str = format_all(aTHX, hl, 1, cendl, &size);
    RETVAL = str;

  OUTPUT: RETVAL

  CLEANUP:
    GMEM_DEL(str, char*, size);


const char*
as_string_without_sort(SV* self, ...)
  PREINIT:
    HList* hl = 0;
    char* str = 0;
    int size = 0;

  CODE:
    hl = fetch_hlist(aTHX, self);
    GLOG(("=X= @@@ as_string_without_sort(%p|%d) %d", hl, hlist_size(hl), items));

    const char* cendl = "\n";
    if ( items > 1 ) {
      SV* pendl = ST(1);
      cendl = SvPV_nolen(pendl);
    }

    str = format_all(aTHX, hl, 0, cendl, &size);
    RETVAL = str;

  OUTPUT: RETVAL

  CLEANUP:
    GMEM_DEL(str, char*, size);


void
scan(SV* self, SV* sub)
  PREINIT:
    HList* hl = 0;
    int    j;
    int    k;

  CODE:
    hl = fetch_hlist(aTHX, self);
    GLOG(("=X= @@@ scan(%p|%d)", hl, hlist_size(hl)));

    hlist_sort(hl);
    for (j = 0; j < hl->ulen; ++j) {
      HNode* hn = &hl->data[j];
      const char* header = hn->header->name;
      SV* pheader = newSVpv(header, 0);
      PList* pl = hn->values;
      for (k = 0; k < pl->ulen; ++k) {
        PNode* pn = &pl->data[k];
        SV* value = (SV*) pn->ptr;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        PUSHs( pheader );
        PUSHs( value );
        PUTBACK;
        call_sv( sub, G_DISCARD );

        FREETMPS;
        LEAVE;
      }
    }
