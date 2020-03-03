#!perl

sub mysub {
    undef *mysub;
    1 if $ENV{F};
    1 if $ENV{F};
    1 if $ENV{F};
}

mysub();

print "1..1\n";
print "ok 1\n" if $::{ENV};
