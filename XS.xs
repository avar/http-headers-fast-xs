#define PERL_NO_GET_CONTEXT     /* we want efficiency */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "glog.h"
#include "header.h"
#include "plist.h"
#include "hlist.h"

#define HLIST_KEY_STR "hlist"
#define HLIST_KEY_LEN 5

#define MY_CXT_KEY "HTTP::Headers::Fast::XS::_guts" XS_VERSION

typedef struct {
    SV **translate;
} my_cxt_t;

START_MY_CXT;

static HList* fetch_hlist(pTHX_  SV* self);
static void set_scalar(pTHX_  HList* h, int trans, const char* ckey, SV* pval);
static void set_array (pTHX_  HList* h, int trans, const char* ckey, AV* pval);
static void set_value (pTHX_  HList* h, int trans, const char* ckey, SV* pval);

static HList* fetch_hlist(pTHX_  SV* self) {
  HList* h;

  h = (HList*) SvIV(*hv_fetch((HV*) SvRV(self),
                    HLIST_KEY_STR, HLIST_KEY_LEN, 0));
  return h;
}

/* FIXME: don't send self */
static int fetch_translate(pTHX_ SV* self) {
  dMY_CXT;

  SV* ptrans = GvSV(*MY_CXT.translate);
  if (!ptrans) {
    croak("$TRANSLATE_UNDERSCORE variable does not exist");
  }
  int trans = SvOK(ptrans) && SvTRUE(ptrans);
  GLOG(("=X= translate_underscore is %d", trans));
  return trans;
}

static int format_all(pTHX_ HList* h, char* str, const char* endl) {
  int pos = 0;
  for (int j = 0; j < h->ulen; ++j) {
    HNode* hn = &h->data[j];
    const char* header = hn->header->name;
    PList* pl = hn->values;
    for (int k = 0; k < pl->ulen; ++k) {
      PNode* pn = &pl->data[k];
      const char* value = SvPV_nolen( (SV*) pn->ptr );
      GLOG(("=X= [%s] => [%s]", header, value));
      pos += sprintf(str + pos, "%s: %s%s", header, value, endl);
    }
  }
  str[pos] = '\0';
  return pos;
}

static void set_scalar(pTHX_  HList* h, int trans, const char* ckey, SV* pval) {
  hlist_add(h, ckey, newSVsv(pval));
  GLOG(("=X= set scalar [%s] => [%s]", ckey, SvPV_nolen(pval)));
}

static void set_array(pTHX_  HList* h, int trans, const char* ckey, AV* pval) {
  int count = av_len(pval) + 1;
  int j;
  for (j = 0; j < count; ++j) {
    GLOG(("=X= set array %2d [%s]", j, ckey));
    SV** svp = av_fetch(pval, j, 0);
    set_value(aTHX_  h, trans, ckey, *svp);
  }
}

static void set_value(pTHX_  HList* h, int trans, const char* ckey, SV* pval) {
  if ( ! SvOK(pval) ) {
    GLOG(("=X= deleting [%s]", ckey));
    hlist_del( h, ckey );
    return;
  }

  if ( ! SvROK(pval) ) {
    set_scalar(aTHX_  h, trans, ckey, pval);
    return;
  }

  SV* deref = SvRV(pval);
  if (SvTYPE(deref) != SVt_PVAV) {
    set_scalar( aTHX_  h, trans, ckey, pval);
    return;
  }

  AV* array = (AV*) deref;
  set_array(aTHX_  h, trans, ckey, array);
}

/*
 * Given an HList, return all of its nodes to Perl.
 */
static void return_hlist(pTHX_   HList* list, const char* func, int want) {

  dSP;

  if (want == G_VOID) {
    GLOG(("=X= %s: no return expected, nothing will be returned", func));
    return;
  }

  int count = hlist_size(list);

  if (want == G_SCALAR) {
    GLOG(("=X= %s: returning number of elements", func));
    EXTEND(SP, 1);
    PUSHs(sv_2mortal(newSViv(count)));
    PUTBACK;
  }

  if (count <= 0) {
    GLOG(("=X= %s: hlist is empty, returning nothing", func));
    return;
  }

  if (want == G_ARRAY) {
    GLOG(("=X= %s: returning as %d elements", func, count));
    EXTEND(SP, count);

    int num = 0;
    for (int j = 0; j < list->ulen; ++j) {
      HNode* node = &list->data[j];
      ++num;

      const char* s = node->header->name;
      GLOG(("=X= %s: returning %2d - str [%s]", func, num, s));
      PUSHs(sv_2mortal(newSVpv(s, 0)));
    }
    PUTBACK;
  }
}

/*
 * Given an PList, return all of its nodes to Perl.
 */
static void return_plist(pTHX_   PList* list, const char* func, int want) {

  dSP;

  if (want == G_VOID) {
    GLOG(("=X= %s: no return expected, nothing will be returned", func));
    return;
  }

  int count = plist_size(list);

  if (count <= 0) {
    if (want == G_ARRAY) {
      GLOG(("=X= %s: plist is empty, wantarray => 0", func));
      EXTEND(SP, 1);
      PUSHs(sv_2mortal(newSViv(0)));
      PUTBACK;
    } else {
      GLOG(("=X= %s: plist is empty, returning nothing", func));
    }
    return;
  }

  GLOG(("=X= %s: returning %d values", func, count));

  if (want == G_SCALAR) {
    GLOG(("=X= %s: returning as single string", func));
    EXTEND( SP, 1 );

    char rstr[1024]; // TODO
    int rpos = 0;
    int num = 0;
    for (int j = 0; j < list->ulen; ++j) {
      PNode* node = &list->data[j];
      ++num;

      /* handle returning one value,
         useful when storing an object
      */
      if ( count == 1 ) {
        PUSHs( (SV*)node->ptr );
        break;
      }

      /* concatenate values
         useful for full header strings
      */
      STRLEN len;
      char* str = SvPV( (SV*)node->ptr, len );
      GLOG(("=X= %s: returning %2d - str [%s]", func, num, str));
      if (rpos > 0) {
        rstr[rpos++] = ',';
        rstr[rpos++] = ' ';
      }

      memcpy(rstr + rpos, str, len);
      rpos += len;

    }

    /* if we concatenated, return it */
    if ( count > 1 ) {
      rstr[rpos] = '\0';
      PUSHs(sv_2mortal(newSVpv(rstr, rpos)));
    }

    PUTBACK;
  }

  if (want == G_ARRAY) {
    GLOG(("=X= %s: returning as %d elements", func, count));
    EXTEND(SP, count);
    int num = 0;
    for (int j = 0; j < list->ulen; ++j) {
      PNode* node = &list->data[j];
      ++num;

      PUSHs( (SV*)node->ptr );
    }

    PUTBACK;
  }
}


MODULE = HTTP::Headers::Fast::XS        PACKAGE = HTTP::Headers::Fast::XS
PROTOTYPES: DISABLE

BOOT:
{
    MY_CXT_INIT;
    MY_CXT.translate = hv_fetch(
        gv_stashpvn( "HTTP::Headers::Fast", 19, 0 ),
        "TRANSLATE_UNDERSCORE",
        20,
        0
    );
}


#################################################################


SV *
new( SV* klass, ... )
  PREINIT:
    int    j;
    int    ctrans = 0;
    HList* list = 0;
    SV*    self = 0;
    HV*    hash;
    SV*    pkey;
    SV*    pval;
    char*  ckey;

  CODE:
    if ( ( items - 1 ) % 2 )
        croak("Expecting a hash as input to constructor");

    hash = newHV();
    list = hlist_create();
    GLOG(("=X= @@@ new(%p|%d)", list, hlist_size(list)));

    if ( !list )
      croak("Could not initialize HList list object");

    SV** hlist_created = hv_store( hash, "hlist", strlen("hlist"), newSViv((IV)list), 0 );

    if ( !hlist_created )
      croak("We could not store value for 'hlist'. This should not happen.");

    /* create the initial list */
    /* FIXME: don't send self */
    ctrans = fetch_translate(aTHX_ self);
    for (j = 1; j < items; ) {
        pkey = ST(j++);

        /* did we reach the end by any chance? */
        if (j == items) {
          break;
        }

        pval = ST(j++);
        ckey = SvPV_nolen(pkey);
        GLOG(("=X= Will set [%s] to [%s]", ckey, SvPV_nolen(pval)));
        set_value(aTHX_  list, ctrans, ckey, pval);
    }

    GLOG(("=X= Will bless new object"));
    self = newRV_noinc( (SV*)hash );
    RETVAL = sv_bless( self, gv_stashpv( SvPV_nolen(klass), 0 ) );

  OUTPUT: RETVAL


SV *
clone( SV* self )
  PREINIT:
    HList* h = 0;
    HList* list = 0;
    SV*    them = 0;
    HV*    hash;
    char*  klass;

  CODE:
    h = fetch_hlist(aTHX_  self);
    GLOG(("=X= @@@ clone(%p|%d)", h, hlist_size(h)));

    hash = newHV();
    list = hlist_clone(h);

    if ( !list )
      croak("Could not initialize HList list object");

    /* Clone the SVs into new ones */
    for (int j = 0; j < list->ulen; ++j) {
      HNode* hnode = &list->data[j];
      PList* plist = hnode->values;
      for (int k = 0; k < plist->ulen; ++k) {
        PNode* pnode = &plist->data[k];
        pnode->ptr = newSVsv( (SV*)pnode->ptr );
      }
    }

    SV** hlist_created = hv_store( hash, "hlist", strlen("hlist"), newSViv((IV)list), 0 );

    if ( !hlist_created )
      croak("We could not store value for 'hlist'. This should not happen.");

    them = newRV_noinc( (SV*)hash );
    klass = HvNAME(SvSTASH(SvRV(self)));
    RETVAL = sv_bless( them, gv_stashpv( klass, 0 ) );

  OUTPUT: RETVAL


#
# Object's destructor, called automatically
#
void
DESTROY(SV* self, ...)
  PREINIT:
    HList* h = 0;

  CODE:
    h = fetch_hlist(aTHX_  self);
    GLOG(("=X= @@@ destroy(%p|%d)", h, hlist_size(h)));

    for (int j = 0; j < h->ulen; ++j) {
      HNode* hn = &h->data[j];
      PList* pl = hn->values;
      for (int k = 0; k < pl->ulen; ++k) {
        PNode* pn = &pl->data[k];
        sv_2mortal( (SV*) pn->ptr );
      }
    }

    hlist_destroy(h);


#
# Clear object, leaving it as freshly created.
#
void
clear(SV* self, ...)
  PREINIT:
    HList* h = 0;

  CODE:
    h = fetch_hlist(aTHX_  self);
    GLOG(("=X= @@@ clear(%p|%d)", h, hlist_size(h)));
    hlist_clear(h);


#
# Get all the keys in an existing HList.
#
void
_header_keys(SV* self)
  PREINIT:
    HList* h = 0;

  PPCODE:
    h = fetch_hlist(aTHX_  self);
    GLOG(("=X= @@@ _header_keys(%p|%d), want %d",
          h, hlist_size(h), GIMME_V));

    PUTBACK;
    return_hlist(aTHX_   h, "_header_keys", GIMME_V);
    SPAGAIN;


#
# init_header
#
void
init_header(SV* self, ...)
  PREINIT:
    int argc = 0;
    HList* h = 0;
    HNode* n = 0;
    int    ctrans = 0;
    SV*    pkey;
    SV*    pval;
    STRLEN len;
    char*  ckey;

  CODE:
    argc = items - 1;
    if (argc != 2) {
      croak("init_header needs two arguments");
    }

    h = fetch_hlist(aTHX_  self);
    ctrans = fetch_translate(aTHX_ self);
    GLOG(("=X= @@@ init_header(%p|%d), %d params, want %d, trans %d",
          h, hlist_size(h), argc, GIMME_V, ctrans));

    pkey = ST(1);
    ckey = SvPV(pkey, len);
    pval = ST(2);

    if (!hlist_get(h, ckey)) {
      set_value(aTHX_  h, ctrans, ckey, pval);
    }

#
# push_header
#
void
push_header(SV* self, ...)
  PREINIT:
    int argc = 0;
    HList* h = 0;
    HNode* n = 0;
    int    ctrans = 0;
    int    j = 0;
    SV*    pkey;
    SV*    pval;
    STRLEN len;
    char*  ckey;

  CODE:
    argc = items - 1;
    if (argc % 2 != 0) {
      croak("push_header needs an even number of arguments");
    }

    h = fetch_hlist(aTHX_  self);
    ctrans = fetch_translate(aTHX_ self);
    GLOG(("=X= @@@ push_header(%p|%d), %d params, want %d, trans %d",
          h, hlist_size(h), argc, GIMME_V, ctrans));

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
        set_value(aTHX_  h, ctrans, ckey, pval);
    }


#
# header
#
void
header(SV* self, ...)
  PREINIT:
    int argc = 0;
    HList* h = 0;
    HNode* n = 0;
    int    ctrans = 0;
    int    j = 0;
    SV*    pkey;
    SV*    pval;
    STRLEN len;
    char*  ckey;
    HList* seen = 0;

  PPCODE:
    argc = items - 1;
    h = fetch_hlist(aTHX_  self);
    ctrans = fetch_translate(aTHX_ self);
    GLOG(("=X= @@@ header(%p|%d), %d params, want %d, trans %d",
          h, hlist_size(h), argc, GIMME_V, ctrans));

    do {
      if (argc == 0) {
        croak("header called with no arguments");
        break;
      }

      if (argc == 1) {
        pkey = ST(1);
        ckey = SvPV(pkey, len);
        HNode* n = hlist_get(h, ckey);
        if (n && plist_size(n->values) > 0) {
          PUTBACK;
          return_plist(aTHX_   n->values, "header1", GIMME_V);
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

          HNode* n = hlist_get(h, ckey);
          if (n) {
            if (j > argc && plist_size(n->values) > 0) {
              /* Last value, return its current contents */
              PUTBACK;
              return_plist(aTHX_   n->values, "header2", GIMME_V);
              SPAGAIN;
            }
            if (clear) {
              plist_clear(n->values);
            }
          }

          set_value(aTHX_  h, ctrans, ckey, pval);
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
    int argc = 0;
    HList* h = 0;
    HNode* n = 0;
    int    ctrans = 0;
    int    j = 0;
    SV*    pkey;
    STRLEN len;
    char*  ckey;
    int    size = 0;
    int    total = 0;

  PPCODE:
    argc = items - 1;
    h = fetch_hlist(aTHX_  self);
    ctrans = fetch_translate(aTHX_ self);
    GLOG(("=X= @@@ remove_header(%p|%d), %d params, want %d, trans %d",
          h, hlist_size(h), argc, GIMME_V, ctrans));

    for (j = 1; j <= argc; ++j) {
      pkey = ST(j);
      ckey = SvPV(pkey, len);

      HNode* n = hlist_get(h, ckey);
      if (!n) {
        continue;
      }

      size = plist_size(n->values);
      if (size > 0) {
        total += size;
        if (GIMME_V == G_ARRAY) {
          PUTBACK;
          return_plist(aTHX_   n->values, "remove_header", G_ARRAY);
          SPAGAIN;
        }
      }

      hlist_del(h, ckey);
      GLOG(("=X= remove_header: deleted key [%s]", ckey));
    }

    if (GIMME_V == G_SCALAR) {
      GLOG(("=X= remove_header: returning count %d", total));
      EXTEND(SP, 1);
      PUSHs(sv_2mortal(newSViv(total)));
    }


void
_as_string(SV* self, int sort, const char* endl)
  PREINIT:
    HList* h = 0;

  PPCODE:
    h = fetch_hlist(aTHX_  self);
    GLOG(("=X= @@@ as_string(%p|%d) %d - [%s]", h, hlist_size(h), sort, endl));

    if (sort) {
      hlist_sort(h);
    }
    char str[10240]; // TODO
    int pos = format_all(aTHX_ h, str, endl);
    EXTEND(SP, 1);
    PUSHs(sv_2mortal(newSVpv(str, pos)));
