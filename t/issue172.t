#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=172
# miss to mark empty overloaded package
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 2;
my $script = <<'EOF';
package Foo;
use overload q("") => sub { "Foo" };
package main;
my $foo = bless {}, "Foo";
print "ok\n" if "$foo" eq "Foo";
print "$foo\n";
EOF

# fixed with 1.42_67
use B::C ();
my $todo = ($B::C::VERSION ge '1.42_67' and $] < 5.018) ? "" : "TODO ";
ctest(1, "ok\nFoo",'C','ccode208i',$script,$todo.'#172 miss to mark empty overloaded package');
ctest(2, "ok\nFoo",'C,-uFoo','ccode208i',$script,'#172 -uFoo includes overloaded package');
