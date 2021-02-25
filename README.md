The B::C, B::CC, B::Bytecode Perl Compiler Kit
======

INSTALL
-------

This doesn't work on Windows any more as we removed threads support during a
re-write. Every branch only supports a specific version of Perl. Moreover, this
will likely not work on system perl, as it requires Perl to be both [single
threaded and compiled with a specific patch
set.](https://github.com/cpanel/docker-perl-compiler/tree/perl-v5.32.0/patches)

    perl Makefile.PL && make test && make install

USAGE
-----

Bytecode and CC bakends have been removed as they were incomplete and unused.

To compile perl program foo.pl with the C backend, do

    perlcc -ofoo foo.pl
    ./foo

STATUS
------

C is stable, CC is unstable.  Bytecode stable until 5.16 The Bytecode compiler
is disabled for 5.6.2, use the default instead.

See STATUS for details.

BUGS
----

Bugs and Todo items can be found here: https://github.com/cpanel/perl-compiler/issues

* Copyright (c) 2012, 2013, 2014, 2019 cPanel Inc
* Copyright (c) 2008, 2009, 2010, 2011 Reini Urban
* Copyright (c) 1996, 1997, Malcolm Beattie
