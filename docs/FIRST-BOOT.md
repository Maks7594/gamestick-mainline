# First-boot checklist

Before putting the image on any card:

1. Keep the original full-card image and its checksum offline.
2. Run `scripts/validate-build.sh` against the kernel build, root directory,
   boot image, and disk image.
3. Confirm the build used a real Wi-Fi config with the correct regulatory
   country and that `/etc/wpa_supplicant/wpa_supplicant.conf` is mode 0600.
4. Confirm `/root/.ssh/authorized_keys` contains the key available on the
   recovery computer, or deliberately set a temporary root password hash.
5. Confirm partition 5 is ext4 and the root boot argument is
   `/dev/mmcblk0p5 rootwait rw`.
6. Record the new image SHA-256. This project does not contain or invoke a
   flashing command.

On the first boot:

1. Keep the known RTL8188ETV installed. If possible, also attach a supported
   USB Ethernet adapter to the other port.
2. The status LED should blink while recovery networking is searching.
3. Watch the DHCP lease table for hostname `gamestick`; do not assume a fixed
   address.
4. SSH as root using the configured public key. The LED becomes solid after
   networking is ready and Dropbear is launched.
5. Immediately save:

   ```sh
   uname -a
   cat /proc/cmdline
   dmesg
   cat /var/log/gamestick-network.log
   cat /var/log/gamestick-dropbear.log
   ip addr
   ls -l /sys/bus/usb/devices
   ```

The first milestone is complete only when that SSH session is stable across a
cold boot and a delayed Wi-Fi adapter enumeration.
