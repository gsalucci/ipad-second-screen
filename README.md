# iPad as a second monitor for niri

Turn a jailbroken iPad into a real second monitor for a Wayland desktop running
[niri](https://github.com/YaLTeR/niri) — a monitor the compositor treats like any
other, so you can drag windows onto it, move workspaces to it, and use the same
keybindings and clipboard.

No kernel parameters, no initramfs changes, no reboot, and no HDMI dummy plug.
Nothing is written outside this directory; a reboot removes every trace.

```sh
./second-screen up       # create the monitor, start streaming, tell the iPad to connect
./second-screen down     # remove it
./second-screen status   # down | up | connected
./second-screen toggle
```

---

## How it works

niri cannot create a virtual output, so the extra display is made *below* the
compositor, in the kernel:

1. **Force a spare DRM connector on.** A connector's detected state is a writable
   file — `echo on > /sys/class/drm/card0-DP-1/status`.
2. **Give it an EDID.** debugfs accepts a monitor description that no cable ever
   carried — `cat edid.bin > /sys/kernel/debug/dri/0/DP-1/edid_override`.
   `mkedid.py` generates one matching the iPad panel.
3. **Place it in the layout** with `niri msg output`.
4. **Stream it** with `wayvnc -o DP-1`, bound to your LAN address.
5. **Tell the iPad to connect** over SSH, using the `vnc://` URL scheme.

Both kernel writes are runtime-only, which is why nothing survives a reboot.

---

## Requirements

**Host**

| | |
|---|---|
| compositor | niri (any Wayland compositor with `niri msg`-style output control can be adapted) |
| packages | `wayvnc`, `python3`, `iproute2`, `openssh` |
| GPU | a free DRM connector. Tested on NVIDIA 580.178.04; also works on amdgpu and i915 |
| access | `sudo` for two sysfs/debugfs writes; debugfs mounted |

**iPad**

| | |
|---|---|
| jailbreak | any that gives you `uiopen` and an SSH server (tested with Dopamine, rootless) |
| client | [RealVNC Viewer](https://apps.apple.com/app/vnc-viewer/id352019548), free |
| network | same LAN as the host |

Only the auto-connect step needs the jailbreak. Without it, everything still
works — you just open the VNC client and type the address yourself.

---

## Setup

### 1. Pick a connector

```sh
ls /sys/class/drm/            # card0-DP-1, card0-HDMI-A-1, ...
cat /sys/class/drm/card0-DP-1/status
```

Choose one that reads `disconnected`. **Use DisplayPort, not HDMI** — see below.

### 2. Configure

```sh
cp .env.example .env
$EDITOR .env
```

At minimum set `HOST_IP` (this machine's LAN address) and `CONN`.

`W`/`H` default to 2160x1620, the iPad 8 panel. For another model use its native
resolution. `POS_X`/`POS_Y` place the monitor in the niri layout, in logical
pixels: to centre it below a 2560x1440 monitor at 0,0, use
`POS_X = (2560 - W/SCALE) / 2` and `POS_Y = 1440`.

### 3. Set up SSH to the iPad (optional, for auto-connect)

Install an SSH server from your package manager on the device (Sileo, Zebra …)
and authorise a key. A rootless jailbreak puts `mobile`'s home at
`/var/jb/var/mobile`, so the key goes in
`/var/jb/var/mobile/.ssh/authorized_keys`, **not** `/var/mobile/.ssh/`.

```sh
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_ipad
ssh mobile@<ipad-ip> 'mkdir -p /var/jb/var/mobile/.ssh && cat >> /var/jb/var/mobile/.ssh/authorized_keys' \
    < ~/.ssh/id_ed25519_ipad.pub
```

The device's sshd listens on every interface, so this works over Wi-Fi — no
cable, and no `usbmuxd` port forwarding.

### 4. Run it

```sh
./second-screen up
```

The iPad shows **"Continue connecting?"** — confirm it. Then drag something over:

```sh
niri msg action move-window-to-monitor DP-1
```

---

## Why DisplayPort

An EDID with no CEA-861 extension block makes the driver treat the connector as
**DVI** and apply the 165 MHz single-link pixel-clock ceiling. 2160x1620@60 needs
231.8 MHz. Measured on NVIDIA 580.178.04:

| connector | mode | pixel clock | result |
|---|---|---|---|
| HDMI-A-1 | 1920x1080@60 | 140.4 MHz | accepted |
| HDMI-A-1 | 2160x1620@60 | 231.8 MHz | **rejected** |
| HDMI-A-1 | 2160x1620@42 | 162.2 MHz | accepted |
| DP-1 | 2160x1620@60 | 231.8 MHz | **accepted** |

The 40/42 Hz results show the limit is the pixel clock, not the resolution.
DisplayPort has no such ceiling. If you only have HDMI free, either lower `R` to
about 40 or reduce the resolution.

---

## The DankBar button

For [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) users,
`dms-plugin/` adds a bar button that toggles the monitor.

```sh
./dms-plugin/install.sh
```

Left click toggles, right click forces it down. The icon shows the state: muted
tablet = down, amber = up with nothing connected, `cast_connected` = a client is
attached.

To reload DMS afterwards, kill its process and let your session supervisor
restart it. Avoid `dms restart`: it re-execs itself as a daemon child, and if a
supervisor also respawns one you end up with two shells and two stacked bars.

---

## Configuration

Everything is set in `.env` and can be overridden per-invocation:

```sh
CONN=DP-3 ./second-screen up
W=2388 H=1668 ./second-screen up      # iPad Air
AUTOCONNECT=0 ./second-screen up      # do not touch the tablet
```

See `.env.example` for the full list.

---

## Troubleshooting

**"the driver rejected 2160x1620"** — you are probably on an HDMI connector. See
*Why DisplayPort*. The error prints the modes the driver did offer; if they are
only 1024x768/800x600/640x480, the EDID's detailed timing was refused.

**"could not force the connector"** — debugfs is not mounted or not readable by
root: `mount | grep debugfs`.

**"WAYLAND_DISPLAY unset"** — run the command from inside the niri session, not
from a TTY or over plain SSH.

**The iPad is not found** — it may be asleep, or its address changed. Discovery
tries the cached address, then the ARP table, then a scan of the /24. Pin it with
`IPAD_HOST` in `.env` to skip all of that. The monitor comes up either way.

**Nothing after a reboot** — expected. Run `./second-screen up` again.

---

## Limitations

- **The monitor exists whether or not the iPad is connected.** niri will keep
  placing windows on it. Run `./second-screen down` when you are done.
- **One tap per connect.** RealVNC asks for confirmation on every `vnc://` URL
  and offers no way to disable it. If the client is already open it reconnects on
  its own and no tap is needed — that case is detected and no URL is pushed.
- **No transport encryption.** The server binds your LAN address, not 0.0.0.0.
  Do not port-forward it.
- **Resolution is fixed at creation time.** Changing it means `down`, edit,
  `up` — the EDID is regenerated each time.

---

## Layout

```
second-screen        entrypoint: up | down | toggle | status
lib/common.sh        configuration, logging, process helpers
lib/display.sh       DRM connector forcing, EDID, niri placement
lib/vnc.sh           the wayvnc server
lib/ipad.sh          device discovery and the connect push
mkedid.py            EDID generator
wayvnc.conf          wayvnc settings
dms-plugin/          optional DankMaterialShell bar button
```
