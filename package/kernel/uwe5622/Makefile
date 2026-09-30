# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=uwe5622
PKG_VERSION:=2026.08.15
PKG_RELEASE:=2

PKG_SOURCE_VERSION:=d6bec7538a0b4b67e35715ad71eaa056555524cb
PKG_SOURCE:=$(PKG_NAME)-$(PKG_SOURCE_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/armbian/uwe5622/tar.gz/$(PKG_SOURCE_VERSION)?
PKG_HASH:=d85333868862d820f2dae3379ee7b9962ebfd8aeb1ee9cb84c66c725f292ea11
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_SOURCE_VERSION)

PKG_LICENSE:=GPL-2.0
PKG_LICENSE_FILES:=README.md
PKG_MAINTAINER:=jukeboge <jukeboge@gmail.com>
PKG_BUILD_PARALLEL:=1
PKG_EXTMOD_SUBDIRS:=unisocwcn unisocwifi

STAMP_CONFIGURED_DEPENDS := $(STAGING_DIR)/usr/include/mac80211-backport/backport/autoconf.h

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

define KernelPackage/uwe5622
  SUBMENU:=Wireless Drivers
  TITLE:=UNISOC UWE5622 (AW859A) SDIO wireless driver
  URL:=https://github.com/armbian/uwe5622
  DEPENDS:=@TARGET_sunxi_cortexa53 +kmod-cfg80211 +uwe5622-firmware
  FILES:= \
	$(PKG_BUILD_DIR)/unisocwcn/uwe5622_bsp_sdio.ko \
	$(PKG_BUILD_DIR)/unisocwifi/sprdwl_ng.ko
  # TANPA AutoLoad. kmodloader memuat modules.d pada S10boot, jauh sebelum
  # S20network; di Orange Pi Zero 3 probe SDIO uwe5622_bsp_sdio menggantung di
  # sana dan boot berhenti total -- board menyala, link ethernet hidup, nol
  # frame terkirim, tidak bisa dijangkau sama sekali. Kedua modul kini dimuat
  # oleh init sprdwl-delay setelah jaringan naik, sehingga kegagalan driver
  # hanya mematikan Wi-Fi, bukan seluruh gateway.
endef

define KernelPackage/uwe5622/description
  Community-maintained SDIO Wi-Fi driver for the UNISOC UWE5622 chipset
  used by the AW859A module on the Orange Pi 3 LTS.
endef

define KernelPackage/uwe5622/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/sprdwl-delay $(1)/etc/init.d/sprdwl-delay
endef

define Build/Configure
endef

NOSTDINC_FLAGS := \
	$(KERNEL_NOSTDINC_FLAGS) \
	-I$(PKG_BUILD_DIR)/unisocwcn/include \
	-I$(STAGING_DIR)/usr/include/mac80211-backport \
	-I$(STAGING_DIR)/usr/include/mac80211-backport/uapi \
	-I$(STAGING_DIR)/usr/include/mac80211 \
	-I$(STAGING_DIR)/usr/include/mac80211/uapi \
	-include backport/autoconf.h \
	-include backport/backport.h \
	-DOPENWRT_CFG80211_BACKPORT

define Build/Compile
	+$(KERNEL_MAKE) $(PKG_JOBS) \
		M=$(PKG_BUILD_DIR)/unisocwcn \
		CONFIG_AW_WIFI_DEVICE_UWE5622=y \
		CONFIG_AW_BIND_VERIFY=y \
		UNISOC_FW_PATH_CONFIG=\"/lib/firmware/uwe5622/\" \
		modules
	+$(KERNEL_MAKE) $(PKG_JOBS) \
		M=$(PKG_BUILD_DIR)/unisocwifi \
		CONFIG_WLAN_UWE5622=m \
		UNISOC_BSP_INCLUDE=$(PKG_BUILD_DIR)/unisocwcn/include \
		UNISOC_WIFI_CUS_CONFIG=/lib/firmware/uwe5622 \
		NOSTDINC_FLAGS="$(NOSTDINC_FLAGS)" \
		KBUILD_EXTRA_SYMBOLS="$(KERNEL_BUILD_DIR)/symvers/mac80211.symvers $(PKG_BUILD_DIR)/unisocwcn/Module.symvers" \
		modules
endef

$(eval $(call KernelPackage,uwe5622))
