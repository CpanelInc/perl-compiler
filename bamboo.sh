#!/bin/sh

echo "Removing perl526 & installing perl524"
rpm -e --nodeps cpanel-perl-526 >/dev/null 2>&1 ||:
rpm -e --nodeps cpanel-perl-526-build >/dev/null 2>&1 ||:
#rpm -Uv --force rpms/cpanel-perl-524-5.24.1-17.cp1162.x86_64.rpm
# cheating for now...
rpm -Uv --force rpms/cpanel-perl-524-5.24.1-5.cp1168.x86_64.rpm

echo "Setting prove for 524 - can also adjust symlinks"
[ -L /usr/local/cpanel/3rdparty/bin/prove ] && rm -f /usr/local/cpanel/3rdparty/bin/prove
ln -s /usr/local/cpanel/3rdparty/perl/524/bin/prove /usr/local/cpanel/3rdparty/bin/prove
