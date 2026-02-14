FROM ubuntu:22.04

# Proxy support for build-time network access (set via --build-arg).
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG http_proxy
ARG https_proxy
ENV DEBIAN_FRONTEND=noninteractive \
    HTTP_PROXY=${HTTP_PROXY} \
    HTTPS_PROXY=${HTTPS_PROXY} \
    http_proxy=${http_proxy} \
    https_proxy=${https_proxy} \
    WINEDEBUG=-all \
    WINEARCH=win64

RUN set -eux; \
  if [ -n "${HTTP_PROXY:-}" ]; then \
    printf 'Acquire::http::Proxy "%s";\nAcquire::https::Proxy "%s";\n' "$HTTP_PROXY" "$HTTPS_PROXY" > /etc/apt/apt.conf.d/99proxy; \
  fi; \
  apt-get update -o Acquire::Retries=5 && apt-get install -y --no-install-recommends --fix-missing \
  autoconf automake autotools-dev curl python3 python3-pip python3-tomli \
  libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo \
  gperf libtool patchutils bc zlib1g-dev libexpat-dev libisl-dev ninja-build git cmake \
  libglib2.0-dev libslirp-dev libncurses-dev ca-certificates \
  wine64 winbind \
  gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64 binutils-mingw-w64-x86-64 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /src
