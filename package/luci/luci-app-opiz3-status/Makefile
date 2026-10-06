# SPDX-License-Identifier: GPL-2.0-only
#
# Board panel for LuCI Status -> Overview (SoC temperatures, CPU frequency,
# the UWE5622 Wi-Fi driver) and System -> CPU frequency (governor, limits).

include $(TOPDIR)/rules.mk

# set explicitly: luci.mk takes the version from git, and the package is
# built from a copy without one
PKG_VERSION:=1.0.0
PKG_RELEASE:=4

LUCI_TITLE:=Orange Pi Zero 2/3 board status and CPU frequency
LUCI_DEPENDS:=+luci-base +rpcd-mod-ucode
LUCI_PKGARCH:=all

PKG_LICENSE:=GPL-2.0-only

define Package/luci-app-opiz3-status/conffiles
/etc/config/opiz3
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
