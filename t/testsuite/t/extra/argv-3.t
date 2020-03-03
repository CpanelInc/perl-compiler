#!perl

sub mysub {
    $ARGV{DEBUG} | $ARGV{DEBUG} | $ARGV{DEBUG};
}

mysub();
undef *mysub;

print "1..1\n";
print "ok 1\n" if $::{ARGV};
