package B::METHOP;

use strict;

use B qw/cstring SVf_FAKE/;
use B::C::File qw( methopsect init init2 );
use B::C::Config;
use B::C::Helpers::Symtable qw/savesym/;
use B::C::Helpers qw/do_labels/;
use B::C::Save qw/savestashpv/;

sub do_save {
    my ( $op, $level ) = @_;

    $level ||= 0;

    methopsect()->comment_common("first, rclass");

    my $union = $op->name eq 'method' ? "{.op_first=(OP*)%s}" : "{.op_meth_sv=(SV*)%s}";
    my $s = "%s, $union, (SV*)%s";    # rclass

    my $ix     = methopsect()->index + 1;
    my $rclass = $op->rclass->save("op_rclass_sv");
    if ( $rclass =~ /^&sv_list/ ) {
        init()->sadd( "SvREFCNT_inc_simple_NN(%s); /* methop_list[%d].op_rclass_sv */", $rclass, $ix );

        # Put this simple PV into the PL_stashcache, it has no STASH,
        # and initialize the method cache.
        # TODO: backref magic for next, init the next::method cache
        my $name = $op->rclass()->PV();
        my $sym  = savestashpv($name);
        init2()->sadd( "Perl_mro_method_changed_in(%s);  /* %s */", $sym, $name );
    }
    my $first = $op->name eq 'method' ? $op->first->save : $op->meth_sv->save;
    if ( $first =~ /^&sv_list/ ) {
        init()->sadd( "SvREFCNT_inc_simple_NN(%s); /* methop_list[%d].op_meth_sv */", $first, $ix );
    }

    methopsect()->sadd( $s, $op->_save_common, $first, $rclass );
    methopsect()->debug( $op->name, $op->flagspv ) if debug('flags');
    my $sym = savesym( $op, "(OP*)&methop_list[$ix]" );    # save it before do_labels
    if ( $op->name eq 'method' ) {
        do_labels( $op, $level + 1, 'first', 'rclass' );
    }
    else {
        do_labels( $op, $level + 1, 'meth_sv', 'rclass' );
    }

    return $sym;
}

1;
