package B::UNOP_AUX;

use strict;

use B qw/svref_2object/;
use B::C::Debug qw/debug/;
use B::C::File qw/unopauxsect init free meta_unopaux_item/;
use B::C::Helpers qw/is_constant/;
use B::C::Save qw/savecowpv/;

sub _clear_stack {

    #'B::C::Save'->can('stack_flat')->();
    return join '', ( 1 .. 42 );    # large enough to do stuff & clear
}

# hardcoded would require a check to detect this is going to the correct position
sub OP_AUX_IX { 15 }

sub do_save {
    my ($op) = @_;

    _clear_stack();                 # avoid a weird B (or B::C) issue when calling aux_list_thr

    unopauxsect()->comment_for_op("first, aux");
    my ( $ix, $sym ) = unopauxsect()->reserve( $op, "OP*" );
    unopauxsect()->debug( $op->name, $op );

    unopauxsect()->supdate(
        $ix, "%s, %s, %s", $op->save_baseop, $op->first->save,
        'AUX-TO-BE-FILLED'
    );

    my @aux_list;
    if ( $op->name eq 'argelem' ) {

        # argelem has no aux_list, it's stealing the pointer to save one integer
        # from pp.c for PP(pp_argelem)
        #      IV ix = PTR2IV(cUNOP_AUXo->op_aux);

        my $op_aux = $op->aux_ptr2iv // 0;
        unopauxsect()->update_field( $ix, OP_AUX_IX(), $op_aux );

        return $sym;
    }
    elsif ( $op->name eq 'argcheck' ) {
        @aux_list = $op->aux_list_thr;

        #print STDERR join( ' ', '# ARGCHECK', @aux_list, "\n" );
    }
    elsif ( $op->name eq 'multideref' ) {
        @aux_list = $op->aux_list_thr;
    }
    elsif ( $op->name eq 'multiconcat' ) {
        my $list = aux_list_for_multiconcat($op);
        @aux_list = @$list;
    }
    else {    # ithread
              # Usage: B::UNOP_AUX::aux_list(o, cv)
        die "ithreads";
        @aux_list = $op->aux_list;    # GH#283, GH#341
    }

    #### Saving the regular AUX LIST

    my $auxlen = scalar @aux_list;
    my @to_be_filled = map { 0 } 1 .. $auxlen;    #

    my $list_size         = $auxlen + 1;
    my $unopaux_item_sect = meta_unopaux_item($list_size);

    $unopaux_item_sect->comment(q{length prefix, UNOP_AUX_item * $auxlen });
    my $uaux_item_ix = $unopaux_item_sect->add( join( ', ', qq[{.uv=$auxlen}], @to_be_filled ) );

    my $symname = sprintf(
        'meta_unopaux_item%d_list[%d]', $list_size,
        $uaux_item_ix
    );
    my $op_aux = sprintf( '&%s.aaab', $symname );

    unopauxsect()->update_field( $ix, OP_AUX_IX(), $op_aux );

    # This cannot be a section, as the number of elements is variable
    my $i            = 1;         # maybe rename to field_ix
    my $struct_field = q{aaaa};

    my $action = 0;
    foreach my $item (@aux_list) {
        my $field;

        $struct_field++;
        my $symat = "${symname}.$struct_field";

        unless ( ref $item ) {

            # symbolize MDEREF action
            #my $cmt = $op->get_action_name($item);
            $action = $item;

            if ( $item =~ qr{^-?[0-9]+$} && $item < 0 ) {    # -1 should be the only negative known value at this point
                $field = sprintf( '{.iv=%d}', $item );
            }
            elsif ( $item =~ qr{COWPV} ) {
                $field = sprintf( '{.pv= (char*) %s}', $item );
            }
            else {
                #debug( hv => $op->name . " action $action $cmt" );
                $field = sprintf( '{.uv=0x%x}', $item );     #  \t/* %s: %u */ , $cmt, $item
            }

        }
        else {
            # const and sv already at compile-time, gv deferred to init-time.
            # testcase: $a[-1] -1 as B::IV not as -1
            # hmm, if const ensure that candidate CONSTs have been HEKified. (pp_multideref assertion)
            # || SvTYPE(keysv) >= SVt_PVMG
            # || !SvOK(keysv)
            # || SvROK(keysv)
            # || SvIsCOW_shared_hash(keysv));
            my $constkey = ( $action & 0x30 ) == 0x10 ? 1 : 0;
            my $itemsym = $item->save( "$symat" . ( $constkey ? " const" : "" ) );
            if ( is_constant($itemsym) ) {
                if ( ref $item eq 'B::IV' ) {
                    my $iv = $item->IVX;
                    $field = "{.iv=$iv}";
                }
                elsif ( ref $item eq 'B::UV' ) {    # also for PAD_OFFSET
                    my $uv = $item->UVX;
                    $field = "{.uv=$uv}";
                }
                else {                              # SV
                    $field = "{.sv=$itemsym}";
                }
            }
            else {
                if ( $itemsym =~ qr{^PL_} ) {
                    $field = "{.sv=Nullsv}";        #  \t/* $itemsym */
                    init()->add("$symat.sv = (SV*)$itemsym;");
                    init()->add("SvREFCNT_inc_NN((SV*)$itemsym);");
                }
                else {
                    ## gv or other late inits
                    $field = "{.sv = (SV*) $itemsym}";
                }
            }
        }

        $unopaux_item_sect->update_field( $uaux_item_ix, $i, q[ ] . $field );
        $i++;
    }

    free()->add("    ($sym)->op_type = OP_NULL;");

    return $sym;
}

sub get_action_name {
    my ( $op, $item ) = @_;

    my $cmt = 'action';
    if ( $op->name eq 'multideref' ) {
        my $act = $item & 0xf;    # MDEREF_ACTION_MASK
        $cmt = 'AV_pop_rv2av_aelem'          if $act == 1;
        $cmt = 'AV_gvsv_vivify_rv2av_aelem'  if $act == 2;
        $cmt = 'AV_padsv_vivify_rv2av_aelem' if $act == 3;
        $cmt = 'AV_vivify_rv2av_aelem'       if $act == 4;
        $cmt = 'AV_padav_aelem'              if $act == 5;
        $cmt = 'AV_gvav_aelem'               if $act == 6;
        $cmt = 'HV_pop_rv2hv_helem'          if $act == 8;
        $cmt = 'HV_gvsv_vivify_rv2hv_helem'  if $act == 9;
        $cmt = 'HV_padsv_vivify_rv2hv_helem' if $act == 10;
        $cmt = 'HV_vivify_rv2hv_helem'       if $act == 11;
        $cmt = 'HV_padhv_helem'              if $act == 12;
        $cmt = 'HV_gvhv_helem'               if $act == 13;
        my $idx = $item & 0x30;    # MDEREF_INDEX_MASK
        $cmt .= ''             if $idx == 0x0;
        $cmt .= ' INDEX_const' if $idx == 0x10;
        $cmt .= ' INDEX_padsv' if $idx == 0x20;
        $cmt .= ' INDEX_gvsv'  if $idx == 0x30;
    }
    elsif ( $op->name eq 'signature' ) {    # cperl only for now
        my $act = $item & 0xf;              # SIGNATURE_ACTION_MASK
        $cmt = 'reload'            if $act == 0;
        $cmt = 'end'               if $act == 1;
        $cmt = 'padintro'          if $act == 2;
        $cmt = 'arg'               if $act == 3;
        $cmt = 'arg_default_none'  if $act == 4;
        $cmt = 'arg_default_undef' if $act == 5;
        $cmt = 'arg_default_0'     if $act == 6;
        $cmt = 'arg_default_1'     if $act == 7;
        $cmt = 'arg_default_iv'    if $act == 8;
        $cmt = 'arg_default_const' if $act == 9;
        $cmt = 'arg_default_padsv' if $act == 10;
        $cmt = 'arg_default_gvsv'  if $act == 11;
        $cmt = 'arg_default_op'    if $act == 12;
        $cmt = 'array'             if $act == 13;
        $cmt = 'hash'              if $act == 14;
        my $idx = $item & 0x3F;    # SIGNATURE_MASK
        $cmt .= ''           if $idx == 0x0;
        $cmt .= ' flag skip' if $idx == 0x10;
        $cmt .= ' flag ref'  if $idx == 0x20;
    }
    elsif ( $op->name eq 'multiconcat' ) {
        $cmt .= ' multiconcat';
    }
    else {
        die "Unknown UNOP_AUX op {$op->name}";
    }

    return $cmt;

}

sub MULTICONCAT_IX_NARGS     { 0 }    # number of arguments
sub MULTICONCAT_IX_PLAIN_PV  { 1 }    # non-utf8 constant string
sub MULTICONCAT_IX_PLAIN_LEN { 2 }    # non-utf8 constant string length
sub MULTICONCAT_IX_UTF8_PV   { 3 }    # utf8 constant string
sub MULTICONCAT_IX_UTF8_LEN  { 4 }    # utf8 constant string length

#sub MULTICONCAT_IX_LENGTHS   { 5 }    # first of nargs+1 const segment lens - B::C does not need this value

sub MULTICONCAT_HEADER_SIZE { 5 }     # The number of fields of a multiconcat header

=pod

    with multiconcat the string:

        "a=$a b=$bX"

    will become
        [
            2,            # nargs
            'c= d=X',     # string as a single pv
            2, 3, 1       # length of segments
        ]

=cut

sub aux_list_for_multiconcat {
    my ($op) = @_;

    # note that the B API aux_list method needs a useless CV
    # we are using our own custom version of aux_list for multiconcat
    # (required to read content correctly when the string is utf8)
    #   - it returns the plain PV & the utf8 PV (the original B function only return one PV)
    #   - it also returns the raw contents of the aux slots (@segments part) without converting it
    my ( $nargs, $pv_as_sv_plain, $pv_as_sv_utf8, @segments ) = $op->aux_list_thr();    # is this complete

    # initialize the multiconcat header: all values to 0
    my @header = (0) x MULTICONCAT_HEADER_SIZE();

    $header[ MULTICONCAT_IX_NARGS() ] = $nargs;                                         # ix=0

    if ( defined $pv_as_sv_plain ) {
        my ( $savesym, $cur, $len, $utf8 ) = savecowpv($pv_as_sv_plain);
        $header[ MULTICONCAT_IX_PLAIN_PV() ]  = $savesym;                               # ix=1
        $header[ MULTICONCAT_IX_PLAIN_LEN() ] = $cur;                                   # ix=2
    }

    if ( defined $pv_as_sv_utf8 ) {
        my ( $savesym, $cur, $len, $utf8 ) = savecowpv($pv_as_sv_utf8);
        $header[ MULTICONCAT_IX_UTF8_PV() ]  = $savesym;                                # ix=3
        $header[ MULTICONCAT_IX_UTF8_LEN() ] = $cur;                                    # ix=4
    }

    return [ @header, @segments ];
}

1;
