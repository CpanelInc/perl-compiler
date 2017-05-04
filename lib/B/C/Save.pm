package B::C::Save;

use strict;

use B qw(cstring svref_2object);
use B::C::Config;
use B::C::File qw( xpvmgsect decl init const );
use B::C::Helpers qw/strlen_flags is_shared_hek cstring_cow cow_strlen_flags/;
use B::C::Save::Hek qw/save_shared_he/;

use Exporter ();
our @ISA = qw(Exporter);

our @EXPORT_OK = qw/savepvn constpv savepv savecowpv inc_pv_index savestashpv/;

my %strtable;
my %cowtable;

# Two different families of save functions
#   save_* vs save*

my $pv_index = -1;

sub inc_pv_index {
    return ++$pv_index;
}

sub savecowpv {
    my $pv = shift;
    my ( $cstring, $cur, $len, $utf8 ) = cow_strlen_flags($pv);

    return @{ $cowtable{$cstring} } if defined $cowtable{$cstring};

    my $ix = const()->add('FAKE_CONST');
    my $pvsym = sprintf( "cowpv%d", $ix );

    my $max_len = 0;
    if ( $max_len && $cur > $max_len ) {
        my $chars = join ', ', map { cchar $_ } split //, pack( "a*", $pv );
        const()->update( $ix, sprintf( "Static const char %s[] = { %s };", $pvsym, $chars ) );
        $cowtable{$cstring} = [ $pvsym, $cur, $len ];
    }
    else {
        const()->update( $ix, sprintf( "Static const char %s[] = %s;", $pvsym, $cstring ) );
        $cowtable{$cstring} = [ $pvsym, $cur, $len ];
    }
    return ( $pvsym, $cur, $len );    # NOTE: $cur is total size of the perl string. len would be the length of the C string.
}

sub constpv {                         # could also safely use a cowpv
    return savepv( shift, 1 );
}

sub savepv {
    my $pv    = shift;
    my $const = shift;
    my ( $cstring, $len, $utf8 ) = strlen_flags($pv);

    return $strtable{$cstring} if defined $strtable{$cstring};
    my $pvsym = sprintf( "pv%d", inc_pv_index() );
    $const = $const ? " const" : "";
    my $maxlen = 0;
    if ( $maxlen && $len > $maxlen ) {
        my $chars = join ', ', map { cchar $_ } split //, pack( "a*", $pv );
        decl()->sadd( "Static%s char %s[] = { %s };", $const, $pvsym, $chars );
        $strtable{$cstring} = $pvsym;
    }
    else {
        if ( $cstring ne "0" ) {    # sic
            decl()->sadd( "Static%s char %s[] = %s;", $const, $pvsym, $cstring );
            $strtable{$cstring} = $pvsym;
        }
    }
    return $pvsym;
}

sub savepvn {
    my ( $dest, $pv, $sv, $cur ) = @_;
    my @init;

    my $maxlen = 0;

    $pv = pack "a*", $pv if defined $pv;
    if ( $maxlen && length($pv) > $maxlen ) {
        push @init, sprintf( "Newx(%s,%u,char);", $dest, length($pv) + 2 );
        my $offset = 0;
        while ( length $pv ) {
            my $str = substr $pv, 0, $maxlen, '';
            push @init, sprintf( 'Copy(%s, %s+%d, %u, char);', cstring($str), $dest, $offset, length($str) );
            $offset += length $str;
        }
        push @init, sprintf( "%s[%u] = '\\0';", $dest, $offset );
        debug( pv => "Copying overlong PV %s to %s\n", cstring($pv), $dest );
    }
    else {
        # If READONLY and FAKE use newSVpvn_share instead. (test 75)
        if ( $sv and is_shared_hek($sv) ) {
            debug( sv => "Saving shared HEK %s to %s\n", cstring($pv), $dest );
            my $shared_he = save_shared_he($pv);
            push @init, sprintf( "%s = %s->shared_he_hek.hek_key;", $dest, $shared_he ) unless $shared_he eq 'NULL';
        }
        else {
            my $cstr = cstring($pv);
            my $cur ||= ( $sv and ref($sv) and $sv->can('CUR') and ref($sv) ne 'B::GV' ) ? $sv->CUR : length( pack "a*", $pv );
            if ( $sv and B::C::IsCOW($sv) ) {
                $cstr = cstring_cow( $pv, q{\000\001} );
                $cur += 2;
            }
            debug( sv => "Saving PV %s:%d to %s", $cstr, $cur, $dest );
            $cur = 0 if $cstr eq "" and $cur == 7;    # 317
            push @init, sprintf( "%s = savepvn(%s, %u); " . _caller_comment(), $dest, $cstr, $cur );
        }
    }
    return @init;
}

sub _caller_comment {
    return '' unless debug('stack');
    my $s = stack_flat(+1);
    return qq{/* $s */};
}

sub stack {
    my @stack;
    foreach my $level ( 0 .. 100 ) {
        my @caller = grep { defined } caller($level);
        @caller = map { $_ =~ s{/usr/local/cpanel/3rdparty/perl/5[0-9]+/lib64/perl5/cpanel_lib/x86_64-linux-64int/}{lib/}; $_ } @caller;

        last if !scalar @caller or !defined $caller[0];
        push @stack, join( ' ', @caller );
    }

    return \@stack;
}

sub stack_flat {
    my $remove = shift || 0;    # number of stack levels to remove
    $remove += 2;
    my @stack = @{ stack() };
    splice( @stack, 0, $remove );    # shift the first X elements
    return join "\n", @stack;
}

sub savestashpv {                    # save a stash from a string (pv)
    my $name = shift;
    no strict 'refs';
    return svref_2object( \%{ $name . '::' } )->save;
}

1;
