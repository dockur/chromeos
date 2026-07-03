<h1 align="center">ChromeOS<br />
<div align="center">
<a href="https://github.com/dockur/chromeos/"><img src="https://github.com/dockur/chromeos/raw/master/.github/logo.png" title="Logo" style="max-width:100%;" width="128" /></a>
</div>
<div align="center">


[![Build]][build_url]
[![Version]][hub_url]
[![Size]][hub_url]
[![Pulls]][hub_url]

</div></h1>

ChromeOS Flex inside a Docker container.

## Features ✨

 - Automatic download
 - KVM acceleration
 - Web-based viewer
 - Audio support
 - GPU acceleration (Intel, AMD, or Nvidia)

## Usage 🐳

##### Docker Compose:

```yaml
services:
  chromeos:
    image: dockurr/chromeos
    container_name: chromeos
    environment:
      VERSION: "stable"
      GPU: "Y"
      FORCE_HOST_CURSOR: "Y"
      KEEP_AWAKE: "N"
    devices:
      - /dev/kvm
      - /dev/net/tun
    device_cgroup_rules:
      - "c 226:* rwm"
    cap_add:
      - NET_ADMIN
    ports:
      - 8006:8006
      - 5900:5900/tcp
      - 5900:5900/udp
    volumes:
      - ./chromeos:/storage
      - /dev/dri:/dev/dri:rw
    restart: always
    stop_grace_period: 2m
```

##### Docker CLI:

```bash
docker run -it --rm --name chromeos -e "VERSION=stable" -p 8006:8006 --device=/dev/kvm --device=/dev/net/tun --device-cgroup-rule="c 226:* rwm" --cap-add NET_ADMIN -v "${PWD:-.}/chromeos:/storage" -v /dev/dri:/dev/dri --stop-timeout 120 docker.io/dockurr/chromeos
```

##### Kubernetes:

```shell
kubectl apply -f https://raw.githubusercontent.com/forkymcforkface/chromeos/main/kubernetes.yml
```

##### GitHub Codespaces:

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/dockur/chromeos)

## Requirements ⚙️

 - A Linux host with KVM support, or Docker Desktop / Podman on Windows 11 with nested virtualization enabled.
 - At least 4 GB of RAM available.
 - At least 64 GB of free disk space.

> [!NOTE]
> Docker Desktop on macOS and Windows 10 do not currently provide the required KVM support for this image.

> [!IMPORTANT]
> For best performance, run on a host with a GPU and `/dev/dri/` exposed. GPU acceleration uses the QEMU egl-headless path: Intel and AMD render nodes go through the open-source Mesa driver, Nvidia through its proprietary driver (see the FAQ). Without a usable GPU it falls back to software rendering, which works but is slow.

## FAQ 💬

### How do I use it?

  Very simple! These are the steps:

  - Start the container and connect to [port 8006](http://127.0.0.1:8006/) using your web browser.

  - The container downloads the current Flex recovery image and lands you in Flex's installer.

  - Click through the installer to install Flex to the persistent disk, then run through OOBE.

  Enjoy your brand new machine, and don't forget to star this repo!

### How do I select the channel?

  By default, the stable channel is installed. But you can add the `VERSION` environment variable to your compose file, in order to specify an alternative channel to be downloaded:

  ```yaml
  environment:
    VERSION: "ltr"
  ```

  Select from the values below:

  | **Value** | **Channel**        | **Cadence** |
  |---|---|---|
  | `stable`  | Stable             | ~4 weeks    |
  | `beta`    | Beta               | ~weekly     |
  | `ltc`     | Long-Term Channel  | ~6 months   |
  | `ltr`     | Long-Term Release  | ~18 months  |

### How do I install a custom image?

  In order to download an unsupported image, specify its URL in the `VERSION` environment variable:

  ```yaml
  environment:
    VERSION: "https://example.com/chromeos.bin.zip"
  ```

  Alternatively, you can also skip the download and use a local file instead, by binding it in your compose file in this way:

  ```yaml
  volumes:
    - ./example.bin:/boot.img
  ```

  Replace the example path `./example.bin` with the filename of your desired image. The value of `VERSION` will be ignored in this case.

### How do I change the storage location?

  To change the storage location, include the following bind mount in your compose file:

  ```yaml
  volumes:
    - ./chromeos:/storage
  ```

  Replace the example path `./chromeos` with the desired storage folder or named volume.

### How do I change the size of the disk?

  To expand the default size of 64 GB, add the `DISK_SIZE` setting to your compose file and set it to your preferred capacity:

  ```yaml
  environment:
    DISK_SIZE: "256G"
  ```

> [!TIP]
> This can also be used to resize an existing disk to a larger capacity without any data loss.
>
> However afterwards you will need to run the following command from the host, with the container stopped:
>
> `sudo ./tools/resize.sh ./chromeos`
>
> to allocate this additional space.

### How do I change the amount of CPU or RAM?

  By default, ChromeOS Flex will be allowed to use 2 CPU cores and 4 GB of RAM.

  If you want to adjust this, you can specify the desired amount using the following environment variables:

  ```yaml
  environment:
    RAM_SIZE: "8G"
    CPU_CORES: "4"
  ```

### How do I password-protect the viewer?

  By default the viewer on port 8006 is open to anyone who can reach it. Set `PROTECT` to require a login (HTTP basic auth). The default credentials are `Docker` / `admin`, so override them with `USERNAME` and `PASSWORD`:

  ```yaml
  environment:
    PROTECT: "Y"
    USERNAME: "admin"
    PASSWORD: "your-password"
  ```

### How do I let the host reclaim unused memory?

  By default the VM holds the full `RAM_SIZE` for its entire lifetime. Set `BALLOONING` to enable dynamic memory ballooning, which lets the host reclaim guest RAM that isn't in use:

  ```yaml
  environment:
    BALLOONING: "Y"
  ```

  The target can be tuned with `BALLOONING_MIN_MEM` (default `33%`) and `BALLOONING_RAM_THRESHOLD` (default `80.0`).

### How does GPU acceleration work?

  The container expects the host's `/dev/dri/` to be bind-mounted in. At startup, the entrypoint scans for a usable render node and hands it to QEMU as the VirGL backend (`-display egl-headless,rendernode=...` + `virtio-vga-gl`). Both the `volumes: - /dev/dri:/dev/dri:rw` mount and the `device_cgroup_rules: - "c 226:* rwm"` rule in the example compose are required for this. Intel and AMD render nodes work out of the box; for Nvidia see below. If no usable render node is found, the container falls back to software rendering.

  The `GPU` setting accepts:

  | Value | Effect |
  |-------|--------|
  | `Y` / `auto` | Auto-detect (default); prefers a ready Nvidia node, otherwise Intel/AMD |
  | `N` | Off — software rendering (3–15 fps) |
  | `intel` / `amd` / `nvidia` | Force a specific vendor, useful on multi-GPU hosts |

  For finer control, set `RENDERNODE` to a specific node (e.g. `/dev/dri/renderD128`). On a miss the container logs exactly what was found and what to fix, then falls back to software rendering.

### How do I use an Nvidia GPU?

  Nvidia cards render through the same egl-headless path, with two extra requirements:

  - The host must load `nvidia-drm` with `modeset=1` (add `options nvidia_drm modeset=1` to a file in `/etc/modprobe.d/`, run `update-initramfs -u`, then reboot). Without it the card is invisible to the GBM/EGL backend the container uses.
  - Run the container with the Nvidia runtime and the `graphics` capability so the driver's EGL libraries are injected:

  ```yaml
  services:
    chromeos:
      image: forkymcforkface/chromeos
      runtime: nvidia
      environment:
        GPU: "Y"
        NVIDIA_VISIBLE_DEVICES: "all"
        NVIDIA_DRIVER_CAPABILITIES: "all"
      device_cgroup_rules:
        - "c 226:* rwm"
      volumes:
        - /dev/dri:/dev/dri:rw
  ```

  Or with the CLI: add `--gpus all -e NVIDIA_DRIVER_CAPABILITIES=all`. The render node is auto-detected by vendor, so no card-specific configuration is needed. If both an Nvidia and an Intel/AMD GPU are present, the Nvidia card is preferred once its EGL libraries are available; force the choice either way with `GPU: "nvidia"` / `GPU: "intel"`, or pin a node with `RENDERNODE`.

### How does the cursor work?

  ChromeOS Flex sees the input device as a touchscreen and doesn't render a cursor. noVNC has an optional "Show dot when no cursor" setting, but the dot is small and easy to miss. By default the container overrides this with a CSS rule so the browser's normal cursor shows through:

  ```yaml
  environment:
    FORCE_HOST_CURSOR: "Y"
  ```

  Set it to `"N"` to disable the override.

### How do I right-click?

  ChromeOS treats the input device as a touchscreen, so right-click events are ignored. To open a context menu, **left-click and hold for about half a second**. The touch UI interprets a long-press as a context-menu gesture.

### How do I get a native cursor and native right-click instead?

  By default the container exposes the guest as a touchscreen (`usb-tablet`) so that noVNC's absolute click coordinates land exactly where you click, at the cost of no native cursor (the host cursor is shown instead) and no right-click button (use a long-press). If you would rather have ChromeOS's native cursor and native right-click, switch to mouse mode:

  ```yaml
  environment:
    TABLET: "N"
    FORCE_HOST_CURSOR: "N"
  ```

  This swaps the tablet for a `usb-mouse`, so ChromeOS shows its own cursor and right-click works. The trade-off is pointer tracking: ChromeOS scales the relative movements noVNC sends, so the cursor drifts away from the real pointer position over distance and clicks land off-target. This mode suits a direct VNC client more than the browser viewer; for noVNC, the default tablet mode is recommended.

### How do I stop the display from going to sleep?

  ChromeOS Flex blanks the display after ~8 minutes of inactivity and can be hard to wake from the browser viewer. To prevent this, set:

  ```yaml
  environment:
    KEEP_AWAKE: "Y"
  ```

  This sends a no-op `pause` key event to the VM every 4 minutes, keeping the idle timer reset. Alternatively, install the "Keep Awake" extension from the Chrome Web Store inside Flex.

### How do I enable audio?

  Audio is off by default. To stream the guest's audio to the browser, set:

  ```yaml
  environment:
    AUDIO: "Y"
  ```

  Then tick the **Audio** box under Settings → Advanced in the noVNC toolbar. Audio only streams while that box is checked, so it adds no bandwidth when unused.

### How do I reduce bandwidth for remote noVNC sessions?

  Enable lossy VNC encoding to let QEMU's Tight encoder use JPEG for color regions:

  ```yaml
  environment:
    LOSSY: "Y"
  ```

  Trade-off: slight blurring on photos and gradients (invisible on UI text). Most useful when accessing the container over WAN or on bandwidth-constrained networks.

### How do I enable developer mode?

  Add `DEV_MODE: "Y"` to your compose file:

  ```yaml
  environment:
    DEV_MODE: "Y"
  ```

  On the next boot the container switches the data disk's bootloader from `chromeos-vhd.A` (verified, read-only rootfs) to `chromeos-hd.A` (unverified, read-write rootfs). Inside Flex, open crosh with `Ctrl+Alt+T` and type `shell` to get a bash prompt. `sudo -i` for root.

  An "OS verification is OFF" banner appears at every boot, and Flex's in-VM auto-update is disabled (the container's `VERSION` env handles the channel anyway). To turn dev mode back off, set `DEV_MODE: "N"` and restart the container. The next boot flips the default back to `chromeos-vhd.A`.

### How do I install Linux packages?

  Enable developer mode (above), then use [chromebrew](https://github.com/chromebrew/chromebrew), a package manager for ChromeOS, from inside the guest:

  ```bash
  bash <(curl -L git.io/vddgY) && . ~/.bashrc
  ```

  It installs to `/usr/local/tmp/crew` on the stateful partition, so it survives reboots. This runs inside ChromeOS, not the container; on ChromeOS M117+ the installer requires a VT-2 terminal (`Ctrl+Alt+F2`) rather than crosh.

### How do I assign an individual IP address to the container?

  By default, the container uses bridge networking, which shares the IP address with the host. If you want to assign an individual IP address to the container, you can create a macvlan network as follows:

  ```bash
  docker network create -d macvlan \
      --subnet=192.168.0.0/24 \
      --gateway=192.168.0.1 \
      --ip-range=192.168.0.100/28 \
      -o parent=eth0 vlan
  ```

  Then add this to your compose file:

  ```yaml
  networks:
    default:
      name: vlan
      external: true
  ```

  This way the container becomes part of the LAN as a separate device, reachable by its own IP. Note that some routers don't allow the host and the container to communicate over the macvlan, so check first.

### How can ChromeOS Flex acquire an IP address from my router?

  After configuring the container for [macvlan](#how-do-i-assign-an-individual-ip-address-to-the-container), it is possible for ChromeOS to be a part of your home network by requesting an IP from your router, just like a real PC. To enable this mode, add the following to your compose file:

  ```yaml
  environment:
    DHCP: "Y"
  devices:
    - /dev/vhost-net
  device_cgroup_rules:
    - 'c *:* rwm'
  ```

### How do I pass through a USB device?

  To pass through a USB device, first look up its vendor and product IDs via the `lsusb` command, then add them to your compose file like this:

  ```yaml
  environment:
    ARGUMENTS: "-device usb-host,vendorid=0x1234,productid=0x1234"
  devices:
    - /dev/bus/usb
  ```

### How do I verify if my system supports KVM?

  First check if your software is compatible using this chart:

  | **Product**       | **Linux** | **Win11** | **Win10** | **macOS** |
  |---|---|---|---|---|
  | Docker CLI        | ✅        | ✅        | ❌        | ❌        |
  | Docker Desktop    | ❌        | ✅        | ❌        | ❌        |
  | Podman CLI        | ✅        | ✅        | ❌        | ❌        |
  | Podman Desktop    | ✅        | ✅        | ❌        | ❌        |

  After that you can run the following commands in Linux to check your system:

  ```bash
  sudo apt install cpu-checker
  sudo kvm-ok
  ```

  If you receive an error from `kvm-ok` indicating that KVM cannot be used, please check whether:

  - the virtualization extensions (`Intel VT-x` or `AMD SVM`) are enabled in your BIOS.

  - you enabled "nested virtualization" if you are running the container inside a virtual machine.

  - you are not using a cloud provider, as most of them do not allow nested virtualization for their VPSs.

  If you did not receive any error from `kvm-ok` but the container still complains about a missing KVM device, it could help to add `privileged: true` to your compose file (or `sudo` to your `docker` command) to rule out any permission issue.

### How do I run Windows in a container?

  You can use [dockur/windows](https://github.com/dockur/windows) for that. It shares many of the same features and conventions.

### How do I run macOS in a container?

  You can use [dockur/macos](https://github.com/dockur/macos) for that. It shares many of the same features and conventions.

### How do I run a Linux desktop in a container?

  You can use [qemus/qemu](https://github.com/qemus/qemu) for that, which is the QEMU base this project is built on.

### Is this project legal?

  Yes, this project contains only open-source code and does not distribute any copyrighted material. Every recovery image is downloaded directly from Google's CDN, under your own licensing relationship with Google. 

 ## Acknowledgements 🙏

Special thanks to [forkymcforkface](https://github.com/forkymcforkface), this project would not exist without his invaluable work.

## Stars 🌟
[![Stargazers](https://raw.githubusercontent.com/star-stats/stars/refs/heads/data/charts/dockur-chromeos.svg)](https://github.com/dockur/chromeos/stargazers)

## Disclaimer ⚖️

*The product names, logos, brands, and other trademarks referred to within this project are the property of their respective trademark holders. This project is not affiliated, sponsored, or endorsed by Google LLC.*

[build_url]: https://github.com/dockur/chromeos/
[hub_url]: https://hub.docker.com/r/dockurr/chromeos/

[Build]: https://github.com/dockur/chromeos/actions/workflows/build.yml/badge.svg?v=1
[Size]: https://img.shields.io/docker/image-size/dockurr/chromeos/latest?color=066da5&label=size&v=1
[Pulls]: https://img.shields.io/docker/pulls/dockurr/chromeos.svg?style=flat&label=pulls&logo=docker&v=1
[Version]: https://img.shields.io/docker/v/dockurr/chromeos/latest?arch=amd64&sort=semver&color=066da5&v=1
