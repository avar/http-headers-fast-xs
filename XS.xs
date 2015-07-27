#define PERL_NO_GET_CONTEXT     /* we want efficiency */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include <string.h>

#define MY_CXT_KEY "HTTP::Headers::Fast::XS::_guts" XS_VERSION

typedef struct {
    HV *standard_case;
    SV **translate;
} my_cxt_t;

START_MY_CXT;

char *translate_underscore(pTHX_ char *field, int len) {
    dMY_CXT;
    int i;
    SV *translate = GvSV( *MY_CXT.translate );

    if (!translate)
        croak("$translate_underscore variable does not exist");

    if ( SvOK(translate) && SvTRUE(translate) )
        for ( i = 0; i < len; i++ )
            if ( field[i] == '_' )
                field[i] = '-';
    return field;
};


void handle_standard_case(pTHX_ char *field, int len) {
    dMY_CXT;
    char *orig;
    bool word_boundary;
    int  i;
    SV   **standard_case_val;

    /* make a copy to represent the original one */
    orig = (char *) alloca(len);
    my_strlcpy( orig, field, len + 1 );
    /* lc */
    for ( i = 0; i < len; i++ )
        field[i] = tolower( field[i] );

    /* uc first char after word boundary */
    standard_case_val = hv_fetch(
        MY_CXT.standard_case, field, len, 1
    );

    if (!standard_case_val)
        croak("hv_fetch() failed. This should not happen.");

    if ( !SvOK(*standard_case_val) ) {
        word_boundary = true;

        for (i = 0; i < len; i++ ) {
            if ( ! isWORDCHAR( orig[i] ) ) {
                word_boundary = true;
                continue;
            }

            if (word_boundary) {
                orig[i] = toupper( orig[i] );
                word_boundary = false;
            }
        }

        *standard_case_val = newSVpv( orig, len );
    }
}

MODULE = HTTP::Headers::Fast::XS		PACKAGE = HTTP::Headers::Fast::XS
PROTOTYPES: DISABLE

BOOT:
{
    MY_CXT_INIT;
    MY_CXT.standard_case = get_hv( "HTTP::Headers::Fast::standard_case", 0 );
    MY_CXT.translate     = hv_fetch(
        gv_stashpvn( "HTTP::Headers::Fast", 19, 0 ),
        "TRANSLATE_UNDERSCORE",
        20,
        0
    );
}

char *
_standardize_field_name(SV *field)
    PREINIT:
        char *f;
        STRLEN len;
    CODE:
        f = SvPV(field, len);
        translate_underscore(aTHX_ f, len);
        handle_standard_case(aTHX_ f, len);
        RETVAL = f;
    OUTPUT: RETVAL

void
push_header( SV *self, ... )
    PREINIT:
        /* variables for standardization */
        int  i;
        STRLEN  len;

        char *field;
        SV   *val;
        char *found_colon;
        SV   **h;
        SV   *h_copy;
    CODE:
        if ( items % 2 == 0 )
            croak("You must provide key/value pairs");

        for ( i = 1; i < items; i += 2 ) {
            field = SvPV(ST(i), len);
            val   = newSVsv( ST( i + 1 ) );

            /* leading ':' means "don't standardize" */
            found_colon = index( field, ':' );
            if ( found_colon == NULL || found_colon != 0 ) {
                translate_underscore(aTHX_ field, len);
                handle_standard_case(aTHX_ field, len);
            }

            h = hv_fetch( (HV *) SvRV(self), field, len, 1 );
            if ( h == NULL )
                croak("hv_fetch() failed. This should not happen.");

            if ( ! SvOK(*h) ) {
                *h = (SV *) newAV();
            } else if ( SvTYPE(*h) != SVt_RV ) {
                h_copy = newSVsv(*h);
                *h = (SV *) newAV();
                av_push( (AV *)*h, h_copy );
            }

            if ( SvROK(val) && SvTYPE( SvRV(val) ) == SVt_PVAV )
                av_push( (AV *) *h, newSVsv( SvRV(val) ) );
            else
                av_push( (AV *) *h, val );
        }
