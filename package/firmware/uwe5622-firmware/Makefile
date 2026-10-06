# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=uwe5622-firmware
PKG_VERSION:=2023.09.02
PKG_RELEASE:=1

FW_SOURCE_VERSION:=612bc7cc0e3539ea89c659049b7d8432e2de8ed7

PKG_LICENSE:=Redistributable
PKG_MAINTAINER:=jukeboge <jukeboge@gmail.com>

include $(INCLUDE_DIR)/package.mk

define Download/uwe5622-wcnmodem
  URL:=https://raw.githubusercontent.com/armbian/firmware/$(FW_SOURCE_VERSION)/uwe5622
  URL_FILE:=wcnmodem.bin
  FILE:=uwe5622-wcnmodem.bin
  HASH:=119b87ce30875734a67462f7293fb8fe85acf3270fe8b78c978ae24be7715a80
endef
$(eval $(call Download,uwe5622-wcnmodem))

define Download/uwe5622-wifi-config
  URL:=https://raw.githubusercontent.com/armbian/firmware/$(FW_SOURCE_VERSION)/uwe5622
  URL_FILE:=wifi_2355b001_1ant.ini
  FILE:=uwe5622-wifi_2355b001_1ant.ini
  HASH:=1f3c40ec245a8d0b99ad1c23706597d6dd5008ab80cefb7bcc1956efc4e938f7
endef
$(eval $(call Download,uwe5622-wifi-config))

define Package/uwe5622-firmware
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=UNISOC UWE5622 firmware
  URL:=https://github.com/armbian/firmware/tree/master/uwe5622
endef

define Build/Compile
endef

define Package/uwe5622-firmware/install
	$(INSTALL_DIR) $(1)/lib/firmware/uwe5622
	$(INSTALL_DATA) $(DL_DIR)/uwe5622-wcnmodem.bin \
		$(1)/lib/firmware/uwe5622/wcnmodem.bin
	$(INSTALL_DATA) $(DL_DIR)/uwe5622-wifi_2355b001_1ant.ini \
		$(1)/lib/firmware/uwe5622/wifi_2355b001_1ant.ini
endef

$(eval $(call BuildPackage,uwe5622-firmware))
