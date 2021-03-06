## defaults that will intentionally fail unless you pass good values in
ARG REGISTRY_HOST=dorkus.malorkus.net
ARG CPVERSION=11.69

FROM ${REGISTRY_HOST}/cpanel-perl/centos7:${CPVERSION}
LABEL maintainer="Pax Aurora"

## which: used in the B::C testsuite
## gdbm-devel: for '-lgdbm'
## libdb-devel: for '-ldb'
RUN yum -y update \
    && yum -y groups install "Development Tools" \
    && yum -y install sudo which gdbm-devel libdb-devel expat-devel expat libidn-devel libidn openssl-devel openssl \
    && yum clean all \
    && rm -rf /var/cache/yum

RUN echo -e 'Defaults:jenkins !requiretty\njenkins ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/jenkins \
    && groupadd --gid 1008 jenkins \
    && useradd --uid 1008 --gid 1008 --comment "User to match the host user id" jenkins

USER jenkins
