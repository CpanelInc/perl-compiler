#      C.pm
#
#      Copyright (c) 1996, 1997, 1998 Malcolm Beattie
#      Copyright (c) 2008, 2009, 2010, 2011 Reini Urban
#      Copyright (c) 2010 Nick Koston
#      Copyright (c) 2011-2017 cPanel Inc
#
#      You may distribute under the terms of either the GNU General Public
#      License or the Artistic License, as specified in the README file.
#

package B::C;

our $VERSION = '5.024020';
our $caller  = caller;       # So we know how we were invoked.

# can be improved
our $nullop_count     = 0;
our $unresolved_count = 0;

our $gv_index = 0;

our $settings = {
    'signals'       => 1,
    'debug_options' => '',
    'output_file'   => '',
    'init_name'     => '',
    'skip_packages' => {},
    'used_packages' => {},
};

# This loads B/C_heavy.pl from the same location C.pm came from.
sub load_heavy {
    my $bc = $INC{'B/C.pm'};
    $bc =~ s/\.pm$/_heavy.pl/;
    require $bc;
}

sub setup_stashes {
    if ( exists $main::{'!'} ) {
        if ( !$INC{'Errno.pm'} ) {

            # STATIC_HV: Altering the stash by loading modules after the white list has been established can lead to
            # problems. Ideally this code should be removed in favor of a better solution.
            eval 'require Errno';
        }
    }
    return;
}

BEGIN {
    # setup the stash before walking our OpTree and calling compile
    setup_stashes();    # if $! then load Errno.
}

# This is the sub called once the BEGIN state completes.
# We want to capture stash and %INC information before we go and corrupt it!
my @configure_options;

sub build_c_file {
    parse_options(@configure_options);    # Parses command line options and populates $settings where necessary
    save_compile_state();
    load_heavy();                         # Loads B::C_heavy.pl

    # After we did a require, clear the SWASH cache so it's not saved.
    utf8->can('reset_swash') and utf8->can('reset_swash')->();

    start_heavy();                        # Invokes into B::C_heavy.pl
}

# This is what is called when you do perl -MO=C,....
# It tells O.pm what to invoke once the program completes the BEGIN state.
sub compile {
    @configure_options = @_;
    do { $DB::single = $DB::single = 1 } if defined &DB::DB;
    return \&build_c_file;
}

sub skip_B {    # wrapper around skip packages to know if we should skip B or not
                # perlcc is going to provide us the -UB option
    return $settings->{'skip_packages'} && $settings->{'skip_packages'}->{'B'} ? 1 : 0;
}

sub save_compile_state {

    # On initial start of B::C save, clear the SWASH cache so it's not saved.
    utf8->can('reset_swash') and utf8->can('reset_swash')->();

    $settings->{'dl_so_files'} = save_xsloader_so();
    $settings->{'dl_modules'}  = save_xsloader_modules();
    $settings->{'needs_xs'}    = scalar @{ $settings->{'dl_so_files'} };

    $settings->{'uses_re'} = scalar grep { m{\Q/re/re.so\E$} } @{ $settings->{'dl_so_files'} };

    $settings->{'template_dir'} = $INC{'B/C.pm'};
    $settings->{'template_dir'} =~ s{\.pm$}{/Templates};

    $settings->{'starting_INC'} = save_inc();

    $settings->{'starting_stash'} = starting_stash( $::{"main::"}, 1 );
    cleanup_stashes();

    set_stashes_enames( $settings->{'starting_stash'} );

    # We're
    $settings->{'starting_stash'}->{'XSLoader::'}->{'load_file'} = 1 if $settings->{'needs_xs'};    #

    $settings->{'starting_flat_stashes'} = flatten_stashes( $settings->{'starting_stash'} );

    #eval q{ require Data::Dumper; $Data::Dumper::Sortkeys = $Data::Dumper::Sortkeys = 1; };
    #eval q { print STDERR Data::Dumper::Dumper($settings->{'dl_so_files'}, $settings->{'dl_modules'}) };
    #eval q { print STDERR Data::Dumper::Dumper($settings->{'starting_INC'}, $settings->{'starting_stash'}) };
    #eval q { print STDERR Data::Dumper::Dumper(\%seen) };
    #eval q[print STDERR Data::Dumper::Dumper( $settings->{'starting_flat_stashes'} )];
    #exit;

    return;
}

sub save_inc {
    my %compiled_INC = %INC;
    my @to_skip      = qw{B/C O};
    push @to_skip, 'B' if skip_B();
    delete $compiled_INC{"$_.pm"} foreach @to_skip;
    foreach my $key ( keys %compiled_INC ) {
        delete $compiled_INC{$key} if $key =~ m/^unicore/;
    }
    return \%compiled_INC;
}

my %seen;

sub starting_stash {
    my ( $stash, $in_main ) = @_;

    $seen{"$stash"} = 1 if ($in_main);

    my %hash;
    foreach my $key ( sort keys %$stash ) {
        next if $key eq 'bootstrap';    ## we do not want to save any bootstrap function ( XS takes care of it )
        if ( $key =~ m/::$/ ) {
            my $goto = $stash->{$key};
            my $name = "$goto";
            if ( !$seen{$name} ) {
                $seen{$name} = 1;
                $hash{$key}  = starting_stash($goto);
            }
            else {
                $hash{$key} = 1;
            }
        }
        else {
            $hash{$key} = 1;    # need to remove if we do not want to save them ?
        }
    }

    return \%hash;
}

sub cleanup_stashes {
    my $use_re  = $settings->{'uses_re'};
    my $stashes = $settings->{'starting_stash'};

    # cleanup stashes from command line client option -U
    if ( ref $settings->{'skip_packages'} ) {
        foreach my $k ( sort keys %{ $settings->{'skip_packages'} } ) {
            my $to_skip = "$k";      # do a copy
            $to_skip =~ s{::$}{};    # remove the trailing :: if client provide it

            my @namespace = split( qr{::}, $to_skip );
            my $cursor = $stashes;
            while ( my $ns = shift @namespace ) {
                $ns .= q{::};

                # stash is not defined, no need to remove it
                next unless ref $cursor && ref $cursor->{$ns};
                if ( scalar @namespace ) {    # let's move deeper
                    $cursor = $cursor->{$ns};
                }
                else {                        # we found it, we remove it from our whitelist
                    delete $cursor->{$ns};
                }
            }
        }
    }

    #if ( !$uses_re ) {
    #    delete $stashes->{'re::'};
    #    delete $stashes->{'Regexp::'};    # unsure
    #}

    # cleanup special variables
    foreach my $k (qw{ BEGIN ARGV ENV }) {
        delete $stashes->{$k};
    }

    # cleanup sepcial stashes
    delete $stashes->{'O::'};
    delete $stashes->{'B::'} if skip_B();
    delete $stashes->{'B::'}{'C::'} if exists $stashes->{'B::'};    # always purge B::C::*

    foreach my $st ( sort keys %$stashes ) {
        next unless ref $stashes->{$st} eq 'HASH';    # only stashes are hash ref
        next if $st eq 'DB::';

        #delete $stashes->{$st} if !scalar keys %{ $stashes->{$st} };
    }

    # special logic for CORE::GLOBAL:: MUST exist ( PL_debstash )

    if ( exists $stashes->{'Carp::'} && scalar keys %{ $stashes->{'Carp::'} } == 1 && exists $stashes->{'Carp::'}->{'croak'} ) {
        delete $stashes->{'Carp::'};
    }

    # STATIC_HV - need more love to make it dynamic
    # preserve the file location but remove our bloat and the special -e to avoid a reparse
    {
        my @files_to_delete = qw{
          /usr/local/cpanel/3rdparty/perl/524/lib64/perl5/5.24.1/x86_64-linux-64int/O.pm
          /usr/local/cpanel/3rdparty/perl/524/lib64/perl5/cpanel_lib/x86_64-linux-64int/B/C.pm
          -e
        };
        if ( skip_B() ) {
            push @files_to_delete, '/usr/local/cpanel/3rdparty/perl/524/lib64/perl5/5.24.1/x86_64-linux-64int/B.pm';
        }

        foreach my $f ( map { q{_<} . $_ } @files_to_delete ) {
            delete $stashes->{$f};
        }
    }

    # PerlIO
    # root_stash name keys_to_clear
    my $clear_stash_keys = sub {
        my ( $root_stash, $name, $keys_to_clear ) = @_;

        return unless ref $root_stash->{$name};    # maybe die during devel

        foreach my $k (@$keys_to_clear) {
            delete $root_stash->{$name}->{$k};
        }
        delete $root_stash->{$name} if !scalar keys %{ $root_stash->{$name} };

        return;
    };

    my $CORE_subs             = {};
    my $clear_stash_keys_core = sub {
        my ( $name_stash, $name, $keys_to_clear ) = @_;

        my $root_stash = $stashes;
        my $full_stash = $name;

        if ( $name_stash && $name_stash ne 'main' ) {
            $root_stash = $stashes->{$name_stash};
            $full_stash = $name_stash . $name;

            #$full_stash =~ s{::^}{};
        }

        foreach my $k (@$keys_to_clear) {
            $CORE_subs->{ $full_stash . $k } = 1;
        }

        return $clear_stash_keys->( $root_stash, $name, $keys_to_clear );
    };

    # B::C provides its own DynaLoader boot
    $clear_stash_keys_core->( 'File::', 'Glob::', [qw{GLOB_ABEND GLOB_ALPHASORT GLOB_ALTDIRFUNC GLOB_BRACE GLOB_CSH GLOB_ERR GLOB_LIMIT GLOB_MARK GLOB_NOCASE GLOB_NOCHECK GLOB_NOMAGIC GLOB_NOSORT GLOB_NOSPACE GLOB_QUOTE GLOB_TILDE}] );

    # we are saving subs defined by CORE at startup
    $settings->{CORE_subs} = $CORE_subs;

    ### we are leaving(/saving) these DynaLoader functions for now - TODO ?
    # 'bootstrap_inherit'
    # 'dl_librefs'
    # 'dl_modules'
    # 'dl_require_symbols'
    # 'dl_shared_objects'

    # too fancy for now, enable it later ???
    # if ( ! $settings->{'needs_xs'} ) {
    #     delete $stashes->{'DynaLoader::'};
    #     delete $stashes->{'XSLoader::'};
    # }

    return;
}

sub _flatten_stashes {
    my ( $stash, $prefix, $flat ) = @_;

    return unless ref $stash eq 'HASH';

    foreach my $k ( sort keys %$stash ) {
        next unless $k =~ qr{::$};
        my $p          = $prefix . $k;
        my $stash_name = $p;
        $stash_name =~ s{::$}{};
        $flat->{$stash_name} = 1;

        _flatten_stashes( $stash->{$k}, $p, $flat );
    }

    return;
}

sub flatten_stashes {
    my ($start_stash) = @_;

    my $flat = {};
    _flatten_stashes( $start_stash, '', $flat );

    return $flat;
}

sub set_stashes_enames {
    my ( $stash, $name ) = @_;

    return unless ref $stash;
    $name = '' unless defined $name;
    foreach my $k ( keys %$stash ) {
        next unless $k =~ qr{::$};
        my $stn = $name . $k;
        my $ename = eval { B::svref_2object( \*{"${stn}"} )->EGV->NAME };
        if ( $ename && $k ne $ename ) {

            # increase our white list to take into account the enames [could probably merge hashes recursively]
            if ( !exists $stash->{$ename} or !ref $stash->{$ename} ) {
                $stash->{$ename} = { %{ $stash->{$k} } };
            }
            else {
                $stash->{$ename} = { %{ $stash->{$ename} }, %{ $stash->{$k} } };
            }
        }
        set_stashes_enames( $stash->{$k}, $stn );
    }

    return;
}

sub save_xsloader_so {
    my @DL = eval '@DynaLoader::dl_shared_objects';                    # Quoted eval gets rid of no warnings once issue.
    my @short = grep { $_ !~ qr{\QPerlIO/scalar/scalar.so\E$} } @DL;
    @short = grep { $_ !~ m{/B/B\.so$} } @short if skip_B();
    return [@short];
}

sub save_xsloader_modules {
    my @DL = eval '@DynaLoader::dl_modules';                             # Quoted eval gets rid of no warnings once issue.
    my @short = grep { $_ !~ m{^B::C} && $_ ne 'PerlIO::scalar' } @DL;
    @short = grep { $_ !~ m{^B$} } @short if skip_B();
    return [@short];
}

# This parses the options passed to sub compile but not until build_c_file is invoked at the end of BEGIN.
# It is NOT SAFE to mess with anything outside of the %B::C:: stash

sub parse_options {
    my (@opts) = @_;
    my ( $option, $opt, $arg );

    while ( $option = shift @opts ) {
        next unless length $option;    # fixes -O=C,,-v,...
        if ( $option =~ /^-(.)(.*)/ ) {
            $opt = $1;
            $arg = $2 || '';
        }
        else {
            die( "Unexpected options passed to O=C: " . join( ",", @opts ) );
        }

        if ( $opt eq "-" && $arg eq "-" ) {
            die( "Unexpected options passed to O=C: --" . join( ",", @opts ) );
        }

        if ( $opt eq "w" ) {
            $settings->{'warn_undefined_syms'} = 1;
        }
        elsif ( $opt eq "D" ) {
            $arg ||= shift @opts;
            $arg =~ s{^=+}{};
            $settings->{'debug_options'} .= $arg;
        }
        elsif ( $opt eq "o" ) {
            $arg ||= shift @opts;
            $settings->{'output_file'} = $arg;
        }
        elsif ( $opt eq "n" ) {
            $arg ||= shift @opts;
            $settings->{'init_name'} = $arg;
        }
        elsif ( $opt eq "m" ) {
            $settings->{'used_packages'}->{$arg} = 1;
        }
        elsif ( $opt eq "v" ) {
            $settings->{'enable_verbose'} = 1;
        }
        elsif ( $opt eq "u" ) {
            $arg ||= shift @opts;
            if ( $arg =~ /\.p[lm]$/ ) {
                eval "require(\"$arg\");";    # path as string
            }
            else {
                eval "require $arg;";         # package as bareword with ::
            }
            $settings->{'used_packages'}->{$arg} = 1;
        }
        elsif ( $opt eq "U" ) {
            $arg ||= shift @opts;
            $settings->{'skip_packages'}->{$arg} = 1;

            # Maybe delete the stash from save_inc ?
        }
        else {
            die "Invalid option $opt";
        }
    }

    @opts and die("Used to call B::C::File::output_all but this sub has been gone for a while!");

    return;
}

1;

__END__

=head1 NAME

B::C - Perl compiler's C backend

=head1 SYNOPSIS

	perl -MO=C[,OPTIONS] foo.pl

=head1 DESCRIPTION

This compiler backend takes Perl source and generates C source code
corresponding to the internal structures that perl uses to run
your program. When the generated C source is compiled and run, it
cuts out the time which perl would have taken to load and parse
your program into its internal semi-compiled form. That means that
compiling with this backend will not help improve the runtime
execution speed of your program but may improve the start-up time.
Depending on the environment in which your program runs this may be
either a help or a hindrance.

=head1 OPTIONS

If there are any non-option arguments, they are taken to be
names of objects to be saved (probably doesn't work properly yet).
Without extra arguments, it saves the main program.

=over 4

=item B<-o>I<filename>

Output to filename instead of STDOUT

=item B<-n>I<init_name>

Default: "perl_init" and "init_module"

=item B<-v>

Verbose compilation. Currently gives a few compilation statistics.

=item B<-u>I<Package> "use Package"

Force all subs from Package to be compiled.

This allows programs to use eval "foo()" even when sub foo is never
seen to be used at compile time. The down side is that any subs which
really are never used also have code generated. This option is
necessary, for example, if you have a signal handler foo which you
initialise with C<$SIG{BAR} = "foo">.  A better fix, though, is just
to change it to C<$SIG{BAR} = \&foo>. You can have multiple B<-u>
options. The compiler tries to figure out which packages may possibly
have subs in which need compiling but the current version doesn't do
it very well. In particular, it is confused by nested packages (i.e.
of the form C<A::B>) where package C<A> does not contain any subs.

=item B<-U>I<Package> "unuse" skip Package

Ignore all subs from Package to be compiled.

Certain packages might not be needed at run-time, even if the pessimistic
walker detects it.

=item B<-D>C<[OPTIONS]>

Debug options, concatenated or separate flags like C<perl -D>.
Verbose debugging options are crucial, because the interactive
debugger L<Od> adds a lot of ballast to the resulting code.

=item B<-Dfull>

Enable all full debugging, as with C<-DoOcAHCMGSpWF>.
All but C<-Du>.

=item B<-Do>

All Walkop'ed OPs

=item B<-DO>

OP Type,Flags,Private

=item B<-DS>

Scalar SVs, prints B<SV/RE/RV> information on saving.

=item B<-DP>

Extra PV information on saving. (static, len, hek, fake_off, ...)

=item B<-Dc>

B<COPs>, prints COPs as processed (incl. file & line num)

=item B<-DA>

prints B<AV> information on saving.

=item B<-DH>

prints B<HV> information on saving.

=item B<-DC>

prints B<CV> information on saving.

=item B<-DG>

prints B<GV> information on saving.

=item B<-DM>

prints B<MAGIC> information on saving.

=item B<-DR>

prints B<REGEXP> information on saving.

=item B<-Dp>

prints cached B<package> information, if used or not.

=item B<-Ds>

prints all compiled sub names, optionally with " not found".

=item B<-DF>

Add Flags info to the code.

=item B<-DW>

Together with B<-Dp> also prints every B<walked> package symbol.

=item B<-Du>

do not print B<-D> information when parsing for the unused subs.

=item B<-Dr>

Writes debugging output to STDERR and to the program's generated C file.
Otherwise writes debugging info to STDERR only.

=back

=head1 EXAMPLES

    perl -MO=C,-ofoo.c foo.pl
    perl cc_harness -o foo foo.c

Note that C<cc_harness> lives in the C<B> subdirectory of your perl
library directory. The utility called C<perlcc> may also be used to
help make use of this compiler.

    perlcc foo.pl

    perl -MO=C,-v,-DcA bar.pl > /dev/null

=over

=item Warning: Problem with require "$name" - $INC{file.pm}

Dynamic load of $name did not add the expected %INC key.

=item Warning: C.xs PMOP missing for QR

In an initial C.xs runloop all QR regex ops are stored, so that they
can matched later to PMOPs.

=item Warning: DynaLoader broken with 5.15.2-5.15.3.

[perl #100138] DynaLoader symbols were XS_INTERNAL. Strict linking
could not resolve it. Usually libperl was patched to overcome this
for these two versions.
Setting the environment variable NO_DL_WARN=1 omits this warning.

=item Warning: __DATA__ handle $fullname not stored. Need -O2 or -fsave-data.

Since processing the __DATA__ filehandle involves some overhead, requiring
PerlIO::scalar with all its dependencies, you must use -O2 or -fsave-data.

=item Warning: Write BEGIN-block $fullname to FileHandle $iotype \&$fd

Critical problem. This must be fixed in the source.

=item Warning: Read BEGIN-block $fullname from FileHandle $iotype \&$fd

Critical problem. This must be fixed in the source.

=item Warning: -o argument ignored with -c

-c does only check, but not accumulate C output lines.

=back

=head1 BUGS

Current status: A few known bugs, but usable in production

=head1 AUTHOR

Malcolm Beattie C<MICB at cpan.org> I<(1996-1998, retired)>,
Nick Ing-Simmons <nik at tiuk.ti.com> I(1998-1999),
Vishal Bhatia <vishal at deja.com> I(1999),
Gurusamy Sarathy <gsar at cpan.org> I(1998-2001),
Mattia Barbon <mbarbon at dsi.unive.it> I(2002),
Reini Urban C<perl-compiler@googlegroups.com> I(2008-)

=head1 SEE ALSO

L<perlcompiler> for a general overview,
L<B::CC> for the optimising C compiler,
L<B::Bytecode> + L<ByteLoader> for the bytecode compiler,
L<Od> for source level debugging in the L<B::Debugger>,
L<illguts> for the illustrated Perl guts,
L<perloptree> for the Perl optree.

=cut

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 2
#   fill-column: 78
# End:
# vim: expandtab shiftwidth=2:
