package B::C::Helpers;

use Exporter ();
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw/svop_name padop_name mark_package do_labels read_utf8_string get_cv_string is_constant strlen_flags/;

# wip to be moved
*do_labels    = \&B::C::do_labels;
*mark_package = \&B::C::mark_package;
*padop_name   = \&B::C::padop_name;
*svop_name    = \&B::C::svop_name;

# B/C/Helpers/Sym

use B qw/cstring/;

sub is_constant {
    my $s = shift;
    return 1 if $s =~ /^(&sv_list|\-?[0-9]+|Nullsv)/;    # not gv_list, hek
    return 0;
}

# lazy helper for backward compatibility only (we can probably avoid to use it)
sub strlen_flags {
    my $str = shift;

    my ( $is_utf8, $len ) = read_utf8_string($str);
    return ( cstring($str), $len, $is_utf8 ? 'SVf_UTF8' : '0' );
}

# maybe move to B::C::Helpers::Str ?
sub read_utf8_string {
    my ($name) = @_;

    my $len;

    #my $is_utf8 = $utf_len != $str_len ? 1 : 0;
    my $is_utf8 = utf8::is_utf8($name);
    if ($is_utf8) {
        my $copy = $name;
        $len = utf8::upgrade($copy);
    }
    else {
        #$len = length( pack "a*", $name );
        $len = length($name);
    }

    return ( $is_utf8, $len );
}

sub get_cv_string {
    my ( $name, $flags ) = @_;
    warn 'undefined flags' unless defined $flags;

    my $cname = cstring($name);

    my ( $is_utf8, $length ) = read_utf8_string($name);

    $flags = '' unless defined $flags;
    $flags .= "|SVf_UTF8" if $is_utf8;
    $flags =~ s/^\|//;

    if ( $flags =~ qr{^0?$} ) {
        return qq/get_cv($cname, 0)/;
    }
    else {
        return qq/get_cvn_flags($cname, $length, $flags)/;
    }
}

1;
