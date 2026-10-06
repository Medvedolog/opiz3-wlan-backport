# SPDX-License-Identifier: GPL-2.0-only
#
# Board panel for LuCI Status -> Overview: SoC temperatures, CPU frequency
# and the state of the UWE5622 Wi-Fi driver.

include $(TOPDIR)/rules.mk

# set explicitly: luci.mk takes the version from git, and the package is
# built from a copy without one
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

LUCI_TITLE:=Orange Pi Zero 3 board status (temperature, Wi-Fi driver)
LUCI_DEPENDS:=+luci-base +rpcd-mod-ucode
LUCI_PKGARCH:=all

PKG_LICENSE:=GPL-2.0-only

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
