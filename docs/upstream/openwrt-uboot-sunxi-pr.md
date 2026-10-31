# OpenWrt PR: U-Boot 2026.04 for 1.5 GB H616/H618 boards and the YT8531 warm-reboot fix

[Русская версия](openwrt-uboot-sunxi-pr.ru.md)

Ready-to-send text of a pull request to
[openwrt/openwrt](https://github.com/openwrt/openwrt) (package
`uboot-sunxi`), plus what to check before sending. The U-Boot side of the
PHY bug has its own draft: [uboot-yt8531-power-down.md](uboot-yt8531-power-down.md).

## In short

- **1.5 GB boards.** OpenWrt 25.12.x ships U-Boot 2025.01. Its H616/H618
  DRAM size detection only knows power-of-two sizes, so the 1.5 GB Zero 3
  and Zero 2W do not boot. Support came in U-Boot v2026.04 (commit
  c47b636737).
- **Ethernet after a warm reboot.** From U-Boot v2025.04 on, U-Boot no
  longer resets the PHY at start-up (commit bab54f5942). Linux powers the
  YT8531 down when eth0 goes down, a warm reboot keeps it down, and the
  next kernel fails with "EMAC reset timeout" until a power cycle. 2025.01
  still did the reset, so the old U-Boot works on Ethernet but not on
  1.5 GB, and the new one the other way round.
- This project builds U-Boot v2026.04 for the H618 boards with the reset
  restored (`uboot/patches/001-net-phy-reset-the-PHY-on-connect.patch`);
  tested on hardware.

## Before sending

1. **Sign-off.** `Signed-off-by:` with your real name and e-mail.
2. **Order.** OpenWrt usually wants the fix in U-Boot first. Test option B
   from [uboot-yt8531-power-down.md](uboot-yt8531-power-down.md) (clear
   `BMCR_PDOWN` in the Motorcomm driver only), send it to
   `u-boot@lists.denx.de`, and link that mail in the PR.
3. **Scope.** Bumping `uboot-sunxi` touches every sunxi board, and the
   maintainers will ask about that. Either test more boards or limit the new
   version to the H616/H618 boards, as this project's CI does.
4. **Commits.** One commit for the version bump, one for the patch; the
   commit message is the PR description below, cut to the point.

## PR text

**Title:** `uboot-sunxi: update to 2026.04 for 1.5 GB H616/H618 boards, restore PHY reset (YT8531 warm reboot)`

Two problems on the Orange Pi Zero 3 (Allwinner H618, sun8i-emac, Motorcomm
YT8531 RGMII PHY), one caused by the fix for the other.

**1. 1.5 GB boards do not boot with U-Boot 2025.01**

OpenWrt 25.12.x ships U-Boot 2025.01. Its H616/H618 DRAM size detection only
handles power-of-two sizes, so the 1.5 GB variants of the Zero 3 and Zero 2W
do not boot (user reports; 1 GB boards are fine). Support for
non-power-of-two sizes arrived with U-Boot commit c47b636737 ("sunxi: dram:
detect non-power-of-2 sized DRAM chips"), first released in v2026.04. With
v2026.04 (TF-A 2.10, `orangepi_zero3_defconfig`) the 1.5 GB boards boot.

**2. Updating to ≥ 2025.04 breaks Ethernet after a warm reboot**

With U-Boot v2025.04 or later, Ethernet is dead after `reboot` from Linux;
a power cycle brings it back. v2025.01 is fine.

1. At shutdown Linux brings eth0 down; phylib suspends the PHY, which sets
   `BMCR_PDOWN`.
2. A warm reset keeps the PHY powered, so it is still in power-down when
   U-Boot starts.
3. Up to v2025.01, `phy_connect_dev()` did a `phy_reset()`, which cleared
   `BMCR_PDOWN`. Commit bab54f5942 ("net: phy: Do not do CL22 phy reset
   before ethernet phy driver probe") removed it. `yt8531_config()` →
   `genphy_config_aneg()` does not touch `BMCR_PDOWN`, so the PHY stays down.
4. Without the PHY's RX clock the stmmac DMA software reset times out, and
   the next kernel fails to bring up the MAC:
   ```
   dwmac-sun8i 5020000.ethernet: EMAC reset timeout
   ```
   (open fails with `-110`; the PHY still answers on MDIO).

**This PR**

- bumps `uboot-sunxi` to v2026.04 for the H616/H618 boards;
- carries a patch that soft-resets the PHY in `phy_connect_dev()` again, as
  up to v2025.01 (`001-net-phy-reset-the-PHY-on-connect.patch`).

A narrower alternative is to clear `BMCR_PDOWN` in `yt8531_config()`
(Motorcomm driver only). That is what I intend to send upstream to U-Boot,
since bab54f5942 removed the generic reset on purpose (some PHYs must not be
reset before their driver probes). It is not yet tested on hardware; the
generic reset in this PR is.

**Tested on**

Orange Pi Zero 3 (1 GB and 1.5 GB), OpenWrt 25.12.5, Linux 6.12, U-Boot
v2026.04 + the reset patch, TF-A v2.10:
- 1.5 GB board boots;
- several warm reboots with the cable in: eth0 up at 2.6 s, link at 5.7 s,
  no `EMAC reset timeout`;
- without the patch every warm reboot ends in `EMAC reset timeout` until a
  power cycle.

Not tested: other H616/H618 boards with other PHYs (e.g. RTL8211F on the
Zero 2), and whether the generic reset affects the PHYs bab54f5942 was
meant to protect.

```
Signed-off-by: Your Name <your@email>
```
