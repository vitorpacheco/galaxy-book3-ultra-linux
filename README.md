# Samsung Galaxy Book3 Ultra on Linux (Omarchy)

Webcam driver and PipeWire/WirePlumber configuration for the **Samsung Galaxy
Book3 Ultra (NP960XFH)** on [Omarchy](https://omarchy.org) (Arch, kernel
`linux-omarchy` 7.2, PipeWire 1.6.8, WirePlumber 0.5.17, libcamera 0.7.2).

> 🇧🇷 Driver e configurações para a webcam (OV02C10 / Intel IPU6) do Galaxy
> Book3 Ultra no Omarchy: imagem na orientação certa, 26 MHz, cores corrigidas,
> câmera no PipeWire/navegadores/OBS. Veja "Install" abaixo.

Tested on one NP960XFH-XA1BR (Raptor Lake, Intel Iris Xe + RTX 4050).

## Result

- Internal camera works in PipeWire, Firefox/Zen, Chromium and OBS
  (1920x1080, 30 fps by default, 20 fps configured here).
- Image upright and not mirrored, neutral colors, auto exposure that works
  indoors.

## What was wrong

| Layer | Problem | Fix |
|---|---|---|
| Kernel `ov02c10` | Board clocks the sensor at **26 MHz**; the in-tree driver only accepts 19.2 MHz. The common community patch just widens the check, so the sensor runs 26/19.2 = 1.35x fast (40.7 fps), reports a 400 MHz link that is really 541.7 MHz and a wrong pixel rate. | `driver/`: report real pixel rate / link frequency, pad the frame to 30 fps (PLL tables unchanged, OmniVision's 26 MHz PLL values are not public). |
| Kernel `ov02c10` | Module is mounted **upside down and mirrored**, SSDB says rotation 0. | DMI quirk for `960XFH`: `rotation=180` + inverted HFLIP, libcamera flips the image. |
| Kernel `ov02c10` | libcamera's software ISP only drives analogue gain (max 15.5x): dark image indoors. | Analogue gain range continues into sensor digital gain (up to 62x). |
| Kernel `ov02c10` | No `get_selection()`: libcamera "sensor kernel driver needs to be fixed". | Implemented for the pixel array. |
| libcamera tuning | Community `ov02c10.yaml` CCM (green 0.92, red/blue 1.05) gives a **7% magenta cast**. | `tuning/ov02c10.yaml`: libcamera defaults (AWB + Adjust) + fixed black level. |
| WirePlumber 0.5.17 | libcamera monitor node never finishes activation: camera listed but nothing links to it. | Camera node created by PipeWire (`user/pipewire/...`), libcamera monitor disabled. |
| WirePlumber 0.5.17 | Disabling the IPU6 V4L2 device with a rule **stalls the event dispatcher** (no audio, no camera at all). | V4L2 monitor disabled instead (`90-camera-monitors.conf`). |
| WirePlumber 0.5.17 | Streams without a media type (`Stream/Input/Unknown`, e.g. GStreamer `pipewiresrc`) never get a target. | Patched `create-item.lua`. |
| libcamera GPU ISP | Debayer fails on NVIDIA EGL (`glFramebufferTexture2D` error). | PipeWire/WirePlumber forced to Mesa EGL. |
| Autologin | WirePlumber/PipeWire start before logind grants access to `/dev/media0`; libcamera never retries. | Wait for the ACL in `ExecStartPre`. |
| Firefox/Zen | Opens raw V4L2 nodes (Bayer data) and blocks the device. | `media.webrtc.camera.allow-pipewire=true`. |

### Optional: dead analog audio

My unit's ALC298 analog codec is broken: any open of its PCMs blocks in
`snd_hdac_bus_get_response` and hangs PipeWire/WirePlumber. `--no-analog-audio`
hides it (`snd_sof_intel_hda codec_mask=4`, keeping HDMI, the DMIC microphones
and Bluetooth). **Do not use it on a working laptop: it disables the speakers
and headphone jack.**

## Install

Requirements: `dkms`, headers for your kernels (`linux-omarchy-headers`),
`libcamera`, `pipewire-libcamera`, `wireplumber` 0.5.17.

```sh
git clone https://github.com/vitorpacheco/galaxy-book3-ultra-linux
cd galaxy-book3-ultra-linux
sudo ./install-system.sh        # add --no-analog-audio only for a dead codec
./install-user.sh               # same flag here if used above
reboot
```

Firefox/Zen: add `user/zen/user.js` to your profile or set
`media.webrtc.camera.allow-pipewire` in `about:config`. OBS: use the
"Video Capture Device (PipeWire)" source with an **ABGR8888** format
(XBGR8888 renders black in OBS).

### Driver options

`/etc/modprobe.d/ov02c10.conf`, `options ov02c10 ...`:

| Option | Default | |
|---|---|---|
| `frame_rate=5..30` | 30 (20 in this repo) | Lower = longer exposure, less gain and noise. Apps can't select a frame rate: PipeWire's libcamera plugin doesn't expose one. |
| `gain_boost=1..16` | 4 | Extra digital gain range, 1 disables. |
| `analog_gain_max=16..248` | 248 | Switch to digital gain above this analogue gain code. |
| `rotation=0\|180`, `mirror=0\|1` | auto | Override the DMI quirk. |
| `true_link_freq=0` | 1 | Report the nominal 400 MHz link frequency again. |

Try options without installing: `cd driver && make && sudo ./test-load.sh frame_rate=15`.

## Notes

- WirePlumber upgrades: `create-item.lua` is a patched copy of the 0.5.17
  script; re-apply the change on top of the new version.
- USB webcams won't show up in PipeWire while the V4L2 monitor is disabled.
- `tools/pwcount.c` counts frames a PipeWire client receives
  (`gcc -o pwcount pwcount.c $(pkg-config --cflags --libs libpipewire-0.3)`).
  GStreamer's `pipewiresrc` sometimes stops after a few frames on format
  renegotiation; native PipeWire clients (browsers, OBS) don't.
- A single `csi2-0 error: Frame sync error` when a stream starts is expected.

## License

`driver/` is GPL-2.0 (derived from the Linux kernel driver).
`user/wireplumber/scripts/` is MIT (derived from WirePlumber). Everything else
is CC0-1.0.

## Kernel patches

`kernel-patches/` has the driver changes as a clean series against Linux
7.2.5 (`drivers/media/i2c/ov02c10.c`), in the format used by
[omarchy-pkgs `linux-omarchy`](https://github.com/omacom/omarchy-pkgs/tree/master/pkgbuilds/linux-omarchy):

- `0544` media: ov02c10: support a 26 MHz external clock
- `0545` media: ov02c10: add Samsung Galaxy Book3 Ultra mounting quirk
- `0546` media: ov02c10: implement get_selection()

The DKMS driver in `driver/` is this series plus the tuning options
(`frame_rate`, `gain_boost`, `analog_gain_max`), which are not suitable for
upstream.
