#!perl

sub mysub {
    undef *mysub;

    return $ENV{A} | $ENV{B};
}

mysub();

print "1..1\n";
print "ok 1\n" if $::{ENV};
