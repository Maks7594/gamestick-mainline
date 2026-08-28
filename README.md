# Mainline Linux on the H133 Game Stick

Alpine 3.24 on mainline Linux 6.18.39, running on an undocumented Allwinner
T113-s3 HDMI dongle. Both CPU cores, HDMI via DRM/KMS at 1920x1080, HDMI audio,
Wi-Fi, and an SSH shell.

The board ships Android-ish vendor firmware on a 5.4 BSP kernel. Nothing here
uses the vendor kernel: this is upstream Linux plus three patches and a board
DTS, booted by the vendor's own U-Boot out of the existing Android boot
partition.

For the blow-by-blow record of how this was reached, including the dead ends,
see [`docs/HISTORY.md`](docs/HISTORY.md). That file is a lab notebook and
contradicts itself in places; this file is the truth about the current build.

---

## Status

| Subsystem | State | Notes |
|---|---|---|
| Boot | works | vendor U-Boot -> Android boot image in p4 -> mainline |
| CPU | **2 cores** | 2x Cortex-A7 @ 1.008 GHz, stable under load |
| RAM | works | 256 MiB, ~243 MiB usable, 64 MiB reserved for CMA |
| MMC / SD | works | root on `mmcblk0p5`, ~59.5 GB ext4 |
| HDMI video | works | DRM/KMS, 1920x1080 console, ported D1 PHY |
| HDMI audio | works | **48 kHz only** |
| USB | works | EHCI/OHCI, 4 buses, hubs and HID enumerate |
| Wi-Fi | works | RTL8188ETV via mainline `rtl8xxxu` |
| Watchdog | works | provides the restart handler; `reboot` works |
| Crash logs | works | ramoops/pstore, survives *some* resets - see below |
| X11 | works | `modesetting` on KMS, pinned to 1280x720 |
| Video playback | partial | 640x360 software decode is smooth; no hardware decode |
| CPU hotplug | **disabled** | vendor PSCI `CPU_OFF` hangs the machine |
| Hardware video decode | **unavailable** | Cedrus cannot claim SRAM on this SoC |
| RTC | not enabled | SoC has `rtc@7090000`, `CONFIG_RTC_CLASS` is off |
| Serial console | **none** | UART pads never located on this board |

### Known limitations

- **No UART.** UART0 is PB8/PB9 in the vendor DT, but the pads have never been
  identified on this board and the vendor never answered a public question
  about them. Every diagnosis here was made without a serial console, which is
  why the display is used as the debug channel throughout.
- **Warm reset is unreliable.** `reboot` usually works, but boot0 re-runs DRAM
  init against a live controller and the result is a coin flip between
  preserved memory, corrupted memory, and a hang before the kernel is entered.
  Do not build anything that depends on DRAM surviving a reset.
- **Audio is 48 kHz only.** `pll-audio1` is fixed at 3072000000 and nothing
  reconfigures it per stream, so 32000 and 44100 fail with `EINVAL` even though
  the PCM advertises `RATE: [32000 48000]`. This also breaks `plughw`, which
  picks 44100 as "nearest" and hands it to hardware that cannot do it. Force
  48 kHz (`--audio-samplerate=48000`).
- **No hardware video decode.** `sunxi_sram_claim()` needs an `allwinner,sram`
  property pointing at an SRAM section node, and mainline's
  `sun20i_d1_sramc_variant` defines no sections. Cedrus is not a matter of
  picking a compatible string.

---

## Hardware

| | |
|---|---|
| SoC | Allwinner T113-s3 (`sun8iw20p1`), 2x Cortex-A7 |
| CPU clock | 1,008,000,000 Hz (read from `clk_summary`; rated 1.2 GHz) |
| DRAM | 256 MiB at `0x40000000` |
| Status LED | PB12 |
| UART0 | PB8/PB9 per vendor DT; **pads not located** |
| Wi-Fi | RTL8188ETV, USB `0bda:0179` |
| Boot media | removable SD card, GPT disk id `AB6F3888-569A-4926-9668-80941DCB40BC` |

> **Always identify the card by GPT disk id, never by device name.** It has
> enumerated as both `/dev/sdc` and `/dev/sdd` depending on what else is
> plugged in. On the development host `/dev/sdb2` is the root filesystem and
> must never be written.
>
> ```sh
> lsblk -dno PATH,PTUUID | awk 'tolower($2)=="ab6f3888-569a-4926-9668-80941dcb40bc"{print $1}'
> ```

### Partition layout

| Part | Size | Contents |
|---|---|---|
| p1 | 1 MiB | `boot-resource` (vendor, untouched) |
| p2 | 252 KiB | `env` (vendor, untouched) |
| p3 | 252 KiB | `env-redund` (vendor, untouched) |
| p4 | 6,451,200 B | Android boot image - **this is what gets flashed** |
| p5 | ~59.5 GB | Alpine root, ext4, read-write |

The raw bootloader region (sectors 4-41463) holds boot0 and U-Boot and is not
touched by any procedure here.

### Boot chain

```
vendor boot0  ->  vendor U-Boot  ->  Android boot image v0 (p4)
                                       -> zImage + appended DTB
                                       -> Alpine on p5
```

The boot image is Android header v0, base `0x40000000`, kernel offset `0x8000`,
page size 2048, board `h133-p2nor`. U-Boot cannot patch an appended DTB, so
anything U-Boot would normally inject (memory reservations, `disp_reserve`)
must be written into the DTS by hand.

U-Boot leaves a framebuffer running at **`0x4bee8c40`, 1280x720x32, stride
5120**. That is `disp_reserve`'s `0x4bee8c00` plus `0x40`; the raw address
produced console lines rotated left by two characters.

---

## Build

Everything is built inside the Arch VM (`~/archvm.sh` on the host, then
`ssh mcvm`).

| | |
|---|---|
| Kernel source | `~/gamestick-shit/gamestick-mainline/src/linux-6.18.39` |
| Build directory | `~/gcc14-test/build-hdmi` |
| Project copy | `~/gcc14-test/{kernel,dts,scripts}` |
| Kernel compiler | `arm-linux-gnueabihf-` (Debian GCC 14.2.0, via Bedrock) |
| Userspace compiler | `~/armv7-toolchain` (crosstool-NG, armv7 musl) |

```sh
# on the VM
cd ~/gcc14-test
JOBS=6 sh kernel/build-kernel.sh \
  /home/user/gamestick-shit/gamestick-mainline/src/linux-6.18.39 \
  /home/user/gcc14-test/build-hdmi \
  arm-linux-gnueabihf-

sh scripts/make-android-boot.sh \
  build-hdmi/artifacts/zImage \
  build-hdmi/artifacts/sun8i-t113s-h133-game-stick.dtb \
  ~/gcc14-test/boot-new.img
```

`build-kernel.sh` runs `allnoconfig`, merges `kernel/game-stick.fragment`, then
`olddefconfig`. Validate the result before flashing:

```sh
sh kernel/validate-config.sh /path/to/kernel.config
```

The kernel compiler matters: GCC 14.2.0 is known good. An earlier GCC 16.1 was
suspected of miscompiling and then exonerated, but 14.2.0 is what everything
here is built and tested with.

---

## Flash

### Over SSH (preferred)

Only possible when the stick boots and reaches the network.

```sh
scp -i ~/.ssh/gamestick_ed25519 boot-new.img user@gamestick:/tmp/
ssh -i ~/.ssh/gamestick_ed25519 user@gamestick '
  doas dd if=/tmp/boot-new.img of=/dev/mmcblk0p4 bs=1M conv=fsync status=none
  doas sync
  sz=$(stat -c %s /tmp/boot-new.img)
  doas dd if=/dev/mmcblk0p4 bs=1 count=$sz status=none | sha256sum'
```

Always compare the readback hash against the image. **Never** write to any
partition other than p4 this way.

### Via the card reader (recovery)

The only route when the stick will not boot. There is no FEL/USB recovery on
this board - the micro-USB and USB-A ports do not enumerate for it - but the
bootloader lives on a removable card, so the reader *is* the recovery path.

```sh
dev=$(lsblk -dno PATH,PTUUID | awk 'tolower($2)=="ab6f3888-569a-4926-9668-80941dcb40bc"{print $1}')
[ -n "$dev" ] || { echo "card not found"; exit 1; }
sudo dd if=boot-new.img of="${dev}4" bs=1M conv=fsync status=none
sudo sync
```

Verify the readback hash, then `sudo udisksctl power-off -b "$dev"`.

The USB-C reader in use is orientation-sensitive and only enumerates one way
round. A write that fails partway (`Input/output error`) leaves p4 corrupt -
just retry and re-verify.

### Known-good images

`artifacts/` holds every flashed build. Useful fallbacks:

| Image | What it is |
|---|---|
| `boot-2core-v71.img` | **current** - two cores, diagnostics stripped |
| `boot-cntvoff-v70.img` | first two-core build, diagnostics still in |
| `boot-audiohub-v57.img` | last single-core build with working audio |
| `boot-userns-v52.img` | pre-DRM, `simple-framebuffer` console |

---

## Kernel configuration

`kernel/game-stick.fragment` is merged onto `allnoconfig`. Resolving on an
all-disabled baseline stops leftover child-board symbols from selecting OMAP,
QCOM, Tegra and friends back on, but it has a serious cost:

> **`allnoconfig` silently drops `default y` infrastructure.** Eight symbols
> have been lost this way and each one produced a confusing downstream failure:
> `PM`, `REGULATOR`, `HID`, `WATCHDOG`, `COMPAT_32BIT_TIME`, `INOTIFY_USER`,
> `SYSVIPC`, `DMADEVICES`.

Two more were dropped not by `allnoconfig` but by **menu gating** - the parent
menu was off, so `merge_config` discarded everything under it without warning:

- `MISC_FILESYSTEMS=y` gates `PSTORE`
- `DEBUG_KERNEL=y` gates `SOFTLOCKUP_DETECTOR` and `DETECT_HUNG_TASK`

Load-bearing choices:

| Symbol | Why |
|---|---|
| `THUMB2_KERNEL=n` | vendor PSCI jumps in ARM state; a Thumb entry point makes the address odd and CPU1 faults |
| `HOTPLUG_CPU=n` | vendor PSCI `CPU_OFF` hangs the machine; this makes the path unreachable |
| `ARM_APPENDED_DTB=y` | U-Boot supplies no usable DTB |
| `CMDLINE_FORCE=y` | ignore stale vendor bootargs |
| `KERNEL_XZ=y` | keeps zImage + DTB inside p4's 6,451,200 bytes |
| `CMA_SIZE_MBYTES=64` | 32 was too small - a 1080p buffer is 8.3 MB and mpv failed with "Cannot create dumb buffer" |
| `REGULATOR=y` | supplies MMC's OCR voltage mask - see below |
| `DMADEVICES=y`, `DMA_SUN6I=y` | i2s cannot get DMA channels without it |
| `DRM_SIMPLEDRM=n` | `FB_SIMPLE` depends on `!DRM_SIMPLEDRM`, keeping simplefb as a fallback |
| `FONT_TER16x32` | 1080p console is unreadable at 8x16 |

Current command line:

```
console=ttyS0,115200 console=tty0 earlycon clk_ignore_unused pd_ignore_unused
root=/dev/mmcblk0p5 rootfstype=ext4 rootwait rw fbcon=font:TER16x32
```

`clk_ignore_unused` is not optional: without it the clock framework culls the
DE/TCON/HDMI clocks U-Boot left running and the display dies mid-boot. The
vendor bootargs carry it for the same reason.

### Module vermagic

`CONFIG_THUMB2_KERNEL` changes module vermagic (`ARMv7 thumb2 p2v8` vs
`ARMv7 p2v8`). **Kernel and modules are a matched pair - flash both together.**

---

## Patches

`kernel/patches/`, applied to a pristine 6.18.39 tree.

| Patch | Purpose |
|---|---|
| `0001-drm-sun4i-add-D1-T113-HDMI-PHY.patch` | the HDMI PHY driver mainline lacks |
| `0002-ASoC-sun4i-i2s-internal-audio-hub.patch` | routes I2S TX to the internal audio hub |
| `0003-arm-psci-log-cpu_on-return.patch` | logs the PSCI `CPU_ON` return value |

### 0001 - the HDMI PHY

Less was missing upstream than early notes claimed. The DE2 mixers, TCON-LCD/TV
and TCON-TOP are all present in `sunxi-d1s-t113.dtsi`, and `ccu-sun20i-d1.c`
already implements `CLK_BUS_HDMI`, `CLK_HDMI_24M`, `CLK_HDMI_CEC` and
`RST_BUS_HDMI_{MAIN,SUB}`. Only two things were absent: the PHY driver and the
DT nodes.

The D1/T113 does not use the Synopsys PHY that `sun8i_hdmi_phy.c` handles for
the A83T and H6. Samuel Holland wrote a driver for the custom one in 2022 and
never upstreamed it - `smaeul/linux` branch `d1/hdmi-support`, commit titled
`[HACK] drm/sun4i: Copy in BSP code for D1 HDMI PHY`. That is why it never
landed: BSP register pokes against a header of magic bitfield offsets. This
patch forward-ports it to 6.18. `dw_hdmi_phy_ops` and `phy_force_vendor` did
not drift between 6.2 and 6.18, so only the D1 additions were carried across.

The node also needed `devm_clk_get_optional()` for `tmds`: there is no TMDS
clock on this HDMI node because the PHY makes its own from its PLL.

Result: `Detected HDMI TX controller v2.12a with HDCP (sun8i_dw_hdmi_phy)`.

### 0002 - HDMI audio

Bit 31 (`HUB_EN`) of the I2S FIFO control register (`0x14`) routes TX into the
SoC's internal audio hub, which is what feeds the HDMI controller. The DT opts
in with `allwinner,tx-hub-en`. Verified by register read during playback:
`0x14 = 800400f5`.

---

## Device tree

`dts/sun8i-t113s-h133-game-stick.dts` includes upstream `sun8i-t113s.dtsi` and
adds only what the board needs. Every addition and why:

### The timer - this is what gives us two cores

```dts
/ {
	timer {
		arm,cpu-registers-not-fw-configured;
		clock-frequency = <24000000>;
	};
};
```

The vendor firmware leaves **`CNTVOFF` uninitialised on the secondary core**.
Linux reads the virtual counter, `CNTVCT = CNTPCT - CNTVOFF`, so the two cores
disagree about what time it is - by a constant ~7481 seconds on this board.
`ktime_get()` then returns a different answer depending on which CPU calls it,
and every timer deadline, scheduling decision and printk timestamp becomes
unreliable the moment CPU1 joins.

This property makes `arm_arch_timer` use the **physical** counter, which has no
per-core offset. `sun6i-a31`, `sun8i-a23-a33` and `sun9i-a80` all carry it for
the same reason. Confirmation is one word in the boot log:

```
arch_timer: cp15 timer running at 24.00MHz (phys).
```

`CNTVOFF` is writable only from HYP mode. The kernel does try -
`secondary_startup` calls `__hyp_stub_install_secondary`, which zeroes it - but
this firmware enters Linux in SVC, so that path never runs.

`clock-frequency` is required because the property means `CNTFRQ` cannot be
trusted either. 24 MHz matches `&dcxo` in the SoC dtsi and was checked against
the host clock afterwards (20.02 s measured on the stick for a 20.0 s interval).

### `/chosen` and the framebuffer

```dts
chosen {
	#address-cells = <1>;
	#size-cells = <1>;
	ranges;
	framebuffer0: framebuffer@4bee8c40 { ... };
};
```

All three properties are mandatory. `#address-cells` and `#size-cells` do
inherit from the root, but **`ranges` does not**, and without it
`of_translate_one()` refuses to translate at all - `reg` never becomes a
resource and simplefb fails with `No memory resource` / `-22`.

The matching reservation must be **page-aligned at both ends**:

```dts
fb_reserved: framebuffer@4bee8000 {
	reg = <0x4bee8000 0x385000>;
	no-map;
};
```

ARM's `ioremap` checks `memblock_is_map_memory(PFN_PHYS(pfn))` - the *page*
containing the address. Reserving from the unaligned `0x4bee8c00` left
`0x4bee8000-0x4bee8c00` mapped as ordinary RAM, the check saw mapped memory,
and `ioremap_wc()` returned NULL for the whole framebuffer.

### Nodes with no upstream label

`soc` and `timer` carry no label in `sun8i-t113s.dtsi`, so `&soc` and `&timer`
fail with `Label or path not found`. Reopen them by path: `/ { soc { ... } }`.

### Everything else

| Addition | Why |
|---|---|
| `hdmi` + `hdmi_phy` nodes | the driver from patch 0001 needs somewhere to bind |
| `&de { status = "okay"; }` | display engine is disabled upstream |
| `tcon_top_hdmi_out` endpoint | upstream leaves `port@5` dangling |
| `&i2s2` + `allwinner,tx-hub-en` | HDMI audio source |
| `hdmi-sound` simple-audio-card | links i2s2 to the dw-hdmi codec |
| `&wdt { status = "okay"; }` | **both** watchdog nodes are `status = "reserved"` upstream |
| `psci` node + `enable-method` | vendor firmware provides PSCI; not in the upstream dtsi |
| `ramoops@4c280000` | crash logs, deliberately **not** `no-map` so it can be memremapped |
| LED `mmc0` trigger | disk activity indicator |

`sound-dai = <&hdmi>` resolves even though dw-hdmi's codec is a bare platform
device with no `of_node`: `soc_component_to_node()` falls back to
`component->dev->parent->of_node`, and dw-hdmi registers the codec with
`parent = hdmi dev`.

---

## Subsystem notes

### SMP

Two cores, brought up at boot. Three separate things had to be right:

1. **`CONFIG_THUMB2_KERNEL=n`.** A Thumb function pointer makes the PSCI entry
   address odd (`entry=0x40108009`). The vendor firmware jumps in ARM state, so
   CPU1 faulted immediately. `CPU_ON` returned 0 the whole time.
2. **The `CNTVOFF` workaround** described above. Without it both cores come up
   and the machine falls apart within seconds.
3. **`CONFIG_HOTPLUG_CPU=n`.** The firmware can start a core but cannot cleanly
   stop one - `echo 0 > /sys/devices/system/cpu/cpu1/online` hangs the machine
   hard. With hotplug compiled out that file does not exist.

Verified: `stress-ng --cpu 4 --matrix 2 --cache 2 --vm 1` oversubscribed on two
cores for 123 s - 9 stressors, 0 failed, both cores at 100%, and **zero kernel
log entries** for the entire run.

### MMC

Needs `CONFIG_REGULATOR=y`. `mmc_select_voltage()` does `ocr &= host->ocr_avail`,
and `ocr_avail` is filled by `mmc_regulator_get_supply()` from
`vmmc-supply = <&reg_vcc3v3>` - a **stub** when `CONFIG_REGULATOR=n`. The mask
stayed empty, no card voltage could match, and the card was rejected with
`no support for card's volts` / `error -22`.

This was examined once and dismissed on the wrong axis: the regulator nodes are
`regulator-always-on` with no enable GPIO, so `REGULATOR=n` starves nothing.
True of *power*, and irrelevant - the regulator's other job is supplying the OCR
voltage mask, which is pure software.

### Display

DRM/KMS through the ported PHY, console at the panel's preferred 1920x1080 with
Terminus 16x32 (120x33 characters).

`simple-framebuffer` is deliberately kept as a fallback. `FB_SIMPLE` depends on
`!DRM_SIMPLEDRM`, **not** `!DRM`, so with `DRM_SIMPLEDRM=n` both are built in:
if `sun4i-drm` binds it evicts simplefb via
`aperture_remove_all_conflicting_devices()`; if it fails to probe, simplefb
survives and the console still works.

**The fallback is not total.** It only covers a driver that fails *before*
touching the hardware. If the PHY binds and then produces a bad signal, the TCON
has already been reprogrammed out from under the U-Boot display and the screen
goes black regardless. Recovery is the card reader.

### X11

`modesetting` on KMS (`10-modesetting.conf`; the old `10-fbdev.conf` is kept
disabled at `/root/10-fbdev.conf.disabled`). There is no GPU, so
`AccelMethod "none"` is deliberate - glamor over llvmpipe is slower than the
shadow-buffer path.

X is pinned to **1280x720** while the console runs at 1080p. 1080p is 2.25x the
pixels to compose in software. The two are independent, so this costs nothing on
the console.

### Video playback

Pure software decode on two 1.008 GHz A7s. A 640x360 H.264 clip with audio plays
end to end with **0 dropped frames** using:

```sh
mpv --vd-lavc-threads=2 --audio-samplerate=48000 clip.mp4
```

`--vd-lavc-threads=2` matters - without it the decode path does not use the
second core. The same clip dropped frames on one core. 720p desynchronises.

### Watchdog, reboot and crash logs

Both watchdog nodes are `status = "reserved"` upstream, so `sunxi-wdt` never
bound, `/sys/class/watchdog/` was empty, and the kernel had no restart handler -
`reboot` simply halted. `&wdt { status = "okay"; }` fixes it.

The driver registers a restart handler but **does not arm the watchdog**.
"Watchdog enabled (timeout=16 sec, nowayout=0)" is printed on *registration*.
To make a hang self-recover, arm it from userspace:

```sh
doas sh -c 'exec 3>/dev/watchdog; while true; do printf 1 >&3; sleep 5; done' &
```

ramoops keeps the kernel log across a reset, readable from
`/sys/fs/pstore/console-ramoops-0`. **A power cycle loses it** - DRAM is not
preserved. A warm reset preserves it *sometimes*; see the reset caveat above.

---

## Traps

Recurring failure modes on this board, each of which cost at least one session.

**Setting a config symbol is not evidence the driver bound.** Check
`/sys/class/<subsystem>/` before claiming a fix. `CONFIG_SUNXI_WATCHDOG=y` was
reported as fixing reboot when reboot had never worked at all.

**A test that requires human intervention cannot distinguish "works" from
"does not work".** The reboot fix looked good for weeks because the board was
being power-cycled by hand each time.

**A reboot issued from the running kernel exercises *that* kernel's restart
handler**, not the one just flashed to p4. Testing a reboot fix requires
booting into it first.

**A control that suppresses the symptom is not a control.** `maxcpus=1` was
added to isolate "is it SMP or the instruction set". It did isolate that, and
then hid the actual bug for a week, because the `CNTVOFF` symptom only appears
with both cores up.

**Single-bit instruments fail the same silent way as the thing being
measured.** Four sessions were spent inferring from one LED. Builds where the
LED could not light for unrelated reasons produced "no signal" results that were
indistinguishable from real failures. Always include a positive control, and
prefer a channel that carries more than one bit.

**`allnoconfig` and menu gating drop symbols without warning.** See the kernel
configuration section. `validate-config.sh` exists to catch this.

**Reserved-memory regions must be page-aligned at both ends**, or `ioremap`
silently returns NULL.

**`ranges` does not inherit** in the device tree, unlike `#address-cells` and
`#size-cells`.

---

## Recovery

| Symptom | Action |
|---|---|
| Boots, network up | flash over SSH |
| Boots, no network | card reader |
| Black screen, no console text | hang before the kernel - card reader |
| Hangs mid-boot with console text | note the last line, card reader |
| Wedged after a change | power cycle; `reboot` may not survive |

There is no FEL/USB recovery on this board. The bootloader is on the removable
card, so the card reader is always the way back. Backups live in `backups/`:

- `gamestick-rootfs-20260826.tar.gz` - full p5 rootfs (831 M, 60,624 entries,
  verified; **root-owned**)
- `gamestick-bootarea-20260826.img.gz` - sectors 0-57119, the raw bootloader
  region and p1-p4
- `mmcblk0p4-live-pre-v53.img` - p4 before the DRM work
- `v52-working-kernel-backup.tar.gz` - config, zImage, DTB, boot image, modules
  and sources for the last pre-DRM build

---

## Open problems

1. **Higher-resolution video.** Check whether the cpufreq governor sits below
   1.008 GHz during playback, and whether `--vo=drm` without X buys anything.
2. **The hotplug asymmetry.** When CPU1 was brought online at runtime it
   executed *nothing* - a marker painted by its first instruction, before the
   MMU, never appeared - yet at boot it starts fine. The `CNTVOFF` bug does not
   explain that difference. Moot now that hotplug is compiled out, but unsolved.
3. **Warm reset.** Still a coin flip. Mainline U-Boot (which has supported the
   T113-s3 since v2024.01) would likely fix it. It is no longer needed for SMP.
4. **UART.** A CP2102 adapter and the PB8/PB9 pads would make every future
   diagnosis ordinary instead of ingenious.
5. **This tree is not under version control.** `git status` reports
   `not a git repository`. None of this work has history.
