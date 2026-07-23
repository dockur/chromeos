# syntax=docker/dockerfile:1

FROM scratch AS runner
COPY --from=qemux/qemu:7.39 / /

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

RUN <<'EOF'
  set -eu

  sed -i \
    's@if ! enabled "$GPU" || isAmdCpu || \[\[ "$ARCH" != "amd64" \]\]; then@if ! enabled "$GPU" || [[ "$ARCH" != "amd64" ]]; then@' \
    /run/display.sh

  sed -i \
    's| -device usb-tablet||' \
    /run/config.sh

  sed -i \
    's@USB_OPTS="-device $USB"@& \&\& { [[ "${TABLET:-Y}" =~ ^[Yy] ]] \&\& USB_OPTS+=" -device usb-tablet" || USB_OPTS+=" -device usb-mouse"; }@' \
    /run/config.sh

  grep -q 'usb-mouse' /run/config.sh || {
    echo "patch failed: TABLET conditional not injected into config.sh" >&2
    exit 1
  }

  ! grep -q 'isAmdCpu' /run/display.sh || {
    echo "patch failed: AMD GPU gate not removed from display.sh" >&2
    exit 1
  }

  bash -n /run/display.sh /run/config.sh
EOF

VOLUME /storage
EXPOSE 5900 8006

ENV RAM_SIZE="4G"
ENV CPU_CORES="2"
ENV DISK_SIZE="64G"
ENV VERSION="stable"
ENV GPU="Y"

ENTRYPOINT ["/usr/bin/tini", "-s", "/run/entry.sh"]
