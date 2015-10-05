package B::AV;

use strict;

use Config;
use B qw/cstring SVf_IOK SVf_POK/;
use B::C::Config;
use B::C::File qw/init xpvavsect svsect padlistsect padnamelistsect/;
use B::C::Helpers::Symtable qw/objsym savesym/;

# maybe need to move to setup/config
my ( $use_av_undef_speedup, $use_svpop_speedup ) = ( 1, 1 );
my $MYMALLOC = $Config{usemymalloc} eq 'define';

sub save {
    my ( $av, $fullname ) = @_;
    my $sym = objsym($av);
    return $sym if defined $sym;

    $fullname = '' unless $fullname;
    my ( $fill, $avreal, $max );

    my $ispadlist     = ref($av) eq 'B::PADLIST';
    my $ispadnamelist = ref($av) eq 'B::PADNAMELIST';

    if ( $ispadnamelist or $ispadlist ) {
        $fill = $av->MAX;
    }
    else {
        eval { $fill = $av->FILL; };    # cornercase: tied array without FETCHSIZE
        $fill = -1 if $@;               # catch error in tie magic
    }

    $max = $fill;
    my $svpcast = $ispadlist ? "(PAD*)" : "(SV*)";
    $svpcast = "(PADNAME*)" if $ispadnamelist;

    if ($ispadnamelist) {
        padnamelistsect()->comment("xpadnl_fill, xpadnl_alloc, xpadnl_max, xpadnl_max_named, xpadnl_refcnt");

        # TODO: max_named walk all names and look for non-empty names
        my $refcnt = $av->REFCNT + 1;    # XXX defer free to global destruction: 28
        padnamelistsect()->add("$fill, NULL, $fill, $fill, $refcnt");
        my $padnamelist_index = padnamelistsect()->index;
        $sym = savesym( $av, "&padnamelist_list[$padnamelist_index]" );
        push @B::C::static_free, $sym;
    }
    elsif ($ispadlist) {
        padlistsect()->comment("xpadl_max, xpadl_alloc, xpadl_outid");
        padlistsect()->add("$fill, NULL, 0");    # Perl_pad_new(0)
        my $padlist_index = padlistsect()->index;
        $sym = savesym( $av, "&padlist_list[$padlist_index]" );
    }
    else {
        # 5.14
        # 5.13.3: STASH, MAGIC, fill max ALLOC
        my $line = "Nullhv, {0}, -1, -1, 0";
        $line = "Nullhv, {0}, $fill, $max, 0" if $B::C::av_init or $B::C::av_init2;
        xpvavsect()->add($line);
        svsect()->add(
            sprintf(
                "&xpvav_list[%d], %lu, 0x%x, {%s}",
                xpvavsect()->index, $av->REFCNT, $av->FLAGS,
                '0'
            )
        );
    }

    my ( $magic, $av_index ) = ('');
    if ( !$ispadlist and !$ispadnamelist ) {
        svsect()->debug( $fullname, $av );
        my $sv_ix = svsect()->index;
        $av_index = xpvavsect()->index;

        # protect against recursive self-references (Getopt::Long)
        $sym = savesym( $av, "(AV*)&sv_list[$sv_ix]" );
        $magic = $av->save_magic($fullname);
    }

    debug( av => "saving AV $fullname 0x%x [%s] FILL=$fill", $$av, ref($av) );

    # XXX AVf_REAL is wrong test: need to save comppadlist but not stack
    if ( $fill > -1 and defined $magic and $magic !~ /D/ ) {
        my @array = $av->ARRAY;    # crashes with D magic (Getopt::Long)
        if ( debug('av') ) {
            my $i = 0;
            foreach my $el (@array) {
                my $val = '';

                # if SvIOK print iv, POK pv
                if ( $el->can('FLAGS') ) {
                    $val = $el->IVX           if $el->FLAGS & SVf_IOK;
                    $val = cstring( $el->PV ) if $el->FLAGS & SVf_POK;
                }
                debug( av => "AV %s \[%d] = %s %s", $av, $i++, ref($el), $val );
            }
        }

        #	my @names = map($_->save, @array);
        # XXX Better ways to write loop?
        # Perhaps svp[0] = ...; svp[1] = ...; svp[2] = ...;
        # Perhaps I32 i = 0; svp[i++] = ...; svp[i++] = ...; svp[i++] = ...;

        # micro optimization: op/pat.t ( and other code probably )
        # has very large pads ( 20k/30k elements ) passing them to
        # ->add is a performance bottleneck: passing them as a
        # single string cuts runtime from 6min20sec to 40sec

        # you want to keep this out of the no_split/split
        # map("\t*svp++ = (SV*)$_;", @names),
        my $acc = '';

        # Init optimization by Nick Koston
        # The idea is to create loops so there is less C code. In the real world this seems
        # to reduce the memory usage ~ 3% and speed up startup time by about 8%.
        my ( $count, @values );
        {
            # TODO: This local may no longer be needed now we've removed the 5.16 conditional here.
            local $B::C::const_strings = $B::C::const_strings;

            @values = map { $_->save( $fullname . "[" . $count++ . "]" ) || () } @array;
        }
        $count = 0;
        for ( my $i = 0; $i <= $#array; $i++ ) {
            if (   $use_svpop_speedup
                && defined $values[$i]
                && defined $values[ $i + 1 ]
                && defined $values[ $i + 2 ]
                && $values[$i] =~ /^\&sv_list\[(\d+)\]/
                && $values[ $i + 1 ] eq "&sv_list[" . ( $1 + 1 ) . "]"
                && $values[ $i + 2 ] eq "&sv_list[" . ( $1 + 2 ) . "]" ) {
                $count = 0;
                while ( defined( $values[ $i + $count + 1 ] ) and $values[ $i + $count + 1 ] eq "&sv_list[" . ( $1 + $count + 1 ) . "]" ) {
                    $count++;
                }
                $acc .= "\tfor (gcount=" . $1 . "; gcount<" . ( $1 + $count + 1 ) . "; gcount++) {" . " *svp++ = $svpcast&sv_list[gcount]; };\n\t";
                $i += $count;
            }
            elsif ($use_av_undef_speedup
                && defined $values[$i]
                && defined $values[ $i + 1 ]
                && defined $values[ $i + 2 ]
                && $values[$i] =~ /^ptr_undef|&PL_sv_undef$/
                && $values[ $i + 1 ] =~ /^ptr_undef|&PL_sv_undef$/
                && $values[ $i + 2 ] =~ /^ptr_undef|&PL_sv_undef$/ ) {
                $count = 0;
                while ( defined $values[ $i + $count + 1 ] and $values[ $i + $count + 1 ] =~ /^ptr_undef|&PL_sv_undef$/ ) {
                    $count++;
                }
                $acc .= "\tfor (gcount=0; gcount<" . ( $count + 1 ) . "; gcount++) {" . " *svp++ = $svpcast&PL_sv_undef; };\n\t";
                $i += $count;
            }
            else {    # XXX 5.8.9d Test::NoWarnings has empty values
                $acc .= "\t*svp++ = $svpcast" . ( $values[$i] ? $values[$i] : '&PL_sv_undef' ) . ";\n\t";
            }
        }
        init()->no_split;

        if ($ispadnamelist) {
            my $fill1 = $fill + 1;
            init()->add( "{", "\tPADNAME **svp;" );
            init()->add("\tregister int gcount;") if $count;
            init()->add(
                "\tPADNAMELIST *padnl = $sym;",
                sprintf( "\tNewxz(svp, %d, PADNAME *);", $fill + 1 ),
                "\tPadnamelistARRAY(padnl) = svp;",
            );
            init()->add( substr( $acc, 0, -2 ) );
            init()->add("}");
        }
        elsif ($ispadlist) {
            my $fill1 = $fill + 1;
            init()->add( "{", "\tPAD **svp;" );
            init()->add("\tregister int gcount;") if $count;
            init()->add(
                "\tPADLIST *padl = $sym;",
                sprintf( "\tNewxz(svp, %d, PAD *);", $fill + 1 ),
                "\tPadlistARRAY(padl) = svp;",
            );
            init()->add( substr( $acc, 0, -2 ) );
            init()->add("}");
        }

        # With -fav-init2 use independent_comalloc()
        elsif ($B::C::av_init2) {
            my $i = $av_index;
            $B::C::xpvav_sizes[$i] = $fill;
            my $init_add = "{ SV **svp = avchunks[$i]; AV *av = $sym;\n";
            $init_add .= "\tregister int gcount;\n" if $count;
            if ( $fill > -1 ) {

                $init_add .= "\tAvALLOC(av) = svp;\n" . "\tAvARRAY(av) = svp;\n";
            }
            $init_add .= substr( $acc, 0, -2 );
            init()->add( $init_add . "}" );
        }

        # With -fav-init faster initialize the array as the initial av_extend()
        # is very expensive.
        # The problem was calloc, not av_extend.
        # Since we are always initializing every single element we don't need
        # calloc, only malloc. wmemset'ting the pointer to PL_sv_undef
        # might be faster also.
        elsif ($B::C::av_init) {
            init()->add(
                "{ /* Slow array init mode. */",
                "\tSV **svp;",
                "\tAV *av = $sym;"
            );
            init()->add("\tregister int gcount;") if $count;
            my $fill1 = $fill < 3 ? 3 : $fill + 1;
            if ( $fill > -1 ) {

                # Perl_safesysmalloc (= calloc => malloc) or Perl_malloc (= mymalloc)?
                if ($MYMALLOC) {
                    init()->add(
                        sprintf( "\tNewx(svp, %d, SV*);", $fill1 ),
                        "\tAvALLOC(av) = svp;"
                    );
                }
                else {
                    # Bypassing Perl_safesysmalloc on darwin fails with "free from wrong pool", test 25.
                    # So with DEBUGGING perls we have to track memory and use calloc.
                    init()->add(
                        "#ifdef PERL_TRACK_MEMPOOL",
                        sprintf( "\tsvp = (SV**)Perl_safesysmalloc(%d * sizeof(SV*));", $fill1 ),
                        "#else",
                        sprintf( "\tsvp = (SV**)malloc(%d * sizeof(SV*));", $fill1 ),
                        "#endif",
                        "\tAvALLOC(av) = svp;"
                    );
                }

                init()->add("\tAvARRAY(av) = svp;");
            }
            init()->add( substr( $acc, 0, -2 ) );    # AvFILLp already in XPVAV
            init()->add("}");
        }
        else {                                       # unoptimized with the full av_extend()
            my $fill1 = $fill < 3 ? 3 : $fill + 1;
            init()->add( "{", "\tSV **svp;" );
            init()->add("\tregister int gcount;") if $count;
            init()->add(
                "\tAV *av = $sym;",
                "\tav_extend(av, $fill1);",
                "\tsvp = AvARRAY(av);"
            );
            init()->add( substr( $acc, 0, -2 ) );
            init()->add( "\tAvFILLp(av) = $fill;", "}" );
        }
        init()->split;

        # we really added a lot of lines ( B::C::InitSection->add
        # should really scan for \n, but that would slow
        # it down
        init()->inc_count($#array);
    }
    else {
        my $max = $av->MAX;
        init()->add("av_extend($sym, $max);")
          if $max > -1;
    }

    return $sym;
}

1;
