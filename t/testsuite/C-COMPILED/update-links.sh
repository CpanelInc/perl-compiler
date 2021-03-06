#!/bin/sh

set -e

for d in "benchmark" "base" "bigmem" "cmd" "comp" "extra" "io" "mro" "op" "opbasic" "re" "uni"; do
    pushd $d
    echo "* $d"
    # cleanup before link recreation
    rm -f *.t ||:
    test -d ../../t/$d
    for t in ../../t/$d/*.t; do
        BN=$(basename $t)
        echo - updating: $BN
        [ -f $BN ] && rm -f $BN ||:
        ln -s ../template.pl $BN
    done
    # remove threaded tests
    rm -f *_thr.t ||:
    popd
done
