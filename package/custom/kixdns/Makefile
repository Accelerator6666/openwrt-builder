include $(TOPDIR)/rules.mk

PKG_NAME:=kixdns
PKG_VERSION:=0.2.0
PKG_RELEASE:=1

PKG_SOURCE:=kixdns-linux-x86_64-musl
PKG_SOURCE_URL:=https://github.com/olicesx/kixdns/releases/download/v$(PKG_VERSION)/
PKG_HASH:=e63817b446828a5715c011bc6ee5f741942445567c0c33ad6cf6bae8e9a9bcbf

PKG_LICENSE:=GPL-3.0-only
PKG_MAINTAINER:=Accelerator6666
PKGARCH:=x86_64

include $(INCLUDE_DIR)/package.mk

define Package/kixdns
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=IP Addresses and Names
  TITLE:=KixDNS asynchronous DNS forwarding server
  URL:=https://github.com/olicesx/kixdns
  DEPENDS:=@TARGET_x86_64 +ca-bundle
endef

define Package/kixdns/description
 KixDNS is an asynchronous non-recursive DNS forwarding server written in Rust.
 This package uses the pinned upstream x86_64 musl release binary.
endef

define Package/kixdns/conffiles
/etc/kixdns/pipeline.json
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) $(DL_DIR)/$(PKG_SOURCE) $(PKG_BUILD_DIR)/kixdns
endef

define Build/Compile
endef

define Package/kixdns/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/kixdns $(1)/usr/bin/kixdns

	$(INSTALL_DIR) $(1)/etc/kixdns
	$(INSTALL_CONF) ./files/pipeline.json $(1)/etc/kixdns/pipeline.json

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/kixdns.init $(1)/etc/init.d/kixdns
endef

$(eval $(call BuildPackage,kixdns))
