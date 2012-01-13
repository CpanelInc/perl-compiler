#! /usr/bin/env perl
# brian d foy: "Compiled perlpod should be faster then uncompiled"
use Test::More;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}

use Config;
use File::Spec;
use Time::HiRes qw(gettimeofday tv_interval);

sub faster { ($_[1] - $_[0]) < 0.01 }

my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $perldoc = File::Spec->catfile($Config{installbin}, 'perldoc');
my $perlcc = $] < 5.008
  ? "$X -Iblib/arch -Iblib/lib blib/script/perlcc"
  : "$X -Mblib blib/script/perlcc";
$perlcc .= " -Wb=-fno-fold,-fno-warnings,-fno-stash -UB";
my $exe = $Config{exe_ext};
my $perldocexe = "perldoc$exe";
# XXX bother File::Which?
die "1..1 # $perldoc not found\n" unless -f $perldoc;
plan tests => 7;

my $compile = "$perlcc -o perldoc$exe $perldoc";
diag $compile;
my $res = `$compile`;
ok(-s $perldocexe, "$perldocexe compiled"); #1

diag "see if $perldoc -T works";
my $T_opt = "-T -f wait";
my $ori;
my $PAGER = '';
my $t0 = [gettimeofday];
if ($^O eq 'MSWin32') {
  $T_opt = "-t -f wait";
  $PAGER = "PERLDOC_PAGER=type ";
  $ori = `$PAGER$X -S $perldoc $T_opt`;
} else {
  $ori = `$X -S $perldoc $T_opt 2>&1`;
}
my $t1 = tv_interval( $t0, [gettimeofday]);
if ($ori =~ /Unknown option/) {
  $T_opt = "-t -f wait";
  $PAGER = "PERLDOC_PAGER=cat " if $^O ne 'MSWin32';
  diag "No, use $PAGER instead";
  $t0 = [gettimeofday];
  $ori = `$PAGER$X -S $perldoc $T_opt`;
  $t1 = tv_interval( $t0, [gettimeofday]);
} else {
  diag "it does";
}
$t0 = [gettimeofday];
my $cc = `$PAGER ./perldoc $T_opt`;
my $t2 = tv_interval( $t0, [gettimeofday]);
TODO: {
  # old perldoc 3.14_04-3.15_04: Can't locate object method "can" via package "Pod::Perldoc" at /usr/local/lib/perl5/5.14.1/Pod/Perldoc/GetOptsOO.pm line 34
  # dev perldoc 3.15_13: Can't locate object method "_is_mandoc" via package "Pod::Perldoc::ToMan"
  local $TODO = "compiled does not print yet" if $] >= 5.010;
  is($cc, $ori, "same result"); #2
}

SKIP: {
  skip "cannot compare times", 1 if $cc ne $ori;
  ok(faster($t2,$t1), "compiled faster than uncompiled: $t2 < $t1"); #3
}

$compile = "$perlcc -O3 -o perldoc_O3$exe $perldoc";
diag $compile;
$res = `$compile`;
ok(-s "perldoc_O3$exe", "perldoc compiled"); #4

$t0 = [gettimeofday];
$cc = $^O eq 'MSWin32' ? `$PAGER perldoc$exe $T_opt` : `$PAGER ./perldoc $T_opt`;
my $t3 = tv_interval( $t0, [gettimeofday]);
TODO: {
  local $TODO = "compiled does not print yet" if $] >= 5.010;
  is($cc, $ori, "same result"); #5
}

SKIP: {
  skip "cannot compare times", 2 if $cc ne $ori;
  ok(faster($t3,$t2), "compiled -O3 not slower than -O0: $t3 <= $t2"); #6
  ok(faster($t3,$t1),  "compiled -O3 faster than uncompiled: $t3 < $t1"); #7
}

END {
  unlink $perldocexe if -e $perldocexe;
  unlink "perldoc_O3$exe" if -e "perldoc_O3$exe";
}
