# U-Boot: YT8531 left powered down after a warm reboot (draft report and patch)

Status: draft, not sent. Send after the patch below (option B) is tested on
the Orange Pi Zero 3. Option A is what this project ships and is verified on
hardware.

## How to send

U-Boot takes patches by e-mail only, plain text, no attachments:

- list: `u-boot@lists.denx.de`
- Cc: the author of the regression commit and the Motorcomm PHY / sunxi
  maintainers: `./scripts/get_maintainer.pl <patch>` in a U-Boot tree prints
  them.
- the patch goes as the mail body with `git send-email`; the cover text
  below goes after the `---` line of the patch or as a separate report mail.

`Signed-off-by:` must carry your real name and e-mail (Developer's
Certificate of Origin); fill in the placeholders.

---

## Report mail

```
Subject: [REGRESSION] net: phy: YT8531 stays powered down after warm reboot since v2025.04

Hi,

On the Orange Pi Zero 3 (Allwinner H618, sun8i-emac, Motorcomm YT8531
RGMII PHY) Ethernet is dead after a warm reboot from Linux with U-Boot
v2025.04 and later; a power cycle brings it back. v2025.01 is fine.

What happens:

1. Linux brings eth0 down at shutdown; phylib suspends the PHY, which sets
   BMCR_PDOWN (genphy_suspend).
2. A warm reboot keeps the PHY powered, so it is still in power-down when
   U-Boot starts.
3. Up to v2025.01, phy_connect_dev() did a phy_reset(), which cleared
   BMCR_PDOWN. Commit bab54f5942 ("net: phy: Do not do CL22 phy reset before
   ethernet phy driver probe") removed it. yt8531_config() ->
   genphy_config_aneg() does not touch BMCR_PDOWN, so the PHY stays down.
4. Linux then fails to bring up the MAC, the stmmac DMA software reset
   needs the PHY's RX clock:

     dwmac-sun8i 5020000.ethernet: EMAC reset timeout
     (open fails with -110, -ETIMEDOUT)

   <paste the exact dmesg lines from the board here>

Restoring phy_reset() in phy_connect_dev() fixes it (tested: several warm
reboots, eth0 up 2.6 s after boot, link at 5.7 s). I understand the reset
was removed on purpose, so the patch below clears the power-down bit in the
YT8531 driver instead, where the PHY is configured at probe.

Board: Orange Pi Zero 3, 1 GB and 1.5 GB
U-Boot: v2026.04, orangepi_zero3_defconfig, TF-A v2.10
Linux: 6.12 (OpenWrt 25.12.5)

Thanks,
<Your Name>
```

---

## Option B: targeted fix in the Motorcomm driver (proposed, not yet tested)

`sun8i_emac_eth_probe()` -> `sun8i_phy_init()` -> `phy_config()` runs
`yt8531_config()` at every boot, so clearing the bit there is enough.

```diff
From: <Your Name> <your@email>
Subject: [PATCH] net: phy: motorcomm: power up the YT8531 in config

Linux powers the PHY down (BMCR_PDOWN) when the interface goes down. A
warm reboot keeps the PHY powered, so it is still in power-down when
U-Boot configures it. Since commit bab54f5942 ("net: phy: Do not do CL22
phy reset before ethernet phy driver probe") nothing clears the bit any
more: the PHY gives no RX clock and the MAC fails to come up, in U-Boot
and in the next kernel ("EMAC reset timeout").

Clear BMCR_PDOWN before configuring the PHY.

Fixes: bab54f5942 ("net: phy: Do not do CL22 phy reset before ethernet phy driver probe")
Signed-off-by: <Your Name> <your@email>
---
 drivers/net/phy/motorcomm.c | 5 +++++
 1 file changed, 5 insertions(+)

diff --git a/drivers/net/phy/motorcomm.c b/drivers/net/phy/motorcomm.c
--- a/drivers/net/phy/motorcomm.c
+++ b/drivers/net/phy/motorcomm.c
@@ static int yt8531_config(struct phy_device *phydev)
 	u16 mask, val;
 	int ret;
 
+	/* Linux may have left the PHY powered down before a warm reboot */
+	ret = phy_modify(phydev, MDIO_DEVAD_NONE, MII_BMCR, BMCR_PDOWN, 0);
+	if (ret < 0)
+		return ret;
+
 	ret = genphy_config_aneg(phydev);
 	if (ret < 0)
 		return ret;
```

The hunk header is written by hand; regenerate the patch with
`git format-patch` from a real commit before sending. `yt8531s_config()`
(YT8531S) has the same shape and may need the same line; check whether
the maintainers want it covered in the same patch.

To test before sending: put this file in place of
`uboot/patches/001-net-phy-reset-the-PHY-on-connect.patch`, build, then
`reboot` the Zero 3 three times with the cable in. Each boot must show
eth0 up with no `EMAC reset timeout`.

---

## Option A: what this project ships (tested)

`uboot/patches/001-net-phy-reset-the-PHY-on-connect.patch`, a soft reset
in `phy_connect_dev()` as before v2025.04:

```diff
--- a/drivers/net/phy/phy.c
+++ b/drivers/net/phy/phy.c
@@ -842,6 +842,13 @@ struct phy_device *phy_find_by_mask(struct mii_dev *bus, uint phy_mask)
 static void phy_connect_dev(struct phy_device *phydev, struct udevice *dev,
 			    phy_interface_t interface)
 {
+	/*
+	 * Soft reset the PHY, as U-Boot did up to v2025.01. Linux powers the
+	 * PHY down (BMCR_PDOWN) when the interface goes down; a warm reset
+	 * keeps it powered down, and the stmmac DMA reset in Linux then times
+	 * out without the PHY's RX clock. The reset brings the PHY back up.
+	 */
+	phy_reset(phydev);
 	if (phydev->dev && phydev->dev != dev) {
```

It reverts, for every board, what bab54f5942 removed on purpose (some PHYs
must not be reset before their driver probes), so upstream will likely
prefer option B. Mention it in the report as the tested workaround.
