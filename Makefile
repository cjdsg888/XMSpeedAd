# ============================================================================
# XMSpeedAd — Makefile
# 自动检测: 设了 $THEOS 就用 Theos 编译, 否则用 macOS Xcode 直接编译
# ============================================================================

# ---- Theos 编译 (Linux/macOS, 需要 THEOS 环境变量) ----
ifneq ($(THEOS),)
TARGET      := iphone:clang:latest:12.0
ARCHS       := arm64
DEBUG       := 0
PACKAGE_VERSION = 1.0.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME           = XMSpeedAd
XMSpeedAd_FILES      = Tweak.m
XMSpeedAd_CFLAGS     = -fobjc-arc
XMSpeedAd_FRAMEWORKS = Foundation UIKit AVFoundation

include $(THEOS_MAKE_PATH)/tweak.mk

# ---- 直接编译 (macOS + Xcode, 无需 Theos) ----
else
ARCH   ?= arm64
MIN_IOS ?= 12.0
SDK    ?= $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)

XMSpeedAd.dylib: Tweak.m
	@if [ -z "$(SDK)" ]; then echo "Error: Xcode not found (no SDK)"; exit 1; fi
	clang -arch $(ARCH) -fobjc-arc -miphoneos-version-min=$(MIN_IOS) \
		-isysroot $(SDK) \
		-dynamiclib \
		-framework Foundation -framework UIKit -framework AVFoundation \
		-o $@ $< \
		-Xlinker -install_name -Xlinker @rpath/$@

all: XMSpeedAd.dylib

deb: XMSpeedAd.dylib
	mkdir -p _package/DEBIAN _package/Library/MobileSubstrate/DynamicLibraries
	cp XMSpeedAd.dylib _package/Library/MobileSubstrate/DynamicLibraries/
	cp XMSpeedAd.plist _package/Library/MobileSubstrate/DynamicLibraries/
	cp control _package/DEBIAN/control
	chmod 755 _package/DEBIAN
	dpkg-deb -b _package XMSpeedAd.deb
	rm -rf _package

clean:
	rm -rf XMSpeedAd.dylib XMSpeedAd.deb _package

.PHONY: all deb clean
endif
