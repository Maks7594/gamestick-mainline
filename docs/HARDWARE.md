# Hardware facts and uncertainties

## Confirmed from this exact stick

- SoC: Allwinner H133 / T113-S3 family (`sun8iw20p1`), dual Cortex-A7.
- RAM: 256 MiB starting at `0x40000000`.
- Boot SD: MMC0, PF0-PF5, four-bit bus; PF6 is active-low card detect.
- UART0: PB8/PB9, 115200 baud. The pins are described but no usable physical
  UART connection is currently available.
- USB host controllers: EHCI/OHCI 0 and 1. The RTL8188ETV appeared on the
  second high-speed host in the vendor system.
- Wi-Fi USB ID: Realtek `0bda:0179`.
- USB VBUS: fixed, always-on 5 V in the vendor hardware description; no enable
  GPIO was present.
- Status LED: PB12. Polarity remains uncertain: vendor data and mainline probe
  behavior have not yet produced an unambiguous result. Timing-based probes
  must work regardless of whether the visible pulse is logically inverted.
- Vendor boot partition: Android boot image v0, 2048-byte pages, kernel address
  `0x40008000`, ramdisk address `0x41000000`, board `h133-p2nor`.

## Board identification and candidate UART header (2026-08-02)

Photographs of this exact board (red PCB) show:

- SoC marked **`MG99` / `N9058DA` / `2346`**. This matches community reports of
  "Game Stick Lite 4K with h133 renamed MG99 and 256 MB RAM", so the board is a
  known-but-undocumented H133 variant rather than a one-off.
- Two Hynix `H5TQ1G83TFR` DRAM packages (1 Gbit each = the 256 MiB confirmed
  above), a 24.000 MHz crystal, micro-USB, USB-A, microSD and HDMI.
- **A six-hole castellated tab protruding from the bottom board edge**, just to
  the right of the microSD slot and below the DRAM. It carries no silkscreen.
  This footprint - six half-plated holes on an edge tab with no surrounding
  components - is the usual vendor factory test/programming header and is the
  strongest UART candidate on the board. Pin identity is **unconfirmed**; it
  could also be SPI-flash programming or an unpopulated feature.

Community evidence (stick-ow.pro forum, thread "Консоль ОС"): a user soldered a
header to the UART on their stick and posted a photo of a live serial console,
confirming these devices do expose a working serial port. No one has published
pad locations for any variant, and a direct question about it on that forum has
gone unanswered.

Procedure to identify TX without a multimeter, once a 3.3 V USB-TTL adapter is
available:

1. clip adapter **GND** to the metal **HDMI shell** (guaranteed chassis ground);
2. touch the adapter's **RX** line - an input, so it cannot damage the board -
   to each of the six pads in turn;
3. terminal at **115200 8N1**, then power on;
4. the SoC's TX idles high and emits U-Boot output immediately, so the correct
   pad identifies itself.

Connect only GND and RX. Leave the adapter's TX unconnected and never connect
its VCC: the stick is self-powered and 5 V into a 3.3 V pin destroys it.

## Deliberately unresolved

- PCB manufacturer and exact board model. The DTS therefore uses only the
  upstream `allwinner,sun8i-t113s` fallback compatible instead of inventing a
  board compatible string.
- CPU voltage regulator details. The vendor tree used a vendor-specific PWM
  regulator. Milestone 1 leaves bootloader voltage in place and does not enable
  DVFS.
- Which externally visible connector maps to USB0. Both host controllers are
  enabled for recovery, but USB1 is the one known to contain the Wi-Fi device.
- Mainline HDMI wiring and display pipeline. They are outside this milestone.
- Whether this vendor U-Boot accepts a conventional mainline zImage with an
  appended DTB in its Android v0 container. The container addresses are known,
  but the first hardware boot remains the proof. The stock boot image must be
  retained for recovery.

The vendor DTS is evidence for board wiring only. No vendor-only clocks,
display nodes, address-management drivers, rfkill nodes, or private properties
were copied into the mainline DTS.
