// SPDX-License-Identifier: GPL-2.0-or-later
// Tiny PID 1 for no-UART bring-up. Avoids a shell/shebang dependency entirely.
#define _GNU_SOURCE
#include <dirent.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define SUNXI_PIO_BASE 0x02000000UL
#define SUNXI_PIO_SIZE 0x500UL
#define SUNXI_PIO_BANK_STRIDE 0x30UL
#define PB12_BANK 1U
#define PB12_PIN 12U

static char led[512];

static void direct_pb12_set(int on)
{
	int fd;
	volatile uint32_t *pio;
	uint32_t cfg;
	unsigned cfg_index = PB12_PIN / 8;
	unsigned cfg_shift = (PB12_PIN % 8) * 4;
	unsigned bank_offset = PB12_BANK * SUNXI_PIO_BANK_STRIDE;
	unsigned cfg_offset = bank_offset + cfg_index * 4;
	unsigned data_offset = bank_offset + 0x10;

	fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) return;
	pio = mmap(NULL, SUNXI_PIO_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED,
		   fd, SUNXI_PIO_BASE);
	if (pio == MAP_FAILED) {
		close(fd);
		return;
	}

	cfg = pio[cfg_offset / 4];
	cfg &= ~(0xfU << cfg_shift);
	cfg |=  (0x1U << cfg_shift); /* output */
	pio[cfg_offset / 4] = cfg;
	if (on)
		pio[data_offset / 4] |= (1U << PB12_PIN);
	else
		pio[data_offset / 4] &= ~(1U << PB12_PIN);

	munmap((void *)pio, SUNXI_PIO_SIZE);
	close(fd);
}

static void write_led(const char *name, const char *value)
{
	char path[640];
	int fd;
	if (!led[0]) return;
	snprintf(path, sizeof(path), "%s/%s", led, name);
	fd = open(path, O_WRONLY);
	if (fd >= 0) {
		(void)write(fd, value, strlen(value));
		close(fd);
	}
}

static void pulse(unsigned count)
{
	unsigned i;
	write_led("trigger", "none\n");
	write_led("brightness", "0\n");
	for (i = 0; i < count; i++) {
		write_led("brightness", "1\n"); sleep(1);
		write_led("brightness", "0\n"); sleep(1);
	}
}

static void find_led(void)
{
	DIR *dir = opendir("/sys/class/leds");
	struct dirent *entry;
	if (!dir) return;
	while ((entry = readdir(dir))) {
		if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, ".."))
			continue;
		snprintf(led, sizeof(led), "/sys/class/leds/%s", entry->d_name);
		break;
	}
	closedir(dir);
}

static int start_alpine(const char *root)
{
	int fd;
	char *const argv[] = { "/sbin/init", NULL };
	if (mount(root, "/newroot", "ext4", 0, "rw") != 0) return -1;
	mkdir("/newroot/var", 0755);
	mkdir("/newroot/var/log", 0755);
	fd = open("/newroot/var/log/gamestick-initramfs.log",
		  O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fd >= 0) {
		dprintf(fd, "binary initramfs mounted %s and is starting Alpine\n", root);
		close(fd);
	}
	sync();
	if (chdir("/newroot") == 0 && chroot(".") == 0 && chdir("/") == 0)
		execv(argv[0], argv);
	return -1;
}

int main(void)
{
	static const char *roots[] = {
		"/dev/mmcblk0p5", "/dev/mmcblk1p5", "/dev/mmcblk2p5"
	};
	unsigned i;
	mkdir("/proc", 0555); mkdir("/sys", 0555); mkdir("/dev", 0755);
	mkdir("/newroot", 0755);
	(void)mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);

	/* Direct PB12 proof path, independent of sysfs LED registration. */
	direct_pb12_set(1); sleep(5);
	direct_pb12_set(0); sleep(1);

	(void)mount("proc", "/proc", "proc", 0, NULL);
	(void)mount("sysfs", "/sys", "sysfs", 0, NULL);
	find_led();

	/* Three-second solid pulse proves this ELF PID 1 actually executed. */
	write_led("trigger", "none\n");
	write_led("brightness", "1\n"); sleep(3);
	write_led("brightness", "0\n"); sleep(1);

	for (;;) {
		int found = 0;
		for (i = 0; i < sizeof(roots) / sizeof(roots[0]); i++) {
			struct stat st;
			if (stat(roots[i], &st) != 0 || !S_ISBLK(st.st_mode)) continue;
			found = 1;
			(void)start_alpine(roots[i]);
		}
		pulse(found ? 4 : 2);
		sleep(2);
	}
}
