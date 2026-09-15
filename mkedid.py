#!/usr/bin/env python3
"""Generate a 128-byte EDID 1.4 blob for a virtual sink.

Used by niri-screen-up.sh to give a force-enabled DRM connector a mode the
iPad panel actually is (2160x1620). No cable is involved, so the timings only
have to be self-consistent and inside the GPU's limits; they are
CVT-reduced-blanking shaped.

    EW=2160 EH=1620 ER=60 python3 mkedid.py out.bin

Established timings for 640x480/800x600/1024x768 are included on purpose: if
the driver ever rejects the detailed timing, the connector still comes up with
*something*, which is what makes a rejection diagnosable instead of silent.

Pixel clock matters more than it looks. A connector with no CEA-861 extension
block is treated as DVI, and NVIDIA enforces the 165 MHz single-link DVI
ceiling: 2160x1620@60 needs 232 MHz and is rejected on HDMI-A-1, while the
same EDID on DP-1 is accepted. Verified both ways on 580.178.04 -- see
README.md. Use a DisplayPort connector.
"""
import sys

import os
HACT = int(os.environ.get('EW', 2160)); VACT = int(os.environ.get('EH', 1620)); REFRESH = int(os.environ.get('ER', 60))
HFRONT, HSYNC, HBACK = 48, 32, 80          # CVT-RB horizontal blanking = 160
VFRONT, VSYNC, VBACK = 3, 4, 38            # 4:3 -> vsync width 4; vblank = 45
HMM, VMM = 207, 155                        # 10.2" 4:3 panel

HBLANK = HFRONT + HSYNC + HBACK
VBLANK = VFRONT + VSYNC + VBACK
HTOTAL, VTOTAL = HACT + HBLANK, VACT + VBLANK
PCLK = HTOTAL * VTOTAL * REFRESH           # Hz
pclk10k = round(PCLK / 10000)

def mfg(code):
    v = 0
    for ch in code:
        v = (v << 5) | (ord(ch) - ord('A') + 1)
    return [(v >> 8) & 0xFF, v & 0xFF]

def dtd():
    d = [0] * 18
    d[0], d[1] = pclk10k & 0xFF, (pclk10k >> 8) & 0xFF
    d[2], d[3] = HACT & 0xFF, HBLANK & 0xFF
    d[4] = ((HACT >> 8) & 0xF) << 4 | ((HBLANK >> 8) & 0xF)
    d[5], d[6] = VACT & 0xFF, VBLANK & 0xFF
    d[7] = ((VACT >> 8) & 0xF) << 4 | ((VBLANK >> 8) & 0xF)
    d[8], d[9] = HFRONT & 0xFF, HSYNC & 0xFF
    d[10] = ((VFRONT & 0xF) << 4) | (VSYNC & 0xF)
    d[11] = (((HFRONT >> 8) & 3) << 6 | ((HSYNC >> 8) & 3) << 4
             | ((VFRONT >> 4) & 3) << 2 | ((VSYNC >> 4) & 3))
    d[12], d[13] = HMM & 0xFF, VMM & 0xFF
    d[14] = ((HMM >> 8) & 0xF) << 4 | ((VMM >> 8) & 0xF)
    d[15] = d[16] = 0                       # borders
    d[17] = 0x1E                            # digital separate, HSync+, VSync+
    return d

def desc(tag, payload):
    body = list(payload[:13]) + [0x0A] * (13 - len(payload[:13]))
    return [0, 0, 0, tag, 0] + body

def rng():
    # Range limits wide enough that the driver never rejects the DTD.
    return [0, 0, 0, 0xFD, 0, 50, 75, 30, 160, (pclk10k // 1000) + 1,
            0, 0x0A, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20]

e = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]      # header
e += mfg('IPD')                                            # manufacturer
e += [0x01, 0x00]                                          # product code
e += [0x01, 0x00, 0x00, 0x00]                              # serial
e += [1, 36]                                               # week 1, year 2026
e += [1, 4]                                                # EDID 1.4
e += [0x80]                                                # digital input
e += [round(HMM / 10), round(VMM / 10)]                    # size in cm
e += [0x78]                                                # gamma 2.2
e += [0x06]                                                # preferred timing mode
e += [0xEE, 0x91, 0xA3, 0x54, 0x4C, 0x99, 0x26, 0x0F, 0x50, 0x54]   # sRGB chroma
e += [0x21, 0x08, 0x00]                                    # est: 640x480@60, 800x600@60, 1024x768@60
e += [0x01, 0x01] * 8                                      # no standard timings
e += dtd()
e += rng()
e += desc(0xFC, b'iPad Virtual')                           # monitor name
e += desc(0x10, b'')                                       # dummy
e += [0x00]                                                # no extensions
assert len(e) == 127, len(e)
e.append((256 - (sum(e) % 256)) % 256)

open(sys.argv[1], 'wb').write(bytes(e))
print('%dx%d@%d  htotal=%d vtotal=%d  pclk=%.3f MHz (field %d)  checksum=0x%02X'
      % (HACT, VACT, REFRESH, HTOTAL, VTOTAL, PCLK / 1e6, pclk10k, e[-1]))
