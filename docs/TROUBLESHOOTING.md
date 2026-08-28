# Troubleshooting without UART

## No DHCP lease appears

The daemon retries forever; waiting does not consume the only recovery path.
Try a USB Ethernet adapter supported by `asix`, `ax88179_178a`, `r8152`,
`cdc_ether`, or `cdc_ncm`. It is discovered dynamically and does not need to be
named `eth0`.

If neither interface appears, inspect the ext4 root partition from another
Linux machine. The persistent evidence is in:

- `/var/log/gamestick-network.log`
- `/var/log/gamestick-network.log.old`
- `/var/log/gamestick-dropbear.log`

The USB snapshots in the network log show every enumerated VID:PID. Absence of
`0bda:0179` points to USB/PHY/DT rather than Wi-Fi credentials. Presence of the
ID followed by a `modprobe` failure points to module/firmware/ABI packaging.

## Adapter appears but no wireless interface exists

Verify the mounted root contains matching files for the exact `uname -r`:

```sh
find /lib/modules -name '8188eu.ko*'
grep -i 'usb:v0BDAp0179' /lib/modules/*/modules.alias
ls -l /lib/firmware/rtlwifi/rtl8188eufw.bin
```

Do not copy a module from another kernel build. Re-run the module installer and
`depmod` against the same kernel release.

## Association repeatedly times out

The selected backend is wpa_supplicant using nl80211. Check the country code,
SSID spelling, PSK, AP security mode, and 2.4 GHz availability. RTL8188ETV is a
2.4 GHz 802.11n adapter. The backend boundary is one executable under
`/usr/local/libexec/gamestick/`; changing it does not alter interface discovery,
DHCP, retry, logging, or Dropbear startup.

## DHCP succeeds but SSH does not

Inspect `gamestick-dropbear.log` on the root partition. Confirm root has either
a nonempty `/root/.ssh/authorized_keys` with directory mode 0700/file mode 0600
or a deliberately configured password hash. Host keys are generated on first
boot and Dropbear is restarted indefinitely after any exit.

## Kernel never reaches networking

With no UART, the useful split test is the SD card itself. If persistent logs
are absent after a powered boot, userspace probably never mounted root. Recheck
the Android boot container, appended DTB, MMC0/card-detect description, ext4
integrity, and `/dev/mmcblk0p5 rootwait rw`. Restore the stock card rather than
modifying its boot partitions in place.
