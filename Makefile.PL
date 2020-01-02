#!perl -w

use 5.022;

use strict;
use warnings;

use ExtUtils::MakeMaker;
use Config ();
use Data::Dumper;
use File::Spec;
use Carp;

$^O eq 'MSWin32' and die "Windows (threads) is unsupported.";
my $devnull = '/dev/null';

# We can't have a symlink in t/testsuite/t or we get a circular find from File::Find
# https://github.com/Perl-Toolchain-Gang/ExtUtils-Manifest/issues/5
if ( -e '.gdbinit' ) { # not shipped by the RPM - this do not belong there
    system("cp .gdbinit t/testsuite/t/.gdbinit") and die;
}

my $core = grep { $_ eq 'PERL_CORE=1' } @ARGV;
mkdir "lib/B/C" unless -d "lib/B/C";
unless ( -e 'lib/B/C/Flags.pm' ) {
    open PH, ">", "lib/B/C/Flags.pm";
    print PH "package B::C::Flags;\n\n";
    print PH "\n1;\n";
    close PH;
    chmod 0644, "lib/B/C/Flags.pm";
}

my ( $extra_cflags, $extra_libs ) = ( "", "" );

{
    my ($e_c) = grep { /-extra-cflags[= ](.+)/ } @ARGV;
    my ($e_l) = grep { /-extra-libs[= ](.+)/ } @ARGV;
    $extra_cflags .= " $e_c" if $e_c;
    $extra_libs   .= " $e_l" if $e_l;
}

sub write_b_c_flags {
    my $version = shift;
    mkdir "lib/B/C" unless -d "lib/B/C";

    open PH, ">", "lib/B/C/Flags.pm";
    print PH "# written by B::C Makefile.PL. \$extra_{cflags,libs} need a leading space if used.\n";
    print PH "package B::C::Flags;\n\n";
    print PH "our \$VERSION = '$version';\n";
    my $REV = '';

    if ( my $sha1 = `git rev-list HEAD -1 --abbrev=7 --abbrev-commit 2>$devnull` ) {
        chomp $sha1;

        # POSIX systems only with wc
        if ( my $num = `git rev-list --abbrev-commit HEAD | wc -l 2>$devnull` ) {
            chomp $num;
            $REV .= "-$num";
        }
        $REV .= '-g' . $sha1;
        print PH "\$B::C::REVISION = '$REV';\n\n";
    }
    print PH "# -fav-init optimization\n";

    print PH "# use extra compiler flags, after ccopts, resp. ldopts\n";
    print PH "our \$extra_cflags = \"$extra_cflags\";\n";
    print PH "our \$extra_libs = \"$extra_libs\";\n";

    $Data::Dumper::Terse    = 1;
    $Data::Dumper::Sortkeys = 1;
    my %cfg;

    # protection to check that C99 is always enabled
    $Config::Config{d_c99_variadic_macros} or die "This version of B::C does not support compilers without C99";
    $Config::Config{useithreads}     and die "This version of B::C does not support ithreads";
    $Config::Config{usemultiplicity} and die "This version of B::C does not support multiplicity";
    $Config::Config{i_dlfcn} && $Config::Config{d_dlopen} or die "was using more logic if HAVE_DLFCN_DLOPEN is not true, but seems to always be the case for us";

    {    # signals
        my @signames = split /\s+/, $Config::Config{sig_name};
        my @signums  = split /\s+/, $Config::Config{sig_num};

        die unless scalar @signums == scalar @signames;
        die unless scalar @signums;

        my %signals;
        while (@signames) {
            $signals{ $signames[0] } = $signums[0];
            shift @signames;
            shift @signums;
        }

        $cfg{'SIGNAL_NAMES'} = \%signals;
    }

    {
        use POSIX ();

        foreach my $k ( qw{LONG_MIN LONG_MAX DBL_MIN DBL_MAX } ) {
            if ( my $f = 'POSIX'->can($k) ) {
                $cfg{$k} = $f->();
            }
        }
    }

    # Ensure to add all used Config keys in B::C here, otherwise they will be silently empty!
    # easier hash key/value slices only came with 5.22
    for my $s (
        qw(archname cc ccflags d_dlopen d_isinf d_isnan d_longdbl dlext i_dlfcn
        ivdformat ivsize nvgformat ptrsize sig_size static_ext usecperl
        usedl uselongdouble usemymalloc uvuformat)
      ) {
        $cfg{$s} = $Config::Config{$s};
    }
    my $conf = Dumper \%cfg;
    $conf =~ s/^\s*{/(/;
    $conf =~ s/}\s*$/);/;
    print PH "our \%Config = $conf\n";
    print PH "\n";

    print PH "# make it a restricted hash\n";

    #print PH "Internals::SvREADONLY( \%Config, 1 );\n\n";

    print PH "1;\n";
    close PH;
    chmod 0644, "lib/B/C/Flags.pm";
}

WriteMakefile(
    NAME         => "B::C",
    VERSION_FROM => "lib/B/C.pm",
    PL_FILES     => { 'script/perlcc.PL' => 'script/perlcc' },
    EXE_FILES    => [qw(script/perlcc script/cc_harness)],
    PREREQ_PM    => {
        'Opcodes'         => '0',       # optional
        'IPC::Run'        => '0',       # optional
        'B::Flags'        => '0.15',    # optional
        'Time::HiRes'     => '0',       # optional
        'Encode'          => 2.60,      # 2.58 is broken so let's be sure we're higher than this.
        'ExtUtils::Embed' => '1.25'     # mandatory (missing on redhat)
                                        #'B'        => '1.0901' # required but in CORE
    },
    'TEST_REQUIRES' => {
        'Test2::Tools::Explain'     => '0',
        'Test2::Plugin::NoWarnings' => '0',
        'Test::Trap'                => '0',
        'Test::Deep'                => '0',
    },
    'AUTHOR'   => 'Malcolm Beattie (retired), ' . 'Reini Urban <perl-compiler@googlegroups.com>',
    'ABSTRACT' => 'Perl compiler',
    'LICENSE'  => 'perl',
    (
        ( $ExtUtils::MakeMaker::VERSION gt '6.31' and $ExtUtils::MakeMaker::VERSION lt '6.46' )
        ? (
            'EXTRA_META' => "recommends:\n" . "    B::Flags:  0.15\n" . "    B::Debug:  1.16\n" . "    Opcodes:   0.10\n" . "    IPC::Run:  0\n",
          )
        : ()
    ),
    (
        $ExtUtils::MakeMaker::VERSION gt '6.46'
        ? (
            'META_MERGE' => {
                "recommends" => {
                    'B::Flags' => '0.15',
                    "B::Debug" => '1.16',
                    "Opcodes"  => '0.10',
                    "IPC::Run" => 0,
                },
                resources => {
                    license     => 'http://dev.perl.org/licenses/',
                    homepage    => 'http://www.perl-compiler.org',
                    bugtracker  => 'http://code.google.com/p/perl-compiler/issues',
                    repository  => 'http://perl-compiler.googlecode.com/',
                    MailingList => 'http://groups.google.com/group/perl-compiler',
                },
            }
          )
        : ()
    ),
    SIGN  => 0,
    clean => { FILES => "*.core *.stackdump a.out a.exe *.cee *.c *.asm *.dbg *.plc *.obj " . "*.concise *~ dll.base dll.exp mod.pl pcc* *.bak *.a " . "t/CORE/*/*.bin t/CORE/*/*.c Io_argv* t/CORE/*/*.subtest.*.t t/CORE/tmp* tmp*" },
);

sub headerpath {
    if ($core) {
        return File::Spec->catdir(
            File::Spec->updir,
            File::Spec->updir
        );
    }
    else {
        return File::Spec->catdir( $Config::Config{archlibexp}, "CORE" );
    }
}

package MY;

# Ignore certain files
sub libscan {

    # Ignore temp testing files
    return 0 if $_[1] =~ /^(\.git|\.svn|jit.*|i386|.*\.orig|c?ccode.*|regen_lib\.pl)$/;
    return 0 if $_[1] =~ /\.svn|~/;                                                       # needed for msys perl5.6
                                                                                          # On windows the C compiler would work if DynaLoader.lib would be provided.
                                                                                          # return 0 if $^O eq 'MSWin32' and !-d ".git" and $_[1] =~ /C\.pm|C\.xs|Stackobj\.pm/;
    return $_[1];
}

# Fix ActivePerl for MSVC6
# The linker for cl 12.0.8804 has no -opt:ref,icf, which is MSVC8 linker syntax.
sub const_config {
    my $s = shift->SUPER::const_config(@_);
    if ( $Config::Config{ccversion} eq '12.0.8804' and $Config::Config{cc} eq 'cl' ) {
        $s =~ s/ -opt:ref,icf//gm;
    }
    $s;
}

sub post_constants {
    my $mm = shift;
    main::write_b_c_flags( $mm->{VERSION} );
    my $libs = "\nLIBS = $Config::Config{libs}";
    $libs .= $extra_libs if $extra_libs;

    #XXX PERL_MALLOC_DEF = -DPERL_EXTMALLOC_DEF -Dmalloc=Perl_malloc -Dfree=Perl_mfree -Drealloc=Perl_realloc -Dcalloc=Perl_calloc
    return "$libs\n";
}

sub ccflags {
    my $ccflags = shift->SUPER::ccflags(@_);
    $ccflags .= $extra_cflags if $extra_cflags;
    return $ccflags if !-d ".git" or $ENV{NO_AUTHOR};

    # Recommended by http://www.network-theory.co.uk/docs/gccintro/gccintro_32.html
    # -ansi -pedantic -Wall -W -Wconversion -Wshadow -Wcast-qual -Wwrite-strings (-W => -WExtra)
    $ccflags .= " -ansi -pedantic -Wall -Wextra -Wconversion -Wshadow -Wcast-qual -Wwrite-strings"
      if $Config::Config{cc} =~ /gcc/;
}

sub depend {
    my $headerpath = main::headerpath();
    my @headers    = map { File::Spec->catfile( $headerpath, $_ ) } qw(op.h cop.h sv.h);
    my $result     = "
TAGS :
	etags --language=perl lib/B/*.pm
";

    $result .= "\ntest :: subdirs-test\n\n";

    if ( $Config::Config{make} eq 'mingw32-make' ) {    # mingw32 make different to msys make
        $result .= "\n.PHONY : \$(CONFIGDEP)\n\n";
    }
    $result;
}

sub test {
    shift->SUPER::test(@_) . qq(
testmod :: pure_all
	PERL_DL_NONLAZY=1 \$(FULLPERLRUN) -Iblib/arch -Iblib/lib t/modules.t
testmodall :: pure_all
	PERL_DL_NONLAZY=1 \$(FULLPERLRUN) -Iblib/arch -Iblib/lib t/modules.t -no-subset -no-date t/top100
testc :: pure_all
	PERL_DL_NONLAZY=1 \$(FULLPERLRUN) -Iblib/arch -Iblib/lib t/c.t
	PERL_DL_NONLAZY=1 \$(FULLPERLRUN) -Iblib/arch -Iblib/lib t/c_o3.t
testcc :: pure_all
	PERL_DL_NONLAZY=1 \$(FULLPERLRUN) -Iblib/arch -Iblib/lib t/cc.t
testbc :: pure_all
testfast :: pure_all
	NO_AUTHOR=1 \$(FULLPERLRUN) -S prove -b -j10 -f
testfast-log :: pure_all
	NO_AUTHOR=1 \$(FULLPERLRUN) -S prove -b -j10 -f  | tee log.test-$]-`git describe --tags`
testcritical :: pure_all
	t/critical.sh
teststatus :: pure_all
	./status_upd -fqd
testrelease :: pure_all
	\$(ECHO) run t/release-testing.sh and perlall testvm --all
testcore :: pure_all
	-/bin/rm -f .prove
	-\$(FULLPERLRUN) -S prove -b --state=save -j4 -f t/$^V/C-COMPILED/*/*.t
	\$(FULLPERLRUN) -S prove -v -b --state=failed
\%.t :: pure_all
	\$(FULLPERLRUN) -S prove -b -v t/$^V/C-COMPILED/\$@
)
}

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:
