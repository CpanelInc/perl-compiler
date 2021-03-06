package B::NULL;

use strict;
use B::C::Debug qw/debug verbose/;
use B::C::File qw/svsect/;

sub do_save {
    my ( $sv, $fullname ) = @_;

    # debug
    if ( $$sv == 0 ) {
        debug("NULL::save for sv = 0 called from @{[(caller(1))[3]]}");
        return "(void*)Nullsv";
    }

    my $ix = svsect()->sadd( "NULL, %Lu, 0x%x, {0}", $sv->REFCNT, $sv->FLAGS );
    debug( sv => "Saving SVt_NULL sv_list[$ix]" );

    return sprintf( "&sv_list[%d]", $ix );
}

1;
