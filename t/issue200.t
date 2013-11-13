#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=200
# utf8 hash keys
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 6;
my $i=0;
sub test3 {
  my $name = shift;
  my $script = shift;
  my $cmt = join('',@_);
  my $todo = "";
  #$todo = 'TODO ' if $] > 5.015;
  plctestok($i*3+1, $name, $script, $cmt);
  ctestok($i*3+2, "C", $name, $script, "C $cmt");
  ctestok($i*3+3, "CC", $name, $script, $todo."CC $cmt");
  $i++;
}

test3('ccode200i_r', '%u=("\x{123}"=>"fo"); print "ok" if $u{"\x{123}"} eq "fo"', 'run-time utf8 hek');
test3('ccode200i_c', 'BEGIN{%u=("\x{123}"=>"fo")} print "ok" if $u{"\x{123}"} eq "fo"', 'TODO compile-time utf8 hek');
