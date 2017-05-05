package B::PVLV;

use strict;

use B q/cchar/;

use B::C::Config;
use B::C::Save qw/savepvn/;
use B::C::File qw/xpvlvsect svsect init/;
use B::C::Decimal qw/ get_double_value/;

# Warning not covered by the (cpanel)core test suite...
# FIXME... add some test coverage for PVLV

sub do_save {
    my ( $sv, $fullname ) = @_;

    my ( $pvsym, $cur, $len, $pv, $static, $flags ) = B::PV::save_pv_or_rv( $sv, $fullname );
    my ( $lvtarg, $lvtarg_sym );    # XXX missing

    # STATIC HV: Static stash please.
    xpvlvsect()->comment('STASH, MAGIC, CUR, LEN, GvNAME, xnv_u, TARGOFF, TARGLEN, TARG, TYPE');
    xpvlvsect()->add(
        sprintf(
            "Nullhv, %s, %u, %d, 0/*GvNAME later*/, %s, %u, %u, Nullsv, %s",
            $sv->save_magic($fullname), $cur,         $len, get_double_value( $sv->NVX ),
            $sv->TARGOFF,               $sv->TARGLEN, cchar( $sv->TYPE )
        )
    );
    my $ix = svsect()->add(
        sprintf(
            "&xpvlv_list[%d], %Lu, 0x%x, {(char*)%s}",
            xpvlvsect()->index, $sv->REFCNT, $flags, $pvsym
        )
    );

    svsect()->debug( $fullname, $sv );

    return "&sv_list[" . $ix . "]";
}

1;
