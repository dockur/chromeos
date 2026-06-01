# syntax=docker/dockerfile:1

FROM scratch AS runner
COPY --from=qemux/qemu:7.31 / /

ARG VERSION_ARG="0.0"
ARG DEBCONF_NOWARNINGS="yes"
ARG DEBIAN_FRONTEND="noninteractive"
ARG DEBCONF_NONINTERACTIVE_SEEN="true"

RUN set -eu && \
    apt-get update && \
    apt-get --no-install-recommends -y install mtools && \
    apt-get clean && \
    cp /var/www/img/qemu.ffs /var/www/img/chromeosflex.ffs && \
    echo "$VERSION_ARG" > /run/version && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --chmod=755 ./src /run/

RUN set -eu && \
    sed -i \
      -e 's|websocket=$WSS_PORT -vga|websocket=$WSS_PORT${LOSSY_OPT:-} -vga|' \
      -e 's|"-display vnc=:$port -vga $VGA"|"-display vnc=:$port${LOSSY_OPT:-} -vga $VGA"|' \
      -e 's| -vnc :$port,websocket=$WSS_PORT"| -vnc :$port,websocket=$WSS_PORT${LOSSY_OPT:-}"|' \
      -e 's| -vnc :$port"| -vnc :$port${LOSSY_OPT:-}"|' \
      /run/display.sh && \
    sed -i 's|if \[\[ "$CPU_VENDOR" != "GenuineIntel" \]\]; then|if false; then|' /run/display.sh && \
    sed -i 's| -device usb-tablet||' /run/config.sh && \
    sed -i 's@USB_OPTS="-device $USB"@& \&\& { [[ "${TABLET:-Y}" =~ ^[Yy] ]] \&\& USB_OPTS+=" -device usb-tablet" || USB_OPTS+=" -device usb-mouse"; }@' /run/config.sh && \
    grep -q 'LOSSY_OPT' /run/display.sh || { echo "patch failed: LOSSY_OPT not injected into display.sh" >&2; exit 1; }
RUN set -eu && \
    [ "$(grep -c 'LOSSY_OPT' /run/display.sh)" -ge 4 ] || { echo "patch failed: expected 4 LOSSY_OPT sites in display.sh" >&2; exit 1; } && \
    grep -q 'usb-mouse' /run/config.sh || { echo "patch failed: TABLET conditional not injected into config.sh" >&2; exit 1; } && \
    ! grep -q 'GenuineIntel' /run/display.sh || { echo "patch failed: GenuineIntel gate not removed from display.sh" >&2; exit 1; }

VOLUME /storage
EXPOSE 5900 8006

ENV APP="ChromeOSFlex"
ENV VERSION="stable"
ENV RAM_SIZE="4G"
ENV CPU_CORES="2"
ENV DISK_SIZE="64G"
ENV GPU="Y"

ENTRYPOINT ["/usr/bin/tini", "-s", "/run/entry.sh"]
