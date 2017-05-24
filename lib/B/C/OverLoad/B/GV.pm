package B::GV;

use strict;

use B qw/cstring svref_2object SVt_PVGV SVf_ROK SVf_UTF8/;

use B::C::Config;
use B::C::Save::Hek qw/save_shared_he/;
use B::C::File qw/init init2 init_static_assignments gvsect gpsect xpvgvsect/;
use B::C::Helpers qw/get_cv_string strlen_flags/;
use B::C::Helpers::Symtable qw/objsym savesym/;
use B::C::Optimizer::ForceHeavy qw/force_heavy/;

my %gptable;

sub Save_HV()   { 1 }
sub Save_AV()   { 2 }
sub Save_SV()   { 4 }
sub Save_CV()   { 8 }
sub Save_FORM() { 16 }
sub Save_IO()   { 32 }
sub Save_FILE() { 64 }

sub _savefields_to_str {
    my $i = shift;
    return '' unless debug('gv') && $i;
    my $s = qq{$i: };
    $s .= 'HV '   if $i & Save_HV();
    $s .= 'AV '   if $i & Save_AV();
    $s .= 'SV '   if $i & Save_SV();
    $s .= 'CV '   if $i & Save_CV();
    $s .= 'FORM ' if $i & Save_FORM();
    $s .= 'IO '   if $i & Save_IO();
    $s .= 'FILE ' if $i & Save_FILE();

    return $s;
}

my $CORE_SYMS = {
    'main::ENV'    => 'PL_envgv',
    'main::ARGV'   => 'PL_argvgv',
    'main::STDIN'  => 'PL_stdingv',
    'main::STDERR' => 'PL_stderrgv',
    'main::stdin'  => 'PL_stdingv',
    'main::stdout' => 'PL_defoutgv',
    'main::stderr' => 'PL_stderrgv',
};

sub do_save {
    my ( $gv, $name ) = @_;

    # return earlier for special cases
    return $CORE_SYMS->{ $gv->get_fullname } if $gv->is_coresym();

    # This is probably dead code.

    # STATIC_HV need to handle $0

    my $gv_ix = gvsect()->add('FAKE_GV');
    my $gvsym = sprintf( '&gv_list[%d]', $gv_ix );
    savesym( $gv, $gvsym );    # cache it

    my $savefields = get_savefields( $gv, $gv->get_fullname() );

    debug( gv => '===== GV::do_save for %s [ savefields=%s ] ', $gv->get_fullname(), _savefields_to_str($savefields) );

    my $gpsym = $gv->savegp_from_gv($savefields);

    my $stash_symbol = $gv->get_stash_symbol();

    xpvgvsect()->comment("stash, magic, cur, len, xiv_u={.xivu_namehek=}, xnv_u={.xgv_stash=}");
    my $xpvg_ix = xpvgvsect()->sadd(
        "%s, {0}, 0, {.xpvlenu_len=0}, {.xivu_namehek=(HEK*)%s}, {.xgv_stash=%s}",
        $stash_symbol,    # STATIC_HV: The symbol for the HV stash. Which field is it??
        'NULL',           # the namehek (HEK*)
        $stash_symbol,    # The symbol for the HV stash. Which field is it??
    );
    my $xpvgv = sprintf( 'xpvgv_list[%d]', $xpvg_ix );

    {
        my $gv_refcnt = $gv->REFCNT;    #  + 1;    # TODO probably need more love for both refcnt (+1 ? extra flag immortal)
        my $gv_flags  = $gv->FLAGS;

        gvsect()->comment("XPVGV*  sv_any,  U32     sv_refcnt; U32     sv_flags; union   { gp* } sv_u # gp*");

        # replace our FAKE entry above
        gvsect()->update( $gv_ix, sprintf( "&%s, %u, 0x%x, {.svu_gp=(GP*)%s} /* %s */", $xpvgv, $gv_refcnt, $gv_flags, $gpsym, $gv->get_fullname() ) );
    }

    debug( gv => 'Save for %s = %s VS %s', $gv->get_fullname(), $gvsym, $gv->NAME );

    # TODO: split the fullname and plug all of them in known territory...
    # relies on template logic to preserve the hash structure...

    #my @namespace = split( '::', $gv->get_fullname() );

    # FIXME... need to plug it to init()->sadd( "%s = %s;", $sym, gv_fetchpv_string( $name, $gvadd, 'SVt_PV' ) );

    # STATIC_HV: Is there a way to do this up on the xpvgvsect()->sadd line ??
    if ( my $gvname = $gv->NAME ) {
        my $shared_he = save_shared_he($gvname);    # ,....

        if ( $shared_he ne 'NULL' ) {

            # plug the shared_he HEK to xpvgv: GvNAME_HEK($gvsym) =~(similar to) $xpvgv.xiv_u.xivu_namehek
            # This is the static version of
            #  init()->sadd( "GvNAME_HEK(%s) = (HEK*) &(( (SHARED_HE*) %s)->shared_he_hek);", $gvsym, $shared_he );
            # sharedhe_list[68] => shared_he_68
            my $sharedhe_ix;
            $sharedhe_ix = $1 if $shared_he =~ qr{\[([0-9]+)\]};
            die unless defined $sharedhe_ix;
            my $se = q{sHe} . $sharedhe_ix;

            # Note: the namehek here is the HEK and not the hek_key
            xpvgvsect->supdate_field( $xpvg_ix, GV_IX_NAMEHEK(), qq[ {.xivu_namehek=(HEK*) ((void*) &%s + 3*sizeof(void*)) } /* %s */ ], $se, $gvname );

            1;
        }
    }

    return $gvsym;
}

sub get_package {
    my $gv = shift;

    return '__ANON__' if ref( $gv->STASH ) eq 'B::SPECIAL';
    return $gv->STASH->NAME;
}

sub is_coresym {
    my $gv = shift;

    return $CORE_SYMS->{ $gv->get_fullname() } ? 1 : 0;
}

sub get_fullname {
    my $gv = shift;

    return $gv->get_package() . "::" . $gv->NAME();
}

my %saved_gps;

# hardcode the order of GV elements, so we can use macro instead of indexes
sub GP_IX_SV()     { 0 }
sub GP_IX_IO()     { 1 }
sub GP_IX_CV()     { 2 }
sub GP_IX_CVGEN () { 3 }
sub GP_IX_REFCNT() { 4 }
sub GP_IX_HV()     { 5 }
sub GP_IX_AV()     { 6 }
sub GP_IX_FORM()   { 7 }
sub GP_IX_GV()     { 8 }
sub GP_IX_LINE()   { 9 }
sub GP_IX_FLAGS()  { 10 }
sub GP_IX_HEK()    { 11 }

# FIXME todo and move later to B/GP.pm ?
sub savegp_from_gv {
    my ( $gv, $savefields ) = @_;

    # no GP to save there...
    return 'NULL' unless $gv->isGV_with_GP and $gv->GP;

    # B limitation GP is just a number not a reference so we cannot use objsym / savesym
    my $gp = $gv->GP;
    return $saved_gps{$gp} if defined $saved_gps{$gp};

    my $gvname   = $gv->NAME;
    my $fullname = $gv->get_fullname;

    # cannot do this as gp is just a number
    #my $gpsym = objsym($gp);
    #return $gpsym if defined $gpsym;

    # gp fields initializations
    # gp_cvgen: not set, no B api ( could be done in init section )
    my ( $gp_sv, $gp_io, $gp_cv, $gp_cvgen, $gp_hv, $gp_av, $gp_form, $gp_egv ) = ( '(SV*)&PL_sv_undef', 'NULL', 'NULL', 0, 'NULL', 'NULL', 'NULL', 'NULL' );

    # walksymtable creates an extra reference to the GV (#197): STATIC_HV: Confirm this is actually a true statement at this point.
    my $gp_refcount = $gv->GvREFCNT + 1;    # +1 for immortal: do not free our static GVs

    my $gp_line = $gv->LINE;                # we want to use GvLINE from B.xs
                                            # present only in perl 5.22.0 and higher. this flag seems unused ( saving 0 for now should be similar )

    if ( !$gv->is_empty ) {

        # S32 INT_MAX
        $gp_line = $gp_line > 2147483647 ? 4294967294 - $gp_line : $gp_line;
    }

    my $gp_flags = $gv->GPFLAGS;            # PERL_BITFIELD32 gp_flags:1; ~ unsigned gp_flags:1
    die("gp_flags seems used now ???") if $gp_flags;    # STATIC_HV: Does removing this die fix any tests?

    # gp_file_hek is only saved for non-stashes.
    my $gp_file_hek = q{NULL};
    if ( $fullname !~ /::$/ and $gv->FILE ne 'NULL' ) {    # and !$B::C::optimize_cop
        $gp_file_hek = save_shared_he( $gv->FILE );        # use FILE instead of FILEGV or we will save the B::GV stash
    }

    $gp_sv   = $gv->save_gv_sv($fullname)     if $savefields & Save_SV;
    $gp_av   = $gv->save_gv_av($fullname)     if $savefields & Save_AV;
    $gp_hv   = $gv->save_gv_hv($fullname)     if $savefields & Save_HV;
    $gp_cv   = $gv->save_gv_cv($fullname)     if $savefields & Save_CV;
    $gp_form = $gv->save_gv_format($fullname) if $savefields & Save_FORM;    # FIXME incomplete for now

    my $io_sv;
    ( $gp_io, $io_sv ) = $gv->save_gv_io($fullname) if $savefields & Save_IO;    # FIXME: get rid of sym
    $gp_sv = $io_sv if $io_sv;

    gpsect()->comment('SV, gp_io, CV, cvgen, gp_refcount, HV, AV, CV* form, GV, line, flags, HEK* file');

    my $gp_ix = gpsect()->sadd(
        "(SV*) %s, %s, (CV*) %s, %d, %u, %s, %s, (CV*) %s, %s, %u, %d, %s ",
        $gp_sv, $gp_io, $gp_cv, $gp_cvgen, $gp_refcount, $gp_hv, $gp_av, $gp_form, $gp_egv,
        $gp_line, $gp_flags, $gp_file_hek eq 'NULL' ? 'NULL' : qq{(HEK*) ((void*)&$gp_file_hek + sizeof(HE))}
    );
    $saved_gps{$gp} = sprintf( "&gp_list[%d]", $gp_ix );

    #print STDERR "===== GP:$gp_ix SV:$gp_sv, AV:$gp_av, HV:$gp_hv, CV:$gp_cv \n";
    # we can only use static values for sv, av, hv, cv, if they are coming from a static list

    my @postpone = (
        [ 'gp_sv', GP_IX_SV(), $gp_sv ],
        [ 'gp_av', GP_IX_AV(), $gp_av ],
        [ 'gp_hv', GP_IX_HV(), $gp_hv ],
        [ 'gp_cv', GP_IX_CV(), $gp_cv ],
    );

    # Find things that can't be statically compiled and defer them
    foreach my $check (@postpone) {
        my ( $field_name, $field_ix, $field_v ) = @$check;

        # if the value is null or using a static list, then it's fine
        next if $field_v =~ qr{null}i or $field_v =~ qr{list} or $field_v =~ qr{^s\\_\S+$};

        # replace the value by a null one
        debug( gv => q{Cannot use static value '%s' for gp_list[%d].%s => postpone to init}, $field_v, $gp_ix, $field_name );
        gpsect()->update_field( $gp_ix, $field_ix, 'NULL' );

        # postpone the setting to init section
        init_static_assignments()->sadd( q{gp_list[%d].%s = %s; /* deferred GV initialization for %s */}, $gp_ix, $field_name, $field_v, $fullname );
    }

    return $saved_gps{$gp};
}

# hardcode the order of GV elements, so we can use macro instead of indexes
sub GV_IX_STASH ()     { 0 }
sub GV_IX_MAGIC ()     { 1 }
sub GV_IX_CUR ()       { 2 }
sub GV_IX_LEN ()       { 3 }
sub GV_IX_NAMEHEK ()   { 4 }
sub GV_IX_XGV_STASH () { 5 }

sub get_stash_symbol {
    my ($gv) = @_;

    my @namespace = split( '::', $gv->get_fullname() );
    pop @namespace;
    my $stash_name = join "::", @namespace;
    $stash_name .= '::';

    no strict 'refs';
    return svref_2object( \%{$stash_name} )->save($stash_name);
}

sub save_egv {
    my ($gv) = @_;

    return if $gv->is_empty;

    my $egv = $gv->EGV;
    if ( ref($egv) ne 'B::SPECIAL' && ref( $egv->STASH ) ne 'B::SPECIAL' && $$gv != $$egv ) {
        return $egv->save;
    }

    return;
}

sub save_gv_sv {
    my ( $gv, $fullname ) = @_;

    my $gvsv = $gv->SV;
    return 'NULL' unless $$gvsv;

    #my $gvname  = $gv->NAME;
    # STATIC_HV: We think this special case needs to go away but don't have proof yet.
    # Reported in https://code.google.com/archive/p/perl-compiler/issues/91
    #if ( $gvname && $gvname eq 'VERSION' and $gvsv->FLAGS & SVf_ROK ) {
    #    die ("STATIC_HV: DEAD CODE??");
    #    my $package = $gv->get_package();
    #    debug( gv => "Strip overload from $package\::VERSION, fails to xs boot (issue 91)" );
    #    my $rv     = $gvsv->object_2svref();
    #    my $origsv = $$rv;
    #    no strict 'refs';
    #    ${$fullname} = "$origsv";
    #    return svref_2object( \${$fullname} )->save($fullname);
    #}

    return $gvsv->save($fullname);
}

sub save_gv_av {    # new function to be renamed later..
    my ( $gv, $fullname ) = @_;

    my $gvav = $gv->AV;
    return 'NULL' unless $gvav && $$gvav;

    # # rely on final replace to get the symbol name, it s fine
    # my $svsym = sprintf( "s\\_%x", $$gvsv );

    my $svsym = $gvav->save($fullname);
    if ( $fullname eq 'main::-' ) {    # fixme: can directly save these values
        init()->sadd( "AvFILLp(s\\_%x) = -1;", $$gvav );
        init()->sadd( "AvMAX(s\\_%x) = -1;",   $$gvav );
    }

    return $svsym;
}

sub save_gv_hv {                       # new function to be renamed later..
    my ( $gv, $fullname ) = @_;

    my $gvhv = $gv->HV;
    return 'NULL' unless $gvhv && $$gvhv;

    # Handle HV exceptions first...
    return 'NULL' if $fullname eq 'main::ENV';    # do not save %ENV

    debug( gv => "GV::save \%$fullname" );

    # skip static %Encode::Encoding since 5.20. GH #200. sv_upgrade cannot upgrade itself.
    # Let it be initialized by boot_Encode/Encode_XSEncodingm with exceptions.
    # GH #200 and t/testc.sh 75
    if ( $fullname eq 'Encode::Encoding' ) {
        debug( gv => "skip some %Encode::Encoding - XS initialized" );
        my %tmp_Encode_Encoding = %Encode::Encoding;
        %Encode::Encoding = ();    # but we need some non-XS encoding keys
        foreach my $k (qw(utf8 utf-8-strict Unicode Internal Guess)) {
            $Encode::Encoding{$k} = $tmp_Encode_Encoding{$k} if exists $tmp_Encode_Encoding{$k};
        }
        my $sym = $gvhv->save($fullname);

        #         init()->add("/* deferred some XS enc pointers for \%Encode::Encoding */");
        #         init()->sadd( "GvHV(%s) = s\\_%x;", $sym, $$gvhv );

        %Encode::Encoding = %tmp_Encode_Encoding;
        return $sym;
    }

    return $gvhv->save($fullname);
}

sub save_gv_cv {
    my ( $gv, $fullname ) = @_;

    debug( gv => ".... save_gv_cv $fullname" );

    my $package = $gv->get_package();
    my $gvcv    = $gv->CV;
    if ( !$$gvcv ) {

        # STATIC_HV: We're not expanding AUTOLOAD and missing stuff.
        #debug( gv => "Empty CV $fullname, AUTOLOAD and try again" );
        #no strict 'refs';

        # Fix test 31, catch unreferenced AUTOLOAD. The downside:
        # It stores the whole optree and all its children.
        # Similar with test 39: re::is_regexp
        #svref_2object( \*{"$package\::AUTOLOAD"} )->save if $package and exists ${"$package\::"}{AUTOLOAD};
        #svref_2object( \*{"$package\::CLONE"} )->save    if $package and exists ${"$package\::"}{CLONE};
        #$gvcv = $gv->CV;    # try again

        return 'NULL';    # ??? really
    }

    return 'NULL' unless ref($gvcv) eq 'B::CV';
    return 'NULL' if ref( $gvcv->GV ) eq 'B::SPECIAL' or ref( $gvcv->GV->EGV ) eq 'B::SPECIAL';

    my $gvname = $gv->NAME();
    my $gp     = $gv->GP;

    my $cvsym = 'NULL';

    # Can't locate object method "EGV" via package "B::SPECIAL" at /usr/local/cpanel/3rdparty/perl/520/lib/perl5/cpanel_lib/i386-linux-64int/B/C/OverLoad/B/GV.pm line 450.
    {
        my $package  = $gvcv->GV->EGV->STASH->NAME;    # is it the same than package earlier ??
        my $oname    = $gvcv->GV->EGV->NAME;
        my $origname = $package . "::" . $oname;

        if ( $gvcv->XSUB and $oname ne '__ANON__' and $fullname ne $origname ) {    #XSUB CONSTSUB alias

            # TODO
            #die "TODO";

            # {
            #     no strict 'refs';
            #     svref_2object( \&{"$package\::bootstrap"} )->save
            #       if $package and defined &{"$package\::bootstrap"};
            # }

            # # XXX issue 57: incomplete xs dependency detection
            # my %hack_xs_detect = (
            #     'Scalar::Util'  => 'List::Util',
            #     'Sub::Exporter' => 'Params::Util',
            # );
            # if ( my $dep = $hack_xs_detect{$package} ) {
            #     svref_2object( \&{"$dep\::bootstrap"} )->save;
            # }

            # # must save as a 'stub' so newXS() has a CV to populate
            # debug( gv => "save stub CvGV for $sym GP assignments $origname" );
            #init2()->sadd( "if ((sv = (SV*)%s))", get_cv_string( $origname, "GV_ADD" ) );
            #init2()->sadd( "    GvCV_set(%s, (CV*)SvREFCNT_inc_simple_NN(sv));", $sym );
        }
        elsif ($gp) {
            if ( $fullname eq 'Internals::V' ) {
                $gvcv = svref_2object( \&__ANON__::_V );
            }
            $cvsym = $gvcv->save($fullname);
        }
    }

    return $cvsym;
}

sub save_gv_format {
    my ( $gv, $fullname ) = @_;

    my $gvform = $gv->FORM;
    return 'NULL' unless $gvform && $$gvform;

    return $gvform->save($fullname);

    # init()->sadd( "GvFORM(%s) = (CV*)s\\_%x;", $sym, $$gvform );
    # init()->sadd( "SvREFCNT_inc(s\\_%x);", $$gvform );

    # return;
}

sub save_gv_io {
    my ( $gv, $fullname ) = @_;    # TODO: this one needs sym for now

    my $gvio = $gv->IO;
    return 'NULL' unless $$gvio;

    my $is_data;
    my $sv;
    if ( $fullname eq 'main::DATA' or ( $fullname =~ m/::DATA$/ ) ) {
        no strict 'refs';
        my $fh = *{$fullname}{IO};
        use strict 'refs';
        $is_data = 'is_DATA';

        # TODO: save_data only used for GV... can probably use it there
        $sv = $gvio->save_data( $fullname, <$fh> ) if $fh->opened;
    }

    return ( $gvio->save( $fullname, $is_data ), $sv );
}

sub get_savefields {
    my ( $gv, $fullname ) = @_;

    my $gvname = $gv->NAME;

    # default savefields
    my $all_fields = Save_HV | Save_AV | Save_SV | Save_CV | Save_FORM | Save_IO;
    my $savefields = 0;

    $gv->save_egv();    # STATIC_HV: where do save_egv actions get saved??
    my $gp = $gv->GP;

    # some non-alphabetic globs require some parts to be saved
    # ( ex. %!, but not $! )
    if ( ref($gv) eq 'B::STASHGV' and $gvname !~ /::$/ ) {

        # https://code.google.com/archive/p/perl-compiler/issues/79 - Only save stashes for stashes.
        $savefields = 0;
    }
    elsif ( $fullname eq 'main::!' ) {    #Errno
        $savefields = Save_HV | Save_SV | Save_CV;
    }
    elsif ( $fullname =~ /^DynaLoader::dl_(require_symbols|resolve_using|librefs)$/ ) {    # no need to assign any SV/AV/HV to them (172)
        $savefields = Save_CV | Save_FORM | Save_IO;
    }
    elsif ( $fullname eq 'main::ENV' or $fullname eq 'main::SIG' ) {
        $savefields = $all_fields ^ Save_HV;
    }
    elsif ( $fullname eq 'main::ARGV' ) {
        $savefields = $all_fields ^ Save_AV;
    }
    elsif ( $fullname =~ /^main::STD(IN|OUT|ERR)$/ ) {
        $savefields = Save_FORM | Save_IO;
    }
    elsif ( $fullname eq 'main::_' ) {
        $savefields = Save_AV | Save_SV;
    }
    elsif ( $fullname eq 'main::@' ) {
        $savefields = Save_SV;
    }
    elsif ( $gvname =~ /^[^A-Za-z]$/ ) {
        $savefields = Save_SV;
    }
    else {
        $savefields = $all_fields;
    }

    # avoid overly dynamic POSIX redefinition warnings: GH #335, #345
    if ( $fullname =~ m/^POSIX::M/ or $fullname eq 'attributes::bootstrap' ) {
        $savefields &= ~Save_CV;
    }

    my $is_gvgp    = $gv->isGV_with_GP;
    my $is_coresym = $gv->is_coresym();
    if ( !$is_gvgp or $is_coresym ) {
        $savefields &= ~Save_FORM;
        $savefields &= ~Save_IO;
    }

    $savefields |= Save_FILE if ( $is_gvgp and !$is_coresym );

    return $savefields;
}

sub savecv {
    my $gv      = shift;
    my $package = $gv->STASH->NAME;
    my $name    = $gv->NAME;
    my $cv      = $gv->CV;
    my $sv      = $gv->SV;
    my $av      = $gv->AV;
    my $hv      = $gv->HV;

    # We Should NEVER compile B::C packages so if we get here, it's a bug.
    # TODO: Currently breaks xtestc/0350.t and xtestc/0371.t if we make this a die.
    return if $package eq 'B::C';

    my $fullname = $package . "::" . $name;
    debug( gv => "Checking GV *%s 0x%x\n", cstring($fullname), ref $gv ? $$gv : 0 ) if verbose();

    # We may be looking at this package just because it is a branch in the
    # symbol table which is on the path to a package which we need to save
    # e.g. this is 'Getopt' and we need to save 'Getopt::Long'
    #
    return if ( $package ne 'main' and !is_package_used($package) );
    return if ( $package eq 'main'
        and $name =~ /^([^\w].*|_\<.*|INC|ARGV|SIG|ENV|BEGIN|main::|!)$/ );

    debug( gv => "GV::savecv - Used GV \*$fullname 0x%x", ref $gv ? $$gv : 0 );
    debug( gv => "... called from %s", 'B::C::Save'->can('stack_flat')->() );
    return unless ( $$cv || $$av || $$sv || $$hv || $gv->IO || $gv->FORM );
    if ( $$cv and $name eq 'bootstrap' and $cv->XSUB ) {

        #return $cv->save($fullname);
        debug( gv => "Skip XS \&$fullname 0x%x", ref $cv ? $$cv : 0 );
        return;
    }
    if (
        $$cv and B::C::in_static_core( $package, $name ) and ref($cv) eq 'B::CV'    # 5.8,4 issue32
        and $cv->XSUB
      ) {
        debug( gv => "Skip internal XS $fullname" );
        return;
    }

    # load utf8 and bytes on demand.
    if ( my $newgv = force_heavy( $package, $fullname ) ) {
        $gv = $newgv;
    }

    # XXX fails and should not be needed. The B::C part should be skipped 9 lines above, but be defensive
    return if $fullname eq 'B::walksymtable' or $fullname eq 'B::C::walksymtable';

    $B::C::dumped_package{$package} = 1 if !exists $B::C::dumped_package{$package} and $package !~ /::$/;
    debug( gv => "Saving GV \*$fullname 0x%x", ref $gv ? $$gv : 0 );
    $gv->save($fullname);
}

1;
