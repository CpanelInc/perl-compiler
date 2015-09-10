package B::REGEXP;

use strict;

use Config;
use B qw/cstring/;
use B::C::Config;
use B::C::File qw/init svsect xpvsect/;
use B::C::Helpers::Symtable qw/objsym savesym/;

# post 5.11: When called from save_rv not from PMOP::save precomp
sub save {
    my ( $sv, $fullname ) = @_;

    my $sym = objsym($sv);
    return $sym if defined $sym;
    my $pv  = $sv->PV;
    my $cur = $sv->CUR;

    # construct original PV
    $pv =~ s/^(\(\?\^[adluimsx-]*\:)(.*)\)$/$2/;
    $cur -= length( $sv->PV ) - length($pv);
    my $cstr = cstring($pv);

    # Unfortunately this XPV is needed temp. Later replaced by struct regexp.
    xpvsect()->add( sprintf( "Nullhv, {0}, %u, %u", $cur, 0 ) );
    svsect()->add(
        sprintf(
            "&xpv_list[%d], %lu, 0x%x, {%s}",
            xpvsect()->index, $sv->REFCNT, $sv->FLAGS, $cstr
        )
    );
    my $ix = svsect()->index;
    debug( rx => "Saving RX $cstr to sv_list[$ix]" );

    init()->add(    # replace sv_any->XPV with struct regexp. need pv and extflags
        sprintf(
            "SvANY(&sv_list[$ix]) = SvANY(CALLREGCOMP(newSVpvn(%s, %d), 0x%x));",
            $cstr, $cur, $sv->EXTFLAGS
        )
    );

    init()->add(
        sprintf( "SvCUR(&sv_list[$ix]) = %d;", $cur ),
        "SvLEN(&sv_list[$ix]) = 0;"
    );

    svsect()->debug( $fullname, $sv );
    $sym = savesym( $sv, sprintf( "&sv_list[%d]", $ix ) );
    $sv->save_magic($fullname);
    return $sym;
}

1;
