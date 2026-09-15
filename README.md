# iPad second screen

Two working setups, both built and verified 2026-09-15 on `x570`.

**Rung 2 is the one you want.** It gives the live niri session a real second
monitor — drag windows to it, move workspaces to it, same keybinds, same
clipboard — and it turned out to need **no kernel parameters, no initramfs
rebuild and no reboot**. It is two
writes into sysfs/debugfs plus a `wayvnc` process, and a reboot erases it.

**Rung 1** is a headless `sway` beside niri. It does *not* extend the desktop:
windows cannot be dragged to it, you launch apps onto it explicitly. It is kept
because it needs no root at all and it is the fallback if a driver update ever
breaks connector forcing.

| | rung 1 (sway) | rung 2 (niri) |
|---|---|---|
| extends the niri desktop | no | **yes** |
| drag windows to it | no | **yes** |
| needs root | no | yes (sysfs + debugfs) |
| survives reboot | n/a, just re-run | no, re-run the script |
| measured | 29.5 fps, 12.9 Mbit/s | **30.1 fps, 16.1 Mbit/s** |
| CPU while streaming | sway 2.7 % + wayvnc 5.3 % | niri 2.4 % + wayvnc |
| renderer | pixman (software, forced) | GPU, niri's own |
| port | 5900 | 5901 |

Both can run at once.

---

# Rung 2 — a real second monitor for niri

```sh
./niri-screen-up.sh                              # DP-1 @ 2160x1620, right of DP-2
CONN=DP-3 POS_X=-2160 ./niri-screen-up.sh        # different connector / side
./niri-screen-down.sh                            # release it
niri msg action move-window-to-monitor DP-1      # send the focused window over
```

Then point the iPad VNC client at **10.0.0.10:5901**.

The output is placed **centred below the Dell** by default — the Dell is
2560x1440 logical at 0,0 and the iPad is 1080 logical wide at scale 2, so
(2560-1080)/2 = 740, giving `740,1440`. Push the cursor off the bottom middle of
the Dell and it lands on the iPad. Override with `POS_X` / `POS_Y`.

## Install

```sh
./fetch-novnc.sh          # only if you want the browser client (WEB=1)
./dms-plugin/install.sh   # the DankBar button, if you run DankMaterialShell
```

Host-specific values are environment variables with defaults for this machine —
`BIND` (10.0.0.10), `CONN` (DP-1), `POS_X`/`POS_Y`, `W`/`H`/`SCALE`. The iPad's
address is discovered, not configured.

Requires `sway`, `wayvnc`, `python3`, and a jailbroken iPad reachable by SSH key
for the auto-connect. Root is needed only for the two sysfs/debugfs writes.

## DankBar button

A DMS plugin toggles all of this from the bar:
`~/.config/DankMaterialShell/plugins/ipadScreen/`.

- **left click** — toggle (down -> up, anything else -> down)
- **right click** — force down
- icon state: muted tablet = down, amber tablet = up but nothing connected,
  `cast_connected` + "iPad" = a client is attached

Clicking it brings up the monitor and tells the iPad to connect.

## How the iPad side works

**RealVNC Viewer is the client.** `niri-screen-up.sh` finishes by SSHing into the
iPad over Wi-Fi and running `uiopen --url 'vnc://10.0.0.10:5901'`. RealVNC
registers the scheme (`com.realvnc.VNCViewer` 4.9.4; the binary carries the
format string `vnc://%@:%ld`), so no UI automation is involved.

**It costs one tap per toggle, and that is not removable.** RealVNC gates every
`vnc://` URL behind *"Continue connecting?" / "You are attempting to connect to
%@." / [Cancel] [OK]*. The binary contains
`dialog_connect_url_{title,body,button_ok,button_cancel}` and nothing resembling
a "don't ask again" flag. It is not the unencrypted-connection warning, so
enabling auth does not help. RealVNC also does not auto-retry when the server
goes away, so a toggle always ends in a push and therefore a tap.

It is worth it: RealVNC hides the iPad status bar and the 2160x1620 framebuffer
maps 1:1 onto the 4:3 panel — genuinely full screen, no wasted pixels — and it
runs at **19.23 Mbit/s** versus noVNC's 7.18 on the same content.

`niri-screen-up.sh` still waits `AUTOCONNECT_WAIT` (10) seconds before pushing,
in case a client comes back by itself; if one does, no URL is sent and no tap is
needed.

### The browser alternative: tapless, but letterboxed

`WEB=1 CLIENT=web ./niri-screen-up.sh` starts two more services and points the
iPad at noVNC instead:

| port | what |
|---|---|
| `5901` | raw RFB — RealVNC (always on) |
| `5902` | `wayvnc --websocket`, same output (WEB=1 only) |
| `6080` | bundled noVNC, `vendor/novnc` v1.6.0 (WEB=1 only) |

`--websocket` makes a listener WebSocket-*only*, so it is a second wayvnc
instance rather than a flag on the first.

Loaded as a Home Screen web app (Safari → Share → Add to Home Screen; noVNC ships
`apple-mobile-web-app-capable=yes` and iOS icons) it has one real advantage:
`autoconnect=true&reconnect=true&reconnect_delay=2000` means it reconnects by
itself on every toggle, **verified over two consecutive cycles with the iPad
untouched**. Zero taps, ever.

The reason it is not the default: **a web app cannot hide the iPad status bar.**
The usable viewport is the panel minus that bar, so it is no longer exactly 4:3
and `resize=scale` letterboxes the image. You lose pixels at the top and on two
sides, and a third of the bandwidth advantage.

### Dead ends, recorded so they are not retried

- **`uiopen` cannot launch a Home Screen web app.** iOS 18 installs one as a real
  bundle under `/var/containers/Bundle/Application`, but with **no executable**
  and `LSApplicationLaunchProhibited: true`. `--bundleid`, `--app` and `--path`
  all exit 0 and do nothing; `uicache -i` reports `Executable Name: (null)`.
- **Removing that flag does not help.** Patched the Info.plist as root,
  re-registered with `uicache -p`, no change — then reverted. The bundle still
  has no executable; SpringBoard drives these through its own API, which no
  on-device CLI exposes (`sbdidlaunch` only notifies).
- **Hand-writing a `.webclip` does not register anything.** On iOS 18 the
  `.webclip` is only the data half of a real `installd` install; `uicache -i`
  rejects a hand-made one as an invalid bundle id.
- **Shortcuts cannot bridge it.** `shortcuts://run-shortcut?name=` *is* reachable
  from `uiopen`, but the *Open App* picker uses the same LaunchServices filter
  and does not list web apps.
- **No touch injection exists.** The device repos carry only tweaks, no CLI that
  posts HID events, so the tap cannot be delivered without WebDriverAgent — which
  needs USB to start.

### Other iPad-side facts

- **The iPad's sshd is reachable over Wi-Fi.** Everything in `../tools/` forwards
  port 22 through `usbmuxd` because *usbmuxd* has no Wi-Fi support on Linux — but
  the device's own sshd listens on all interfaces. `ssh mobile@10.0.0.20`
  works with the existing key and no cable. That is what makes any of this work.
- **`uiopen` requires `--url`.** With the URL as a bare argument it exits 0 and
  launches the app while silently dropping the URL — it looks exactly like a
  broken URL scheme and is not one.
- The iPad's address is resolved by cache (`run/ipad-host`), then its MAC in the
  ARP table, then a port-22 sweep of the /24 — each candidate confirmed by
  checking it has `/var/jb/usr/bin/uiopen`, so a random sshd cannot be mistaken
  for the tablet. The MAC is a hint only: iOS rotates its private Wi-Fi address.

`AUTOCONNECT=0` disables the push entirely.

It shells out to `ipad-toggle.sh`, which is the same state machine you can drive
by hand:

```sh
./ipad-toggle.sh status    # down | up | connected  (also exit code 0 | 1 | 2)
./ipad-toggle.sh toggle
```

Two things bit while building it, both worth remembering:

- **Do not use `dms restart` in this session.** DMS's restart (and `SIGUSR1`)
  re-execs itself as `dms run -d --daemon-child`, while `~/.local/bin/x570-session-shell`
  *also* supervises and respawns its own `dms run`. The result is two shells and
  **two stacked bars**. To reload, kill the supervised `dms run` (the one whose
  parent is `x570-session-shell`) and let the supervisor bring it back.
- **`Proc.runCommand` debounces by id, and DankBar builds one widget instance per
  screen.** With a fixed id (`"ipadScreen.status"`) the two instances' polls
  collapse into one and only one bar ever updates — visible as the Dell showing
  "connected" while the iPad's own bar showed a stale icon. The id is now keyed to
  `parentScreen.name`.

Note the bar config is `screenPreferences: ["all"]`, so the iPad screen gets its
own full DankBar. On a 1080x810 logical screen that costs real estate; set that
bar to specific screens if you would rather it stayed on the Dell.

## How it works, and why it is so cheap

The kernel exposes a connector's detected state as a *writable* file:

```sh
echo on > /sys/class/drm/card0-DP-1/status
```

and debugfs lets you hand that connector an EDID that no cable ever carried:

```sh
cat edid.bin > /sys/kernel/debug/dri/0/DP-1/edid_override
```

**NVIDIA 580.178.04 honours both at runtime.** That was the open question in
the obvious question, and the answer makes the kernel-parameter approach —
`video=DP-1:e drm.edid_firmware=...` in the bootloader, a dracut config, three
initramfs rebuilds and a reboot — unnecessary. `mkedid.py` generates the EDID
(2160×1620, the iPad 8 panel); `niri-screen-up.sh` does the two writes, places
the output in niri, and starts `wayvnc -o DP-1`.

## Use DisplayPort, not HDMI — this is not arbitrary

An EDID with no CEA-861 extension block makes the driver treat the connector as
**DVI**, and NVIDIA enforces the 165 MHz single-link DVI ceiling. Measured on
this machine:

| connector | mode | pixel clock | result |
|---|---|---|---|
| HDMI-A-1 | 1920×1080@60 | 140.4 MHz | **accepted** |
| HDMI-A-1 | 2160×1620@60 | 231.8 MHz | rejected — only 1024×768/800×600/640×480 offered |
| HDMI-A-1 | 2160×1620@42 | 162.2 MHz | **accepted** |
| HDMI-A-1 | 2160×1620@40 | 154.5 MHz | **accepted** |
| DP-1 | 2160×1620@60 | 231.8 MHz | **accepted** |

The 40/42 Hz results are what pin the cause to the clock rather than the
resolution. DisplayPort has no such ceiling, and `card0` has **three** free DP
connectors (DP-1, DP-3, DP-4). `niri-screen-up.sh` warns if you point it at an
HDMI port.

The EDID includes established timings for 640×480/800×600/1024×768 deliberately:
if a detailed timing is ever rejected the connector still comes up, which is
what made the table above possible instead of a silent failure.

## Rung 2 costs

- **No packages beyond the five rung 1 already installed.**
- **No persistent system changes at all.** No bootloader, no initramfs, no
  `/lib/firmware`, no services, no `/etc`. A reboot returns the machine to
  exactly its previous state — which also means you re-run the script after one.
- **Root is needed** for the two writes. The scripts take `SUDO_PWD` from
  `~/.secrets` and pass it on **stdin** (`sudo -S -p ''`), never in argv.
- `~/.config/niri/monitor.kdl` is *not* touched. Output placement is applied at
  runtime with `niri msg output`. Note that if you run `nwg-displays` while the
  forced output is up, it will write a `DP-1` block into that file, which then
  persists — delete it if you do not want it.

## Rung 2 usability notes

- It is a real monitor to niri, so it behaves like one in every respect —
  including when the iPad is **not** connected. The output still exists and niri
  will still place windows there. Run `./niri-screen-down.sh` when you are done
  rather than leaving a blind monitor attached.
- Resolution is fixed by the EDID, so changing it means re-running the script
  (which regenerates the EDID). Rung 1 changes with an env var.
- Latency and input are identical to rung 1 — same `wayvnc`, same RFB.

---

# Rung 1 — headless sway

## Use

```sh
./screen-up.sh                 # start (2160x1620 @ scale 2, matches the iPad panel)
./screen-run.sh foot           # launch an app onto the iPad screen
./screen-status.sh             # what is running, what is on screen
./screen-down.sh               # stop, leave packages installed
./uninstall.sh                 # stop + remove the 5 packages + generated state
```

Then on the iPad, point any VNC client at **10.0.0.10:5900**.
RealVNC Viewer (free, App Store) is the reference client; App Store apps do not
consume one of the three free developer slots, so this costs nothing against
the `resign.sh` budget.

Overrides, all env vars on `screen-up.sh`:

| var | default | note |
|---|---|---|
| `W` / `H` | `2160` / `1620` | iPad 8 native panel |
| `SCALE` | `2` | logical desktop becomes 1080x810 |
| `FPS` | `30` | software renderer; see below |
| `BIND` | `10.0.0.10` | the LAN address, never `0.0.0.0` |
| `PORT` | `5900` | |

## Measured

All numbers from a raw RFB client written for the purpose, streaming a
continuously-updating terminal for 15 s:

```
2160x1620  15.0s  frames=443 (29.5 fps)  rects=16751  bytes=23.1 MiB  12.93 Mbit/s
```

- **29.5 fps** against a 30 fps cap — the cap is the limit, not the machine.
- **12.9 Mbit/s** with ZRLE. Comfortable on Wi-Fi.
- **sway 2.7 % CPU / 71 MiB, wayvnc 5.3 % CPU / 49 MiB** while streaming.

Input was verified in both directions, not assumed:

- **Keyboard** — RFB `KeyEvent`s for `hello-from-ipad` plus Return were sent to
  the server; the shell running in the captured window read back
  `GOT:[hello-from-ipad]`.
- **Pointer** — an RFB `PointerEvent` to (1500, 1200) was followed by a frame
  capture: 10 distinct colours in a 28x28 box at that coordinate, 1 distinct
  colour in the same-sized box elsewhere on the same row. The cursor is where
  it was told to be.

## `WLR_RENDERER=pixman` is required, not a preference

With the default `gles2` renderer on the headless backend, wayvnc's capture
returns a **uniform `#606060` frame**. This was verified rather than guessed:
with a window demonstrably mapped and focused on the output, a full-framebuffer
RFB capture of all 2160x1620 pixels contained exactly **one** distinct colour.
The identical test under `WLR_RENDERER=pixman` returns the real desktop. The
launcher therefore sets pixman, and that is also why `FPS` defaults to 30.

`run/wayvnc.log` still shows this line on every client connect:

```
ERROR: ../src/ext-image-copy-capture.c: 448: No supported buffer formats were found
```

It is cosmetic. wayvnc 0.9.1 tries `ext-image-copy-capture-v1` first, finds no
usable buffer format on the headless backend, and falls back to
`zwlr-screencopy-v1`, which works — the measurements above were taken with this
error present in the log.

## Containment

Five packages were added: `sway`, `swaybg`, `wayvnc`, `neatvnc`, `aml` —
6.4 MB installed. `wlroots0.20`, `seatd` and `libdrm` were already present, so
nothing was upgraded. Beyond that:

- **No runit services.** Nothing starts at boot.
- **No kernel parameters, no reboot, no DRM, no seat, no TTY.** The headless
  wlroots backend is pure userspace under uid 1000.
- **No files outside this directory.** `XDG_CONFIG_HOME` is pinned to
  `./xdg`, sway is launched with an explicit `-c`, and both IPC sockets live in
  `./run`. `~/.config/sway` and `~/.config/wayvnc` are never created.
- **The niri session is untouched.** Sway is a sibling compositor on its own
  `$WAYLAND_DISPLAY`; niri keeps `wayland-1` and DP-2.

`./uninstall.sh` reverses all of it, then `rm -rf` this directory finishes the
job.

## Gotchas worth keeping

- **Sway offers no flag to choose its wayland socket name.** It uses
  `wl_display_add_socket_auto()`. Reading `/proc/$PID/environ` to discover the
  name fails too — sway sets `PR_SET_DUMPABLE=0`, which reparents those `/proc`
  entries to root, so the read returns `Permission denied` even for the owning
  user. `screen-up.sh` instead asks sway to report it, by running a child
  through sway's own IPC that prints the environment it inherited.
- **`pgrep -f` matches the script's own command line.** Liveness checks here
  compare PIDs from `run/*.pid` with `kill -0`.
- **RFB has no transport encryption here.** `BIND` is the LAN address on
  purpose. Do not port-forward 5900 or 5901.
- **`$!` after `setsid` is not the pid you want.** `setsid` forks when the
  caller is already a process-group leader, and the grandchild's pid is never
  reported back. This bit for real: a teardown deleted the pidfile while the
  actual `wayvnc` kept running and kept port 5901 bound. Both teardown scripts
  now treat the pidfile as a hint and fall back to resolving the process by a
  marker unique to the launch (its `--socket` path, or sway's `-c` config path),
  scanning `/proc/*/cmdline` directly — which, unlike `pgrep -f`, cannot match
  the calling script.

## What this rung does not give you

Extending the actual niri desktop. Use rung 2 above for that — it turned out to
cost less than this one in every way except needing root.
