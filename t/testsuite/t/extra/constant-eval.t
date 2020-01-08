#!perl

# insipired from CPANEL-31105

use strict;
use warnings;

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
}

plan tests => 2;

my %storage;

sub get_string {
  my ( $str ) = @_;
  return ":$str:";
}

use constant SAMPLE_CONSTANT => defined eval { $storage{cache} = get_string('abcd') };

is SAMPLE_CONSTANT, 1, "constant is set to true";
is $storage{cache}, ':abcd:', "cache is set at compile time";
