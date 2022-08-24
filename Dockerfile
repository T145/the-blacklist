FROM golang:1.17 AS go

# https://golang.org/doc/go-get-install-deprecation#what-to-use-instead
# the install paths are where "main.go" lives

# https://github.com/projectdiscovery/httpx#usage
# https://github.com/projectdiscovery/dnsx#usage
# https://github.com/ipinfo/cli#-ipinfo-cli
# https://github.com/StevenBlack/ghosts#ghosts
RUN go install github.com/projectdiscovery/dnsx/cmd/dnsx@latest \
    && go install github.com/projectdiscovery/httpx/cmd/httpx@latest \
    && go install github.com/ipinfo/cli/ipinfo@latest \
    && go install github.com/StevenBlack/ghosts@latest

# https://hub.docker.com/_/ubuntu/
# alias: 22.04, jammy-20220801, jammy, latest, rolling
FROM ubuntu:jammy

LABEL maintainer="T145" \
      version="4.8.4" \
      description="Custom Docker Image used to run blacklist projects."

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# fullstop to avoid lingering connections, data leaks, etc.
STOPSIGNAL SIGKILL

COPY configs/modprobe.d/99disable.conf /etc/modprobe.d/
COPY --from=go /go/bin/ /usr/local/bin/

# just in case
ENV NODE_ENV=production LYCHEE_VERSION=v0.10.0 RESOLUTION_BIT_DEPTH=1600x900x16

# suppress language-related updates from apt-get to increase download speeds and configure debconf to be non-interactive
# https://github.com/phusion/baseimage-docker/issues/58#issuecomment-47995343
RUN echo 'Acquire::Languages "none";' >> /etc/apt/apt.conf.d/00aptitude \
      && echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#run
# https://docs.docker.com/engine/reference/builder/#from
# https://stackoverflow.com/questions/21530577/fatal-error-python-h-no-such-file-or-directory#21530768
# https://github.com/docker-library/postgres/blob/69bc540ecfffecce72d49fa7e4a46680350037f9/9.6/Dockerfile#L21-L24
# use apt-get & apt-cache rather than apt: https://askubuntu.com/questions/990823/apt-gives-unstable-cli-interface-warning
# install apt-utils early so debconf doesn't delay package configuration
RUN apt-get -y update \
      && apt-get -y --no-install-recommends install apt-utils=2.4.7 \
      && apt-get -y upgrade \
      && apt-get install -y --no-install-recommends \
      apt-show-versions=0.22.13 \
      aria2=1.36.0-1 \
      bc=1.07.1-3build1 \
      build-essential=12.9ubuntu3 \
      curl=7.81.0-1ubuntu1.3 \
      debsums=3.0.2 \
      gawk=1:5.1.0-1build3 \
      git=1:2.34.1-1ubuntu1.4 \
      gpg=2.2.27-3ubuntu2.1 \
      gpg-agent=2.2.27-3ubuntu2.1 \
      gzip=1.10-4ubuntu4 \
      iprange=1.0.4+ds-2 \
      jq=1.6-2.1ubuntu3 \
      libdata-validate-domain-perl=0.10-1.1 \
      libdata-validate-ip-perl=0.30-1 \
      libnet-idn-encode-perl=2.500-2build1 \
      libnet-libidn-perl=0.12.ds-3build6 \
      libregexp-common-perl=2017060201-1 \
      libtext-trim-perl=1.04-1 \
      libtry-tiny-perl=0.31-1 \
      locales=2.35-0ubuntu3.1 \
      miller=6.0.0-1 \
      moreutils=0.66-1 \
      nano=6.2-1 \
      p7zip-full=16.02+dfsg-8 \
      pandoc=2.9.2.1-3ubuntu2 \
      preload=0.6.4-5 \
      sed=4.8-1ubuntu2 \
      software-properties-common=0.99.22.3 \
      && apt-get install -y --no-install-recommends --reinstall ca-certificates=* \
      && add-apt-repository ppa:deadsnakes/ppa \
      && apt-get install -y --no-install-recommends \
      python3.8=3.8.13-1+jammy1 \
      python3.8-distutils=3.8.13-1+jammy1 \
      python3-pip=22.0.2+dfsg-1 \
      && apt-add-repository ppa:fish-shell/release-3 \
      && apt-get install -y --no-install-recommends fish=3.5.1-1~jammy \
      && apt-get autoremove -y \
      && apt-get clean \
      && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
      && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8

ENV LANG=en_US.utf8

# configure python packages
ENV PATH=$PATH:/root/.local/bin PIP_NO_CACHE_DIR='true'
RUN python3.8 -m pip install --upgrade -e git+https://github.com/twintproject/twint.git@origin/master#egg=twint \
      && update-alternatives --install /usr/bin/python python /usr/bin/python3.8 10

COPY configs/aria2.conf /configs/
RUN mkdir -p logs && touch logs/aria2.log

# install lychee
# https://github.com/lycheeverse/lychee-action/blob/master/action.yml#L31=
RUN aria2c --conf-path='./configs/aria2.conf' "https://github.com/lycheeverse/lychee/releases/download/${LYCHEE_VERSION}/lychee-${LYCHEE_VERSION}-x86_64-unknown-linux-gnu.tar.gz" \
      && tar -xvzf lychee-*.tar.gz \
      && chmod 755 lychee \
      && mv lychee /usr/local/bin/lychee \
      && rm -f lychee-*.tar.gz

# install the parallel beta that includes parsort
# https://oletange.wordpress.com/2018/03/28/excuses-for-not-installing-gnu-parallel/
# https://git.savannah.gnu.org/cgit/parallel.git/tree/README
# https://www.gnu.org/software/parallel/checksums/
RUN aria2c --conf-path='./configs/aria2.conf' http://pi.dk/3 -o install.sh \
      && sha1sum install.sh | grep 12345678883c667e01eed62f975ad28b6d50e22a \
      && md5sum install.sh | grep cc21b4c943fd03e93ae1ae49e28573c0 \
      && sha512sum install.sh | grep 79945d9d250b42a42067bb0099da012ec113b49a54e705f86d51e784ebced224fdff3f52ca588d64e75f603361bd543fd631f5922f87ceb2ab0341496df84a35 \
      && bash install.sh \
      && echo 'will cite' | parallel --citation || true \
      && rm -f install.sh parallel-*.tar.*

# configure the fish shell environment
RUN ["fish", "--command", "curl -sL https://git.io/fisher | source && fisher install jorgebucaran/fisher"]
#SHELL ["fish", "--command"]
#ENV SHELL=/usr/bin/fish

# Uninstall compilation utilities, configs, & logs after their use
# 'curl' is needed by the parallel installer
RUN apt-get purge -y build-essential curl \
      && apt-get autoremove -y \
      && rm -rf configs/ \
      && rm -rf logs/

RUN chsh -s /usr/bin/fish \
      && useradd --user-group --system --no-log-init --create-home --shell /usr/bin/fish garryhost
USER garryhost
WORKDIR /home/garryhost

ENTRYPOINT ["fish"]
#CMD ["param1","param2"] # passes params to ENTRYPOINT

#COPY --chown=garryhost:garryhost data/ ./black-mirror/data/
#COPY --chown=garryhost:garryhost scripts/ ./black-mirror/scripts/

# --interval=DURATION (default: 30s)
# --timeout=DURATION (default: 30s)
# --start-period=DURATION (default: 0s)
# --retries=N (default: 3)
HEALTHCHECK --retries=1 CMD ipinfo -h && dnsx --help && httpx --help && ghosts -h && twint -h && lychee --help && parsort --help && debsums -sa

# To build and run with elevated permissions
# https://stackoverflow.com/questions/48098671/build-with-docker-and-privileged
