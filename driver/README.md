# RTL8188ETV driver

The known adapter is USB `0bda:0179`.  This directory deliberately retains the
already-tested out-of-tree driver rather than substituting a different driver:

- source: `https://github.com/benetti-engineering/rtl8188eu.git`
- commit: `f42fc9c45d2086c415dce70d3018031b54a7beef`
- module name: `8188eu`
- firmware: `rtl8188eufw.bin` from that pinned source tree

The pinned revision already enables `CONFIG_IOCTL_CFG80211` and
`RTW_USE_CFG80211_STA_EVENT`, retaining the previously developed nl80211 path.
The numbered patches are the compatibility delta verified in the VM against
Linux 6.18.39:

- module namespace import syntax;
- current Kbuild `ccflags-y` propagation;
- timer API and private SHA-256 symbol changes;
- `from_timer()` replacement;
- current cfg80211 radio/link callback parameters.

The resulting module was depmod-indexed and verified to export the exact
`usb:v0BDAp0179` alias.
