FROM golang:1.18 AS go

# https://golang.org/doc/go-get-install-deprecation#what-to-use-instead
# the install paths are where "main.go" lives

# https://github.com/projectdiscovery/dnsx#usage
RUN go install -v github.com/projectdiscovery/dnsx/cmd/dnsx@v1.1.1 \
    # https://github.com/projectdiscovery/httpx#usage
    && go install -v github.com/projectdiscovery/httpx/cmd/httpx@v1.2.5 \
    # https://github.com/projectdiscovery/shuffledns#usage
    && go install -v github.com/projectdiscovery/shuffledns/cmd/shuffledns@v1.0.8 \
    # https://github.com/ipinfo/cli#-ipinfo-cli
    && go install -v github.com/ipinfo/cli/ipinfo@ipinfo-2.10.0 \
    # https://github.com/StevenBlack/ghosts#ghosts
    && go install -v github.com/StevenBlack/ghosts@v0.2.2

# https://hub.docker.com/_/buildpack-deps/
FROM buildpack-deps:stable as utils

SHELL ["/bin/bash", "-o", "pipefail", "-ceux"]
ENV LYCHEE_VERSION=v0.10.3 \
    PANDOC_VERSION=2.19.2

# https://oletange.wordpress.com/2018/03/28/excuses-for-not-installing-gnu-parallel/
# https://git.savannah.gnu.org/cgit/parallel.git/tree/README
# https://www.gnu.org/software/parallel/checksums/
RUN curl http://pi.dk/3/ -o install.bash \
    && sha1sum install.bash | grep 12345678883c667e01eed62f975ad28b6d50e22a \
    && md5sum install.bash | grep cc21b4c943fd03e93ae1ae49e28573c0 \
    && sha512sum install.bash | grep 79945d9d250b42a42067bb0099da012ec113b49a54e705f86d51e784ebced224fdff3f52ca588d64e75f603361bd543fd631f5922f87ceb2ab0341496df84a35 \
    && bash install.bash \
    && find /usr/local/bin/ -type f ! -name 'par*' -delete; \
    # https://github.com/lycheeverse/lychee-action/blob/master/action.yml#L39
    curl -sLO "https://github.com/lycheeverse/lychee/releases/download/${LYCHEE_VERSION}/lychee-${LYCHEE_VERSION}-x86_64-unknown-linux-gnu.tar.gz" \
    && tar -xvzf lychee-*.tar.gz --strip-components 1 -C /usr/local/bin/; \
    # https://github.com/jgm/pandoc/blob/master/INSTALL.md#linux
    # final pandoc install is ~80MB vs ~155MB via apt
    curl -sLO "https://github.com/jgm/pandoc/releases/download/${PANDOC_VERSION}/pandoc-${PANDOC_VERSION}-linux-amd64.tar.gz" \
    && tar -xvzf pandoc-*.tar.gz --strip-components 1 -C /usr/local/ \
    && rm -f /usr/local/bin/pandoc-server; \
    # https://github.com/blechschmidt/massdns#compilation
    # https://github.com/projectdiscovery/shuffledns#prerequisite
    git clone https://github.com/blechschmidt/massdns.git \
    && make -C massdns \
    && mv /massdns/bin/massdns /usr/local/bin/;

# https://wiki.debian.org/DiskFreeSpace
# https://raphaelhertzog.com/mastering-debian/
FROM docker.io/parrotsec/core:base-lts-amd64
LABEL maintainer="T145" \
      version="5.3.5" \
      description="Runs the \"Black Mirror\" project! Check it out GitHub!" \
      org.opencontainers.image.description="https://github.com/T145/black-mirror#-docker-usage"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
STOPSIGNAL SIGKILL

ENV LANG=en_US.UTF-8 \
    # https://stackoverflow.com/questions/2499794/how-to-fix-a-locale-setting-warning-from-perl
    #LC_CTYPE=en_US.UTF-8 \
    #LC_ALL=en_US.UTF-8 \
    RESOLUTION_BIT_DEPTH=1600x900x16 \
    # https://nodejs.dev/en/learn/nodejs-the-difference-between-development-and-production/
    NODE_ENV=production

# https://github.com/ParrotSec/docker-images/blob/master/core/lts-amd64/Dockerfile#L6
# https://www.parrotsec.org/docs/apparmor.html
# rkhunter: https://unix.stackexchange.com/questions/562560/invalid-web-cmd-configuration-option-relative-pathname-bin-false
COPY configs/etc/ /etc/
COPY --from=go /go/bin/ /usr/local/bin/
COPY --from=utils /usr/local/bin/ /usr/local/bin/

# https://github.com/JefferysDockers/ubu-lts/blob/master/Dockerfile#L26
RUN echo '#!/bin/sh' >/usr/sbin/policy-rc.d \
    && echo 'exit 101' >>/usr/sbin/policy-rc.d \
    && chmod +x /usr/sbin/policy-rc.d \
    # https://github.com/JefferysDockers/ubu-lts/blob/master/Dockerfile#L33
    && dpkg-divert --local --rename --add /sbin/initctl \
    && cp -a /usr/sbin/policy-rc.d /sbin/initctl \
    && sed -i 's/^exit.*/exit 0/' /sbin/initctl \
    # https://github.com/phusion/baseimage-docker/issues/58#issuecomment-47995343
    && echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections \
    # https://github.com/JefferysDockers/ubu-lts/blob/master/Dockerfile#L78
    && mkdir -p /run/systemd && echo 'docker' >/run/systemd/container

# https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#run
# https://stackoverflow.com/questions/21530577/fatal-error-python-h-no-such-file-or-directory#21530768
# use apt-get & apt-cache rather than apt: https://askubuntu.com/questions/990823/apt-gives-unstable-cli-interface-warning
RUN apt-get -q -y update --no-allow-insecure-repositories; \
    apt-get -y upgrade; \
    apt-get -y install --no-install-recommends \
    #apt-show-versions # use dpkg -l (L) instead since ASV doesn't like GZ packages
    apparmor=2.13.6-10 \
    apparmor-utils=2.13.6-10 \
    aria2=1.35.0-3 \
    auditd=1:3.0-2 \
    curl=7.85.0-1~bpo11+1 \
    debsums=3.0.2 \
    gawk=1:5.1.0-1 \
    git=1:2.34.1-1~bpo11+1 \
    iprange=1.0.4+ds-2 \
    jq=1.6-2.1 \
    libdata-validate-domain-perl=0.10-1.1 \
    libdata-validate-ip-perl=0.30-1 \
    libnet-idn-encode-perl=2.500-1+b2 \
    libnet-libidn-perl=0.12.ds-3+b3 \
    libregexp-common-perl=2017060201-1 \
    libtext-trim-perl=1.04-1 \
    libtry-tiny-perl=0.30-1 \
    localepurge=0.7.3.10 \
    locales=2.31-13+deb11u5 \
    miller=5.10.0-1 \
    moreutils=0.65-1 \
    p7zip-full=16.02+dfsg-8 \
    #pandoc=2.9.2.1-1+b1 \ # ~155MB binary!
    #preload=0.6.4-5+b1 \ # May run script functions more than once.
    python3-pip=20.3.4-4+deb11u1 \
    rkhunter=1.4.6-9 \
    symlinks=1.4-4; \
    apt-get install -y --no-install-recommends --reinstall ca-certificates=*; \
    apt-get -y autoremove; \
    apt-get -y clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*; \
    rm -f /var/cache/ldconfig/aux-cache; \
    find -P -O3 /var/log -depth -type f -print0 | xargs -0 truncate -s 0; \
    update-locale LANG=en_US.UTF-8; \
    # https://github.com/docker-library/postgres/blob/69bc540ecfffecce72d49fa7e4a46680350037f9/9.6/Dockerfile#L21-L24
    localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8; \
    # https://askubuntu.com/questions/477974/how-to-remove-unnecessary-locales
    localepurge; \
    # https://linuxhandbook.com/find-broken-symlinks/
    symlinks -rd /; \
    apt-get -y purge --auto-remove localepurge symlinks; \
    find -P -O3 /etc/ /usr/ -type d -empty -delete;

# https://cisofy.com/lynis/controls/HRDN-7222/
RUN chown 0:0 /usr/bin/as \
    && chown 0:0 /usr/share/gcc; \
    #rkhunter --update || :; \
    echo 'will cite' | parallel --citation || :; \
    # https://github.com/debuerreotype/debuerreotype/pull/32
    rmdir /run/mount 2>/dev/null || :;

RUN python3 -m pip install --no-cache-dir --upgrade -e git+https://github.com/JustAnotherArchivist/snscrape.git#egg=snscrape; \
    python3 -m pip cache purge; \
    py3clean -v ./usr/lib/python3.9 ./usr/share/python3; \
    rm -rf /root/.cache;

ENTRYPOINT [ "bash" ]

# https://cisofy.com/lynis/controls/FILE-6310/
VOLUME [ "/home", "/tmp", "/var" ]

HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 CMD [ "command -v ipinfo && command -v dnsx && command -v httpx && command -v ghosts && command -v lychee && command -v parsort" ]
