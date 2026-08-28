# Development history

Chronological record of the bring-up, preserved verbatim from the original
README. **This is a lab notebook, not documentation.** Claims made early are
often corrected later in the same file, and several confident conclusions here
turned out to be wrong. For what is actually true of the current build, read
`../README.md` instead.

Kept because the dead ends cost real time and are worth not repeating.

---


This tree builds the milestone-1 system:

```text
existing vendor U-Boot
  -> Linux 6.18.39 LTS + minimal mainline T113-S3 DTB
  -> Alpine 3.24.1 armv7 on read-write ext4 partition 5
  -> persistent network recovery loop
  -> DHCP
  -> supervised Dropbear root shell
```

## Hardware bring-up status (2026-07-23)

The build is complete, but the SSH milestone has **not** been reached on real
hardware yet. Do not interpret the current 500 ms LED blink as proof that
Alpine or the networking service started.

Confirmed on the physical stick/card:

- vendor U-Boot accepts and starts the replacement Android v0 boot image;
- p1 `boot-resource`, p2 `env`, and p3 `env-redund` remain intact;
- p4 is 6,451,200 bytes and accepts the replacement boot image;
- p5 is a clean, read-write ext4 filesystem labeled `rootfs`;
- after the tested boots through diagnostic v4, p5 still reported mount count
  zero, no last-mount time, and no initramfs/network logs;
- the recurring 500 ms on / 500 ms off LED pattern is the older
  kernel/boot-path baseline and has not been a reliable userspace signal;
- the clean kernel-only heartbeat probe produced a different pattern on the
  physical stick, consistent with the kernel heartbeat trigger. This proves
  that the mainline kernel and appended mainline DTB reach the LED driver;
- the card used for tests is the removable 63,864,569,856-byte `/dev/sdc`,
  model `1081CS0`, serial `0123456789ABCDE`; `/dev/sdb2` is the host root and
  must never be written;
- all p4 writes used `cp`, never `dd`, followed by `sync` and a byte-for-byte
  `cmp` against the source artifact.

Important fixes discovered during hardware testing:

- root now uses the exact p5 `PARTUUID` and the DTS treats the boot SD as
  non-removable during bring-up;
- `CONFIG_BINFMT_SCRIPT=y` is required by the diagnostic `/init`;
- `CONFIG_BINFMT_ELF=y` is also required: `/init` is a script whose BusyBox
  interpreter is itself an ELF executable. Diagnostic v7 omitted this on the
  all-disabled Kconfig baseline and therefore remained at the heartbeat;
- the diagnostic initramfs includes BusyBox applet links;
- sysfs must be mounted before discovering `/sys/class/leds`;
- the vendor `bootm 43000000` flow may use the Android ramdisk, so diagnostic
  images carry the same valid initramfs both inside the kernel and in the
  Android boot image;
- `build-kernel.sh` now clears stale `CONFIG_INITRAMFS_SOURCE` unless an
  explicit source is supplied.

The clean kernel-only heartbeat probe was
`artifacts/boot-heartbeat-probe.img` (SHA-256
`d941eddbec09bb3dca34699789730ecae14e310e900414fee0cffaf15a56db4e`): no initramfs,
`CONFIG_LEDS_TRIGGER_HEARTBEAT=y`, and
`linux,default-trigger = "heartbeat"`. The physical result differed from the
500 ms baseline as expected, proving that mainline reaches the LED driver.

Earlier p4 diagnostic image `artifacts/boot-mmc-diagnostic-v7.img`
(SHA-256
`431a7ed444a2c59976bd5c998c1247317501967de1abf2a001c95229db951a3b`).
It has a validated static BusyBox initramfs embedded in the kernel, explicitly
forces `rdinit=/init`, and also carries a valid empty Android ramdisk. On
2026-07-23 it was written to the validated removable card's p4 only, synced,
and compared byte-for-byte successfully. Its LED results mean:

- heartbeat continues: the embedded `/init` did not execute;
- repeating two slow pulses: no `/dev/mmcblk[0-2]p5` appeared;
- repeating four slow pulses: p5 appeared but its ext4 mount failed;
- rapid 250 ms blinking: p5 mounted and Alpine's network recovery daemon ran.

On hardware, v7 remained at the heartbeat: its shell-based `/init` did not
take control. Adding an explicit `CONFIG_BINFMT_ELF=y` produced a byte-identical
kernel, proving ELF support had already been selected and was not the cause.
The next artifact was `artifacts/boot-mmc-diagnostic-v10.img` (SHA-256
`48608ccb34cef8d54bc7090dc6e76bc79341bf03c32935a25fe15892bc79f68f`).
It replaces the script and BusyBox with a VM-compiled, stripped, static,
non-PIE ARM ELF PID 1. A three-second solid LED is its unambiguous entry
signal; subsequent two/four-pulse groups retain the meanings above. It is
built, written to p4, synced, and compared byte-for-byte. On hardware it also
remained at the heartbeat, proving the problem is not BusyBox, shell scripts,
PIE, dynamic linking, or ELF interpreter support.

The previous p4 diagnostic image was `artifacts/boot-mmc-diagnostic-v11.img` (SHA-256
`e7e8648747bcfa792d2581203eee62d77434ad2226f826086195172daaaa8541`).
It is the same static C PID 1 diagnostic as v10, but the kernel config now
sets `CONFIG_INITRAMFS_FORCE=y`. This is meant to force Linux to ignore the
Android boot image ramdisk and execute the built-in initramfs instead. On
2026-07-23 it was written to the validated removable card's p4 only, synced,
and compared byte-for-byte successfully. On hardware it still remained at the
heartbeat.

The previous p4 diagnostic image was `artifacts/boot-mmc-diagnostic-v12.img`
(SHA-256
`6f5e60a1e0b7a9840df33df2d5a3a968229c6e9eb3ddac630cad108b8c08e334`).
It keeps the v11 kernel and built-in static C initramfs, but also places the
same diagnostic initramfs in the Android boot image ramdisk field instead of
the empty ramdisk stub. This tests whether the vendor `bootm` path only
successfully exposes the external Android ramdisk to Linux. On 2026-07-23 it
was written to p4 only, synced, and compared byte-for-byte. On hardware it
still remained at the heartbeat.

The previous p4 diagnostic image was `artifacts/boot-mmc-diagnostic-v13.img`
(SHA-256
`3957031d4881a0a9475206f39dad97f98e0a5e47780954943b59d898651cfda5`).
It keeps the v12 diagnostic arrangement, but disables
`CONFIG_ARM_ATAG_DTB_COMPAT` and its bootloader-command-line import path. The
actual VM-built `.config` was checked and contains the forced command line,
`CONFIG_INITRAMFS_FORCE=y`, and no `CONFIG_ARM_ATAG_DTB_COMPAT*` entries. This
tests whether vendor U-Boot ATAG data was overriding the mainline command line.
On 2026-07-23 it was written to p4 only, synced, and compared byte-for-byte.
On hardware it still remained at the heartbeat.

The previous p4 diagnostic image was `artifacts/boot-mmc-diagnostic-v14.img`
(SHA-256
`13ea914f6776f5f1d425784182573b8b74fd0c30fa8d3ebed0010938d607ed9f`).
It keeps v13's forced command line and initramfs behavior, enables
`CONFIG_DEVMEM=y`, and makes PID 1 mmap the T113/sun8iw20 PIO controller at
`0x02000000` to drive PB12 directly for five seconds before using the LED class
or sysfs. This tests whether PID 1 is running but the LED-class proof path is
invalid. On 2026-07-23 it was written to p4 only, synced, and compared
byte-for-byte. On hardware it still remained at the heartbeat.

The previous p4 diagnostic image was `artifacts/boot-mmc-diagnostic-v15.img`
(SHA-256
`9c9993734c95a8d1227b7e31cc4b55f2607f4a5c209d25bfa8cfe1d3f47e455e`).
It keeps the v14 direct-PB12 PID 1 diagnostic but changes the DTS LED node to
`default-state = "off"` and `linux,default-trigger = "none"`. This removes the
kernel heartbeat trigger as a default DTB behavior. On 2026-07-23 it was
written to p4 only, synced, and compared byte-for-byte. Hardware then showed the
LED going dark and staying off (the "LED stays off" case below): the mainline
DTB is active, but PID 1 never proved entry. The real root cause was found on
2026-08-01 and fixed in v16 (see below). Expected LED meanings:

- heartbeat continues: the observed heartbeat is not coming from this DTB's
  default LED trigger, so the board may not be using the appended DTB/image
  path we think it is, or PB12 is not the observed LED;
- LED stays off: mainline DTB is active, but PID 1 still did not prove entry;
- five seconds solid on immediately after kernel handoff: diagnostic PID 1
  entered and direct PB12 access worked;
- three seconds solid on after that: diagnostic PID 1 entered and LED-class
  access worked;
- repeating two slow pulses: no `/dev/mmcblk[0-2]p5` appeared;
- repeating four slow pulses: p5 appeared but ext4 mount failed;
- rapid 250 ms blinking: p5 mounted and Alpine's network recovery daemon ran.

The image currently written to p4 is `artifacts/boot-mmc-diagnostic-v16.img`
(SHA-256
`ed40af173821fd20c915339c9ca233bd0c202fe22c1bb9f4e94f8a96f9fe5a15`).
It is the v15 direct-PB12 PID 1 diagnostic, unchanged in DTS and source, but
rebuilt to fix the actual regression: **the built-in initramfs shipped in
v7-v15 did not contain the diagnostic `/init`.** Inspection of the shipped
kernels showed that `init/initramfs.c` and `__initramfs_start` were present
(initramfs support was compiled in) but the diagnostic cpio bytes were absent
from `vmlinux` — i.e. the kernels embedded an *empty* built-in initramfs. The
on-disk `build-v15/.config` did list a correct `CONFIG_INITRAMFS_SOURCE`, but
the compiled `zImage` predated that value (config/binary drift): the kernel was
built before `INITRAMFS_SOURCE` took effect and never recompiled. Because
`CONFIG_INITRAMFS_FORCE=y` also makes the kernel ignore the Android boot-image
ramdisk (which *did* contain `/init`), no PID 1 ever ran, and the LED stayed
dark under the v15 DTB. This explains every heartbeat-then-nothing result from
v7 onward independent of the BusyBox/ELF/PIE/ATAG hypotheses.

v16 was produced by a clean rebuild (fresh build directory) from a known-good
source tree with `INITRAMFS_SOURCE` exported, so `.config` and the binary cannot
drift. The fix was verified at the ELF level before flashing: the 19,000-byte
gzipped diagnostic cpio (which unpacks to the 33,716-byte static ARM `/init`)
is linked verbatim into `vmlinux`, and `__initramfs_start` / `populate_rootfs`
are present. The Android boot image's kernel byte-matches that verified
`zImage`, and its ramdisk field also carries `/init` as a fallback. On
2026-08-01 v16 was written to the validated removable card's p4 only
(`cp`, then `sync`), and `cmp` confirmed a byte-for-byte match. Its expected LED
meanings are identical to v15's list above; a five-second solid LED right after
kernel handoff is now the signal that the diagnostic PID 1 finally executed.

Hardware result (2026-08-01): v16 produced only a single brief, **dim** LED
flash at power-on, then dark, with no repetition. This is not the diagnostic
sequence in either polarity (both polarities predict a ~5s steady phase, a ~3s
steady phase, then repeating 2s-period pulses). The symptom did change from
v15's fully-dark result, which indicates the new kernel is loaded and executed
on the appended-DTB/boot path (resolving that open doubt), but PID 1 is still
not sustaining. Conclusion: the empty-initramfs bug was real and is fixed, but
there is a **second, independent problem** — the board reaches the LED framework
(brief flash) yet does not hold a running init, consistent with an early kernel
panic or an init that faults immediately. The dim (not full-brightness) flash
may also point at a power/GPIO-drive or LED-polarity factor.

### 2026-08-01 session: the root cause is upstream of all userspace work

A direct-boot test settled the question that v7-v19 could not. A kernel was
built with **no initramfs at all** and **no `rdinit`**, so Linux itself mounts
p5 from `root=PARTUUID=...` and executes Alpine's `/sbin/init`
(`artifacts/boot-alpine-direct-v20.img`). It also enables
`CONFIG_LEDS_TRIGGER_PANIC=y` with `panic-indicator` in the LED node, so any
kernel panic blinks PB12 forever.

Hardware result: **no LED, and p5's ext4 mount count did not move** (2 before,
2 after; last mount time remained this PC's 21:46 automount; lifetime writes
unchanged; no files modified). Therefore:

- the kernel never mounted the rootfs, with a correct PARTUUID (verified
  against the card: p5 is `a0085546-...-8e49`), `rootfstype=ext4`, and
  `rootwait`;
- no panic occurred, because `rootwait` waits **forever** for a root device
  rather than panicking - which is exactly why the LED stayed dark;
- every earlier "PID 1 does not work" symptom was downstream of this. The
  initramfs versions could not find `/dev/mmcblk*p5` for the same reason the
  kernel could not: **the block device never appears.**

The suspect is therefore the **MMC/SD path under mainline Linux**, not
userspace, not the initramfs, and not the init binary. U-Boot reads the same
card fine, but it uses its own driver, so that proves nothing about Linux.
Confirmed not to be the cause: the `sunxi-mmc` driver does support this SoC
(`allwinner,sun20i-d1-mmc`, which is what the upstream DTSI uses),
`CONFIG_MMC_SUNXI=y`, `CONFIG_PINCTRL_SUN20I_D1=y`, and
`CONFIG_SUN20I_D1_CCU=y` are all set and compiled in.

Also corrected this session:

- the earlier "empty built-in initramfs" bug was real and is fixed; a clean
  rebuild verified at the ELF level (the gzipped cpio is linked verbatim into
  `vmlinux` and `__initramfs_start`/`populate_rootfs` are present). It simply
  was not the whole story;
- mainline 6.18 has **no HDMI support for this SoC**: the D1/T113 DTSI has the
  display engine, mixers and TCONs, but `tcon_top_hdmi_out` is a dangling port
  with no HDMI controller or PHY node, and the sun4i DRM HDMI compatible list
  contains no `sun20i-d1` entry. An HDMI/fbcon console is therefore not
  available as a debugging aid without porting a driver;
- USB keyboards cannot signal a panic either: only `i8042` (PS/2) registers
  `panic_blink`. The LED panic trigger described above is the working
  equivalent.

The immediate open question is whether the mainline kernel boots at all in its
current form. `artifacts/boot-heartbeat-probe.img` (kernel-only, 12-byte
ramdisk stub, LED driven by the kernel heartbeat trigger) is the test: a steady
blink proves kernel + appended DTB + PB12 all work and isolates the fault to
MMC; a dark LED means the kernel is not booting or PB12 is not the status LED,
which would invalidate several assumptions above.

### 2026-08-02: diagnosis is blocked on the absence of a serial console

After the direct-boot result above, several further attempts were made to get
any diagnostic output off the board. All failed, and the reasons are worth
recording so they are not repeated:

- **USB logging** (`boot-usblog-v22.img`): mount a FAT32 stick and write
  `dmesg` to a file. The board hung with the LED frozen and the stick came back
  with no directory entry at all.
- **Raw block writes** (`boot-rawlog-v23.img`, `boot-stagelog-v24.img`): no
  filesystem, no `mount()`, no global `sync()` - open the block device and
  write at a fixed offset, with a marker written the instant the device opens
  so that even a later hang leaves evidence. The target offsets were zeroed
  before each test. **Nothing was ever written**: a full 14.5 GB scan of the
  drive found neither marker nor log.
- The USB stick's own activity light does flash during these tests, but that is
  explained by the kernel's own usb-storage enumeration reading the partition
  table. It is not evidence that our userspace ran.
- **The LED is not a usable channel.** Every build whose init drove PB12 through
  `/dev/mem` produced an uninterpretable result (steady-on, "dimming",
  uncountable flashes); builds that used only `/sys/class/leds` produced no LED
  activity at all, even though the kernel's own heartbeat trigger drives the
  same LED cleanly. The `/dev/mem` writes most likely re-mux the pin, and the
  LED class appears not to be reachable from the initramfs.

Consequently **it is currently unknown whether PID 1 executes at all.** Earlier
notes in this file inferred that it did, from LED behaviour that later proved
unreadable; that inference should not be relied on.

What is solid:

- the mainline kernel boots, the appended DTB is active, and PB12 is the status
  LED (the kernel-only heartbeat probe blinks a clean two-pulse heartbeat);
- the kernel never obtains a root device from MMC, and `rootwait` turns that
  into a silent infinite wait rather than a panic;
- p5 has never been mounted by the board under any build.

**Do not build further blind diagnostics.** Every remaining hypothesis needs
kernel messages to distinguish, and there is no channel to carry them. The next
action is to attach a 3.3 V USB-TTL adapter to the candidate header documented
in `docs/HARDWARE.md` and read the boot log directly; the `sunxi-mmc` probe
failure will almost certainly be visible in the first few hundred lines.

Recommended next steps (not yet done):
- **Run the heartbeat probe** (flashed to p4 on 2026-08-01, result pending) to
  decide between "MMC is broken" and "the kernel is not booting".
- **If the heartbeat blinks, attack MMC directly.** Ideas in rough order:
  drop the local `&mmc0` overrides (`non-removable`, `bus-width`,
  `vmmc-supply`, explicit `pinctrl-0`) and boot the upstream description
  unmodified, since one of those overrides may be preventing probe; check
  whether `mmc0_pins` is the correct upstream label for this SoC; add
  `CONFIG_MMC_DEBUG`/`initcall_debug`; and compare against the working
  `sun8i-t113s-mangopi-mq-r-t113.dts`, which is a known-good mainline board
  using the same SoC and MMC0.
- **UART is still the real unblock:** without a serial console on PB8/PB9
  (115200 8N1) every result is inferred from one LED. A cheap USB-TTL adapter
  (CP2102/CH340/FT232, 3.3 V) plus locating the PB8/PB9 pads would replace all
  of this guesswork with actual kernel messages, including the MMC probe error.
- Note that `rootwait` hides failure as a silent hang. For diagnosis, building
  **without** `rootwait` makes the kernel panic when root is missing, which the
  `panic-indicator` LED trigger then reports as continuous blinking.

Current conclusion:

- v7 through v14 all reached a heartbeat-like LED pattern on hardware, but no
  diagnostic userspace signal ever appeared;
- v10 ruled out shell, BusyBox, dynamic linking, PIE, and interpreter issues;
- v11 ruled out the missing `CONFIG_INITRAMFS_FORCE=y` hypothesis;
- v12 ruled out the empty Android ramdisk field hypothesis;
- v13 ruled out vendor ATAG command-line import overriding the forced mainline
  command line;
- v14 ruled out the LED-class/sysfs path as the only proof mechanism, assuming
  PB12 is the observed LED;
- v15 went dark on hardware, which under its `default-trigger = "none"` DTB is
  the "PID 1 did not prove entry" case, and led to finding the empty-initramfs
  regression described above;
- v16 is the corrected build: the diagnostic `/init` is verified present in the
  kernel's built-in initramfs. It is now written to p4. The next hardware test
  should look for the five-second solid LED immediately after kernel handoff
  (diagnostic PID 1 entered, direct PB12 worked). If v16 *still* stays dark,
  PID 1 entry is no longer the variable, and the investigation should move to
  whether vendor U-Boot actually uses the appended DTB/image path, whether
  another boot partition/image is selected, or whether the observed LED is
  really PB12 (its polarity is still unconfirmed in `docs/HARDWARE.md`).

Resume notes:

- build anything compiled inside the VM launched by `/home/maximized/archvm.sh`;
- VM SSH is `user@127.0.0.1 -p 2222`, password `user`;
- VM source tree used during this bring-up:
  `/home/user/gamestick-mainline/project-v7`;
- VM Linux source:
  `/home/user/gamestick-mainline/src/linux-6.18.39`;
- VM build directories are named `/home/user/gamestick-mainline/build-vN`;
- VM cross compiler prefix:
  `/home/user/fbterm-arm-build/arm-linux-musleabihf-cross/bin/arm-linux-musleabihf-`;
- do not spend more time varying BusyBox scripts or userspace init formats
  until the boot image/DTB selection question is resolved.

Recovery/build artifacts currently retained:

- `ofw/ofw-compact-clean-128m-2026-07-22.img`: p1-p6 preserved; fresh empty
  128 MiB p7/p8;
- `artifacts/gamestick-mainline-60906m.img`: exact-card-size sparse mainline
  image, physically flashed and SHA-256 verified once;
- `artifacts/boot-rootfix.img` and `boot-diagnostic-v*.img`: chronological
  bring-up images; they are diagnostics, not successful release images.

The Wi-Fi configuration and root password are present in the built rootfs but
are intentionally not reproduced in this README.

There is no graphics, audio, Bluetooth, desktop, emulator, compiler, Python, or
Bash in this milestone. Nothing here flashes a card. Build outputs must be
regular files, paths are explicit, and existing outputs are never replaced.
The compact OFW backup helper accepts one validated removable disk as a
read-only source and refuses the disk containing `/`.

`artifacts/` contains VM-built kernels, DTBs, configurations, diagnostic boot
containers, and the sparse full-card image. Credentials must still be supplied
outside the repository for any clean rebuild.

## Design decisions

### Linux and device tree

The kernel fragment is derived from `multi_v7_defconfig`'s ARMv7/sunxi choices,
then resolved on an all-disabled baseline. This avoids an important Kconfig
failure mode where leftover child-board symbols silently select OMAP, QCOM,
Tegra, and other parent platforms back on. MMC, ext4, devtmpfs, the Allwinner
USB PHY, EHCI/OHCI, and serial console are built in. cfg80211, the Realtek
driver, and emergency USB Ethernet drivers are modules. XZ compression keeps
the kernel plus appended DTB inside the existing 6,451,200-byte Android boot
partition. The kernel ignores the Android ramdisk stub and forces the known
ext4 p5 root command line instead of inheriting stale vendor rootfs arguments.

The DTS includes upstream `sun8i-t113s.dtsi`; it does not reproduce the vendor
tree. `docs/HARDWARE.md` separates confirmed wiring from unresolved details.

### wpa_supplicant, not iwd

Both can be cleanly packaged on Alpine, but wpa_supplicant is the safer first
boot backend here:

- the already-developed 8188eu path was tested through cfg80211/nl80211;
- wpa_supplicant has a small, direct configuration and exposes association
  state through `wpa_cli`;
- vendor Realtek drivers can implement a narrower nl80211 feature set than iwd
  expects.

The recovery daemon does not contain wpa_supplicant-specific connection logic.
It calls `wifi-backend-wpa_supplicant`; interface discovery, DHCP, infinite
retry, logging, Ethernet recovery, and SSH readiness are backend-independent.
An iwd backend can therefore replace one executable later.

### Recovery behavior

OpenRC starts two supervised services without waiting on the network. The
network daemon repeatedly:

1. records all enumerated USB VID:PIDs;
2. loads cfg80211 and 8188eu;
3. dynamically discovers wired and wireless interface names;
4. prefers a connected USB Ethernet interface when available;
5. associates Wi-Fi and runs BusyBox udhcpc;
6. returns to discovery whenever the address disappears.

Dropbear waits for the readiness file plus a real IPv4 address. Unique host
keys are generated during image creation and regenerated at boot if absent;
Dropbear restarts after every exit. Logs persist under `/var/log`.
The status LED blinks during recovery and becomes solid when networking is
ready and SSH is launched.

## Build in the VM

Launch `/home/maximized/archvm.sh`, copy this project into the guest, then run
all following commands in that VM. The known VM login is `user`.

Prepare dependencies and sources:

```sh
sudo ./vm/bootstrap-vm.sh
./vm/fetch-sources.sh /home/user/gamestick-mainline
```

Set the existing ARM cross-compiler prefix, or install/build an equivalent
armv7 hard-float cross-toolchain in the VM:

```sh
export CROSS_COMPILE=/home/user/fbterm-arm-build/arm-linux-musleabihf-cross/bin/arm-linux-musleabihf-
```

Create a real Wi-Fi configuration and select a public key outside the
repository. Do not commit either:

```sh
cp rootfs/files/etc/wpa_supplicant/wpa_supplicant.conf.example /tmp/gamestick-wifi.conf
chmod 600 /tmp/gamestick-wifi.conf
# Edit /tmp/gamestick-wifi.conf.

sudo ./rootfs/build-rootfs.sh \
  /home/user/gamestick-mainline/build/rootfs \
  /tmp/gamestick-wifi.conf \
  /tmp/authorized_keys
```

Build the kernel, then build and install the exact matching modules:

```sh
./kernel/build-kernel.sh \
  /home/user/gamestick-mainline/src/linux-6.18.39 \
  /home/user/gamestick-mainline/build/linux \
  "$CROSS_COMPILE"

sudo env PATH="$PATH" JOBS="$(nproc)" \
  ./driver/build-install-rtl8188eu.sh \
  /home/user/gamestick-mainline/src/rtl8188eu \
  /home/user/gamestick-mainline/src/linux-6.18.39 \
  /home/user/gamestick-mainline/build/linux \
  /home/user/gamestick-mainline/build/rootfs \
  "$CROSS_COMPILE"
```

Build the Android v0 boot container used by the existing U-Boot:

```sh
./scripts/make-android-boot.sh \
  /home/user/gamestick-mainline/build/linux/arch/arm/boot/zImage \
  /home/user/gamestick-mainline/build/linux/arch/arm/boot/dts/allwinner/sun8i-t113s-h133-game-stick.dtb \
  /home/user/gamestick-mainline/artifacts/boot.img
```

Optionally assemble a regular full-card image. The reference image supplies
the exact raw bootloader region and original boot-resource/env/env-redund data;
their disk/partition GUIDs are retained as well.
The number is an explicit final image size in MiB. Partition 5 fills all
remaining space as ext4. This command creates a file and cannot accept an SD
card device:

```sh
sudo ./scripts/assemble-disk-image.sh \
  /path/to/original-full-card.img \
  /home/user/gamestick-mainline/artifacts/boot.img \
  /home/user/gamestick-mainline/build/rootfs \
  /home/user/gamestick-mainline/artifacts/gamestick-mainline.img \
  12288
```

To make a compact OFW recovery image before repurposing a card, preserve p1–p6
and replace rootfs_data/UDISK with empty 128 MiB ext4 filesystems:

```sh
sudo ./scripts/compact-ofw-backup.sh /dev/EXPECTED_REMOVABLE_DISK \
  /path/to/ofw-compact-clean-128m.img
```

This helper reads the source disk but never writes it.

Validate before any hardware test:

```sh
./scripts/validate-source-tree.sh
sudo ./scripts/validate-build.sh \
  /home/user/gamestick-mainline/src/linux-6.18.39 \
  /home/user/gamestick-mainline/build/linux \
  /home/user/gamestick-mainline/build/rootfs \
  /home/user/gamestick-mainline/artifacts/boot.img \
  /home/user/gamestick-mainline/artifacts/gamestick-mainline.img
```

Read `docs/FIRST-BOOT.md` before testing and `docs/TROUBLESHOOTING.md` if no
lease appears. The current milestone stops at a stable remote root shell.

## 2026-08-02: pivot to the vendor kernel, and the two ways forward

The stick now runs a working Linux system, reached over SSH. What changed:

- the card was repartitioned to **p1-p5 only** (no p6/p7/p8, no overlay), with p5
  a **read-write ext4 root filling the whole card** (~59.5 GB). p1-p4 kept their
  original offsets so their contents were untouched; the bootloader region
  (sectors 4-41463) was verified byte-identical before and after;
- `/sbin/mount_root` was replaced with a script that just remounts / rw. The
  stock fstools binary, finding no `rootfs_data`, would have mounted a **tmpfs
  overlay** over the root and silently discarded every write at power-off;
- `/etc/init.d/S98dropbear` starts dropbear (key auth, `-B`) before `S99run`;
  verified to survive a real reboot. Keys: `~/.ssh/gamestick_ed25519` on the PC;
- `/bin/networking.sh` + `/etc/wifi.conf` bring up Wi-Fi; called from `S99run`.

### Why mainline failed, and the fix that was never available

U-Boot passes `root=/dev/mmcblk0p5 init=/sbin/init` with **no `rootfstype=`**
(see `setargs_mmc` in the env), so the kernel auto-detects the filesystem - ext4
mounts with no bootloader change at all.

The vendor DTB shows why mainline's MMC never worked:

| | vendor (works) | mainline (fails) |
|---|---|---|
| compatible | `allwinner,sunxi-mmc-v5p3x` | `allwinner,sun20i-d1-mmc` |
| clocks | 4: osc24m, pll_periph, mmc, ahb | 2: ahb, mmc |
| card detect | `cd-gpios` = PF6 | we used `non-removable` |

**The full vendor BSP kernel source is in the VM**:
`/home/user/rtl8188eu-t113-build/tina-linux-5.4-v4` - 1.5 GB, 72,477 files,
Linux 5.4.61, including `drivers/mmc/host/sunxi-mmc-v5p3x.c` (the driver behind
that compatible string) and `drivers/video/fbdev/sunxi/`. Plus
`device-5.4.61.config`, `tina-sdk/`, `toolchain-sunxi-musl/`, and a
`kernel-build-v4/.config` from a previous successful build. This is what
produced the `8188eu.ko`/`cfg80211.ko` with `vermagic 5.4.61`.

### fbcon: the thing that would have saved the whole bring-up

The vendor kernel has **no framebuffer console** - that is why
`/usr/sbin/terminal-console` exists ("FbTerm supplies the missing framebuffer
console") and why kernel panics are invisible. In `device-5.4.61.config`:

    CONFIG_VT=y                              already on
    CONFIG_VT_CONSOLE=y                      already on
    CONFIG_FB=y                              already on
    # CONFIG_FRAMEBUFFER_CONSOLE is not set  <-- the whole problem

Two routes, and they differ:

1. **Vendor kernel + fbcon.** One Kconfig symbol. All drivers keep working.
   Rebuild, repackage into the p4 Android boot image (U-Boot supplies the DTB
   from the bootloader region, so only the kernel changes). Gives a real console
   and visible panics on a machine where everything already works.

2. **Mainline + simple-framebuffer.** Enabling fbcon on mainline alone displays
   *nothing*: mainline has no HDMI support for this SoC (`tcon_top_hdmi_out` is
   a dangling port, no HDMI controller/PHY node, no `sun20i-d1` entry in the
   sun4i DRM HDMI list). But **U-Boot already initialises the display** - that
   is how the Tux bootlogo appears - and the vendor bootargs give its address:

       disp_reserve=3686400,0x4bee8c00
       boot_fb0 = "4bee8c00,500,2d0,20,1400,..."   addr, 1280, 720, 32bpp

   So a `simple-framebuffer` node in the mainline DTS plus `CONFIG_FB_SIMPLE=y`
   and `CONFIG_FRAMEBUFFER_CONSOLE=y` would give mainline a console on HDMI with
   no HDMI driver at all - and finally show why MMC fails:

       chosen {
           framebuffer@4bee8c00 {
               compatible = "simple-framebuffer";
               reg = <0x4bee8c00 0x384000>;
               width = <1280>; height = <720>; stride = <5120>;
               format = "a8r8g8b8";
           };
       };

Route 1 gets a working machine; route 2 attacks the original mainline goal with
the diagnostic channel that was missing all along.

### Also established

- **UART0 is PB8/PB9** (vendor `uart@2500000` uses `pinctrl-0 = <0x14>` =
  `uart0_pins@0`). The `sdc0@3` group mapping PF2/PF4 to uart0 is an unused
  alternate. The 6-pin castellated tab on the board edge is most likely the
  PF0-PF5 SD group, not UART.
- Framebuffer is 1280x720x32, `rgba 8/16,8/8,8/0,8/24`, layer in **pixel alpha**
  mode (`a[pixel 255]`). This is *not* what breaks X.org - writing random bytes
  to `/dev/fb0` shows every pixel - so the earlier alpha theory was wrong. X
  draws only its cursor and never repaints the root window; unexplained, and the
  next step is simply to read `Xorg.0.log`.
- `notgameui` (renamed from `gameui`) is an **LVGL** app on raw framebuffer +
  evdev, with an embedded SQLite catalog (`tbl_game`) in AES-ECB encrypted files
  under `/sdcard/93lib/`, launching games via `/sdcard/93lib/start_game.sh`.
  Proof that a graphical UI runs fine here without X.

## 2026-08-03 session 3: the initramfs is NOT the bug (proved in QEMU)

The question open since session 1 - does the built-in initramfs `/init` ever
execute - was finally attacked by bisection instead of guesswork, using QEMU to
swap out one link of the chain at a time:

    our cpio -> kernel initramfs machinery -> this board's U-Boot handoff -> /init?

Two controlled runs, same emulated hardware, differing only in kernel config:

1. `multi_v7_defconfig` + our cpio:   `Run /init as init process`
2. **our `allnoconfig` + fragment** + our cpio:
   `Run /init as init process` followed by
   `Kernel panic - not syncing: Attempted to kill init! exitcode=0x00000000`

So the following are **cleared by direct test**, not inference: the cpio format,
the embedded-initramfs machinery, `rdinit=`, `INITRAMFS_FORCE`, the static ARM
init binary, and **our kernel configuration**. Whatever breaks `/init` is
specific to this board's boot path - U-Boot's `bootm`, the appended DTB, or the
memory layout - not to anything we build.

Reproduce with:

    qemu-system-arm -M virt -m 256 -nographic \
      -kernel build-ourvirt/arch/arm/boot/zImage

### Real fixes and real mistakes this session

- **`clk_ignore_unused` was missing.** The vendor cmdline carries it; mainline
  has no display driver, so nothing claims the DE/TCON/HDMI clocks U-Boot left
  running and the clock framework culls them. Adding it stops HDMI dropping -
  confirmed on hardware, the bootlogo now persists into Linux.
- **There was no restart handler.** `CONFIG_WATCHDOG` was never set, so
  `sunxi_wdt` was not built and the kernel physically could not reboot. Every
  earlier conclusion of the form "it did not reboot, therefore it did not panic"
  was unfounded.
- **Enabling the watchdog hung early boot** (LED died entirely); it was backed
  out again. `CONFIG_WATCHDOG=n` for now.
- **`allnoconfig` silently drops `default y` infrastructure.** `CONFIG_PM`,
  `CONFIG_REGULATOR` and `CONFIG_DMADEVICES` were all off. They are now on.
  (`CONFIG_SUNXI_SRAM` and `CONFIG_SUNXI_CCU` survived.) Enabling them did not
  fix MMC/USB/simplefb.
- **Several LED tests had no positive control**, so a dark LED could mean either
  "the event did not happen" or "the LED cannot light in this build". Results
  from those builds are void. The heartbeat trigger is the only signal proven to
  work on this board and should always be included as a control.
- simplefb never bound. The DT node and driver path check out (`of/platform.c`
  special-cases `simple-framebuffer` under `/chosen`, `reg` encodes correctly at
  1 address/1 size cell, `FB_CORE`/`FB_DEVICE` are set), so the likely remaining
  suspect is that U-Boot's framebuffer is **not** at the hardcoded `0x4bee8c00`.
  That address came from the *vendor kernel's* bootargs and has never been
  verified for our boot. With an appended DTB, U-Boot cannot patch its own
  `disp_reserve=` into our DT, so the address cannot be read at runtime either -
  it would have to come from the display engine's registers (mixer at
  `0x05100000`), which the vendor source documents.

### Hardware notes confirmed this session

- MMC, USB and simplefb all fail while the kernel itself runs fine (heartbeat,
  no panic). pinctrl and GPIO demonstrably work, since the LED is driven through
  them.
- The keyboard's LEDs behave differently per build (stuck on / reset-cycling /
  off and staying off), so the USB stack *is* being touched and its behaviour
  tracks our config, even though nothing ever enumerates.
- The toolchain in `~/fbterm-arm-build` was deleted to free disk space. Replaced
  by `tools/armv7-unknown-linux-musleabihf` (GCC 16.1, copied into the VM at
  `~/armv7-toolchain`). The vendor OpenWrt toolchain
  (`rtl8188eu-t113-build/toolchain-sunxi-musl`, `arm-openwrt-linux-muslgnueabi-gcc
  6.4.1`) survived and is the correct compiler for the vendor 5.4.61 tree - it
  matches `/proc/version` on the running stick.

### Next step

`artifacts/boot-probe-v34.img` is flashed to p4: the exact configuration in
which the LED demonstrably heartbeated, with **one** variable changed - the init
sleeps 20 s then exits. Heartbeat then a change at ~20 s means the initramfs
works on the board; heartbeat forever means `/init` never runs and the fault is
in the U-Boot handoff. Result not yet observed.

**A 3.3 V USB-TTL adapter on PB8/PB9 remains the single highest-value action.**
Three sessions have been spent building instruments to extract one bit at a
time, and those instruments keep breaking in ways indistinguishable from the
thing being measured.

## Session 4 (2026-08-18) - toolchain control build, v35

### The v25-v34 source changes were lost

This tree is frozen at **2026-07-23** (`kernel/game-stick.fragment` and
`dts/sun8i-t113s-h133-game-stick.dts` mtimes). The v25-v34 edits - the
`clk_ignore_unused pd_ignore_unused` cmdline, `CONFIG_PM`/`CONFIG_REGULATOR`/
`CONFIG_DMADEVICES`, `CONFIG_FB_SIMPLE`, `CONFIG_LEDS_TRIGGER_PANIC`, and the
simple-framebuffer + reserved-memory DT nodes - only ever existed inside the VM
and were destroyed by the Arch reinstall. There is no git history. Only the
prose above records what they were, and they must be re-applied *to files* if
that line of work resumes.

### v35: one variable changed - the kernel compiler

The prime suspect was the GCC 11 -> GCC 16.1 switch: the LED heartbeated
reliably under GCC 11, and every anomalous result (including v33/v34 showing no
LED at all in a previously-working baseline) came afterwards.

Bedrock Linux is now installed in the VM, so Debian's
`arm-linux-gnueabihf-gcc 14.2.0` (binutils 2.44) is available alongside Arch's
GCC 16.1.1. Build inputs for v35:

- **kernel**: the untouched 2026-07-23 tree, compiled with
  `CROSS_COMPILE=arm-linux-gnueabihf-` (GCC 14.2.0).
- **initramfs**: deliberately *unchanged* - still built with the musl
  crosstool-NG GCC 16.1.0. The LED heartbeat is driven entirely kernel-side, so
  changing the libc as well would have confounded the test.

`CONFIG_CC_VERSION_TEXT="arm-linux-gnueabihf-gcc (Debian 14.2.0-19) 14.2.0"`.
`validate-config.sh` passes.

### The initramfs really is embedded this time

The v7-v15 empty-initramfs bug was explicitly ruled out rather than assumed:

- `usr/initramfs_inc_data` = 19739 bytes (gzip; `CONFIG_INITRAMFS_COMPRESSION_GZIP=y`,
  which is why the payload is not greppable as plain text inside `vmlinux`)
- `__initramfs_size` reads `1b4d0000` LE = **19739** - non-zero, matching the blob
- decompressing the embedded blob gives sha256
  `f82c1831...c83aa7aa`, **byte-identical** to `initramfs-gcc14test.cpio`

### Flashed

`artifacts/boot-gcc14-v35.img` (2705408 / 6451200 bytes, board `h133-p2nor`)
written to `/dev/sdc4` and read back byte-identical
(`f7911a4e...bd1b7543`). p5 baseline before boot: **mount count 3**, last mount
time 1970 (i.e. never mounted with a real clock).

Expected LED sequence if `/init` runs, from `scripts/diagnostic-init.c`:
5 s solid (direct PB12 via /dev/mem) -> 1 s off -> 3 s solid (sysfs LED class)
-> 1 s off -> repeating 2 pulses (no rootfs found) or 4 pulses (rootfs found).

Three distinguishable outcomes, and the heartbeat is the built-in control:

| observation | conclusion |
| --- | --- |
| no LED at all | GCC 16.1 is exonerated; the fault is deeper than the compiler |
| heartbeat forever, nothing else | baseline restored; `/init` never runs, so the fault is the U-Boot handoff |
| heartbeat then the pulse sequence | the built-in initramfs works on hardware - the biggest result available without UART |

### v35 result: the LED test was VOID (again)

Observed: no LED at all; U-Boot's Tux bootlogo still on screen, intact, with
green pixel garbage in bands at the bottom-left and bottom-right. p5 mount count
unchanged at 3, last mount time still 1970 - the rootfs was never mounted.

**The table above was inapplicable.** The 2026-07-23 DTS declares the status LED
as `default-state = "off"` with `linux,default-trigger = "none"`. The heartbeat
trigger was part of the *lost* August work. This build could never have lit the
LED whether or not the kernel ran, so "no LED" carries no information. This is
the third time a test has been run without a positive control; the check
"does this build have a working control?" must precede every flash.

### What the green garbage may be worth

This kernel has **no framebuffer driver at all** (no `CONFIG_FB`, no simplefb),
and the DTS declares `memory@40000000` spanning all 256 MiB with **no
`reserved-memory` node**. The kernel therefore treats U-Boot's framebuffer as
ordinary free RAM and is free to allocate over it. On that reading the green
bands are the kernel writing into the memory holding the picture, which would
make them a positive control that needs neither LED nor console.

Competing hypothesis raised on the spot: marginal HDMI/TMDS bit errors. Not yet
excluded. Discriminators:

- TMDS errors are random across the whole frame; Tux is pristine and the
  corruption is confined to bands, which favours memory contents.
- Memory contents are **static**; link errors **shimmer** every frame.
- Memory corruption should differ slightly per boot; cable sparkle should not.

Until someone confirms the pattern is frozen rather than dancing, "the kernel is
running" remains unproven.

### Possible late-boot marker (unconfirmed)

`clk_disable_unused` runs as a `late_initcall`. Before the `clk_ignore_unused`
fix the screen went black; this build has no `clk_ignore_unused` yet the logo
stayed lit indefinitely, which would mean the kernel never reached
`late_initcall`. Deliberately **not** adding `clk_ignore_unused` for now: the
blackout is a free progress marker, and suppressing it would discard a signal.

### v36: the same build with the control restored

Only one change from v35 - `linux,default-trigger = "heartbeat"` on the status
LED (verified present in the compiled DTB). Same GCC 14.2.0 kernel, same musl
initramfs, same everything else. `artifacts/boot-gcc14-hb-v36.img`
(sha256 `4077284d...d7fa6fd7`) flashed to `/dev/sdc4`, read back identical.

| observation | conclusion |
| --- | --- |
| heartbeat | kernel alive; v35's dark LED was purely the missing trigger, and GCC 14 is usable |
| still no LED, screen still corrupts | kernel runs but dies before the LED subsystem |
| still no LED, no corruption either | kernel is not running at all; the U-Boot handoff is the fault |

### v36 result: BASELINE RESTORED - the kernel is healthy

Observed: **Tux disappears, heartbeat visible.** Both markers fired.

1. **Heartbeat = the kernel is alive** and the LED subsystem works. v35's dark
   LED was entirely the missing trigger. **GCC 14.2.0 builds a working kernel**,
   so the toolchain question is settled and there is a trustworthy control again.
2. **Tux disappearing = `clk_disable_unused` ran**, and that is a
   `late_initcall`. The kernel therefore completes the *entire* initcall
   sequence, including every driver probe. The v35 guess that it halted before
   `late_initcall` was wrong, and the "green garbage might be HDMI noise"
   hypothesis is dead too - the display provably tracks kernel activity.

The board was never as broken as three sessions of instrument failures implied.

### The real blocker, located

The heartbeat *continuing* is itself the clue. `diagnostic-init.c` grabs the LED
immediately (`trigger` -> `none`, then 5 s solid). A steady heartbeat means
**`/init` never ran**, while the kernel stayed alive - which rules out a panic.

`init/main.c` (verified in 6.18.39 source, not from memory):

```c
ramdisk_command_access = init_eaccess(ramdisk_execute_command);
if (ramdisk_command_access != 0) {
        pr_warn("check access for rdinit=%s failed: %i, ignoring\n", ...);
        ramdisk_execute_command = NULL;
        prepare_namespace();
}
```

If `/init` is not accessible in the unpacked initramfs the kernel **silently
abandons it** and falls into `prepare_namespace()`, where `rootwait` blocks
forever on a root device this board never registers. A healthy kernel waiting
forever looks exactly like a hung one - which is why every previous LED probe
was uninterpretable.

Ruled out along the way (checked, not assumed):

- wrong CCU/pinctrl driver - `CONFIG_SUN20I_D1_CCU=y` and
  `CONFIG_PINCTRL_SUN20I_D1=y` are both correct for T113-s3
- regulators gating SD power - both `regulator-fixed` nodes are
  `regulator-always-on` with no enable GPIO, so `CONFIG_REGULATOR=n` starves
  nothing
- `CONFIG_VFP=y`, `CONFIG_AEABI=y`, so the hard-float musl init is loadable

Still off from `allnoconfig`, to be restored later: `CONFIG_PM`,
`CONFIG_REGULATOR`, `CONFIG_DMADEVICES` (August already showed these alone do
not fix MMC).

### v37: remove the fallback's escape hatch

`artifacts/boot-nofallback-v37.img` (sha256 `a1bd8feb...a02b3c5d`). One variable:
the cmdline drops `root=` and `rootwait`, becoming
`console=ttyS0,115200 earlycon rdinit=/init panic=0`. Heartbeat trigger retained
as the control. Now the two cases cannot masquerade as each other:

| observation | conclusion |
| --- | --- |
| LED goes solid ~5 s, then pulse groups | `/init` runs - the built-in initramfs works on hardware, and Alpine's blocker is only MMC |
| heartbeat **stops/freezes** | `panic("VFS: Unable to mount root fs")` - `/init` is not accessible, so the initramfs itself is the fault |
| heartbeat continues forever | neither path was taken; something outside this model is wrong |

If `/init` does run, count the repeating pulses: **2 = no rootfs found**,
**4 = p5 found and mounted**.

### v37 result: heartbeats forever - and the test was flawed

Observed: heartbeat forever, third row of the table.

The test could not have decided the question anyway. `write_led()` opens with
`if (!led[0]) return;`, and `led[]` is only filled by `find_led()` scanning
`/sys/class/leds`. If sysfs fails to mount, or the directory is empty, **every
LED call in `diagnostic-init.c` silently becomes a no-op** and PID 1 spins in
its retry loop invisibly. "`/init` never ran" and "`/init` ran but could not
signal" produce byte-identical output. Building a fourth LED instrument that can
also fail silently is not worth another boot.

**Stop inferring from one bit. Get a console.**

### v38: a real console, via U-Boot's own framebuffer

The whole reason this has taken four sessions is the missing console, and the
board has had one available the entire time. U-Boot initialises the display to
draw the bootlogo, and the *running vendor system* recorded exactly where it put
it (`system-report.txt`, `/proc/cmdline`):

    disp_reserve=3686400,0x4bee8c00
    boot_fb0 = "4bee8c00,500,2d0,20,1400"

3686400 == 1280*720*4, and 0x500/0x2d0/0x20/0x1400 == 1280 wide, 720 high,
32bpp, 5120 stride. This is measured from hardware, not inferred. Note also that
the vendor bootargs themselves carry `clk_ignore_unused` - the vendor needs it
for the same reason we do.

Verified against 6.18.39 source before building, rather than from memory:

- `drivers/of/platform.c:576` finds the node with
  `of_get_compatible_child(of_chosen, "simple-framebuffer")`, so it must be a
  **direct child of /chosen** - it is.
- `simplefb` requires `width`, `height`, `stride`, `format`; `"x8r8g8b8"` is a
  real entry in `include/linux/platform_data/simplefb.h` and matches the
  vendor's 32bpp XRGB layout.
- `FB_SIMPLE depends on !DRM_SIMPLEDRM`; DRM is off, and
  `validate-config.sh` was updated to stop forbidding `CONFIG_FB` (a stale
  milestone-1 guard) while still forbidding DRM.

Decompiled DTB confirms `/chosen/framebuffer@4bee8c00` and a `no-map`
`reserved-memory` entry over the same range, so the allocator can no longer
scribble on the picture the way v35 did.

`artifacts/boot-fbcon-v38.img`, sha256 `ea0d2d8a...ea71e71e`. Cmdline:

    console=ttyS0,115200 console=tty0 earlycon clk_ignore_unused
    pd_ignore_unused rdinit=/init loglevel=8 ignore_loglevel panic=0

Still no `root=` and no `rootwait`, which is now doubly useful: the kernel
panics instead of waiting forever, and the panic path prints *"here are the
available partitions:"* followed by every block device it knows about. On a
readable screen that one message settles whether MMC ever registered.

`panic=0` halts rather than reboots, so whatever is on screen stays there to be
photographed.

### v38 result: no text, heartbeat present

The kernel is alive (heartbeat) but nothing rendered. Everything checked out on
inspection, which is why guessing further would have been wasteful:

- `drivers/of/platform.c` creates the device unconditionally - the full
  `of_platform_default_populate_init()` has no branch that skips our node
- `simplefb_probe` even survives `request_mem_region` failure, falling back to
  mapping the resource as-is
- both `simplefb_probe` and `fb_console_init` are linked into `vmlinux`
- `CONFIG_DUMMY_CONSOLE=y`, and `FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER` is off,
  so fbcon should take over the moment a framebuffer registers

One deviation from the upstream binding: its example declares `#address-cells`
and `#size-cells` **on the /chosen node itself**. Ours relies on inheriting them
from the root. That should resolve to the same values, but it is untested here.

### v39: separate the two entangled hypotheses

"No text" cannot distinguish:

- **A.** U-Boot's framebuffer is not at `0x4bee8c00`, so everything rendered
  lands in memory nobody scans out.
- **B.** The address is right and the fb/VT/fbcon plumbing never renders.

`kernel/fb-paint-probe.c.snippet` is appended to `init/main.c` (pristine copy
kept at `init/main.c.orig`) and paints the region **directly** as a
`late_initcall` - no simplefb, no fbcon, no VT, no console, no userspace, and no
way to fail silently the way an LED probe can. Verified: `ioremap_wc` exists on
ARM, and `gamestick_fb_paint_probe` is in `vmlinux` at initcall level 7.

Three horizontal bands - red, green, blue top to bottom - so the pixel format is
checked for free at the same time.

| screen | conclusion |
| --- | --- |
| red/green/blue bands | address **correct**; the fault is the fb/console plumbing (B) |
| unchanged, Tux stays | address **wrong** (A); `0x4bee8c00` must be re-derived |
| bands in the wrong colour order | address correct, pixel **format/byte order** wrong |
| partial or skewed bands | address correct, **stride** wrong |

`artifacts/boot-fbpaint-v39.img`, sha256 `7d77dbe7...4f9e92ba`, flashed and
verified.

Also worth noting for hypothesis A: v35 showed green corruption because the
kernel allocated freely over the framebuffer, but that only proves it hit *some*
scanned-out memory, **not** that the memory was at `0x4bee8c00`. If v38's screen
was clean Tux with no green, the `no-map` reservation over that exact range
successfully protected the real framebuffer, which would independently confirm
the address.

### v39 result: no change, and no corruption in v38 either

Reported: the paint made no difference, and v38's screen had no corruption. Read
naively these contradict - "no paint" says the address is wrong, "no corruption"
says the reservation over that address worked.

**The heartbeat has been over-trusted.** It is driven by a kernel timer. If the
boot thread hangs, timers keep firing and the LED keeps beating, so a heartbeat
proves the kernel is *alive*, never that it is *progressing*. And
`clk_ignore_unused` deliberately suppresses the "Tux disappears" cull, so v38 and
v39 have **no evidence of reaching `late_initcall`** - which is the only place
the v39 paint ran.

One theory covers every observation: the kernel hangs during `device_initcall`,
where simplefb and fbcon probe. Then there is no text, no paint (level 7 never
runs), and less memory allocated than v35 - so no corruption either, with or
without the reservation.

### v40: turn the screen into a boot progress bar

Four bands, each painted from a different initcall level, each in its own
quarter of the screen so they cannot overwrite one another:

| rows | colour | initcall | level |
| --- | --- | --- | --- |
| 0-179 | red | `postcore_initcall` | 2 |
| 180-359 | green | `arch_initcall` | 3 |
| 360-539 | blue | `device_initcall` | 6 |
| 540-719 | white | `late_initcall` | 7 |

Verified in `vmlinux`: `...gamestick_band_postcore2`, `..._arch3`,
`..._device6`, `..._late7` - the trailing digit is the initcall level.

| screen | conclusion |
| --- | --- |
| no bands at all | `0x4bee8c00` is the **wrong address** |
| all four bands | address right, boot completes; fault is fb/console plumbing only |
| bands stop partway | address right, and the **last band shown names the level where the kernel stops** |

Red+green but no blue would confirm the hang is in `device_initcall`, exactly
where simplefb and fbcon probe. This also finally decouples "is the address
right" from "does the kernel get there", which no previous probe managed.

`artifacts/boot-progressbar-v40.img`, sha256 `27f5f742...c021b1b38`.

### v40 result: no bands at all - the address is wrong

Reported: no bands, Tux still on screen. That settles it, because the
alternatives were eliminated rather than assumed:

- the LED heartbeats, and `gpio-leds` is a platform driver probed at
  `device_initcall`, so the kernel demonstrably reaches **level 6**
- therefore the level 2, 3 and 6 bands all executed
- `ioremap_wc` was not the failure: `arch/arm/mm/ioremap.c:318` only returns
  NULL when `memblock_is_map_memory()` is true, and `no-map` makes it false, so
  the mapping succeeded and the writes landed at physical `0x4bee8c00`
- the picture persists, so the display *is* actively scanning out from
  somewhere

**Writes to `0x4bee8c00` do not reach the scanned-out framebuffer**, even though
the running vendor system reported exactly that in `disp_reserve=`. The full
string is `boot_fb0 = "4bee8c00,500,2d0,20,1400,203,d3,2fd,1fc"`; the last four
fields are still unidentified and may encode an offset or a different layer.

The vendor DT puts the display engine at `disp@5000000`.

### v41: stop guessing the address, search for it

Guessing a replacement address - or guessing display-engine register offsets -
would repeat the mistake that has cost this project three sessions. So the top
half of DRAM is reserved `no-map` (`framebuffer@48000000`, 128 MiB; the kernel
runs in the lower 128 MiB) and painted in eight 16 MiB chunks, each a distinct
colour:

| chunk | address | colour |
| --- | --- | --- |
| 0 | `0x48000000` | red |
| 1 | `0x49000000` | green |
| 2 | `0x4a000000` | blue |
| 3 | `0x4b000000` | **yellow** - `0x4bee8c00` lives here |
| 4 | `0x4c000000` | magenta |
| 5 | `0x4d000000` | cyan |
| 6 | `0x4e000000` | white |
| 7 | `0x4f000000` | orange |

Whatever colour appears names the 16 MiB window holding the real framebuffer,
and one further boot subdivides it. Tux surviving unchanged means the buffer is
in the **lower** half of DRAM, which is the next region to sweep.

`CONFIG_FB=n` again for this build, so the suspected `device_initcall` probe
hang cannot interfere with the search. Nothing in the probe depends on simplefb,
fbcon, VT, console or userspace.

`artifacts/boot-fbhunt-v41.img`, sha256 `dae05f1c...2b2888e1`.

### v41 result: FOUND IT - and the address was right all along

Screen came back **yellow over magenta**. Yellow is chunk 3, magenta is chunk 4,
so the boundary on screen is physical `0x4c000000`. Working backwards from where
the boundary falls:

    0x4c000000 - 223 rows * 5120 - 512 px * 4 = 0x4bee8c00

- boundary 31.0% down the screen -> row 223 of 720
- the boundary **steps** 40.0% across -> pixel 512, where the transition lands
  mid-scanline

Both predictions match the photograph. The framebuffer is at **`0x4bee8c00`,
stride 5120, 1280x720x32** - exactly what `disp_reserve=` said. Three probes
concluded "the address is wrong" and all three were wrong.

### Why v39 and v40 failed: a misaligned reservation

`0x4bee8c00 & 0xfff == 0xc00` - **it is not page-aligned.**

ARM's `ioremap` checks `memblock_is_map_memory(PFN_PHYS(pfn))`, i.e. the *page*
containing the address: `0x4bee8000`. The old reservation began at the unaligned
`0x4bee8c00`, so memblock split the region there and left
`0x4bee8000-0x4bee8c00` mapped as ordinary RAM. The check saw mapped memory,
`WARN_ON` fired, `ioremap_wc()` returned **NULL**, and every paint silently did
nothing - including simplefb's own mapping, which is why v38 had no console.

v41 only worked because `0x48000000` happens to be page-aligned.

**Lesson: reserved-memory regions must be page-aligned at both ends.** The
reservation is now `framebuffer@4bee8000`, `reg = <0x4bee8000 0x385000>`,
rounding both ends out to page boundaries while still covering
`0x4bee8c00 + 0x384000`.

### v42: the console, with a fallback marker

- `CONFIG_FB`/`FB_SIMPLE`/`VT`/`FRAMEBUFFER_CONSOLE`/`FONT_8x16` back on
- `/chosen/framebuffer@4bee8c00` simplefb node unchanged
- reservation now page-aligned
- the probe paints only a green band across the top 32 rows at
  `postcore_initcall`, early, as a fallback signal

fbcon clears the screen when it takes over, so the two signals cannot be
confused:

| screen | conclusion |
| --- | --- |
| **console text** | simplefb and fbcon both work - console achieved |
| green band, no text | address and alignment fixed, but fbcon never rendered |
| neither, Tux stays | the reservation fix did not take effect |

`artifacts/boot-console-v42.img`, sha256 `62791477...61a44d15`.

### v42 result: green band present, still no console

The band rendered. **`ioremap_wc(0x4bee8c00)` now works and kernel code can write
to the display reliably** - the misaligned reservation really was the whole
problem, and the capability missing for four sessions now exists.

But the screen was not cleared and Tux survived, so fbcon still never took over.
simplefb/VT/fbcon remain silent for reasons that repeated inspection has not
explained.

### v43: skip fbcon, render text directly

fbcon is not worth further guessing when the framebuffer itself is now proven
writable. `kernel/fb-paint-probe.c.snippet` implements a minimal console using
only the framebuffer and the built-in VGA 8x16 font - no simplefb, no VT, no
fbcon, no console layer, no userspace. 1280x720 at 8x16 gives **160 columns x 45
rows**.

Verified present in `vmlinux`: `find_font`, `font_vga_8x16`,
`gamestick_fbcon_init` (initcall level 7), `gs_kmsg_dump`.

Two triggers, because the message that matters arrives *after* every initcall -
`prepare_namespace()` panics only once `kernel_init` reaches it:

- `late_initcall` renders the boot log so far, proving the renderer works
- a registered `kmsg_dumper` (`max_reason = KMSG_DUMP_MAX`) re-renders on
  panic/oops, capturing the VFS panic and its partition list

`kmsg_dump_get_buffer()` returns the *newest* records that fit, and `gs_render()`
additionally skips to the tail so the last 45 rows are what remain on screen.

The framebuffer is mapped **once** at `late_initcall` and the pointer retained,
because `ioremap()` allocates and is not safe to call from panic context.

If the font is somehow missing, a red bar is drawn instead of failing silently.

`artifacts/boot-fbconsole-v43.img`, sha256 `7d3688da...04f3da0b`.

### v43 result: CONSOLE ACHIEVED - and it named the bug

Kernel log text rendered on screen. Four sessions of inferring from a blinking
LED are over; the board now prints its own diagnosis:

    simple-framebuffer chosen:framebuffer@4bee8c00: No memory resource
    simple-framebuffer chosen:framebuffer@4bee8c00: probe with driver simple-framebuffer failed with error -22
    sunxi-sram 3000000.syscon: probe with driver sunxi-sram failed with error -95

"No memory resource" is exactly the branch read out of `simplefb_probe` earlier:
`platform_get_resource(pdev, IORESOURCE_MEM, 0)` returned NULL, so -EINVAL/-22.
The platform device *was* created from `/chosen` - the node and compatible were
always fine. Its `reg` simply never became a resource.

### Why: /chosen had no `ranges`

This was noticed at v38, recorded as "should resolve to the same values", and
wrongly set aside. From `drivers/of/address.c`:

```c
ranges = of_get_property(parent, rprop, &rlen);
if (ranges == NULL && !of_empty_ranges_quirk(parent) &&
    strcmp(rprop, "dma-ranges")) {
        pr_debug("no ranges; cannot translate\n");
        return 1;                /* translation fails */
}
if (ranges == NULL || rlen == 0) {
        offset = of_read_number(addr, na);
        ...                      /* empty ranges -> 1:1 translation */
```

`#address-cells`/`#size-cells` do resolve by inheritance from the root, so that
part of the reasoning was right - but **`ranges` does not inherit**, and without
it `of_translate_one()` refuses to translate at all. Every in-tree DT that puts
`simple-framebuffer` under `/chosen`
(`sm8250-samsung-common.dtsi`, `msm8953-flipkart-rimob.dts`,
`sdm450-lenovo-tbx605f.dts`) declares all three.

### v44: three lines

`/chosen` now carries `#address-cells = <1>`, `#size-cells = <1>` and an empty
`ranges;`, confirmed in the decompiled DTB. Nothing else changed.

Expected: simplefb binds, fbcon takes over, and the console becomes a normal
scrolling one instead of a 45-row snapshot. The direct renderer and its panic
`kmsg_dumper` are retained as a safety net and to guarantee the *tail* of the log
survives on screen.

Still outstanding from v43's log, to chase once the console is solid:

- `sunxi-sram 3000000.syscon: probe ... failed with error -95` (-EOPNOTSUPP)
- no MMC lines were visible in the captured window; the panic and its
  "available partitions:" list are still the target

`artifacts/boot-simplefb-fixed-v44.img`, sha256 `03ba641d...6754269a`.

### v44 result: fbcon works, /init runs, and MMC named its own bug

The `ranges;` fix landed - the clean left-aligned text is fbcon, with the crude
direct renderer's leftovers stranded at the right edge of the screen. **The
direct renderer can now be removed**; it has done its job.

Three findings, all read directly off the screen rather than inferred:

**1. `/init` runs.**

    Run /init as init process
      with arguments: /init
      with environment: HOME=/ TERM=linux

The built-in initramfs has worked the entire time. Every LED probe that implied
otherwise was measuring its own inability to signal, not the kernel.

**2. USB enumerates.** EHCI/OHCI controllers on 4101000/4200000/4200400/4101400,
four buses registered, hubs found, ports detected.

**3. MMC probes, then rejects the card:**

    sunxi-mmc 4020000.mmc: initialized, max. request size: 2048 KB, uses new timings mode
    sunxi-mmc 4020000.mmc: no support for card's volts
    mmc0: error -22 whilst initialising SD card
    mmc0: Failed to initialize a non-removable card

Also present, harmless for now: `Warning: unable to open an initial console.`
(the initramfs has no `/dev/console` node; `rdinit=` still runs).

### The MMC bug: CONFIG_REGULATOR

`mmc_select_voltage()` does `ocr &= host->ocr_avail` and warns "no support for
card's volts" when nothing overlaps. `host->ocr_avail` is filled in by
`mmc_regulator_get_supply()` from `vmmc-supply = <&reg_vcc3v3>` - which is a
**stub when CONFIG_REGULATOR=n**, so `ocr_avail` stayed empty and no card
voltage could ever match.

`CONFIG_REGULATOR` was one of the three symbols `allnoconfig` silently dropped,
and it was explicitly examined at v36 and dismissed with: *"both regulator-fixed
nodes are regulator-always-on with no enable GPIO, so CONFIG_REGULATOR=n starves
nothing."* That is true of **power** and irrelevant here - the regulator's other
job is supplying the **OCR voltage mask**, which is pure software. Ruled out on
the wrong axis.

### v45

- `CONFIG_REGULATOR=y`, `CONFIG_REGULATOR_FIXED_VOLTAGE=y`
- drop the direct framebuffer renderer from `init/main.c` (restore from
  `init/main.c.orig`) now that fbcon owns the console

If MMC initialises, `mmcblk0` and its partitions appear, and the remaining work
for Alpine is small.

### v45 result: IT BOOTS. Shell prompt on mainline 6.18.39.

`CONFIG_REGULATOR=y` was the last blocker. The board reached a shell:

    Game Stick Linux
    Kernel: 6.18.39
    / #

That prompt proves the entire chain end to end:

1. mainline 6.18.39 boots on the H133 / T113-s3
2. `sunxi-mmc` initialises the card - `ocr_avail` now populated from
   `vmmc-supply` via the regulator framework
3. `mmcblk0p5` exists as a block device (a first for this board on mainline)
4. the built-in initramfs `/init` runs, finds the root, mounts it, chroots
5. the rootfs `/sbin/init` starts and reaches an interactive shell
6. HDMI console via `simple-framebuffer` + fbcon, no display driver at all

Working: MMC, USB (4 buses, hubs enumerating), HDMI console, pinctrl/GPIO, LED,
serial (unused - no adapter), built-in initramfs.

### What actually cost four sessions

Not one hard bug. Four independent faults, each of which made the others
unreadable:

| fault | effect |
| --- | --- |
| empty built-in initramfs (v7-v15) | `/init` genuinely absent; config/binary drift |
| no LED trigger in the DTS | dark LED meant "not asked to light", not "kernel dead" |
| `no-map` reservation unaligned by 0xc00 | `ioremap_wc()` returned NULL, so simplefb **and** every paint probe silently no-oped |
| `/chosen` missing `ranges` | `reg` never became a resource: "No memory resource", -22 |
| `CONFIG_REGULATOR=n` | `ocr_avail` empty -> "no support for card's volts" |

The pattern worth remembering: **every one of these failed silently**, and the
instrument used to detect them (an LED) could fail the same silent way. Progress
only became possible once the board could print - and the console was available
from v38 onward, blocked by a 3-line DT omission and a 0xc00 misalignment.

### Next

- boot `root=/dev/mmcblk0p5` directly and retire `diagnostic-init.c`; the
  initramfs was a workaround for having no console
- restore `rootwait` and a real `root=` in `CONFIG_CMDLINE`
- put Alpine on p5 (the original milestone; p5 currently holds the stripped
  vendor-derived rootfs)
- investigate `sunxi-sram 3000000.syscon: probe ... failed with error -95`
- add `/dev/console` to the initramfs if it is kept (`unable to open an initial
  console`)

## MILESTONE REACHED: Alpine 3.24 on mainline 6.18.39

Confirmed on hardware:

    Welcome to Alpine Linux 3.24
    Kernel 6.18.39 on an armv7l (/dev/tty1)
    gamestick login:

- **MMC**: `mmc0: new high speed SDXC card at address aaaa`,
  `mmcblk0: mmc0:aaaa SD64G 59.5 GiB`, `p1 p2 p3 p4 p5`,
  `EXT4-fs (mmcblk0p5): mounted filesystem ... r/w`
- **USB keyboard**: `hid-generic 0003:1C4F:008F.0001: input: USB HID v1.11
  Keyboard [LIZHI Flash IC USB Keyboard]`, four `/dev/input/event*` nodes
- **RAM**: 243 MiB total, 229 MiB available
- **HDMI console**: simple-framebuffer + fbcon, no display driver
- openrc boots; dropbear generated RSA/ECDSA/ED25519 host keys

### Rootfs build (p5)

Alpine 3.24.1 armv7 minirootfs (checksum verified), then 73 packages
cross-installed from the host with `apk.static --arch armv7` - no qemu needed:
`openrc util-linux agetty e2fsprogs dropbear chrony haveged nano`.

**Cross-install caveat:** apk triggers are armv7 binaries and cannot execute on
an x86_64 host. Three failed, and one casualty was `rc-update` - so
`/etc/runlevels/*` came out **empty** and openrc would have booted into nothing.
The symlinks were created by hand. Any future cross-install must re-check the
runlevels.

`/etc/inittab` keeps `tty2::respawn:/bin/ash -l` as a passwordless rescue shell.
Remove it once the boot is trusted.

### Known issues

- `service 'acpid'/'hwdrivers'/'machine-id'/'watchdog' needs non existent
  service 'dev'` - Alpine's `dev` virtual service comes from mdev or udev and
  the minirootfs has neither. Fix: `apk add busybox-mdev-openrc mdev-conf`, then
  add `mdev` to the sysinit runlevel. Matters mainly because `hwdrivers` is what
  autoloads modules by modalias.
- `ERROR: cannot start crond as swclock would not start` - `swclock` restores
  time from a saved shutdown timestamp that does not exist on a first boot.
- **11-second deferred-probe delay before MMC**: `Waiting for root device` at
  0.41 s, `sunxi-mmc ... initialized` at 11.75 s. Resolves on a retry pass, but
  it is most of the boot time. Suspect a clock/reset/regulator ordering issue.
- No RTC: the SoC has `rtc@7090000` but `CONFIG_RTC_CLASS` is off, so there is
  no `/dev/rtc0` and `hwclock` cannot work.
- **WiFi**: the RTL8188ETV (`0bda:0179`) `8188eu.ko` was built against vendor
  5.4.61 and will not load on 6.18.39. Check whether mainline `rtl8xxxu` claims
  this device.

## v53 - HDMI/DRM port (built, not yet booted)

The first attempt at a real display driver, replacing the U-Boot-inherited
`simple-framebuffer` with DRM/KMS. This unlocks HDMI audio and the DE2 hardware
scaler, which is why it comes before either of those.

### What was actually missing upstream

Less than the earlier notes in this file implied. Re-checked against 6.18:

- The DE2 mixers, TCON-LCD/TV and TCON-TOP are **all present** in
  `sunxi-d1s-t113.dtsi` with `sun20i-d1` compatibles, and the pipeline is wired
  `mixer0 -> tcon_top -> tcon_tv0 -> tcon_top_hdmi_out`.
- `ccu-sun20i-d1.c` **already implements** `CLK_BUS_HDMI`, `CLK_HDMI_24M`,
  `CLK_HDMI_CEC` and `RST_BUS_HDMI_{MAIN,SUB}`. The clock plumbing, usually the
  tedious part, was done.
- What is missing is only (a) the HDMI PHY driver and (b) the two DT nodes.
  `tcon_top_hdmi_out` is a dangling `port@5` because there is nothing to point at.

### The PHY

The D1/T113 does not use the Synopsys PHY that `sun8i_hdmi_phy.c` already
handles for the A83T and H6. Samuel Holland wrote a driver for the custom one in
2022 and never upstreamed it - it lives on `smaeul/linux` branch
`d1/hdmi-support`, and the load-bearing commit is titled
`[HACK] drm/sun4i: Copy in BSP code for D1 HDMI PHY`. That is why it never
landed: BSP register pokes against a header of magic bitfield offsets.

Forward-ported to 6.18 in `kernel/patches/0001-drm-sun4i-add-D1-T113-HDMI-PHY.patch`.
The port is mechanical - `dw_hdmi_phy_ops` and `phy_force_vendor` are unchanged
between 6.2 and 6.18 - so only the D1 additions were carried over, not the API
drift in the original commits.

Confirmation that the BSP data really is for this hardware: the d1-wip DT node
is `hdmi@5500000` with `interrupts = <109>`, and the vendor DT has the same node
at the same address with `0x5d` (93). The 16 difference is exactly the RISC-V
vs `SOC_PERIPHERAL_IRQ()` offset. Same check on the video engine: 82 vs 66.

### simplefb is deliberately kept as a fallback

`FB_SIMPLE` depends on `!DRM_SIMPLEDRM`, **not** on `!DRM`. So with
`DRM_SIMPLEDRM=n` both can be built in:

- if `sun4i-drm` binds, `aperture_remove_all_conflicting_devices()` evicts
  simplefb and `drm_client_setup()` puts fbcon on the DRM fbdev;
- if it fails to probe, simplefb survives and the HDMI console still works.

This is why `DRM_SIMPLEDRM` moved into the validator's forbidden list rather
than `DRM` simply being deleted from it.

**The fallback is not total.** It only covers a driver that fails *before*
touching the hardware. If the PHY binds and then produces a bad signal, the
TCON has already been reprogrammed out from under the U-Boot-configured
display and the screen goes black regardless. Recovery is to pull the card and
restore `artifacts/boot-userns-v52.img`.

### Build notes

- `&soc` does not work: the upstream `soc` node carries no label. Reopen it by
  path with `/ { soc { ... } }`.
- No tmds clock on this HDMI node - the PHY makes its own TMDS clock from its
  PLL - so `sun8i_dw_hdmi.c` had to switch to `devm_clk_get_optional()`.
- zImage grows 3.05 MB -> 3.28 MB. `CMA_SIZE_MBYTES=32`.
- `CONFIG_MODVERSIONS` is off and the module set is byte-identical to v52, so
  the modules already on the device keep loading. No `/lib/modules` reinstall.

Backups before this change: `backups/v52-working-kernel-backup.tar.gz` (config,
zImage, DTB, boot image, modules, sources) and, in the VM,
`~/kernel-src-backup-pre-hdmi/` plus `~/gcc14-test/build-gcc14/`.

## v55/v56 - HDMI audio, and the reboot bug that was never actually fixed

### HDMI audio

The path mainline needs is the same one the vendor uses: `i2s2@2034000` feeding
the codec the HDMI controller exposes. `i2s2` is already in the upstream DTSI
and `sun4i-i2s` claims it through the `allwinner,sun50i-r329-i2s` fallback, so
the DT work was only: mark `i2s2` okay, give the `hdmi` node
`#sound-dai-cells = <0>`, and add a `simple-audio-card` linking the two.

`sound-dai = <&hdmi>` resolves even though dw-hdmi's codec is a bare platform
device with no `of_node` of its own: `soc_component_to_node()` falls back to
`component->dev->parent->of_node`, and dw-hdmi registers the codec with
`parent = hdmi dev`.

**v55 failed**, and not for the reason expected. The worry was
`HDMI_CONFIG0_I2S` - whether this HDMI TX was even synthesised with I2S. The
real cause was much duller:

```
sun4i-i2s 2034000.i2s: Missing dma channel for stream: 0
asoc-simple-card hdmi-sound: ASoC: can't create pcm ... :-22
```

`CONFIG_DMADEVICES` was off, so `sun6i-dma` did not exist and the i2s
controller could not get its channels. **A seventh allnoconfig casualty**,
after REGULATOR, HID, WATCHDOG, COMPAT_32BIT_TIME, INOTIFY_USER and SYSVIPC.
`DMADEVICES` + `DMA_SUN6I` fixed it.

Working in v56:

```
 0 [H133HDMI       ]: simple-card - H133-HDMI
card 0: device 0: 2034000.i2s-i2s-hifi
FORMAT: S16_LE S24_LE S32_LE   CHANNELS: 2   RATE: [32000 48000]
```

### Reboot: CONFIG_SUNXI_WATCHDOG was necessary but not sufficient

v48 claimed to fix reboot by enabling `CONFIG_SUNXI_WATCHDOG`. **That was
wrong.** Reboot never worked; it was masked because the board was being
power-cycled by hand each time.

Both watchdog nodes are `status = "reserved"` in the upstream DTSI:

```
/proc/device-tree/soc/watchdog@20500a0
  status: reserved
```

`of_device_is_available()` rejects anything that is not `okay`, so `sunxi-wdt`
never bound, `/sys/class/watchdog/` was empty, and no restart handler was ever
registered. This SoC has no PSCI firmware either, so `reboot` had nothing at
all to reset the machine with and halted.

`&wdt { status = "okay"; }` fixes it - the driver matches the node's second
compatible and registers a restart handler at priority 128. It does not arm the
watchdog: nothing opens `/dev/watchdog` and no watchdog daemon is installed.
Verified by an unattended reboot that came back in **30 seconds**.

**Lesson, and it is the same one as the allnoconfig casualties:** setting the
config symbol is not evidence the driver bound. Check `/sys/class/<subsystem>/`
before claiming a fix. A test that requires the user to intervene (power cycle)
cannot distinguish "works" from "does not work".

Related trap: a reboot issued from the *running* kernel exercises that kernel's
restart handler, not the one just flashed to p4. Testing a reboot fix requires
booting into it first.

### X moved from fbdev to KMS

`10-fbdev.conf` is superseded by `10-modesetting.conf` (old one kept at
`/root/10-fbdev.conf.disabled`). There is still no GPU, so `AccelMethod "none"`
is deliberate - glamor over llvmpipe is slower than the shadow-buffer path -
but modesetting on real KMS gets page-flipped, vsynced updates that fbdev never
had.

The console runs at the panel's preferred 1920x1080 while **X is pinned to
1280x720**: 1080p is 2.25x the pixels, which is a lot to compose in software.
The two are independent, so this costs nothing on the console.

## v57-v60 - audio actually works, and CPU1 can be started

### HDMI audio works (v57). Earlier "digital silence" was a bad measurement.

The `HUB_EN` patch in `kernel/patches/0002-ASoC-sun4i-i2s-internal-audio-hub.patch`
fixed HDMI audio. Confirmed by ear and by register read: `0x14 = 800400f5`,
bit 31 set, during playback.

**The "digital silence, peak exactly 0" measurement that follows it in the
earlier notes was wrong.** The tone was started over ssh with
`nohup speaker-test ... &` and no `setsid`, so it almost certainly died with the
session teardown; five seconds of nothing playing was recorded and reported as
proof that no audio reached the wire. Every conclusion built on top of that -
including "CTS = 297000 is the remaining fault" - is unsupported. CTS really is
297000 where 148500 was expected, but audio works, so that is not the fault.

**Only 48 kHz works.** `pll-audio1` is fixed at 3072000000 and nothing
reconfigures it per stream, so 32000 and 44100 fail with EINVAL while the PCM
advertises `RATE: [32000 48000]`. That mismatch is why `plughw` does not help -
plug picks 44100 as nearest to the source and hands it to hardware that cannot
do it. Force 48 kHz (`--audio-samplerate=48000`).

### CPU1 can be started: the Thumb bit was the blocker

`0003-arm-psci-log-cpu_on-return.patch` logs the PSCI return, which gave:

    psci: CPU1 cpu_on(mpidr=0x1, entry=0x40108009) returned 0

Return 0 means the firmware accepted the call, so CPU1 started and then never
came online. The entry address is **odd** - bit 0 is the Thumb bit, because
`CONFIG_THUMB2_KERNEL=y` makes `&secondary_startup` a Thumb function pointer.
The vendor firmware's PSCI was only ever exercised by Allwinner's ARM-mode 5.4
kernel, so it evidently jumps in ARM state and CPU1 faults immediately.

With `CONFIG_THUMB2_KERNEL=n` (v60):

    smp: Brought up 1 node, 2 CPUs
    SMP: Total of 2 processors activated (96.00 BogoMIPS).

**But v60 is not stable.** It hangs at varying points - sometimes at the Tux
logo, sometimes a minute into the simplefb stage, sometimes after openrc. That
is a race signature, not a codegen bug: this port has never run SMP before.
Prime suspect is cache coherency (on Cortex-A7 the ACTLR.SMP bit must be set per
core, and the vendor PSCI may not set it for the secondary); `dma-noncoherent`
on the soc node is the other.

**v60 is currently flashed and hangs. Revert to v57 + the Thumb-2 modules.**

### Module vermagic is tied to THUMB2_KERNEL

Changing `CONFIG_THUMB2_KERNEL` changes module vermagic
(`... ARMv7 thumb2 p2v8` vs `... ARMv7 p2v8`), so every module must be rebuilt
and reinstalled with the kernel. v56's note that modules survive kernel changes
was true for that change and does not generalise. On the card,
`/lib/modules/6.18.39.thumb2.bak` holds the Thumb-2 set; the ARM-mode set is in
`artifacts/modules-v60-armmode.tar.gz`. **Kernel and modules are now a matched
pair - always flash both.**

### Corrections to earlier entries

- **`sunxi-sram 3000000.syscon: probe failed with error -95` is fixed.**
  `/sys/kernel/debug/sram` exists and the probe succeeds. Stale known-issue.
- **CPU clock is 1008 MHz**, read from `clk_summary`, not the 837 MHz measured
  by timing dependent ALU ops (those cost ~1.2 cycles, not 1). cpufreq is worth
  much less than earlier notes implied - 1.008 of a rated 1.2 GHz.
- **`CONFIG_CMA_SIZE_MBYTES` is now 64.** 32 was too small: each 1080p buffer is
  8.3 MB and mpv failed with "Cannot create dumb buffer: Out of memory".
- **Cedrus is not a copy-paste.** `sunxi_sram_claim()` needs an `allwinner,sram`
  property pointing at an SRAM section node, and mainline's
  `sun20i_d1_sramc_variant` defines no sections. Picking a compatible without
  documentation would be a guess.
- **The SD card enumerated as `/dev/sdd`, not `/dev/sdc`** (sdc was an empty
  reader slot). Verify by GPT disk id `AB6F3888-569A-4926-9668-80941DCB40BC`,
  never by device name.

### Next session

1. Revert to v57 + Thumb-2 modules to get a working machine back.
2. Add `ramoops`/pstore before any further SMP work - without it every hang
   destroys its own evidence, which is why v60 was debugged blind.
3. Build ARM mode + `maxcpus=1` as a control: if stable, the fault is
   definitively SMP and not the instruction set change.
4. Then investigate ACTLR.SMP / coherency.

## SMP: three dead hypotheses and one live lead (2026-08-24)

> **Superseded.** The "live lead" below - the vendor PSCI trampoline - was
> wrong, and so was the warm-reset breadcrumb plan it proposed. The real cause
> was an uninitialised `CNTVOFF`; see "SOLVED: two cores" at the end of this
> file. Kept for the dead hypotheses, which are still worth not repeating.

Facts established:
- `CONFIG_THUMB2_KERNEL=y` was why CPU1 never started. The Thumb bit made the
  PSCI entry point odd (`entry=0x40108009`); `CPU_ON` returned 0 and the core
  died immediately. ARM mode brings both cores up: "Brought up 1 node, 2 CPUs".
- **ARM mode alone is stable.** v61/v62 with `maxcpus=1` run fine, so the
  instruction-set change is not the problem - SMP is.
- Onlining CPU1 at runtime kills the machine **instantly and silently**: no
  oops, no panic, no softlockup, and nothing in the ramoops console log beyond
  `Run /sbin/init`. `SOFTLOCKUP_DETECTOR` and `DETECT_HUNG_TASK` are compiled in
  and never fire, so the kernel does not survive long enough to notice.
- **ACTLR bit 6 (SMP) is SET on CPU0** (`ACTLR=0x00006040`), so coherency is
  configured and firmware is not blocking non-secure ACTLR writes via NSACR.

Dead hypotheses: firmware rejecting `CPU_ON` (it returns 0); ARM mode being
broken (stable at `maxcpus=1`); ACTLR/NSACR blocking coherency setup (bit 6 is
set).

**Live lead: the vendor firmware's PSCI trampoline.** Mainline U-Boot's
`psci_cpu_on()` (arch/arm/cpu/armv7/sunxi/psci.c) points the secondary at its
own `psci_cpu_entry` and then does `sunxi_cpu_invalidate_cache(cpu)` before
releasing reset. A secondary started **without** its L1 invalidated comes up with
garbage in cache and corrupts memory immediately - which matches the symptom
exactly. If the vendor's trampoline skips that (or mishandles the secure/
non-secure transition), no kernel-side change can fix it.

That points at replacing the vendor boot chain with **mainline U-Boot, which has
supported the T113-s3 since v2024.01**. Bigger job than a kernel patch, but it is
the honest path to two cores.

Cheaper intermediate: patch the secondary startup path to write a magic value to
a fixed scratch address at several points, then read it back after a
watchdog-induced warm reset. That would show how far CPU1 actually gets.

### ramoops works - and the earlier failures were procedural

Placement at `0x4fe00000` (top of RAM) was fine; the "U-Boot relocates there and
clobbers it" theory was wrong. **The only reason pstore came back empty was
power-cycling**, which loses DRAM. A watchdog-induced warm reset preserves it and
the log is readable from `/sys/fs/pstore/console-ramoops-0`.

The watchdog is registered but **not armed** at boot - "Watchdog enabled
(timeout=16 sec, nowayout=0)" is printed on registration, not on arming. To make
a hang self-recover, arm it from userspace first:

    doas sh -c 'exec 3>/dev/watchdog; while true; do printf 1 >&3; sleep 5; done' &

Then a hang stops the petting and the SoC resets itself in ~16 s, warm, with
pstore intact.

## SOLVED: two cores. The vendor firmware never initialised CNTVOFF (2026-08-28)

`nproc` returns 2. Both cores survive sustained load. The live lead recorded in
the previous section - the vendor PSCI trampoline - was **wrong**, as were two
other theories built on top of it.

The actual bug: **the vendor firmware leaves `CNTVOFF` uninitialised on the
secondary core.** Linux reads the virtual counter, `CNTVCT = CNTPCT - CNTVOFF`,
so with garbage in `CNTVOFF` on CPU1 the two cores disagree about what time it
is. `ktime_get()` then returns a different answer depending on which CPU calls
it, and every timer deadline, scheduling decision and printk timestamp in the
system becomes unreliable the moment CPU1 joins.

The whole fix is three lines of DTS:

    / {
        timer {
            arm,cpu-registers-not-fw-configured;
            clock-frequency = <24000000>;
        };
    };

On ARM that property makes `arm_arch_timer` use the **physical** counter, which
has no per-core offset. `sun6i-a31`, `sun8i-a23-a33` and `sun9i-a80` all carry
it for the same reason; 25 boards do ARM-wide. Confirmation is one word in the
boot log:

    arch_timer: cp15 timer running at 24.00MHz (phys).

`CNTVOFF` is writable only from HYP mode. The kernel does try - `secondary_startup`
calls `__hyp_stub_install_secondary`, which zeroes it - but this firmware enters
Linux in SVC, so that path never runs.

The timer node has no label upstream, so it needs the path form, the same trap
as `&soc` in the HDMI work. `clock-frequency` is required because the property
means `CNTFRQ` cannot be trusted either; 24 MHz matches `&dcxo` in the SoC
dtsi, and was checked afterwards against the host clock (20.02 s measured on the
stick for a 20.0 s interval).

### The evidence, and how much of the search was wasted

The diagnosis came from two consecutive lines of kernel log with both cores up:

    [    3.069790] devtmpfs: mounted
    [ 7484.437214] Freeing unused kernel image (initmem) memory: 1024K

The jump lands exactly where CPU1 comes online, and the offset is **constant**
at ~7481 s across every later sample - 26.19 -> 7527.58, then +40 s steps. A
fixed offset, not drift, which is the signature of a bad `CNTVOFF` rather than a
wrong clock rate. Every message from CPU1 carried it:

    watchdog: BUG: soft lockup - CPU#1 stuck for 21s! [swapper/1:0]

That also retroactively explains v60's "ARM mode brings both cores up but is
unstable", which sat unexplained in this file for four days. It was never
instability. It was two cores keeping different time.

**None of the instrumentation built to find this was necessary.** The decisive
evidence was a soft-lockup message visible on HDMI the moment a two-core kernel
booted. Booting `maxcpus=1` as a "control" in v61 hid the bug for a week: it
removed the only condition under which the symptom appears. The lesson is that a
control which suppresses the phenomenon is not a control.

### v65-v69: a diagnostic ladder, mostly built on sand

Recorded because the dead ends cost real time and two of them are worth not
repeating.

- **v65 - DRAM breadcrumbs, self-test.** An earlier run reported no markers at
  all, not even the one CPU0 writes before starting the secondary, which is
  equally consistent with "CPU1 died early", "the hang corrupted DRAM" and "this
  never worked". Adding an unconditional self-test slot settled that the write
  path was fine: `phys_to_virt(0x4c270000)` -> `0xcc270000` -> back, and the
  value read back from DRAM after a clean+invalidate.
- **Warm reset on this board is a coin flip, and that killed the whole
  approach.** boot0 re-runs DRAM init against a live controller. The outcomes
  are preserved memory, corrupted memory, or a hang before the kernel is
  entered - and three consecutive `reboot`s hung black, each costing a power
  cycle. An earlier note in this file treated warm reset as reliable on the
  strength of **one** successful watchdog reset. It is not. Any technique that
  depends on DRAM surviving a reset here is unsound.
- **v66/v67 - the framebuffer as the channel instead.** The display engine DMAs
  out of DRAM and does not care that both CPUs are wedged, so a band painted by
  CPU1 stays on screen at the instant the machine dies. No reset involved.
  First attempt failed with "no 32bpp framebuffer": DRM zeroes
  `fix.smem_start` unless `CONFIG_DRM_FBDEV_LEAK_PHYS_SMEM` is set. No physical
  address is needed at all - sun4i installs `drm_gem_fb_create`, leaving
  `fb->funcs->dirty` NULL, so fbdev emulation takes its non-shadowed path and
  `info->screen_buffer` is the scanout buffer itself.
- **v68 - assembly markers in `head.S`.** A stripe painted at the top of
  `secondary_startup` with the MMU still off, via `adr_l` (PC-relative, so
  physical) and an uncached store. Result: **only CPU0's band appeared.** That
  killed the leading theory - CPU1 was not running incoherently with invisible
  stores, it was executing nothing at all.
- **v69 - drop `maxcpus=1`.** The magenta stripe appeared, so CPU1 *does* run
  when started at boot. This build could barely boot; that is the timer bug
  biting immediately, and it is what forced the SD-card-reader flash of v70.

Dead theories, for the record: incoherent secondary caches (there were no
stores); Linux clobbering the firmware's PSCI trampoline (CPU1 runs fine at
boot); ACTLR/NSACR blocking coherency setup (bit 6 was already set).

One loose end never closed: on the **hotplug** path CPU1 executed nothing, while
at boot it runs. The timer bug does not explain that difference. It is moot now
that hotplug is compiled out, but it was not solved.

### v71: hotplug removed, diagnostics stripped

`CONFIG_HOTPLUG_CPU=n`. The vendor PSCI can start a core but cannot cleanly stop
one - `echo 0 > /sys/devices/system/cpu/cpu1/online` hangs the machine hard,
needing a power cycle. Disabling hotplug makes that `CPU_OFF` path unreachable
rather than merely unused, and `/sys/devices/system/cpu/cpu1/online` no longer
exists.

`arch/arm/kernel/smp.c` and `head.S` are back to pristine upstream; the
`breadcrumb@4c270000` reservation is gone from the DTS and patch 0004 is
deleted. Patches are back to 0001-0003.

### Results

- `stress-ng --cpu 4 --matrix 2 --cache 2 --vm 1` oversubscribed on two cores
  for 123 s: 9 stressors, 0 failed, both cores pegged at 100%, and **zero kernel
  log entries** for the whole run.
- Video: a 640x360 H.264 clip with audio played end to end (2:02) with **0
  dropped frames**, using `--vd-lavc-threads=2`. The same clip dropped frames on
  one core. Decode is still pure software - Cedrus remains unavailable because
  `sun20i_d1_sramc_variant` defines no SRAM sections - so 640x360 is roughly
  what two 1.008 GHz A7s can sustain.
- Reboot works again on v71, after failing three for three on v65.

### Next

1. Higher resolutions: check the cpufreq governor is not sitting below
   1.008 GHz during playback, and whether `--vo=drm` without X buys anything.
2. The hotplug asymmetry above, if it ever matters again.
3. Mainline U-Boot is no longer needed for SMP. It would still fix warm reset,
   which remains a coin flip.
