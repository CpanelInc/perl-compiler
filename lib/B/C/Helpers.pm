package B::C::Helpers;

use Exporter ();
use B::C::Config;
use B qw/SVf_POK SVp_POK/;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw/svop_name padop_name read_utf8_string
  is_constant strlen_flags cow_strlen_flags is_shared_hek
  cstring_cow get_index
  /;

# wip to be moved
*padop_name = \&B::C::padop_name;
*svop_name  = \&B::C::svop_name;

# B/C/Helpers/Sym

use B qw/cstring/;

sub is_constant {
    my $s = shift;
    return 1 if $s =~ /^(&sv_list|\-?[0-9]+|Nullsv)/;    # not gv_list, hek
    return 0;
}

sub is_shared_hek {
    my $sv = shift;
    return 0 unless $sv && $$sv;

    my $flags = $sv->FLAGS;
    return 0 unless $flags & ( SVf_POK | SVp_POK );      # cannot be a shared hek if we have no PV public or private
    return ( ( $flags & 0x09000000 ) == 0x09000000 ) || B::C::IsCOW_hek($sv);
}

# lazy helper for backward compatibility only (we can probably avoid to use it)
sub strlen_flags {
    my $str = shift;

    my ( $is_utf8, $cur ) = read_utf8_string($str);
    my $cstr = cstring($str);

    return ( $cstr, $cur, $is_utf8 ? 'SVf_UTF8' : '0' );
}

sub cstring_cow {
    my ( $str, $cow ) = @_;

    # TODO: we would like to use cstring("$str$cow") but in some cases, the c string is corrupted
    # instead of
    #   cowpv7[] = "$c\000\377";
    # we had
    #   cowpv7[] = "$c\000\303\277";

    my $cstr = cstring($str);

    $cstr =~ s{"$}{$cow"};

    # this is very weird... probably a cstring issue there
    if ( length($cstr) < ( length($cow) + 2 ) ) {    # $cstr && $cstr eq '0' ||
        return qq["$cow"];
    }

    return $cstr;
}

# lazy helper for backward compatibility only (we can probably avoid to use it)
sub cow_strlen_flags {
    my $str = shift;

    my ( $is_utf8, $cur ) = read_utf8_string($str);

    my $cstr = cstring_cow( $str, q{\000\377} );

    #my $xx = join ':', map { ord } split(//, $str );
    #warn "STR $cstr ; $cur [$xx]\n" if $cur < 5;# && $cstr eq '0';

    return ( $cstr, $cur, $cur + 2, $is_utf8 ? 'SVf_UTF8' : '0' );    # NOTE: The actual Cstring length will be 2 bytes longer than $cur
}

# maybe move to B::C::Helpers::Str ?
sub read_utf8_string {
    my ($name) = @_;

    my $cur;

    #my $is_utf8 = $utf_len != $str_len ? 1 : 0;
    my $is_utf8 = utf8::is_utf8($name);
    if ($is_utf8) {
        my $copy = $name;
        $cur = utf8::upgrade($copy);
    }
    else {
        #$cur = length( pack "a*", $name );
        $cur = length($name);    ### ... should use the c lenght
    }

    return ( $is_utf8, $cur );
}

sub get_index {
    my $str = shift;
    return $1 if $str && $str =~ qr{\[([0-9]+)\]};
    die "Cannot get index from '$str'";
}

1;
