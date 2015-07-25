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

#define TRANSLATE_UNDERSCORE(field)                                       \
    STMT_START {                                                          \
        /* underscores to dashes */                                       \
        translate_underscore = GvSV( *MY_CXT.translate );                 \
                                                                          \
        if (!translate_underscore)                                        \
            croak("$translate_underscore variable does not exist");       \
                                                                          \
        len = strlen(field);                                              \
        if ( SvOK(translate_underscore) && SvTRUE(translate_underscore) ) \
            for ( i = 0; i < len; i++ )                                   \
                if ( field[i] == '_' )                                    \
                    field[i] = '-';                                       \
    } STMT_END;

#define HANDLE_STANDARD_CASE( field, len )                       \
    STMT_START {                                                 \
        /* make a copy to represent the original one */          \
        orig = (char *) alloca(len);                             \
        my_strlcpy( orig, field, len + 1 );                      \
                                                                 \
        /* lc */                                                 \
        for ( i = 0; i < len; i++ )                              \
            field[i] = tolower( field[i] );                      \
                                                                 \
        /* uc first char after word boundary */                  \
        standard_case_val = hv_fetch(                            \
            MY_CXT.standard_case, field, len, 1                  \
        );                                                       \
                                                                 \
        if (!standard_case_val)                                  \
            croak("hv_fetch() failed. This should not happen."); \
                                                                 \
        if ( !SvOK(*standard_case_val) ) {                       \
            word_boundary = true;                                \
                                                                 \
            for (i = 0; i < len; i++ ) {                         \
                if ( ! isWORDCHAR( orig[i] ) ) {                 \
                    word_boundary = true;                        \
                    continue;                                    \
                }                                                \
                                                                 \
                if (word_boundary) {                             \
                    orig[i] = toupper( orig[i] );                \
                    word_boundary = false;                       \
                }                                                \
            }                                                    \
                                                                 \
            *standard_case_val = newSVpv( orig, len );           \
        }                                                        \
    } STMT_END;

char *
_standardize_field_name( char *field )
    PREINIT:
        SV   *translate_underscore;
        SV   **standard_case_val;
        char *orig;
        int  i;
        int  len;
        bool word_boundary;
        dMY_CXT;
    CODE:
        TRANSLATE_UNDERSCORE(field);
        HANDLE_STANDARD_CASE(field, len);
        RETVAL = field;
    OUTPUT: RETVAL

AV *
push_header( SV *self, ... )
    PREINIT:
        /* variables for standardization */
        SV   *translate_underscore;
        SV   **standard_case_val;
        char *orig;
        int  i;
        int  len;
        bool word_boundary;
        dMY_CXT;

        char *field;
        SV   *val;
        char *found_colon;
        SV   **h;
        SV   *h_copy;
    CODE:
        if ( items % 2 == 0 )
            croak("You must provide key/value pairs");

        for ( i = 1; i < items; i += 2 ) {
            field = SvPVX( ST(i) );
            val   = newSVsv( ST( i + 1 ) );

            /* leading ':' means "don't standardize" */
            found_colon = index( field, ':' );
            if ( found_colon == NULL || found_colon != 0 ) {
                TRANSLATE_UNDERSCORE(field);
                HANDLE_STANDARD_CASE(field, len);
            }

            h = hv_fetch( (HV *) SvRV(self), field, len, 1 );
            if ( h == NULL )
                croak("hv_fetch() failed. This should not happen."); \

            if ( ! SvOK(*h) ) {
                *h = (SV *) newAV();
            } else if ( SvTYPE(*h) != SVt_RV ) {
                warn("TYPE: %d\n", SvTYPE(*h));
                h_copy = newSVsv(*h);
                *h = (SV *) newAV();
                av_push( (AV *)*h, h_copy );
            }

            if ( SvROK(val) && SvTYPE( SvRV(val) ) == SVt_PVAV )
                av_push( (AV *) *h, newSVsv( SvRV(val) ) );
            else
                av_push( (AV *) *h, val );
        }

        RETVAL = newAV();
    OUTPUT: RETVAL
