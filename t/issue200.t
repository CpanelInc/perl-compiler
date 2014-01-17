#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=200
# utf8 hash keys
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 6;
use Config;

my $i=0;
sub test3 {
  my $name = shift;
  my $script = shift;
  my $cmt = join('',@_);
  my $todo = "";
  $todo = 'TODO BC ' if $name eq 'ccode200i_c' or ($] >= 5.018 and $] < 5.019005 and $Config{useithreads});
  plctestok($i*3+1, $name, $script, $todo.$cmt);
  ctestok($i*3+2, "C", $name, $script, "C $cmt");
  ctestok($i*3+3, "CC", $name, $script, "CC $cmt");
  $i++;
}

test3('ccode200i_r', '%u=("\x{123}"=>"fo"); print "ok" if $u{"\x{123}"} eq "fo"', 'run-time utf8 hek');
test3('ccode200i_c', 'BEGIN{%u=("\x{123}"=>"fo")} print "ok" if $u{"\x{123}"} eq "fo"', 'compile-time utf8 hek');
