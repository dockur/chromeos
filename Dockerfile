# syntax=docker/dockerfile:1

FROM scratch AS runner
COPY --from=qemux/qemu:7.48 / /

ARG VERSION_ARG="0.0"

ARG DEBCONF_NOWARNINGS="yes"
ARG DEBIAN_FRONTEND="noninteractive"
ARG DEBCONF_NONINTERACTIVE_SEEN="true"

RUN <<EOF
  set -eu

  apt-get update
  apt-get --no-install-recommends -y install mtools
  apt-get clean

  # Set version file
  echo "$VERSION_ARG" > /etc/version

  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOF

COPY --chmod=755 ./src /run/

VOLUME /storage
EXPOSE 5900 8006

ENV RAM_SIZE="4G"
ENV CPU_CORES="2"
ENV DISK_SIZE="64G"
ENV VERSION="stable"

ENTRYPOINT ["/usr/bin/tini", "-s", "/run/entry.sh"]
